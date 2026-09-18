const std = @import("std");
const parser = @import("parser");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const extensions = [_][]const u8{
    ".ts",
    ".cts",
    ".mts",
    ".tsx",
    ".js",
    ".jsx",
    ".mjs",
    ".cjs",
};

const max_source_size = 1024 * 1024;
const max_reexport_depth = 8;

pub const ExportMap = struct {
    allocator: Allocator,
    has_default: bool = false,
    include_types: bool = false,
    named: std.StringHashMap(void),

    pub fn init(allocator: Allocator) ExportMap {
        return .{
            .allocator = allocator,
            .named = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *ExportMap) void {
        var iter = self.named.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.named.deinit();
        self.* = undefined;
    }

    pub fn addNamed(self: *ExportMap, name: []const u8) Allocator.Error!void {
        if (std.mem.eql(u8, name, "default")) {
            self.has_default = true;
            return;
        }
        if (self.named.contains(name)) return;
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        try self.named.put(owned, {});
    }

    pub fn hasNamed(self: *const ExportMap, name: []const u8) bool {
        if (std.mem.eql(u8, name, "default")) return self.has_default;
        return self.named.contains(name);
    }
};

pub fn resolveRelativeModule(
    allocator: Allocator,
    io: std.Io,
    file_path: []const u8,
    source: []const u8,
) Allocator.Error!?[]const u8 {
    if (!isRelativeImport(source)) return null;

    const directory = std.fs.path.dirname(file_path) orelse ".";
    const imported_path = try std.fs.path.resolve(allocator, &.{ directory, source });
    errdefer allocator.free(imported_path);

    if (isFile(io, imported_path)) return imported_path;

    for (extensions) |extension| {
        const with_extension = try std.mem.concat(allocator, u8, &.{ imported_path, extension });
        if (isFile(io, with_extension)) {
            allocator.free(imported_path);
            return with_extension;
        }
        allocator.free(with_extension);
    }

    for (extensions) |extension| {
        const index_name = try std.mem.concat(allocator, u8, &.{ "index", extension });
        defer allocator.free(index_name);

        const index_path = try std.fs.path.join(allocator, &.{ imported_path, index_name });
        if (isFile(io, index_path)) {
            allocator.free(imported_path);
            return index_path;
        }
        allocator.free(index_path);
    }

    allocator.free(imported_path);
    return null;
}

pub fn readExportMap(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
) Allocator.Error!?ExportMap {
    return readExportMapWithTypes(allocator, io, path, false);
}

pub fn readExportMapWithTypes(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    include_types: bool,
) Allocator.Error!?ExportMap {
    var visited = std.StringHashMap(void).init(allocator);
    defer {
        var iter = visited.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        visited.deinit();
    }

    return readExportMapInner(allocator, io, path, &visited, 0, include_types);
}

fn readExportMapInner(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    visited: *std.StringHashMap(void),
    depth: usize,
    include_types: bool,
) Allocator.Error!?ExportMap {
    if (depth > max_reexport_depth) return null;
    if (visited.contains(path)) return null;

    const owned_path = try allocator.dupe(u8, path);
    defer allocator.free(owned_path);
    try visited.put(owned_path, {});
    // Track the active recursion path, allowing sibling reexports to revisit a module.
    defer _ = visited.remove(owned_path);

    const source = readFile(allocator, io, path) orelse return null;
    defer allocator.free(source);

    var tree = parser.parse(allocator, source, .{
        .source_type = ast.SourceType.fromPath(path),
        .lang = ast.Lang.fromPath(path),
    }) catch return null;
    defer tree.deinit();
    if (tree.hasErrors()) return null;

    const program = switch (tree.data(tree.root)) {
        .program => |program| program,
        else => return null,
    };

    var map = ExportMap.init(allocator);
    map.include_types = include_types;
    errdefer map.deinit();
    for (tree.extra(program.body)) |statement_index| {
        switch (tree.data(statement_index)) {
            .export_default_declaration => map.has_default = true,
            .export_named_declaration => |declaration| {
                if (declaration.export_kind == .type and !include_types) continue;
                try collectNamedDeclarationExports(allocator, &tree, declaration, &map, path, io, visited, depth);
                if (hasDefaultSpecifier(&tree, declaration)) {
                    if (exportNamedSource(&tree, declaration)) |reexport_source| {
                        if (try reexportHasDefault(allocator, io, path, reexport_source, visited, depth, include_types)) {
                            map.has_default = true;
                        }
                    } else {
                        map.has_default = true;
                    }
                }
            },
            .export_all_declaration => |declaration| {
                if (declaration.export_kind == .type and !include_types) continue;
                if (declaration.exported != .null) {
                    if (moduleExportName(&tree, declaration.exported)) |name| {
                        try map.addNamed(name);
                    }
                    continue;
                }
                try collectExportAll(allocator, io, path, &tree, declaration, &map, visited, depth);
            },
            else => {},
        }
    }

    return map;
}

fn reexportHasDefault(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    source: []const u8,
    visited: *std.StringHashMap(void),
    depth: usize,
    include_types: bool,
) Allocator.Error!bool {
    const resolved = try resolveRelativeModule(allocator, io, path, source) orelse return false;
    defer allocator.free(resolved);

    var map = try readExportMapInner(allocator, io, resolved, visited, depth + 1, include_types) orelse return false;
    defer map.deinit();
    return map.has_default;
}

fn reexportHasNamed(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    source: []const u8,
    name: []const u8,
    visited: *std.StringHashMap(void),
    depth: usize,
    include_types: bool,
) Allocator.Error!bool {
    const resolved = try resolveRelativeModule(allocator, io, path, source) orelse return false;
    defer allocator.free(resolved);

    var map = try readExportMapInner(allocator, io, resolved, visited, depth + 1, include_types) orelse return false;
    defer map.deinit();
    return map.hasNamed(name);
}

fn collectExportAll(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    tree: *const ast.Tree,
    declaration: ast.ExportAllDeclaration,
    map: *ExportMap,
    visited: *std.StringHashMap(void),
    depth: usize,
) Allocator.Error!void {
    const source = exportAllSource(tree, declaration) orelse return;
    const resolved = try resolveRelativeModule(allocator, io, path, source) orelse return;
    defer allocator.free(resolved);

    var remote = try readExportMapInner(allocator, io, resolved, visited, depth + 1, map.include_types) orelse return;
    defer remote.deinit();

    var iter = remote.named.iterator();
    while (iter.next()) |entry| {
        try map.addNamed(entry.key_ptr.*);
    }
}

fn collectNamedDeclarationExports(
    allocator: Allocator,
    tree: *const ast.Tree,
    declaration: ast.ExportNamedDeclaration,
    map: *ExportMap,
    path: []const u8,
    io: std.Io,
    visited: *std.StringHashMap(void),
    depth: usize,
) Allocator.Error!void {
    if (exportNamedSource(tree, declaration)) |source| {
        for (tree.extra(declaration.specifiers)) |specifier_index| {
            const specifier = switch (tree.data(specifier_index)) {
                .export_specifier => |specifier| specifier,
                else => continue,
            };
            if (specifier.export_kind == .type and !map.include_types) continue;
            const local = moduleExportName(tree, specifier.local) orelse continue;
            const exported = moduleExportName(tree, specifier.exported) orelse continue;
            if (try reexportHasNamed(allocator, io, path, source, local, visited, depth, map.include_types)) {
                try map.addNamed(exported);
            }
        }
        return;
    }

    for (tree.extra(declaration.specifiers)) |specifier_index| {
        const specifier = switch (tree.data(specifier_index)) {
            .export_specifier => |specifier| specifier,
            else => continue,
        };
        if (specifier.export_kind == .type and !map.include_types) continue;
        const exported = moduleExportName(tree, specifier.exported) orelse continue;
        try map.addNamed(exported);
    }

    if (declaration.declaration == .null) return;
    try collectDeclarationNames(allocator, tree, declaration.declaration, map);
}

fn collectDeclarationNames(
    allocator: Allocator,
    tree: *const ast.Tree,
    declaration_index: ast.NodeIndex,
    map: *ExportMap,
) Allocator.Error!void {
    switch (tree.data(declaration_index)) {
        .variable_declaration => |declaration| {
            for (tree.extra(declaration.declarators)) |declarator_index| {
                const declarator = switch (tree.data(declarator_index)) {
                    .variable_declarator => |declarator| declarator,
                    else => continue,
                };
                try collectBindingNames(allocator, tree, declarator.id, map);
            }
        },
        .function => |function| {
            const name = bindingIdentifierName(tree, function.id) orelse return;
            try map.addNamed(name);
        },
        .class => |class| {
            const name = bindingIdentifierName(tree, class.id) orelse return;
            try map.addNamed(name);
        },
        .ts_type_alias_declaration => |declaration| try map.addNamed(bindingIdentifierName(tree, declaration.id) orelse return),
        .ts_interface_declaration => |declaration| try map.addNamed(bindingIdentifierName(tree, declaration.id) orelse return),
        .ts_enum_declaration => |declaration| try map.addNamed(bindingIdentifierName(tree, declaration.id) orelse return),
        else => {},
    }
}

fn collectBindingNames(
    allocator: Allocator,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    map: *ExportMap,
) Allocator.Error!void {
    if (index == .null) return;
    switch (tree.data(index)) {
        .binding_identifier => |identifier| try map.addNamed(tree.string(identifier.name)),
        .assignment_pattern => |pattern| try collectBindingNames(allocator, tree, pattern.left, map),
        .binding_rest_element => |element| try collectBindingNames(allocator, tree, element.argument, map),
        .array_pattern => |pattern| {
            for (tree.extra(pattern.elements)) |element| {
                try collectBindingNames(allocator, tree, element, map);
            }
            try collectBindingNames(allocator, tree, pattern.rest, map);
        },
        .object_pattern => |pattern| {
            for (tree.extra(pattern.properties)) |property_index| {
                const property = switch (tree.data(property_index)) {
                    .binding_property => |property| property,
                    else => continue,
                };
                try collectBindingNames(allocator, tree, property.value, map);
            }
            try collectBindingNames(allocator, tree, pattern.rest, map);
        },
        else => {},
    }
}

fn hasDefaultSpecifier(tree: *const ast.Tree, declaration: ast.ExportNamedDeclaration) bool {
    for (tree.extra(declaration.specifiers)) |specifier_index| {
        const specifier = switch (tree.data(specifier_index)) {
            .export_specifier => |specifier| specifier,
            else => continue,
        };
        if (specifier.export_kind == .type) continue;
        const exported = moduleExportName(tree, specifier.exported) orelse continue;
        if (std.mem.eql(u8, exported, "default")) return true;
    }
    return false;
}

fn exportNamedSource(tree: *const ast.Tree, declaration: ast.ExportNamedDeclaration) ?[]const u8 {
    if (declaration.source == .null) return null;
    return switch (tree.data(declaration.source)) {
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn exportAllSource(tree: *const ast.Tree, declaration: ast.ExportAllDeclaration) ?[]const u8 {
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

fn bindingIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .binding_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

pub fn importSource(tree: *const ast.Tree, declaration: ast.ImportDeclaration) ?[]const u8 {
    return switch (tree.data(declaration.source)) {
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

pub fn isRelativeImport(source: []const u8) bool {
    return std.mem.startsWith(u8, source, "./") or
        std.mem.startsWith(u8, source, "../") or
        std.mem.eql(u8, source, ".") or
        std.mem.eql(u8, source, "..");
}

fn readFile(allocator: Allocator, io: std.Io, path: []const u8) ?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_source_size)) catch null;
}

fn isFile(io: std.Io, path: []const u8) bool {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}
