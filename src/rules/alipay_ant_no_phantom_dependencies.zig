const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "@alipay/ant/no-phantom-dependencies";

const max_config_file_size = 1024 * 1024;
const ReferenceLookup = std.AutoHashMap(ast.NodeIndex, traverser.semantic.SymbolId);

const DependencyConfig = struct {
    allocator: Allocator,
    dependencies: std.StringHashMap(void),
    aliases: std.ArrayList([]const u8),

    fn deinit(self: *DependencyConfig) void {
        var iter = self.dependencies.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.dependencies.deinit();

        for (self.aliases.items) |alias| {
            self.allocator.free(alias);
        }
        self.aliases.deinit(self.allocator);
    }
};

pub fn run(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    const config: core.NoPhantomDependenciesConfig = .{};
    return runWithOptions(allocator, io, diagnostics, tree, file_path, symbol_table, &config);
}

pub fn runWithOptions(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
    symbol_table: traverser.semantic.SymbolTable,
    options: *const core.NoPhantomDependenciesConfig,
) Allocator.Error!void {
    const project_root = try findProjectRoot(allocator, io, file_path);
    defer allocator.free(project_root);

    const lerna_path = try std.fs.path.join(allocator, &.{ project_root, "lerna.json" });
    defer allocator.free(lerna_path);
    if (exists(io, lerna_path)) return;

    var config = try readDependencyConfig(allocator, io, project_root, options);
    defer config.deinit();

    var reference_lookup = try buildReferenceLookup(allocator, symbol_table);
    defer reference_lookup.deinit();

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .config = &config,
        .reference_lookup = &reference_lookup,
    };

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    config: *const DependencyConfig,
    reference_lookup: *const ReferenceLookup,

    pub fn enter_program(
        self: *Visitor,
        program: ast.Program,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        for (ctx.tree.extra(program.body)) |statement_index| {
            switch (ctx.tree.data(statement_index)) {
                .import_declaration => |declaration| {
                    try self.checkImportString(ctx.tree, statement_index, importSource(ctx.tree, declaration));
                },
                .export_named_declaration => |declaration| {
                    try self.checkImportString(ctx.tree, statement_index, exportNamedSource(ctx.tree, declaration));
                },
                .export_all_declaration => |declaration| {
                    try self.checkImportString(ctx.tree, statement_index, exportAllSource(ctx.tree, declaration));
                },
                else => {},
            }
        }

        return .proceed;
    }

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (!self.isGlobalRequireReference(ctx.tree, call.callee)) return .proceed;
        const source = requireSource(ctx.tree, call) orelse return .proceed;
        try self.checkImportString(ctx.tree, index, source);
        return .proceed;
    }

    fn isGlobalRequireReference(self: *Visitor, tree: *const ast.Tree, index: ast.NodeIndex) bool {
        const name = identifierReferenceName(tree, unwrapTransparent(tree, index)) orelse return false;
        if (!std.mem.eql(u8, name, "require")) return false;
        return (self.reference_lookup.get(unwrapTransparent(tree, index)) orelse .none) == .none;
    }

    fn checkImportString(
        self: *Visitor,
        tree: *const ast.Tree,
        node_index: ast.NodeIndex,
        import_string: ?[]const u8,
    ) Allocator.Error!void {
        const package_name = missingDependency(self.config, import_string) orelse return;
        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .warning,
            id,
            tree.span(node_index),
            "检测到未在 package.json 中声明的依赖: {s}",
            .{package_name},
        );
    }
};

