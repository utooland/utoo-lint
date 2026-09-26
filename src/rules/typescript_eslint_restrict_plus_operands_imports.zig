const std = @import("std");
const parser = @import("parser");
const semantic_compat = @import("../semantic_compat.zig");
const import_export_map = @import("import_export_map.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;
const max_source_size = 1024 * 1024;

pub const ImportedType = enum { unknown, any, number, string, bigint, boolean };

pub const Binding = struct {
    value: ImportedType = .unknown,
    return_type: ImportedType = .unknown,
};

pub const Map = std.AutoHashMap(parser.traverser.semantic.SymbolId, Binding);

/// Collect primitive annotations on named imports from neighboring source files.
/// The returned map owns no strings and only needs `deinit` from its caller.
pub fn collect(
    allocator: Allocator,
    io: std.Io,
    tree: *const ast.Tree,
    symbols: semantic_compat.SymbolTable,
    file_path: []const u8,
) Allocator.Error!Map {
    var map = Map.init(allocator);
    errdefer map.deinit();

    const program = switch (tree.data(tree.root)) {
        .program => |value| value,
        else => return map,
    };

    for (tree.extra(program.body)) |statement_index| {
        const declaration = switch (tree.data(statement_index)) {
            .import_declaration => |value| value,
            else => continue,
        };
        if (declaration.import_kind == .type) continue;
        var has_named_value = false;
        for (tree.extra(declaration.specifiers)) |specifier_index| {
            const specifier = switch (tree.data(specifier_index)) {
                .import_specifier => |value| value,
                else => continue,
            };
            if (specifier.import_kind != .type) {
                has_named_value = true;
                break;
            }
        }
        if (!has_named_value) continue;
        const source = import_export_map.importSource(tree, declaration) orelse continue;
        const path = try import_export_map.resolveRelativeModule(allocator, io, file_path, source) orelse continue;
        defer allocator.free(path);

        const contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_source_size)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        defer allocator.free(contents);

        var remote = parser.parse(allocator, contents, .{
            .source_type = ast.SourceType.fromPath(path),
            .lang = ast.Lang.fromPath(path),
        }) catch return error.OutOfMemory;
        defer remote.deinit();
        if (remote.hasErrors()) continue;

        for (tree.extra(declaration.specifiers)) |specifier_index| {
            const specifier = switch (tree.data(specifier_index)) {
                .import_specifier => |value| value,
                else => continue,
            };
            if (specifier.import_kind == .type) continue;
            const imported = moduleName(tree, specifier.imported) orelse continue;
            const symbol = symbols.symbolOf(specifier.local) orelse continue;
            const binding = bindingForExport(&remote, imported);
            if (binding.value == .unknown and binding.return_type == .unknown) continue;
            try map.put(symbol, binding);
        }
    }

    return map;
}

const Lookup = struct {
    count: usize = 0,
    binding: Binding = .{},

    fn add(self: *Lookup, binding: Binding) void {
        self.count += 1;
        if (self.count == 1) self.binding = binding;
    }

    fn result(self: Lookup) Binding {
        return if (self.count == 1) self.binding else .{};
    }
};

fn bindingForExport(tree: *const ast.Tree, exported_name: []const u8) Binding {
    const program = switch (tree.data(tree.root)) {
        .program => |value| value,
        else => return .{},
    };
    var found: Lookup = .{};

    for (tree.extra(program.body)) |statement_index| {
        const export_declaration = switch (tree.data(statement_index)) {
            .export_named_declaration => |value| value,
            else => continue,
        };
        if (export_declaration.export_kind == .type) continue;
        if (export_declaration.declaration != .null) {
            const direct = bindingForDeclaration(tree, export_declaration.declaration, exported_name);
            if (direct.count != 0) found.add(direct.result());
            continue;
        }
        // Re-exports need a separate module resolution step. They cannot be
        // assumed to have the annotation of a same-named local declaration.
        if (export_declaration.source != .null) continue;
        for (tree.extra(export_declaration.specifiers)) |specifier_index| {
            const specifier = switch (tree.data(specifier_index)) {
                .export_specifier => |value| value,
                else => continue,
            };
            if (specifier.export_kind == .type) continue;
            const exported = moduleName(tree, specifier.exported) orelse continue;
            if (!std.mem.eql(u8, exported, exported_name)) continue;
            const local = moduleName(tree, specifier.local) orelse continue;
            found.add(bindingForLocal(tree, local));
        }
    }

    return found.result();
}

