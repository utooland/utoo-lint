const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "import/no-duplicates";

pub const Options = struct {
    consider_query_string: bool = false,
};

const ImportGroup = enum {
    value,
    namespace,
    default_type,
    named_type,
    namespace_type,
};

const SeenImport = struct {
    source: []const u8,
    key: []const u8,
    group: ImportGroup,
    source_node: ast.NodeIndex,
    reported: bool = false,
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    program: ast.Program,
) Allocator.Error!void {
    try checkWithOptions(allocator, diagnostics, tree, program, .{});
}

pub fn checkWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    program: ast.Program,
    options: Options,
) Allocator.Error!void {
    var seen: std.ArrayList(SeenImport) = .empty;
    defer seen.deinit(allocator);

    for (tree.extra(program.body)) |statement_index| {
        const declaration = switch (tree.data(statement_index)) {
            .import_declaration => |declaration| declaration,
            else => continue,
        };
        const source = importSource(tree, declaration) orelse continue;
        const key = importKey(source, options);
        const group = importGroup(tree, declaration);

        if (findSeen(seen.items, key, group)) |seen_index| {
            if (!seen.items[seen_index].reported) {
                try addDiagnostic(allocator, diagnostics, tree, seen.items[seen_index].source_node, seen.items[seen_index].source);
                seen.items[seen_index].reported = true;
            }
            try addDiagnostic(allocator, diagnostics, tree, declaration.source, source);
            continue;
        }

        try seen.append(allocator, .{
            .source = source,
            .key = key,
            .group = group,
            .source_node = declaration.source,
        });
    }
}

fn addDiagnostic(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    source: []const u8,
) Allocator.Error!void {
    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        .@"error",
        id,
        tree.span(index),
        "'{s}' imported multiple times.",
        .{source},
    );
}

fn importSource(tree: *const ast.Tree, declaration: ast.ImportDeclaration) ?[]const u8 {
    return switch (tree.data(declaration.source)) {
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn importKey(source: []const u8, options: Options) []const u8 {
    if (options.consider_query_string) return source;
    const query_index = std.mem.indexOfScalar(u8, source, '?') orelse return source;
    return source[0..query_index];
}

fn importGroup(tree: *const ast.Tree, declaration: ast.ImportDeclaration) ImportGroup {
    const specifiers = tree.extra(declaration.specifiers);
    if (declaration.import_kind == .type) {
        if (specifiers.len > 0 and tree.data(specifiers[0]) == .import_default_specifier) return .default_type;
        // A type namespace import cannot be merged with a named type import.
        if (specifiers.len > 0 and tree.data(specifiers[0]) == .import_namespace_specifier) return .namespace_type;
        return .named_type;
    }

    // Keep inline type imports in the named type group, including mixed imports.
    // Namespace declarations cannot be merged into named imports.
    for (specifiers) |specifier_index| {
        const specifier = switch (tree.data(specifier_index)) {
            .import_specifier => |specifier| specifier,
            else => continue,
        };
        if (specifier.import_kind == .type) return .named_type;
    }
    for (specifiers) |specifier_index| {
        if (tree.data(specifier_index) == .import_namespace_specifier) return .namespace;
    }
    return .value;
}

fn findSeen(items: []const SeenImport, key: []const u8, group: ImportGroup) ?usize {
    for (items, 0..) |item, i| {
        if (item.group != group) continue;
        if (std.mem.eql(u8, item.key, key)) return i;
    }
    return null;
}