fn readDependencyConfig(
    allocator: Allocator,
    io: std.Io,
    project_root: []const u8,
    options: *const core.NoPhantomDependenciesConfig,
) Allocator.Error!DependencyConfig {
    var dependencies = std.StringHashMap(void).init(allocator);
    errdefer dependencies.deinit();

    var aliases: std.ArrayList([]const u8) = .empty;
    errdefer aliases.deinit(allocator);

    for (node_dependencies) |dependency| {
        try addDependency(allocator, &dependencies, dependency);
    }
    try addDependency(allocator, &dependencies, "@example/page-runtime");
    for (0..options.external_dependencies.count) |index| {
        try addDependency(allocator, &dependencies, options.external_dependencies.at(index));
    }
    for (0..options.external_alias.count) |index| {
        try addAlias(allocator, &aliases, options.external_alias.at(index));
    }

    const package_path = try std.fs.path.join(allocator, &.{ project_root, "package.json" });
    defer allocator.free(package_path);
    try readPackageJson(allocator, io, package_path, &dependencies);

    const tsconfig_path = try std.fs.path.join(allocator, &.{ project_root, "tsconfig.json" });
    defer allocator.free(tsconfig_path);
    try readTsConfigAliases(allocator, io, tsconfig_path, &aliases);

    try readFrameworkConfig(allocator, io, project_root, "appfw", &dependencies, &aliases);
    try readFrameworkConfig(allocator, io, project_root, "smallfish", &dependencies, &aliases);

    return .{
        .allocator = allocator,
        .dependencies = dependencies,
        .aliases = aliases,
    };
}

fn addDependency(
    allocator: Allocator,
    dependencies: *std.StringHashMap(void),
    name: []const u8,
) Allocator.Error!void {
    if (dependencies.contains(name)) return;
    const owned = try allocator.dupe(u8, name);
    errdefer allocator.free(owned);
    try dependencies.put(owned, {});
}

fn readPackageJson(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    dependencies: *std.StringHashMap(void),
) Allocator.Error!void {
    const source = readConfigFile(allocator, io, path) orelse return;
    defer allocator.free(source);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch return;
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return,
    };

    const dependency_keys = [_][]const u8{
        "devDependencies",
        "peerDependencies",
        "dependencies",
        "optionalDependencies",
    };

    for (dependency_keys) |key| {
        const value = root.get(key) orelse continue;
        const object = switch (value) {
            .object => |object| object,
            else => continue,
        };

        var iter = object.iterator();
        while (iter.next()) |entry| {
            try addDependency(allocator, dependencies, entry.key_ptr.*);
        }
    }
}

fn addAlias(
    allocator: Allocator,
    aliases: *std.ArrayList([]const u8),
    name: []const u8,
) Allocator.Error!void {
    const trimmed = if (std.mem.endsWith(u8, name, "$")) name[0 .. name.len - 1] else name;
    for (aliases.items) |alias| {
        if (std.mem.eql(u8, alias, trimmed)) return;
    }
    try aliases.append(allocator, try allocator.dupe(u8, trimmed));
}

fn readTsConfigAliases(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    aliases: *std.ArrayList([]const u8),
) Allocator.Error!void {
    const source = readConfigFile(allocator, io, path) orelse return;
    defer allocator.free(source);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch return;
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return,
    };
    const compiler_options = switch (root.get("compilerOptions") orelse return) {
        .object => |object| object,
        else => return,
    };
    const paths = switch (compiler_options.get("paths") orelse return) {
        .object => |object| object,
        else => return,
    };

    var iter = paths.iterator();
    while (iter.next()) |entry| {
        try addAlias(allocator, aliases, entry.key_ptr.*);
    }
}

fn readFrameworkConfig(
    allocator: Allocator,
    io: std.Io,
    project_root: []const u8,
    framework: []const u8,
    dependencies: *std.StringHashMap(void),
    aliases: *std.ArrayList([]const u8),
) Allocator.Error!void {
    const js_name = try std.fmt.allocPrint(allocator, "{s}.config.js", .{framework});
    defer allocator.free(js_name);
    const ts_name = try std.fmt.allocPrint(allocator, "{s}.config.ts", .{framework});
    defer allocator.free(ts_name);
    const js_path = try std.fs.path.join(allocator, &.{ project_root, js_name });
    defer allocator.free(js_path);
    const ts_path = try std.fs.path.join(allocator, &.{ project_root, ts_name });
    defer allocator.free(ts_path);

    var source: ?[]u8 = readConfigFile(allocator, io, js_path);
    var source_path = js_path;
    if (readConfigFile(allocator, io, ts_path)) |ts_source| {
        if (source) |js_source| allocator.free(js_source);
        source = ts_source;
        source_path = ts_path;
    }

    const config_source = source orelse return;
    defer allocator.free(config_source);
    if (config_source.len == 0) return;

    try addDependency(allocator, dependencies, "react");
    try addDependency(allocator, dependencies, "react-dom");
    try addDependency(allocator, dependencies, "antd-mobile");

    var tree = parser.parse(allocator, config_source, .{
        .source_type = .script,
        .lang = ast.Lang.fromPath(source_path),
    }) catch return;
    defer tree.deinit();

    var visitor = AppfwAliasVisitor{
        .allocator = allocator,
        .aliases = aliases,
    };
    try traverser.basic.traverse(AppfwAliasVisitor, &tree, &visitor);
}

