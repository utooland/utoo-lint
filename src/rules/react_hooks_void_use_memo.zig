const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const helpers = @import("react_hooks_helpers.zig");
const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "react-hooks/void-use-memo";

pub fn run(allocator: Allocator, diagnostics: *core.DiagnosticList, tree: *const ast.Tree, symbols: helpers.SymbolTable) Allocator.Error!void {
    var visitor = Visitor{ .allocator = allocator, .diagnostics = diagnostics, .context = try helpers.Context.init(allocator, tree, symbols) };
    defer visitor.functions.deinit(allocator);
    defer visitor.context.memo_calls.deinit(allocator);
    try traverser.basic.traverse(Visitor, tree, &visitor);
    if (visitor.failure) |err| return err;
}

const Frame = struct { node: ast.NodeIndex, check: bool, has_value: bool = false, has_throw: bool = false };
const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    context: helpers.Context,
    functions: std.ArrayList(Frame) = .empty,
    failure: ?Allocator.Error = null,

    fn push(self: *Visitor, node: ast.NodeIndex, has_value: bool) Allocator.Error!traverser.Action {
        try self.functions.append(self.allocator, .{ .node = node, .check = self.context.isMemoCallback(node), .has_value = has_value });
        return .proceed;
    }

    pub fn enter_function(self: *Visitor, _: ast.Function, node: ast.NodeIndex, _: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        return self.push(node, false);
    }

    pub fn enter_arrow_function_expression(self: *Visitor, arrow: ast.ArrowFunctionExpression, node: ast.NodeIndex, _: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        return self.push(node, arrow.expression);
    }

    pub fn enter_return_statement(self: *Visitor, _: ast.ReturnStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        if (self.functions.items.len > 0) self.functions.items[self.functions.items.len - 1].has_value = true;
        return .proceed;
    }

    pub fn enter_throw_statement(self: *Visitor, _: ast.ThrowStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        if (self.functions.items.len > 0) self.functions.items[self.functions.items.len - 1].has_throw = true;
        return .proceed;
    }

    fn pop(self: *Visitor) Allocator.Error!void {
        const frame = self.functions.pop().?;
        // This is a no-value check, not a control-flow proof that every path returns.
        // Throwing callbacks are left to compiler analysis rather than guessed at.
        if (frame.check and !frame.has_value and !frame.has_throw) {
            try core.addDiagnostic(self.allocator, self.diagnostics, .@"error", id, "useMemo callbacks must return a value; use an effect or event handler for side effects.", self.context.tree.span(frame.node));
        } else if (frame.has_value) {
            for (self.context.memo_calls.items) |memo| {
                if (memo.callback != frame.node or self.context.renderOwner(memo.node) == null) continue;
                const parent = self.context.symbols.parentOf(self.context.outerExpression(memo.node)) orelse continue;
                if (self.context.tree.data(parent) != .expression_statement) continue;
                const callee = self.context.tree.data(memo.node).call_expression.callee;
                try core.addDiagnostic(self.allocator, self.diagnostics, .@"error", id, "The useMemo result is unused; use an effect or event handler for side effects.", self.context.tree.span(callee));
            }
        }
    }

    pub fn exit_function(self: *Visitor, _: ast.Function, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.pop() catch |err| {
            self.failure = err;
        };
    }

    pub fn exit_arrow_function_expression(self: *Visitor, _: ast.ArrowFunctionExpression, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.pop() catch |err| {
            self.failure = err;
        };
    }
};
