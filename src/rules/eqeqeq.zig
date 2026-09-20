const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "eqeqeq";

pub const Options = struct {
    style: core.EqeqeqStyle = .strict,
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    expression: ast.BinaryExpression,
    index: ast.NodeIndex,
) Allocator.Error!void {
    return checkWithOptions(allocator, diagnostics, tree, expression, index, .{});
}

pub fn checkWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    expression: ast.BinaryExpression,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    const null_check = isNullLiteral(tree, expression.left) or isNullLiteral(tree, expression.right);
    const inverse = null_check and options.style == .never_null;
    if (inverse) {
        if (expression.operator != .strict_equal and expression.operator != .strict_not_equal) return;
    } else {
        if (expression.operator != .equal and expression.operator != .not_equal) return;
        if (options.style == .allow_null and null_check) return;
        if (options.style == .smart and isSmartException(tree, expression)) return;
    }
    const message = if (inverse) "Use loose equality operators when comparing with null." else "Use strict equality operators.";

    if (canAutofix(tree, expression)) {
        if (operatorSpan(tree, expression)) |fix_span| {
            try core.addDiagnosticWithFix(
                allocator,
                diagnostics,
                .warning,
                id,
                message,
                tree.span(index),
                .{
                    .span = fix_span,
                    .replacement = switch (expression.operator) {
                        .equal => "===",
                        .not_equal => "!==",
                        .strict_equal => "==",
                        .strict_not_equal => "!=",
                        else => unreachable,
                    },
                },
            );
            return;
        }
    }

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .warning,
        id,
        message,
        tree.span(index),
    );
}

fn canAutofix(tree: *const ast.Tree, expression: ast.BinaryExpression) bool {
    if (isTypeofExpression(tree, expression.left) or isTypeofExpression(tree, expression.right)) return true;
    const left_kind = literalKind(tree, expression.left) orelse return false;
    const right_kind = literalKind(tree, expression.right) orelse return false;
    return left_kind == right_kind;
}

fn operatorSpan(tree: *const ast.Tree, expression: ast.BinaryExpression) ?ast.Span {
    const operator = switch (expression.operator) {
        .equal => "==",
        .not_equal => "!=",
        .strict_equal => "===",
        .strict_not_equal => "!==",
        else => return null,
    };
    var cursor: usize = @intCast(tree.span(expression.left).end);
    const end: usize = @intCast(tree.span(expression.right).start);

    while (cursor + operator.len <= end) {
        if (commentEndingAfter(tree, cursor)) |comment_end| {
            cursor = comment_end;
            continue;
        }
        if (std.mem.startsWith(u8, tree.source[cursor..end], operator)) {
            return .{ .start = @intCast(cursor), .end = @intCast(cursor + operator.len) };
        }
        cursor += 1;
    }
    return null;
}

fn commentEndingAfter(tree: *const ast.Tree, offset: usize) ?usize {
    for (tree.comments) |comment| {
        const start: usize = @intCast(comment.span.start);
        const end: usize = @intCast(comment.span.end);
        if (start <= offset and offset < end) return end;
    }
    return null;
}

fn isSmartException(tree: *const ast.Tree, expression: ast.BinaryExpression) bool {
    if (isNullLiteral(tree, expression.left) or isNullLiteral(tree, expression.right)) return true;
    if (isTypeofExpression(tree, expression.left) or isTypeofExpression(tree, expression.right)) return true;
    const left_kind = literalKind(tree, expression.left) orelse return false;
    const right_kind = literalKind(tree, expression.right) orelse return false;
    return left_kind == right_kind;
}

fn isNullLiteral(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .null_literal => true,
        else => false,
    };
}

fn isTypeofExpression(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .unary_expression => |unary| unary.operator == .typeof,
        else => false,
    };
}

const LiteralKind = enum {
    bigint,
    boolean,
    null,
    number,
    object,
    string,
};

fn literalKind(tree: *const ast.Tree, index: ast.NodeIndex) ?LiteralKind {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .bigint_literal => .bigint,
        .boolean_literal => .boolean,
        .null_literal => .null,
        .numeric_literal => .number,
        .regexp_literal => .object,
        .string_literal => .string,
        .template_literal => |literal| if (tree.extra(literal.expressions).len == 0) .string else null,
        else => null,
    };
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