const AppfwAliasVisitor = struct {
    allocator: Allocator,
    aliases: *std.ArrayList([]const u8),

    pub fn enter_object_property(
        self: *AppfwAliasVisitor,
        property: ast.ObjectProperty,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const key = nodeName(ctx.tree, property.key) orelse return .proceed;
        if (!std.mem.eql(u8, key, "alias")) return .proceed;

        const alias_object = switch (ctx.tree.data(property.value)) {
            .object_expression => |object| object,
            else => return .proceed,
        };

        for (ctx.tree.extra(alias_object.properties)) |item| {
            const alias_property = switch (ctx.tree.data(item)) {
                .object_property => |object_property| object_property,
                else => continue,
            };

            if (nodeName(ctx.tree, alias_property.key)) |name| {
                try addAlias(self.allocator, self.aliases, name);
            }
            if (nodeName(ctx.tree, alias_property.value)) |name| {
                try addAlias(self.allocator, self.aliases, name);
            }
        }

        return .proceed;
    }
};

fn nodeName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        .identifier_reference => |identifier| tree.string(identifier.name),
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn readConfigFile(allocator: Allocator, io: std.Io, path: []const u8) ?[]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const directory_path = std.fs.path.dirname(path) orelse return null;
        const basename = std.fs.path.basename(path);
        var directory = std.Io.Dir.openDirAbsolute(io, directory_path, .{}) catch return null;
        defer directory.close(io);
        return directory.readFileAlloc(io, basename, allocator, .limited(max_config_file_size)) catch null;
    }

    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_config_file_size)) catch null;
}

fn missingDependency(config: *const DependencyConfig, import_string: ?[]const u8) ?[]const u8 {
    const source = import_string orelse return null;
    if (source.len == 0) return null;

    for (config.aliases.items) |alias| {
        if (std.mem.startsWith(u8, source, alias)) return null;
    }

    const package_name = parsePackageNameFromImport(source) orelse return null;
    if (config.dependencies.contains(package_name)) return null;
    return package_name;
}

fn parsePackageNameFromImport(import_string: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, import_string, "~") or
        std.mem.startsWith(u8, import_string, "/") or
        std.mem.startsWith(u8, import_string, "#") or
        std.mem.startsWith(u8, import_string, "@/") or
        std.mem.startsWith(u8, import_string, "./") or
        std.mem.startsWith(u8, import_string, "../") or
        std.mem.startsWith(u8, import_string, "@appfw/") or
        std.mem.startsWith(u8, import_string, "appfw:") or
        std.mem.startsWith(u8, import_string, "appmini:") or
        std.mem.startsWith(u8, import_string, "@smallfish/") or
        std.mem.startsWith(u8, import_string, "smallfish:") or
        std.mem.startsWith(u8, import_string, "@example-fw/") or
        std.mem.eql(u8, import_string, "@example-runtime") or
        std.mem.startsWith(u8, import_string, "@example-runtime/") or
        std.mem.eql(u8, import_string, ".") or
        std.mem.eql(u8, import_string, ".."))
    {
        return null;
    }

    if (std.mem.startsWith(u8, import_string, "@")) {
        const scope_end = std.mem.indexOfScalarPos(u8, import_string, 1, '/') orelse return import_string;
        const name_end = std.mem.indexOfScalarPos(u8, import_string, scope_end + 1, '/') orelse import_string.len;
        return import_string[0..name_end];
    }

    const end = std.mem.indexOfScalar(u8, import_string, '/') orelse import_string.len;
    return import_string[0..end];
}

