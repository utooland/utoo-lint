const std = @import("std");
const parser = @import("parser");

const ast = parser.ast;
const yuku_semantic = parser.traverser.semantic;

pub const ScopeTree = struct {
    scopes: []const yuku_semantic.Scope,

    pub fn init(scopes: yuku_semantic.ScopeTree) ScopeTree {
        return .{ .scopes = scopes.list };
    }

    pub inline fn getScope(self: ScopeTree, id: yuku_semantic.ScopeId) yuku_semantic.Scope {
        return self.scopes[@intFromEnum(id)];
    }
};

pub const Reference = struct {
    name: ast.String,
    scope: yuku_semantic.ScopeId,
    node: ast.NodeIndex,
    kind: Kind,
    space: yuku_semantic.Reference.Space,
    type_position: bool,

    pub const Kind = enum(u1) { value, type };

    fn fromYuku(reference: yuku_semantic.Reference) Reference {
        return .{
            .name = reference.name,
            .scope = reference.scope,
            .node = reference.node,
            .kind = switch (reference.flags.space) {
                .type => .type,
                .namespace, .any => if (reference.flags.type_position) .type else .value,
                .value, .typeof => .value,
            },
            .space = reference.flags.space,
            .type_position = reference.flags.type_position,
        };
    }
};

pub const SymbolTable = struct {
    tree: *const ast.Tree,
    model: yuku_semantic.Semantic,
    symbols: []const yuku_semantic.Symbol,
    references: []const yuku_semantic.Reference,

    pub fn init(tree: *const ast.Tree, model: yuku_semantic.Semantic) SymbolTable {
        return .{
            .tree = tree,
            .model = model,
            .symbols = model.symbols,
            .references = model.references,
        };
    }

    pub fn resolveAll(_: *SymbolTable, _: ScopeTree) !void {}

    pub inline fn getSymbol(self: SymbolTable, id: yuku_semantic.SymbolId) yuku_semantic.Symbol {
        return self.model.symbol(id);
    }

    pub inline fn getReference(self: SymbolTable, id: yuku_semantic.ReferenceId) Reference {
        return Reference.fromYuku(self.model.reference(id));
    }

    pub inline fn scopeOf(self: SymbolTable, node: ast.NodeIndex) yuku_semantic.ScopeId {
        return self.model.scopeOf(node);
    }

    pub inline fn symbolOf(self: SymbolTable, node: ast.NodeIndex) ?yuku_semantic.SymbolId {
        return self.model.symbolOf(node);
    }

    pub inline fn parentOf(self: SymbolTable, node: ast.NodeIndex) ?ast.NodeIndex {
        return self.model.parentOf(node);
    }

    pub inline fn isWriteReference(self: SymbolTable, id: yuku_semantic.ReferenceId) bool {
        return self.model.reference(id).flags.write;
    }

    pub fn iterSymbols(self: SymbolTable) yuku_semantic.Semantic.SymbolIterator {
        return self.model.iterSymbols();
    }

    pub fn iterReferences(self: SymbolTable) ReferenceIterator {
        return .{ .references = self.references };
    }

    pub fn iterUnresolved(self: SymbolTable) UnresolvedIterator {
        return .{ .references = self.references };
    }

    pub fn findInScope(self: SymbolTable, scope: yuku_semantic.ScopeId, name: []const u8) ?yuku_semantic.SymbolId {
        var bindings = self.model.bindings(scope);
        while (bindings.next()) |id| {
            if (std.mem.eql(u8, self.tree.string(self.model.symbol(id).name), name)) return id;
        }
        return null;
    }

    pub fn resolve(
        self: SymbolTable,
        _: ScopeTree,
        scope: yuku_semantic.ScopeId,
        name: []const u8,
    ) ?yuku_semantic.SymbolId {
        return self.model.lookup(scope, name, .any);
    }

    pub inline fn referenceSymbol(self: SymbolTable, id: yuku_semantic.ReferenceId) yuku_semantic.SymbolId {
        return self.model.reference(id).symbol;
    }

    pub inline fn isUnresolvedReference(self: SymbolTable, node: ast.NodeIndex) bool {
        const reference = self.model.referenceOf(node) orelse return false;
        return self.model.reference(reference).symbol == .none;
    }

    pub inline fn symbolDecls(self: SymbolTable, id: yuku_semantic.SymbolId) []const ast.NodeIndex {
        return self.model.decls(id);
    }

    pub fn symbolUses(self: SymbolTable, id: yuku_semantic.SymbolId) UseIterator {
        return .{ .references = self.references, .ids = self.model.uses(id) };
    }

    pub inline fn isReferenced(self: SymbolTable, id: yuku_semantic.SymbolId) bool {
        return self.model.uses(id).len > 0;
    }

    pub const ReferenceEntry = struct {
        id: yuku_semantic.ReferenceId,
        reference: Reference,
    };

    pub const ReferenceIterator = struct {
        references: []const yuku_semantic.Reference,
        index: u32 = 0,

        pub fn next(self: *ReferenceIterator) ?ReferenceEntry {
            if (self.index >= self.references.len) return null;
            const index = self.index;
            self.index += 1;
            return .{
                .id = @enumFromInt(index),
                .reference = Reference.fromYuku(self.references[index]),
            };
        }
    };

    pub const UnresolvedIterator = struct {
        references: []const yuku_semantic.Reference,
        index: u32 = 0,

        pub fn next(self: *UnresolvedIterator) ?ReferenceEntry {
            while (self.index < self.references.len) {
                const index = self.index;
                self.index += 1;
                const reference = self.references[index];
                if (reference.symbol == .none) {
                    return .{
                        .id = @enumFromInt(index),
                        .reference = Reference.fromYuku(reference),
                    };
                }
            }
            return null;
        }
    };

    pub const UseIterator = struct {
        references: []const yuku_semantic.Reference,
        ids: []const yuku_semantic.ReferenceId,
        index: u32 = 0,

        pub fn next(self: *UseIterator) ?ast.NodeIndex {
            if (self.index >= self.ids.len) return null;
            const reference = self.references[@intFromEnum(self.ids[self.index])];
            self.index += 1;
            return reference.node;
        }
    };
};