fn bindingForLocal(tree: *const ast.Tree, local_name: []const u8) Binding {
    const program = switch (tree.data(tree.root)) {
        .program => |value| value,
        else => return .{},
    };
    var found: Lookup = .{};
    for (tree.extra(program.body)) |statement_index| {
        const declaration_index = switch (tree.data(statement_index)) {
            .export_named_declaration => |value| value.declaration,
            else => statement_index,
        };
        if (declaration_index == .null) continue;
        const candidate = bindingForDeclaration(tree, declaration_index, local_name);
        if (candidate.count != 0) {
            found.count += candidate.count;
            if (found.count == 1) found.binding = candidate.binding;
        }
    }
    return found.result();
}

fn bindingForDeclaration(tree: *const ast.Tree, declaration_index: ast.NodeIndex, name: []const u8) Lookup {
    var found: Lookup = .{};
    switch (tree.data(declaration_index)) {
        .function => |function| {
            const id = bindingName(tree, function.id) orelse return found;
            if (!std.mem.eql(u8, id, name)) return found;
            // An async function returns a Promise and a generator returns an
            // iterator, regardless of its annotated yielded value.
            found.add(.{ .return_type = if (function.async or function.generator) .unknown else annotationType(tree, function.return_type) });
        },
        .variable_declaration => |declaration| {
            if (declaration.kind != .@"const") return found;
            for (tree.extra(declaration.declarators)) |declarator_index| {
                const declarator = switch (tree.data(declarator_index)) {
                    .variable_declarator => |value| value,
                    else => continue,
                };
                const id = bindingName(tree, declarator.id) orelse continue;
                if (!std.mem.eql(u8, id, name)) continue;
                const binding = tree.data(declarator.id).binding_identifier;
                found.add(.{ .value = annotationType(tree, binding.type_annotation) });
            }
        },
        else => {},
    }
    return found;
}

fn annotationType(tree: *const ast.Tree, index: ast.NodeIndex) ImportedType {
    return annotationTypeAtDepth(tree, index, 0);
}

fn annotationTypeAtDepth(tree: *const ast.Tree, index: ast.NodeIndex, depth: usize) ImportedType {
    if (index == .null or depth >= 32) return .unknown;
    return switch (tree.data(index)) {
        .ts_type_annotation => |value| annotationTypeAtDepth(tree, value.type_annotation, depth + 1),
        .ts_parenthesized_type => |value| annotationTypeAtDepth(tree, value.type_annotation, depth + 1),
        .ts_any_keyword => .any,
        .ts_number_keyword => .number,
        .ts_string_keyword => .string,
        .ts_bigint_keyword => .bigint,
        .ts_boolean_keyword => .boolean,
        .ts_literal_type => |value| switch (tree.data(value.literal)) {
            .numeric_literal => .number,
            .string_literal, .template_literal => .string,
            .bigint_literal => .bigint,
            .boolean_literal => .boolean,
            else => .unknown,
        },
        else => .unknown,
    };
}

fn bindingName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .binding_identifier => |value| tree.string(value.name),
        else => null,
    };
}

fn moduleName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .identifier_name => |value| tree.string(value.name),
        .identifier_reference => |value| tree.string(value.name),
        .string_literal => |value| tree.string(value.value),
        else => null,
    };
}