fn findProjectRoot(allocator: Allocator, io: std.Io, file_path: []const u8) Allocator.Error![]u8 {
    const absolute_file = if (std.fs.path.isAbsolute(file_path))
        try allocator.dupe(u8, file_path)
    else blk: {
        const cwd = std.process.currentPathAlloc(io, allocator) catch {
            break :blk try std.fs.path.resolve(allocator, &.{file_path});
        };
        defer allocator.free(cwd);
        break :blk try std.fs.path.resolve(allocator, &.{ cwd, file_path });
    };
    defer allocator.free(absolute_file);

    var current = try allocator.dupe(u8, std.fs.path.dirname(absolute_file) orelse ".");
    errdefer allocator.free(current);

    while (true) {
        const package_path = try std.fs.path.join(allocator, &.{ current, "package.json" });
        defer allocator.free(package_path);
        if (exists(io, package_path)) return current;

        const parent = std.fs.path.dirname(current) orelse return current;
        if (std.mem.eql(u8, parent, current)) return current;

        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }
}

fn exists(io: std.Io, path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
        return true;
    }

    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn importSource(tree: *const ast.Tree, declaration: ast.ImportDeclaration) ?[]const u8 {
    return stringLiteralValue(tree, declaration.source);
}

fn exportNamedSource(tree: *const ast.Tree, declaration: ast.ExportNamedDeclaration) ?[]const u8 {
    return stringLiteralValue(tree, declaration.source);
}

fn exportAllSource(tree: *const ast.Tree, declaration: ast.ExportAllDeclaration) ?[]const u8 {
    return stringLiteralValue(tree, declaration.source);
}

fn requireSource(tree: *const ast.Tree, call: ast.CallExpression) ?[]const u8 {
    if (call.arguments.len == 0) return null;
    const first = tree.extra(call.arguments)[0];
    return stringLiteralValue(tree, first);
}

fn stringLiteralValue(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .string_literal => |literal| tree.string(literal.value),
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

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

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

const node_dependencies = [_][]const u8{
    "assert",
    "assert/strict",
    "async_hooks",
    "buffer",
    "child_process",
    "cluster",
    "console",
    "constants",
    "crypto",
    "dgram",
    "diagnostics_channel",
    "dns",
    "dns/promises",
    "domain",
    "events",
    "fs",
    "fs/promises",
    "http",
    "http2",
    "https",
    "inspector",
    "inspector/promises",
    "module",
    "net",
    "os",
    "path",
    "path/posix",
    "path/win32",
    "perf_hooks",
    "process",
    "punycode",
    "querystring",
    "readline",
    "readline/promises",
    "repl",
    "stream",
    "stream/consumers",
    "stream/promises",
    "stream/web",
    "string_decoder",
    "sys",
    "timers",
    "timers/promises",
    "tls",
    "trace_events",
    "tty",
    "url",
    "util",
    "util/types",
    "v8",
    "vm",
    "wasi",
    "worker_threads",
    "zlib",
};

test "alipay ant no phantom dependencies parses package names like legacy lint" {
    try std.testing.expectEqualStrings("react", parsePackageNameFromImport("react/jsx-runtime").?);
    try std.testing.expectEqualStrings("@scope/pkg", parsePackageNameFromImport("@scope/pkg/sub/path").?);
    try std.testing.expect(parsePackageNameFromImport("./local") == null);
    try std.testing.expect(parsePackageNameFromImport("@example-fw/foo") == null);
    try std.testing.expect(parsePackageNameFromImport("@example-runtime/router") == null);
    try std.testing.expect(parsePackageNameFromImport("@smallfish/router") == null);
    try std.testing.expect(parsePackageNameFromImport("smallfish:stdlib/lodash") == null);
    try std.testing.expectEqualStrings("smallfish-package", parsePackageNameFromImport("smallfish-package").?);
    try std.testing.expectEqualStrings("@smallfish-other/pkg", parsePackageNameFromImport("@smallfish-other/pkg").?);
}