pub const Result = struct {
    scope_tree: ScopeTree,
    symbol_table: SymbolTable,

    pub fn init(tree: *const ast.Tree, model: yuku_semantic.Semantic) Result {
        return .{
            .scope_tree = ScopeTree.init(model.scopes),
            .symbol_table = SymbolTable.init(tree, model),
        };
    }
};

const CompatReference = Reference;
const CompatScopeTree = ScopeTree;
const CompatSymbolTable = SymbolTable;
const CompatResult = Result;

/// Transitional facade for rules that still use Yuku's pre-0.6 semantic API.
/// Traversal types that did not change are forwarded directly to Yuku.
pub const traverser = struct {
    pub const Action = parser.traverser.Action;
    pub const basic = parser.traverser.basic;
    pub const scoped = parser.traverser.scoped;

    pub const semantic = struct {
        pub const Ctx = yuku_semantic.Ctx;
        pub const Scope = yuku_semantic.Scope;
        pub const ScopeId = yuku_semantic.ScopeId;
        pub const Symbol = yuku_semantic.Symbol;
        pub const SymbolId = yuku_semantic.SymbolId;
        pub const ReferenceId = yuku_semantic.ReferenceId;
        pub const Reference = CompatReference;
        pub const ScopeTree = CompatScopeTree;
        pub const SymbolTable = CompatSymbolTable;
        pub const Result = CompatResult;
    };
};

test "adapts Yuku's space-aware symbol resolution" {
    var tree = try parser.parse(
        std.testing.allocator,
        "type Value = string; { const Value = 1; let item: Value; }",
        .{ .lang = .ts },
    );
    defer tree.deinit();

    const model = try parser.semantic.analyze(&tree);
    const result = Result.init(&tree, model);
    var references = result.symbol_table.iterReferences();

    const entry = references.next().?;
    try std.testing.expectEqualStrings("Value", tree.string(entry.reference.name));
    try std.testing.expectEqual(Reference.Kind.type, entry.reference.kind);
    const symbol_id = result.symbol_table.referenceSymbol(entry.id);
    try std.testing.expect(symbol_id != .none);
    try std.testing.expect(model.symbol(symbol_id).flags.type_alias);
    try std.testing.expectEqual(null, references.next());
}

test "distinguishes runtime aliases from erased exports and value queries" {
    const source =
        \\namespace NS { export const Value = 1; export interface Item {} }
        \\import Alias = NS.Value;
        \\import type TypeAlias = NS.Item;
        \\export type { Alias };
        \\export { type TypeAlias };
        \\type Query = typeof Alias;
    ;
    var tree = try parser.parse(std.testing.allocator, source, .{ .lang = .ts });
    defer tree.deinit();

    const model = try parser.semantic.analyze(&tree);
    const result = Result.init(&tree, model);
    var references = result.symbol_table.iterReferences();
    const Expected = struct {
        name: []const u8,
        kind: Reference.Kind,
        type_position: bool,
    };
    const expected = [_]Expected{
        .{ .name = "NS", .kind = .value, .type_position = false },
        .{ .name = "NS", .kind = .type, .type_position = true },
        .{ .name = "Alias", .kind = .type, .type_position = true },
        .{ .name = "TypeAlias", .kind = .type, .type_position = true },
        .{ .name = "Alias", .kind = .value, .type_position = true },
    };
    for (expected) |item| {
        const entry = references.next().?;
        try std.testing.expectEqualStrings(item.name, tree.string(entry.reference.name));
        try std.testing.expectEqual(item.kind, entry.reference.kind);
        try std.testing.expectEqual(item.type_position, entry.reference.type_position);
    }
    try std.testing.expectEqual(null, references.next());
}
