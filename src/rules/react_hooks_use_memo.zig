const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const helpers = @import("react_hooks_helpers.zig");
const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "react-hooks/use-memo";

pub fn run(allocator: Allocator, diagnostics: *core.DiagnosticList, tree: *const ast.Tree, symbols: helpers.SymbolTable) Allocator.Error!void {
    var visitor = Visitor{ .allocator = allocator, .diagnostics = diagnostics, .context = try helpers.Context.init(allocator, tree, symbols) };
    defer visitor.context.memo_calls.deinit(allocator);
    try traverser.basic.traverse(Visitor, tree, &visitor);
    var references = symbols.iterReferences();
    while (references.next()) |entry| {
        if (!symbols.isWriteReference(entry.id)) continue;
        const function = visitor.context.nearestFunction(entry.reference.node) orelse continue;
        if (!visitor.isMemoCallback(function)) continue;
        const symbol = symbols.referenceSymbol(entry.id);
        if (symbol == .none) continue;
        const declarations = symbols.symbolDecls(symbol);
        if (declarations.len == 0) continue;
        var outside = true;
        for (declarations) |declaration| {
            if (visitor.context.nearestFunction(declaration) == function) outside = false;
        }
        if (outside) try visitor.report(entry.reference.node, "useMemo callbacks must not reassign variables declared outside the callback.");
    }
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    context: helpers.Context,

    fn isMemoCallback(self: *const Visitor, node: ast.NodeIndex) bool {
        return self.context.isMemoCallback(node);
    }

    fn check(self: *Visitor, node: ast.NodeIndex, params_node: ast.NodeIndex, async_or_generator: bool) Allocator.Error!traverser.Action {
        if (!self.isMemoCallback(node)) return .proceed;
        const params = self.context.tree.data(params_node).formal_parameters;
        if (params.items.len > 0 or params.rest != .null) {
            try self.report(params_node, "useMemo callbacks must not accept parameters; capture the values needed for the calculation instead.");
        }
        if (async_or_generator) try self.report(node, "useMemo callbacks must be synchronous and must not be async or generator functions.");
        return .proceed;
    }

    pub fn enter_function(self: *Visitor, function: ast.Function, node: ast.NodeIndex, _: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        return self.check(node, function.params, function.async or function.generator);
    }

    pub fn enter_arrow_function_expression(self: *Visitor, arrow: ast.ArrowFunctionExpression, node: ast.NodeIndex, _: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        return self.check(node, arrow.params, arrow.async);
    }

    fn report(self: *Visitor, node: ast.NodeIndex, message: []const u8) Allocator.Error!void {
        try core.addDiagnostic(self.allocator, self.diagnostics, .@"error", id, message, self.context.tree.span(node));
    }
};
