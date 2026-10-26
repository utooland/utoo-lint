const std = @import("std");
const parser = @import("parser");
const core = @import("core.zig");

const ast = parser.ast;
const scoped = parser.traverser.scoped;
const Allocator = std.mem.Allocator;

// These early errors are syntax failures even when optional semantic lint
// checking is disabled. Reuse Yuku's lexical scope and directive tracking.
pub fn appendDiagnostics(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *ast.Tree,
) Allocator.Error!bool {
    const has_candidate = for (tree.nodes.items(.data)) |data| {
        switch (data) {
            .with_statement => break true,
            .unary_expression => |expression| if (expression.operator == .delete) break true,
            else => {},
        }
    } else false;
    if (!has_candidate) return false;

    const previous_count = diagnostics.items.len;
    var visitor = Visitor{ .allocator = allocator, .diagnostics = diagnostics };
    _ = try scoped.traverse(Visitor, tree, &visitor);
    return diagnostics.items.len != previous_count;
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,

    pub fn enter_unary_expression(
        self: *Visitor,
        expression: ast.UnaryExpression,
        index: ast.NodeIndex,
        ctx: *scoped.Ctx,
    ) Allocator.Error!parser.traverser.Action {
        if (expression.operator != .delete or !ctx.scope.get(ctx.scope.current).flags.strict) return .proceed;
        var target = expression.argument;
        while (target != .null) {
            switch (ctx.tree.data(target)) {
                .parenthesized_expression => |value| target = value.expression,
                .chain_expression => |value| target = value.expression,
                else => break,
            }
        }
        if (target != .null and ctx.tree.data(target) == .identifier_reference) {
            try self.report(ctx.tree.span(index), "Deleting a variable in strict mode is not allowed");
        }
        return .proceed;
    }

    pub fn enter_with_statement(
        self: *Visitor,
        _: ast.WithStatement,
        index: ast.NodeIndex,
        ctx: *scoped.Ctx,
    ) Allocator.Error!parser.traverser.Action {
        if (ctx.scope.get(ctx.scope.current).flags.strict) {
            try self.report(ctx.tree.span(index), "'with' statements are not allowed in strict mode");
        }
        return .proceed;
    }

    fn report(self: *Visitor, span: ast.Span, message: []const u8) Allocator.Error!void {
        try core.addDiagnostic(self.allocator, self.diagnostics, .@"error", "parse", message, span);
    }
};
