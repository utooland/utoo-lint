const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

const no_class_assign = @import("no_class_assign.zig");
const no_const_assign = @import("no_const_assign.zig");
const no_ex_assign = @import("no_ex_assign.zig");
const no_func_assign = @import("no_func_assign.zig");
const no_import_assign = @import("no_import_assign.zig");

pub fn shouldRun(options: core.Options) bool {
    return options.no_class_assign or
        options.no_const_assign or
        options.no_ex_assign or
        options.no_func_assign or
        options.no_import_assign;
}

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    semantic_result: traverser.semantic.Result,
    options: core.Options,
) Allocator.Error!void {
    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .scope_tree = semantic_result.scope_tree,
        .symbol_table = semantic_result.symbol_table,
        .options = options,
    };
    defer visitor.namespace_import_names.deinit(allocator);

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    options: core.Options,
    namespace_import_names: std.StringHashMapUnmanaged(void) = .empty,

    pub fn enter_import_namespace_specifier(
        self: *Visitor,
        specifier: ast.ImportNamespaceSpecifier,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (!self.options.no_import_assign) return .proceed;

        const name = bindingIdentifierName(ctx.tree, specifier.local) orelse return .proceed;
        try self.namespace_import_names.put(self.allocator, name, {});
        return .proceed;
    }

    pub fn enter_assignment_expression(
        self: *Visitor,
        expression: ast.AssignmentExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.checkTarget(ctx.tree, expression.left, index);
        return .proceed;
    }

    pub fn enter_update_expression(
        self: *Visitor,
        expression: ast.UpdateExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.checkTarget(ctx.tree, expression.argument, index);
        return .proceed;
    }

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (!self.options.no_import_assign) return .proceed;

        if (isObjectAssignCall(ctx.tree, self.symbol_table, call.callee) and call.arguments.len > 0) {
            const first = ctx.tree.extra(call.arguments)[0];
            if (self.namespaceSymbolFromExpression(ctx.tree, first) != .none) {
                try self.addDiagnostic(ctx.tree, index, no_import_assign.id, "Imported bindings are read-only.");
            }
        }
        return .proceed;
    }

    fn checkTarget(
        self: *Visitor,
        tree: *const ast.Tree,
        target: ast.NodeIndex,
        diagnostic_node: ast.NodeIndex,
    ) Allocator.Error!void {
        const identifier = unwrapTransparent(tree, target);
        const symbol_id = self.symbolFromAssignmentTarget(tree, identifier);

        if (symbol_id != .none) {
            const symbol = self.symbol_table.getSymbol(symbol_id);

            if (self.options.no_ex_assign and symbol.flags.catch_var) {
                try self.addDiagnostic(tree, diagnostic_node, no_ex_assign.id, "Do not reassign catch parameters.");
            }
            if (self.options.no_class_assign and symbol.flags.class) {
                try self.addDiagnostic(tree, diagnostic_node, no_class_assign.id, "Class declarations should not be reassigned.");
            }
            if (self.options.no_const_assign and symbol.flags.const_var) {
                try self.addDiagnostic(tree, diagnostic_node, no_const_assign.id, "Constant bindings should not be reassigned.");
            }
            if (self.options.no_func_assign and symbol.flags.function) {
                try self.addDiagnostic(tree, diagnostic_node, no_func_assign.id, "Function declarations should not be reassigned.");
            }
            if (self.options.no_import_assign and symbol.flags.import) {
                try self.addDiagnostic(tree, diagnostic_node, no_import_assign.id, "Imported bindings are read-only.");
            }
        }

        if (self.options.no_import_assign and self.isForbiddenNamespaceMember(tree, target)) {
            try self.addDiagnostic(tree, diagnostic_node, no_import_assign.id, "Imported bindings are read-only.");
        }
    }

    fn symbolFromAssignmentTarget(self: *Visitor, tree: *const ast.Tree, target: ast.NodeIndex) traverser.semantic.SymbolId {
        if (target == .null) return .none;

        switch (tree.data(unwrapTransparent(tree, target))) {
            .assignment_pattern => |pattern| return self.symbolFromAssignmentTarget(tree, pattern.left),
            .binding_rest_element => |element| return self.symbolFromAssignmentTarget(tree, element.argument),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    const symbol_id = self.symbolFromAssignmentTarget(tree, element);
                    if (symbol_id != .none) return symbol_id;
                }
                return self.symbolFromAssignmentTarget(tree, pattern.rest);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    const symbol_id = self.symbolFromAssignmentTarget(tree, property.value);
                    if (symbol_id != .none) return symbol_id;
                }
                return self.symbolFromAssignmentTarget(tree, pattern.rest);
            },
            else => {},
        }

        if (isIdentifierReference(tree, target)) {
            const reference_id = self.symbol_table.model.referenceOf(target) orelse return .none;
            return self.symbol_table.referenceSymbol(reference_id);
        }

        const name = bindingIdentifierName(tree, target) orelse return .none;
        const scope = self.innermostScopeContaining(tree, target);
        return self.symbol_table.resolve(self.scope_tree, scope, name) orelse .none;
    }

    fn innermostScopeContaining(self: *Visitor, tree: *const ast.Tree, node: ast.NodeIndex) traverser.semantic.ScopeId {
        const node_span = tree.span(node);
        var best: traverser.semantic.ScopeId = if (tree.source_type == .module) .module else .root;
        var best_len: u32 = std.math.maxInt(u32);

        for (self.scope_tree.scopes, 0..) |scope, i| {
            const scope_span = tree.span(scope.node);
            if (scope_span.start > node_span.start or scope_span.end < node_span.end) continue;

            const len = scope_span.end - scope_span.start;
            if (len <= best_len) {
                best = @enumFromInt(@as(u32, @intCast(i)));
                best_len = len;
            }
        }

        return best;
    }

    fn isForbiddenNamespaceMember(self: *Visitor, tree: *const ast.Tree, target: ast.NodeIndex) bool {
        const member = switch (tree.data(unwrapTransparent(tree, target))) {
            .member_expression => |member| member,
            else => return false,
        };

        return self.namespaceSymbolFromExpression(tree, member.object) != .none;
    }

    fn namespaceSymbolFromExpression(self: *Visitor, tree: *const ast.Tree, expression: ast.NodeIndex) traverser.semantic.SymbolId {
        const identifier = unwrapTransparent(tree, expression);
        if (!isIdentifierReference(tree, identifier)) return .none;

        const reference_id = self.symbol_table.model.referenceOf(identifier) orelse return .none;
        const symbol_id = self.symbol_table.referenceSymbol(reference_id);
        if (symbol_id == .none) return .none;

        const symbol = self.symbol_table.getSymbol(symbol_id);
        if (!symbol.flags.import) return .none;

        const name = tree.string(symbol.name);
        if (!self.namespace_import_names.contains(name)) return .none;

        return symbol_id;
    }

    fn addDiagnostic(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        rule_id: []const u8,
        message: []const u8,
    ) Allocator.Error!void {
        try core.addDiagnostic(
            self.allocator,
            self.diagnostics,
            .warning,
            rule_id,
            message,
            tree.span(index),
        );
    }
};

