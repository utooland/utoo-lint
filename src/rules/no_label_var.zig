const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-label-var";

const Label = struct {
    name: []const u8,
    scope: traverser.semantic.ScopeId,
    node: ast.NodeIndex,
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    semantic_result: traverser.semantic.Result,
) Allocator.Error!void {
    var labels: std.ArrayList(Label) = .empty;
    defer labels.deinit(allocator);

    var visitor = Visitor{ .allocator = allocator, .labels = &labels };
    _ = try traverser.scoped.traverse(Visitor, @constCast(tree), &visitor);

    for (labels.items) |label| {
        const symbol_id = semantic_result.symbol_table.resolve(
            semantic_result.scope_tree,
            label.scope,
            label.name,
        ) orelse continue;

        const symbol = semantic_result.symbol_table.getSymbol(symbol_id);
        if (!symbol.flags.intersects(traverser.semantic.Symbol.value_space)) continue;

        try core.addDiagnostic(
            allocator,
            diagnostics,
            .warning,
            id,
            "Found identifier with same name as label.",
            tree.span(label.node),
        );
    }
}

const Visitor = struct {
    allocator: Allocator,
    labels: *std.ArrayList(Label),

    pub fn enter_labeled_statement(
        self: *Visitor,
        statement: ast.LabeledStatement,
        index: ast.NodeIndex,
        ctx: *traverser.scoped.Ctx,
    ) Allocator.Error!traverser.Action {
        const label = switch (ctx.tree.data(statement.label)) {
            .label_identifier => |identifier| identifier,
            else => return .proceed,
        };

        try self.labels.append(self.allocator, .{
            .name = ctx.tree.string(label.name),
            .scope = ctx.scope.current,
            .node = index,
        });
        return .proceed;
    }
};
