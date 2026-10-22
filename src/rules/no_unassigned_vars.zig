const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-unassigned-vars";

const SymbolId = traverser.semantic.SymbolId;
const DeclSymbolMap = std.AutoHashMap(ast.NodeIndex, SymbolId);
const ReferenceLookup = std.AutoHashMap(ast.NodeIndex, SymbolId);

const Candidate = struct {
    symbol_id: SymbolId,
    node: ast.NodeIndex,
    name: []const u8,
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    var decl_symbols = DeclSymbolMap.init(allocator);
    defer decl_symbols.deinit();

    var symbol_iter = symbol_table.iterSymbols();
    while (symbol_iter.next()) |entry| {
        if (!isCandidateSymbol(entry.symbol.flags)) continue;
        for (symbol_table.symbolDecls(entry.id)) |decl| {
            try decl_symbols.put(decl, entry.id);
        }
    }

    var reference_lookup = try buildReferenceLookup(allocator, symbol_table);
    defer reference_lookup.deinit();

    const assigned_symbols = try allocator.alloc(bool, symbol_table.symbols.len);
    defer allocator.free(assigned_symbols);
    @memset(assigned_symbols, false);

    var candidates: std.ArrayList(Candidate) = .empty;
    defer candidates.deinit(allocator);

    var visitor = Visitor{
        .allocator = allocator,
        .decl_symbols = &decl_symbols,
        .reference_lookup = &reference_lookup,
        .symbol_table = symbol_table,
        .assigned_symbols = assigned_symbols,
        .candidates = &candidates,
    };
    try traverser.basic.traverse(Visitor, tree, &visitor);

    const read_symbols = try allocator.alloc(bool, symbol_table.symbols.len);
    defer allocator.free(read_symbols);
    @memset(read_symbols, false);

    var reference_iter = symbol_table.iterReferences();
    while (reference_iter.next()) |entry| {
        if (entry.reference.kind != .value) continue;
        const symbol_id = symbol_table.referenceSymbol(entry.id);
        if (symbol_id == .none) continue;
        read_symbols[@backingInt(symbol_id)] = true;
    }

    for (candidates.items) |candidate| {
        const symbol_index = @backingInt(candidate.symbol_id);
        if (assigned_symbols[symbol_index]) continue;
        if (!read_symbols[symbol_index]) continue;

        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            .warning,
            id,
            tree.span(candidate.node),
            "'{s}' is always 'undefined' because it's never assigned.",
            .{candidate.name},
        );
    }
}

const Visitor = struct {
    allocator: Allocator,
    decl_symbols: *const DeclSymbolMap,
    reference_lookup: *const ReferenceLookup,
    symbol_table: traverser.semantic.SymbolTable,
    assigned_symbols: []bool,
    candidates: *std.ArrayList(Candidate),

    pub fn enter_variable_declarator(
        self: *Visitor,
        declarator: ast.VariableDeclarator,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (declarator.init != .null) return .proceed;

        const declaration = switch (ctx.tree.data(ctx.path.ancestor(1) orelse return .proceed)) {
            .variable_declaration => |declaration| declaration,
            else => return .proceed,
        };
        if (declaration.kind == .@"const" or declaration.declare) return .proceed;

        const name = bindingIdentifierName(ctx.tree, declarator.id) orelse return .proceed;
        const symbol_id = self.decl_symbols.get(declarator.id) orelse return .proceed;
        const symbol = self.symbol_table.getSymbol(symbol_id);
        if (!isCandidateSymbol(symbol.flags)) return .proceed;

        try self.candidates.append(self.allocator, .{
            .symbol_id = symbol_id,
            .node = declarator.id,
            .name = name,
        });
        return .proceed;
    }

    pub fn enter_assignment_expression(
        self: *Visitor,
        expression: ast.AssignmentExpression,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) traverser.Action {
        self.collectWriteTarget(ctx.tree, expression.left);
        return .proceed;
    }

    pub fn enter_update_expression(
        self: *Visitor,
        expression: ast.UpdateExpression,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) traverser.Action {
        self.collectWriteTarget(ctx.tree, expression.argument);
        return .proceed;
    }

    fn collectWriteTarget(self: *Visitor, tree: *const ast.Tree, target: ast.NodeIndex) void {
        if (target == .null) return;

        switch (tree.data(unwrapTransparent(tree, target))) {
            .identifier_reference => {
                const symbol_id = self.reference_lookup.get(unwrapTransparent(tree, target)) orelse return;
                if (symbol_id == .none) return;
                const symbol_index = @backingInt(symbol_id);
                if (symbol_index < self.assigned_symbols.len) {
                    self.assigned_symbols[symbol_index] = true;
                }
            },
            .assignment_pattern => |pattern| self.collectWriteTarget(tree, pattern.left),
            .binding_rest_element => |element| self.collectWriteTarget(tree, element.argument),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    self.collectWriteTarget(tree, element);
                }
                self.collectWriteTarget(tree, pattern.rest);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    self.collectWriteTarget(tree, property.value);
                }
                self.collectWriteTarget(tree, pattern.rest);
            },
            else => {},
        }
    }
};

fn buildReferenceLookup(
    allocator: Allocator,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!ReferenceLookup {
    var lookup = ReferenceLookup.init(allocator);
    errdefer lookup.deinit();
    try lookup.ensureTotalCapacity(@intCast(symbol_table.references.len));

    var iter = symbol_table.iterReferences();
    while (iter.next()) |entry| {
        try lookup.put(entry.reference.node, symbol_table.referenceSymbol(entry.id));
    }

    return lookup;
}

fn isCandidateSymbol(flags: traverser.semantic.Symbol.Flags) bool {
    return (flags.function_scoped_var or flags.block_scoped_var) and
        !flags.const_var and
        !flags.ambient;
}

fn bindingIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .binding_identifier => |identifier| tree.string(identifier.name),
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
