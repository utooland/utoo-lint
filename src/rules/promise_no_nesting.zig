const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;
const SymbolId = traverser.semantic.SymbolId;

pub const id = "promise/no-nesting";

const ReferenceLookup = std.AutoHashMap(ast.NodeIndex, SymbolId);

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    var reference_lookup = ReferenceLookup.init(allocator);
    defer reference_lookup.deinit();

    var reference_iter = symbol_table.iterReferences();
    while (reference_iter.next()) |entry| {
        if (entry.reference.kind != .value) continue;
        try reference_lookup.put(entry.reference.node, symbol_table.referenceSymbol(entry.id));
    }

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .scope_tree = scope_tree,
        .symbol_table = symbol_table,
        .reference_lookup = &reference_lookup,
    };
    defer visitor.callback_stack.deinit(allocator);
    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    reference_lookup: *const ReferenceLookup,
    callback_stack: std.ArrayList(ast.NodeIndex) = .empty,

    pub fn enter_function(
        self: *Visitor,
        _: ast.Function,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.enterFunction(ctx.tree, index, ctx);
        return .proceed;
    }

    pub fn exit_function(self: *Visitor, _: ast.Function, index: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.exitFunction(index);
    }

    pub fn enter_arrow_function_expression(
        self: *Visitor,
        _: ast.ArrowFunctionExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.enterFunction(ctx.tree, index, ctx);
        return .proceed;
    }

    pub fn exit_arrow_function_expression(
        self: *Visitor,
        _: ast.ArrowFunctionExpression,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) void {
        self.exitFunction(index);
    }

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const callback = if (self.callback_stack.items.len == 0)
            return .proceed
        else
            self.callback_stack.items[self.callback_stack.items.len - 1];

        const member = promiseHandlerMember(ctx.tree, call) orelse return .proceed;
        if (self.argumentsReferenceCallbackScope(ctx.tree, call.arguments, callback)) return .proceed;

        try core.addDiagnostic(
            self.allocator,
            self.diagnostics,
            .warning,
            id,
            "Avoid nesting promises.",
            ctx.tree.span(if (member.property == .null) index else member.property),
        );
        return .proceed;
    }

    fn enterFunction(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!void {
        const parent_index = ctx.path.parent() orelse return;
        const parent_call = switch (tree.data(parent_index)) {
            .call_expression => |call| call,
            else => return,
        };
        if (promiseHandlerMember(tree, parent_call) == null) return;
        if (!rangeContains(tree, parent_call.arguments, index)) return;
        try self.callback_stack.append(self.allocator, index);
    }

    fn exitFunction(self: *Visitor, index: ast.NodeIndex) void {
        if (self.callback_stack.items.len == 0) return;
        if (self.callback_stack.items[self.callback_stack.items.len - 1] == index) {
            _ = self.callback_stack.pop();
        }
    }

    fn argumentsReferenceCallbackScope(
        self: *const Visitor,
        tree: *const ast.Tree,
        arguments: ast.IndexRange,
        callback: ast.NodeIndex,
    ) bool {
        for (tree.extra(arguments)) |argument| {
            if (self.nodeReferencesCallbackScope(tree, argument, callback)) return true;
        }
        return false;
    }

    fn nodeReferencesCallbackScope(
        self: *const Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        callback: ast.NodeIndex,
    ) bool {
        if (index == .null) return false;

        return switch (tree.data(index)) {
            .identifier_reference => self.referenceBelongsToCallback(tree, index, callback),
            inline else => |node| self.payloadReferencesCallbackScope(tree, node, callback),
        };
    }

    fn payloadReferencesCallbackScope(
        self: *const Visitor,
        tree: *const ast.Tree,
        payload: anytype,
        callback: ast.NodeIndex,
    ) bool {
        const Payload = @TypeOf(payload);
        if (@typeInfo(Payload) != .@"struct") return false;

        inline for (@typeInfo(Payload).@"struct".field_names) |field_name| {
            const value = @field(payload, field_name);
            if (@FieldType(Payload, field_name) == ast.NodeIndex) {
                if (self.nodeReferencesCallbackScope(tree, value, callback)) return true;
            } else if (@FieldType(Payload, field_name) == ast.IndexRange) {
                for (tree.extra(value)) |child| {
                    if (self.nodeReferencesCallbackScope(tree, child, callback)) return true;
                }
            }
        }
        return false;
    }

    fn referenceBelongsToCallback(
        self: *const Visitor,
        tree: *const ast.Tree,
        reference: ast.NodeIndex,
        callback: ast.NodeIndex,
    ) bool {
        const symbol_id = self.reference_lookup.get(reference) orelse return false;
        if (symbol_id == .none) return false;
        const symbol = self.symbol_table.getSymbol(symbol_id);
        return self.nearestFunctionScopeNode(tree, symbol.scope) == callback;
    }

    fn nearestFunctionScopeNode(
        self: *const Visitor,
        tree: *const ast.Tree,
        start: traverser.semantic.ScopeId,
    ) ast.NodeIndex {
        var current = start;
        while (current != .none) {
            const scope = self.scope_tree.getScope(current);
            switch (tree.data(scope.node)) {
                .function,
                .arrow_function_expression,
                => return scope.node,
                else => {},
            }
            current = scope.parent;
        }
        return .null;
    }
};

fn promiseHandlerMember(tree: *const ast.Tree, call: ast.CallExpression) ?ast.MemberExpression {
    const member = switch (tree.data(unwrapTransparent(tree, call.callee))) {
        .member_expression => |member| member,
        else => return null,
    };
    const name = memberPropertyName(tree, member) orelse return null;
    if (!std.mem.eql(u8, name, "then") and !std.mem.eql(u8, name, "catch")) return null;
    return member;
}

fn memberPropertyName(tree: *const ast.Tree, member: ast.MemberExpression) ?[]const u8 {
    if (member.property == .null) return null;
    return switch (tree.data(member.property)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn rangeContains(tree: *const ast.Tree, range: ast.IndexRange, needle: ast.NodeIndex) bool {
    for (tree.extra(range)) |index| {
        if (index == needle) return true;
    }
    return false;
}

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
