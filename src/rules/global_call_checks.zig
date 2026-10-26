const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const no_alert = @import("no_alert.zig");
const no_eval = @import("no_eval.zig");
const no_implied_eval = @import("no_implied_eval.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    check_no_eval: bool,
    no_eval_allow_indirect: bool,
    check_no_alert: bool,
    check_no_implied_eval: bool,
) Allocator.Error!void {
    if (!check_no_eval and !check_no_alert and !check_no_implied_eval) return;

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .symbol_table = symbol_table,
        .check_no_eval = check_no_eval,
        .no_eval_allow_indirect = no_eval_allow_indirect,
        .check_no_alert = check_no_alert,
        .check_no_implied_eval = check_no_implied_eval,
    };

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    symbol_table: traverser.semantic.SymbolTable,
    check_no_eval: bool,
    no_eval_allow_indirect: bool,
    check_no_alert: bool,
    check_no_implied_eval: bool,

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (self.check_no_eval and isEvalCall(ctx.tree, self.symbol_table, call.callee, self.no_eval_allow_indirect)) {
            try core.addDiagnostic(
                self.allocator,
                self.diagnostics,
                .warning,
                no_eval.id,
                "eval can be harmful.",
                ctx.tree.span(index),
            );
        }

        if (self.check_no_alert) {
            if (alertCalleeName(ctx.tree, self.symbol_table, call.callee, ctx)) |name| {
                try core.addDiagnosticFmt(
                    self.allocator,
                    self.diagnostics,
                    .warning,
                    no_alert.id,
                    ctx.tree.span(index),
                    "Unexpected {s}.",
                    .{name},
                );
            }
        }

        if (self.check_no_implied_eval and
            hasStringFirstArgument(ctx.tree, call.arguments) and
            isImpliedEvalCallee(ctx.tree, self.symbol_table, call.callee))
        {
            try core.addDiagnostic(
                self.allocator,
                self.diagnostics,
                .warning,
                no_implied_eval.id,
                "Implied eval can be harmful. Pass a function instead of a string.",
                ctx.tree.span(index),
            );
        }

        return .proceed;
    }

    pub fn enter_identifier_reference(
        self: *Visitor,
        identifier: ast.IdentifierReference,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (!self.check_no_eval) return .proceed;
        if (self.no_eval_allow_indirect) return .proceed;
        if (!std.mem.eql(u8, ctx.tree.string(identifier.name), "eval")) return .proceed;
        if (isCallCalleeReference(ctx.tree, index, ctx)) return .proceed;

        try core.addDiagnostic(
            self.allocator,
            self.diagnostics,
            .warning,
            no_eval.id,
            "eval can be harmful.",
            ctx.tree.span(index),
        );

        return .proceed;
    }
};

fn isEvalCall(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    callee: ast.NodeIndex,
    allow_indirect: bool,
) bool {
    const unwrapped = unwrapTransparent(tree, callee);

    if (identifierReferenceName(tree, unwrapped)) |name| {
        return std.mem.eql(u8, name, "eval");
    }

    if (allow_indirect) return false;

    switch (tree.data(unwrapped)) {
        .sequence_expression => |sequence| {
            const expressions = tree.extra(sequence.expressions);
            if (expressions.len == 0) return false;
            const last = unwrapTransparent(tree, expressions[expressions.len - 1]);
            const name = identifierReferenceName(tree, last) orelse return false;
            return std.mem.eql(u8, name, "eval");
        },
        .member_expression => |member| return isGlobalEvalMember(tree, symbol_table, member),
        else => return false,
    }
}

fn isGlobalEvalMember(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    member: ast.MemberExpression,
) bool {
    const property_name = propertyName(tree, member) orelse return false;
    if (!std.mem.eql(u8, property_name, "eval")) return false;

    const object = unwrapTransparent(tree, member.object);
    const object_name = identifierReferenceName(tree, object) orelse return false;
    return isEvalGlobalObjectName(object_name) and isUnresolvedReference(symbol_table, object);
}

fn isCallCalleeReference(tree: *const ast.Tree, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) bool {
    var child = index;
    var depth: usize = 1;

    while (ctx.path.ancestor(depth)) |parent_index| : (depth += 1) {
        switch (tree.data(parent_index)) {
            .parenthesized_expression => |parenthesized| {
                if (parenthesized.expression != child) return false;
                child = parent_index;
            },
            .sequence_expression => |sequence| {
                if (!rangeContains(tree, sequence.expressions, child)) return false;
                child = parent_index;
            },
            .call_expression => |call| return call.callee == child,
            else => return false,
        }
    }

    return false;
}

