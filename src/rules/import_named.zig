const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const export_map = @import("import_export_map.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "import/named";

pub fn run(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
) Allocator.Error!void {
    const program = switch (tree.data(tree.root)) {
        .program => |program| program,
        else => return,
    };

    for (tree.extra(program.body)) |statement_index| {
        switch (tree.data(statement_index)) {
            .import_declaration => |declaration| try checkImportDeclaration(
                allocator,
                io,
                diagnostics,
                tree,
                file_path,
                declaration,
            ),
            .export_named_declaration => |declaration| try checkExportNamedDeclaration(
                allocator,
                io,
                diagnostics,
                tree,
                file_path,
                declaration,
            ),
            else => {},
        }
    }
}

fn checkImportDeclaration(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
    declaration: ast.ImportDeclaration,
) Allocator.Error!void {
    if (declaration.import_kind == .type) return;
    const source = export_map.importSource(tree, declaration) orelse return;

    var remote = try readRemoteMap(allocator, io, file_path, source) orelse return;
    defer remote.deinit();

    for (tree.extra(declaration.specifiers)) |specifier_index| {
        const specifier = switch (tree.data(specifier_index)) {
            .import_specifier => |specifier| specifier,
            else => continue,
        };
        if (specifier.import_kind == .type) continue;
        const imported = moduleExportName(tree, specifier.imported) orelse continue;
        if (remote.hasNamed(imported)) continue;
        try reportMissing(allocator, diagnostics, tree, specifier.imported, imported, source);
    }
}

fn checkExportNamedDeclaration(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
    declaration: ast.ExportNamedDeclaration,
) Allocator.Error!void {
    if (declaration.export_kind == .type) return;
    const source = exportNamedSource(tree, declaration) orelse return;

    var remote = try readRemoteMap(allocator, io, file_path, source) orelse return;
    defer remote.deinit();

    for (tree.extra(declaration.specifiers)) |specifier_index| {
        const specifier = switch (tree.data(specifier_index)) {
            .export_specifier => |specifier| specifier,
            else => continue,
        };
        if (specifier.export_kind == .type) continue;
        const local = moduleExportName(tree, specifier.local) orelse continue;
        if (remote.hasNamed(local)) continue;
        try reportMissing(allocator, diagnostics, tree, specifier.local, local, source);
    }
}

fn readRemoteMap(
    allocator: Allocator,
    io: std.Io,
    file_path: []const u8,
    source: []const u8,
) Allocator.Error!?export_map.ExportMap {
    const resolved = try export_map.resolveRelativeModule(allocator, io, file_path, source) orelse return null;
    defer allocator.free(resolved);
    return export_map.readExportMapWithTypes(allocator, io, resolved, true);
}

fn reportMissing(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    node: ast.NodeIndex,
    name: []const u8,
    source: []const u8,
) Allocator.Error!void {
    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        .@"error",
        id,
        tree.span(node),
        "{s} not found in '{s}'",
        .{ name, source },
    );
}

fn exportNamedSource(tree: *const ast.Tree, declaration: ast.ExportNamedDeclaration) ?[]const u8 {
    if (declaration.source == .null) return null;
    return switch (tree.data(declaration.source)) {
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn moduleExportName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}
