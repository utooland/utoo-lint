const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const helpers = @import("react_hooks_helpers.zig");
const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "react-hooks/purity";

pub fn run(allocator: Allocator, diagnostics: *core.DiagnosticList, tree: *const ast.Tree, symbols: helpers.SymbolTable) Allocator.Error!void {
    var visitor = Visitor{ .allocator = allocator, .diagnostics = diagnostics, .context = try helpers.Context.init(allocator, tree, symbols) };
    defer visitor.context.memo_calls.deinit(allocator);
    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    context: helpers.Context,

    pub fn enter_call_expression(self: *Visitor, call: ast.CallExpression, node: ast.NodeIndex, _: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        const value = self.context.resolve(call.callee) orelse return .proceed;
        const impure = if (value.len == 0) self.isGlobal(value.node, "Date") else if (value.len == 1 and value.properties[0] == .field) blk: {
            const property = value.properties[0].field;
            break :blk (self.isGlobal(value.node, "Math") and std.mem.eql(u8, property, "random")) or
                (self.isGlobal(value.node, "Date") and std.mem.eql(u8, property, "now")) or
                (self.isGlobal(value.node, "performance") and std.mem.eql(u8, property, "now")) or
                (self.isGlobal(value.node, "crypto") and std.mem.eql(u8, property, "randomUUID"));
        } else false;
        if (impure) try self.report(node);
        return .proceed;
    }

    pub fn enter_new_expression(self: *Visitor, expression: ast.NewExpression, node: ast.NodeIndex, _: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        const value = self.context.resolve(expression.callee) orelse return .proceed;
        if (expression.arguments.len == 0 and value.len == 0 and self.isGlobal(value.node, "Date")) try self.report(node);
        return .proceed;
    }

    fn isGlobal(self: *const Visitor, node: ast.NodeIndex, expected: []const u8) bool {
        const unwrapped = helpers.unwrap(self.context.tree, node);
        return self.context.symbols.isUnresolvedReference(unwrapped) and
            std.mem.eql(u8, helpers.name(self.context.tree, unwrapped) orelse "", expected);
    }

    fn report(self: *Visitor, node: ast.NodeIndex) Allocator.Error!void {
        if (self.context.renderOwner(node) == null) return;
        try core.addDiagnostic(self.allocator, self.diagnostics, .@"error", id, "Cannot call an impure function during render; move it to an event handler, effect, or lazy state initializer.", self.context.tree.span(node));
    }
};
