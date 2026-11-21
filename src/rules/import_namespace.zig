const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const export_map = @import("import_export_map.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "import/namespace";

const max_source_size = 1024 * 1024;

const NamespaceImport = struct {
    source: []const u8,
    map: export_map.ExportMap,
};

const ReferenceLookup = std.AutoHashMap(ast.NodeIndex, traverser.semantic.SymbolId);

pub fn run(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    var namespaces = std.StringHashMap(NamespaceImport).init(allocator);
    defer {
        var iter = namespaces.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.map.deinit();
        }
        namespaces.deinit();
    }

    try collectNamespaceImports(allocator, io, diagnostics, tree, file_path, &namespaces);
    if (namespaces.count() == 0) return;

    var reference_lookup = try buildReferenceLookup(allocator, symbol_table);
    defer reference_lookup.deinit();

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .namespaces = &namespaces,
        .symbol_table = symbol_table,
        .reference_lookup = &reference_lookup,
    };
    try traverser.basic.traverse(Visitor, tree, &visitor);
}

fn collectNamespaceImports(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
    namespaces: *std.StringHashMap(NamespaceImport),
) Allocator.Error!void {
    const program = switch (tree.data(tree.root)) {
        .program => |program| program,
        else => return,
    };

    for (tree.extra(program.body)) |statement_index| {
        const declaration = switch (tree.data(statement_index)) {
            .import_declaration => |declaration| declaration,
            else => continue,
        };
        if (declaration.import_kind == .type) continue;
        const source = export_map.importSource(tree, declaration) orelse continue;

        const resolved = try export_map.resolveRelativeModule(allocator, io, file_path, source) orelse continue;
        defer allocator.free(resolved);
        const has_export_syntax = try moduleHasExportSyntax(allocator, io, resolved);

        for (tree.extra(declaration.specifiers)) |specifier_index| {
            const specifier = switch (tree.data(specifier_index)) {
                .import_namespace_specifier => |specifier| specifier,
                else => continue,
            };
            const local = bindingIdentifierName(tree, specifier.local) orelse continue;
            var remote = try export_map.readExportMap(allocator, io, resolved) orelse continue;
            errdefer remote.deinit();

            if (!hasAnyExport(&remote)) {
                if (!has_export_syntax) {
                    remote.deinit();
                    continue;
                }
                try core.addDiagnosticFmt(
                    allocator,
                    diagnostics,
                    .@"error",
                    id,
                    tree.span(specifier_index),
                    "No exported names found in module '{s}'.",
                    .{source},
                );
            }

            const gop = try namespaces.getOrPut(local);
            if (gop.found_existing) {
                gop.value_ptr.map.deinit();
            }
            gop.value_ptr.* = .{
                .source = source,
                .map = remote,
            };
        }
    }
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    namespaces: *const std.StringHashMap(NamespaceImport),
    symbol_table: traverser.semantic.SymbolTable,
    reference_lookup: *const ReferenceLookup,

    pub fn enter_member_expression(
        self: *Visitor,
        member: ast.MemberExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const object_name = identifierReferenceName(ctx.tree, unwrapTransparent(ctx.tree, member.object)) orelse return .proceed;
        const namespace = self.namespaceForReference(ctx.tree, unwrapTransparent(ctx.tree, member.object), object_name) orelse return .proceed;

        if (member.computed) {
            try core.addDiagnosticFmt(
                self.allocator,
                self.diagnostics,
                .@"error",
                id,
                ctx.tree.span(member.property),
                "Unable to validate computed reference to imported namespace '{s}'.",
                .{object_name},
            );
            return .proceed;
        }

        const property = memberPropertyName(ctx.tree, member) orelse return .proceed;
        if (!namespace.map.hasNamed(property)) {
            try self.reportMissing(ctx.tree, member.property, property, &.{object_name});
        }
        _ = index;
        return .proceed;
    }

    pub fn enter_assignment_expression(
        self: *Visitor,
        expression: ast.AssignmentExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const member = switch (ctx.tree.data(unwrapTransparent(ctx.tree, expression.left))) {
            .member_expression => |member| member,
            else => return .proceed,
        };
        const object_index = unwrapTransparent(ctx.tree, member.object);
        const object_name = identifierReferenceName(ctx.tree, object_index) orelse return .proceed;
        _ = self.namespaceForReference(ctx.tree, object_index, object_name) orelse return .proceed;

        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .@"error",
            id,
            ctx.tree.span(index),
            "Assignment to member of namespace '{s}'.",
            .{object_name},
        );
        return .proceed;
    }

    pub fn enter_variable_declarator(
        self: *Visitor,
        declarator: ast.VariableDeclarator,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const init_index = unwrapTransparent(ctx.tree, declarator.init);
        const namespace_name = identifierReferenceName(ctx.tree, init_index) orelse return .proceed;
        const namespace = self.namespaceForReference(ctx.tree, init_index, namespace_name) orelse return .proceed;

        const pattern = switch (ctx.tree.data(declarator.id)) {
            .object_pattern => |pattern| pattern,
            else => return .proceed,
        };

        for (ctx.tree.extra(pattern.properties)) |property_index| {
            const property = switch (ctx.tree.data(property_index)) {
                .binding_property => |property| property,
                else => continue,
            };
            const key = objectPatternIdentifierName(ctx.tree, property.key) orelse {
                try core.addDiagnostic(
                    self.allocator,
                    self.diagnostics,
                    .@"error",
                    id,
                    "Only destructure top-level names.",
                    ctx.tree.span(property_index),
                );
                continue;
            };
            if (!namespace.map.hasNamed(key)) {
                try self.reportMissing(ctx.tree, property_index, key, &.{namespace_name});
            }
        }

        return .proceed;
    }

    pub fn enter_jsx_opening_element(
        self: *Visitor,
        opening: ast.JSXOpeningElement,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const member = switch (ctx.tree.data(opening.name)) {
            .jsx_member_expression => |member| member,
            else => return .proceed,
        };
        const object_name = jsxIdentifierName(ctx.tree, member.object) orelse return .proceed;
        const namespace = self.namespaces.get(object_name) orelse return .proceed;
        const property = jsxIdentifierName(ctx.tree, member.property) orelse return .proceed;

        if (!namespace.map.hasNamed(property)) {
            try self.reportMissing(ctx.tree, member.property, property, &.{object_name});
        }
        return .proceed;
    }

    fn namespaceForReference(
        self: *Visitor,
        tree: *const ast.Tree,
        reference: ast.NodeIndex,
        name: []const u8,
    ) ?*const NamespaceImport {
        const namespace = self.namespaces.getPtr(name) orelse return null;
        const symbol_id = self.reference_lookup.get(reference) orelse return null;
        if (symbol_id == .none) return null;

        const symbol = self.symbol_table.getSymbol(symbol_id);
        if (!symbol.flags.import) return null;
        if (!std.mem.eql(u8, tree.string(symbol.name), name)) return null;

        return namespace;
    }

    fn reportMissing(
        self: *Visitor,
        tree: *const ast.Tree,
        node: ast.NodeIndex,
        property: []const u8,
        namepath: []const []const u8,
    ) Allocator.Error!void {
        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .@"error",
            id,
            tree.span(node),
            "'{s}' not found in imported namespace '{s}'.",
            .{ property, namepath[0] },
        );
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

fn hasAnyExport(map: *const export_map.ExportMap) bool {
    return map.has_default or map.named.count() > 0;
}

fn moduleHasExportSyntax(allocator: Allocator, io: std.Io, path: []const u8) Allocator.Error!bool {
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_source_size)) catch return false;
    defer allocator.free(source);

    var tree = try parser.parse(allocator, source, .{
        .source_type = ast.SourceType.fromPath(path),
        .lang = ast.Lang.fromPath(path),
    });
    defer tree.deinit();
    if (tree.hasErrors()) return false;

    const program = switch (tree.data(tree.root)) {
        .program => |program| program,
        else => return false,
    };

    for (tree.extra(program.body)) |statement_index| {
        switch (tree.data(statement_index)) {
            .export_default_declaration,
            .export_named_declaration,
            .export_all_declaration,
            .ts_namespace_export_declaration,
            => return true,
            else => {},
        }
    }
    return false;
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

fn memberPropertyName(tree: *const ast.Tree, member: ast.MemberExpression) ?[]const u8 {
    if (member.computed) return null;
    return switch (tree.data(member.property)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn objectPatternIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
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

fn jsxIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .jsx_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}
