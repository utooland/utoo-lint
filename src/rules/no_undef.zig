const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-undef";

pub const Options = struct {
    check_typeof: bool = false,
    /// Globals declared through `languageOptions.globals`.
    configured_globals: ?*const core.ConfiguredGlobals = null,
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    try runWithOptions(allocator, diagnostics, tree, symbol_table, .{});
}

pub fn runWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    var allowed_typeof_refs = std.AutoHashMap(ast.NodeIndex, void).init(allocator);
    defer allowed_typeof_refs.deinit();

    if (!options.check_typeof) {
        var visitor = TypeofVisitor{ .allowed_refs = &allowed_typeof_refs };
        try traverser.basic.traverse(TypeofVisitor, tree, &visitor);
    }

    var iter = symbol_table.iterUnresolved();

    while (iter.next()) |entry| {
        const reference = entry.reference;
        if (reference.kind != .value) continue;
        if (tree.data(reference.node) == .jsx_identifier) continue;
        if (allowed_typeof_refs.contains(reference.node)) continue;

        const name = tree.string(reference.name);
        if (configuredGlobalState(options, name)) |state| {
            // `off` removes the global, so even a built-in name is undefined.
            if (state != .off) continue;
        } else if (core.isKnownGlobal(name)) continue;

        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            .warning,
            id,
            tree.span(reference.node),
            "'{s}' is not defined.",
            .{name},
        );
    }
}

fn configuredGlobalState(options: Options, name: []const u8) ?core.ConfiguredGlobalState {
    const globals = options.configured_globals orelse return null;
    return globals.lookup(name);
}

const TypeofVisitor = struct {
    allowed_refs: *std.AutoHashMap(ast.NodeIndex, void),

    pub fn enter_unary_expression(
        self: *TypeofVisitor,
        expression: ast.UnaryExpression,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (expression.operator != .typeof) return .proceed;

        const argument = unwrapTransparent(ctx.tree, expression.argument);
        if (argument == .null) return .proceed;
        if (ctx.tree.data(argument) != .identifier_reference) return .proceed;

        try self.allowed_refs.put(argument, {});
        return .proceed;
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