fn unwrapTransparent(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    var current = index;

    while (current != .null) {
        switch (tree.data(current)) {
            .chain_expression => |chain| current = chain.expression,
            .parenthesized_expression => |parenthesized| current = parenthesized.expression,
            else => return current,
        }
    }

    return current;
}

fn bindingIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    return switch (tree.data(index)) {
        .binding_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn isIdentifierReference(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;

    return switch (tree.data(index)) {
        .identifier_reference => true,
        else => false,
    };
}

fn isObjectAssignCall(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    callee: ast.NodeIndex,
) bool {
    const member = switch (tree.data(unwrapTransparent(tree, callee))) {
        .member_expression => |member| member,
        else => return false,
    };

    const property_name = propertyName(tree, member) orelse return false;
    if (!std.mem.eql(u8, property_name, "assign")) return false;

    const object = unwrapTransparent(tree, member.object);
    const object_name = identifierReferenceName(tree, object) orelse return false;
    return std.mem.eql(u8, object_name, "Object") and symbol_table.isUnresolvedReference(object);
}

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn propertyName(tree: *const ast.Tree, member: ast.MemberExpression) ?[]const u8 {
    if (member.property == .null) return null;

    return if (member.computed)
        switch (tree.data(member.property)) {
            .string_literal => |literal| tree.string(literal.value),
            .template_literal => |literal| templateStringValue(tree, literal),
            else => null,
        }
    else switch (tree.data(member.property)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn templateStringValue(tree: *const ast.Tree, literal: ast.TemplateLiteral) ?[]const u8 {
    if (literal.expressions.len != 0 or literal.quasis.len != 1) return null;
    const quasi_index = tree.extra(literal.quasis)[0];
    return switch (tree.data(quasi_index)) {
        .template_element => |element| tree.string(element.cooked),
        else => null,
    };
}