fn rangeContains(tree: *const ast.Tree, range: ast.IndexRange, needle: ast.NodeIndex) bool {
    for (tree.extra(range)) |item| {
        if (item == needle) return true;
    }
    return false;
}

fn alertCalleeName(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    callee: ast.NodeIndex,
    ctx: *traverser.basic.Ctx,
) ?[]const u8 {
    const unwrapped = unwrapTransparent(tree, callee);

    if (identifierReferenceName(tree, unwrapped)) |name| {
        if (isAlertName(name) and isUnresolvedReference(symbol_table, unwrapped)) {
            return name;
        }
        return null;
    }

    const member = switch (tree.data(unwrapped)) {
        .member_expression => |member| member,
        else => return null,
    };

    const object = unwrapTransparent(tree, member.object);
    if (!isAlertGlobalObjectReference(tree, symbol_table, object, ctx)) {
        return null;
    }

    const property_name = propertyName(tree, member) orelse return null;
    if (isAlertName(property_name)) return property_name;

    return null;
}

fn isAlertGlobalObjectReference(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    object: ast.NodeIndex,
    ctx: *traverser.basic.Ctx,
) bool {
    switch (tree.data(object)) {
        .this_expression => return isTopLevelThis(ctx, tree),
        else => {},
    }

    const object_name = identifierReferenceName(tree, object) orelse return false;
    return isAlertGlobalObjectName(object_name) and isUnresolvedReference(symbol_table, object);
}

fn isTopLevelThis(ctx: *traverser.basic.Ctx, tree: *const ast.Tree) bool {
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        switch (tree.data(ancestor)) {
            .program => return true,
            .function,
            .arrow_function_expression,
            .class,
            .static_block,
            => return false,
            else => {},
        }
    }
    return false;
}

fn hasStringFirstArgument(tree: *const ast.Tree, arguments: ast.IndexRange) bool {
    if (arguments.len == 0) return false;

    const first = unwrapTransparent(tree, tree.extra(arguments)[0]);
    return isEvaluatedString(tree, first);
}

fn isEvaluatedString(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(index)) {
        .string_literal => true,
        .template_literal => true,
        .binary_expression => |expression| expression.operator == .add and
            (isEvaluatedString(tree, unwrapTransparent(tree, expression.left)) or
                isEvaluatedString(tree, unwrapTransparent(tree, expression.right))),
        else => false,
    };
}

fn isImpliedEvalCallee(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    callee: ast.NodeIndex,
) bool {
    const unwrapped = unwrapTransparent(tree, callee);

    if (identifierReferenceName(tree, unwrapped)) |name| {
        return isImpliedEvalName(name) and isUnresolvedReference(symbol_table, unwrapped);
    }

    const member = switch (tree.data(unwrapped)) {
        .member_expression => |member| member,
        else => return false,
    };

    const property_name = propertyName(tree, member) orelse return false;
    if (!isImpliedEvalName(property_name)) return false;

    const object = unwrapTransparent(tree, member.object);
    const object_name = identifierReferenceName(tree, object) orelse return false;
    return isImpliedEvalGlobalObjectName(object_name) and isUnresolvedReference(symbol_table, object);
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
    if (literal.expressions.len != 0) return null;

    const quasis = tree.extra(literal.quasis);
    if (quasis.len == 0) return "";

    return switch (tree.data(quasis[0])) {
        .template_element => |element| tree.string(element.cooked),
        else => null,
    };
}

fn isUnresolvedReference(
    symbol_table: traverser.semantic.SymbolTable,
    node: ast.NodeIndex,
) bool {
    return symbol_table.isUnresolvedReference(node);
}

fn isAlertName(name: []const u8) bool {
    return std.mem.eql(u8, name, "alert") or
        std.mem.eql(u8, name, "confirm") or
        std.mem.eql(u8, name, "prompt");
}

fn isImpliedEvalName(name: []const u8) bool {
    return std.mem.eql(u8, name, "setTimeout") or
        std.mem.eql(u8, name, "setInterval") or
        std.mem.eql(u8, name, "execScript");
}

fn isAlertGlobalObjectName(name: []const u8) bool {
    return std.mem.eql(u8, name, "window") or
        std.mem.eql(u8, name, "globalThis");
}

fn isEvalGlobalObjectName(name: []const u8) bool {
    return std.mem.eql(u8, name, "window") or
        std.mem.eql(u8, name, "globalThis");
}

fn isImpliedEvalGlobalObjectName(name: []const u8) bool {
    return std.mem.eql(u8, name, "global") or
        std.mem.eql(u8, name, "window") or
        std.mem.eql(u8, name, "globalThis") or
        std.mem.eql(u8, name, "self");
}
