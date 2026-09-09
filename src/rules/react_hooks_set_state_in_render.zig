const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const helpers = @import("react_hooks_helpers.zig");
const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "react-hooks/set-state-in-render";

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
        const tree = self.context.tree;
        const owner = self.context.renderOwner(node) orelse return .proceed;
        const value = self.context.resolve(call.callee) orelse return .proceed;
        if (value.len != 1 or value.properties[0] != .index or value.properties[0].index != 1 or tree.data(value.node) != .call_expression) return .proceed;
        const hook = tree.data(value.node).call_expression;
        if (!self.context.isReactApi(hook.callee, "useState") or self.context.nearestFunction(value.node) != owner or !self.isUnconditional(node, owner)) return .proceed;
        try core.addDiagnostic(self.allocator, self.diagnostics, .@"error", id, "Calling a state setter unconditionally during render can cause an infinite render loop.", tree.span(node));
        return .proceed;
    }

    fn isUnconditional(self: *const Visitor, node: ast.NodeIndex, owner: ast.NodeIndex) bool {
        return self.isUnconditionalDepth(node, owner, undefined, 0);
    }

    fn isUnconditionalDepth(self: *const Visitor, node: ast.NodeIndex, owner: ast.NodeIndex, ancestors: [32]ast.NodeIndex, depth: usize) bool {
        if (depth >= ancestors.len) return false;
        for (ancestors[0..depth]) |ancestor| {
            if (ancestor == node) return false;
        }
        var path = ancestors;
        path[depth] = node;
        const tree = self.context.tree;
        var current = node;
        while (self.context.symbols.parentOf(current)) |parent| {
            if (parent == owner) return true;
            switch (tree.data(parent)) {
                .function, .arrow_function_expression => {
                    for (self.context.memo_calls.items) |memo| {
                        if (memo.callback == parent and self.isUnconditionalDepth(memo.node, owner, path, depth + 1)) return true;
                    }
                    const outer = self.context.outerExpression(parent);
                    const call_parent = self.context.symbols.parentOf(outer) orelse return false;
                    if (tree.data(call_parent) != .call_expression or tree.data(call_parent).call_expression.callee != outer) return false;
                },
                .if_statement => |s| if (s.@"test" != current) {
                    return false;
                },
                .conditional_expression => |e| if (e.@"test" != current) {
                    return false;
                },
                .logical_expression => |e| if (e.right == current) {
                    return false;
                },
                .while_statement,
                .do_while_statement,
                .for_statement,
                .for_in_statement,
                .for_of_statement,
                .switch_statement,
                .try_statement,
                .catch_clause,
                .assignment_pattern,
                .assignment_expression,
                .class,
                .property_definition,
                .chain_expression,
                => return false,
                .call_expression => |c| if (c.optional) {
                    return false;
                },
                .function_body => |body| if (self.hasPriorControlFlow(body.body, current)) {
                    return false;
                },
                .block_statement => |body| if (self.hasPriorControlFlow(body.body, current)) {
                    return false;
                },
                else => {},
            }
            current = parent;
        }
        return false;
    }

    // Explicit exits can bypass the setter. Loop-local break/continue still
    // reach the following statement; unknown try/switch completion stays conservative.
    fn hasPriorControlFlow(self: *const Visitor, statements: ast.IndexRange, current: ast.NodeIndex) bool {
        for (self.context.tree.extra(statements)) |statement| {
            if (statement == current) return false;
            if (self.mayExit(statement, 0, 0)) return true;
        }
        return false;
    }

    fn mayExit(self: *const Visitor, node: ast.NodeIndex, loops: usize, depth: usize) bool {
        if (node == .null) return false;
        if (depth >= 64) return true;
        return switch (self.context.tree.data(node)) {
            .return_statement, .throw_statement, .try_statement, .switch_statement, .labeled_statement => true,
            .break_statement => |s| loops == 0 or s.label != .null,
            .continue_statement => |s| loops == 0 or s.label != .null,
            .block_statement => |body| blk: {
                for (self.context.tree.extra(body.body)) |statement| {
                    if (self.mayExit(statement, loops, depth + 1)) break :blk true;
                }
                break :blk false;
            },
            .if_statement => |s| self.mayExit(s.consequent, loops, depth + 1) or self.mayExit(s.alternate, loops, depth + 1),
            .for_statement => |s| s.@"test" == .null or self.isAlwaysTrue(s.@"test") or self.mayExit(s.body, loops + 1, depth + 1),
            .while_statement => |s| self.isAlwaysTrue(s.@"test") or self.mayExit(s.body, loops + 1, depth + 1),
            .do_while_statement => |s| self.isAlwaysTrue(s.@"test") or self.mayExit(s.body, loops + 1, depth + 1),
            .for_in_statement => |s| self.mayExit(s.body, loops + 1, depth + 1),
            .for_of_statement => |s| self.mayExit(s.body, loops + 1, depth + 1),
            else => false,
        };
    }

    fn isAlwaysTrue(self: *const Visitor, node: ast.NodeIndex) bool {
        return switch (self.context.tree.data(helpers.unwrap(self.context.tree, node))) {
            .boolean_literal => |literal| literal.value,
            else => false,
        };
    }
};
