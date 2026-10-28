const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "@alipay/ant/prefer-import-from-stdlib";

const max_config_file_size = 1024 * 1024;

const ProjectType = enum {
    appfw,
    appmini,
    smallfish,
    other,
};

const StdlibPackage = struct {
    name: []const u8,
    stdlib_path: []const u8,
    version: u32,
};

const stdlib_packages = [_]StdlibPackage{
    .{ .name = "lodash", .stdlib_path = "lodash", .version = 4 },
    .{ .name = "classnames", .stdlib_path = "classnames", .version = 2 },
    .{ .name = "lodash-es", .stdlib_path = "lodash", .version = 4 },
    .{ .name = "@example/request", .stdlib_path = "request", .version = 1 },
    .{ .name = "dayjs", .stdlib_path = "dayjs", .version = 1 },
    .{ .name = "zustand", .stdlib_path = "zustand", .version = 4 },
};

const VersionMap = std.StringHashMap(u32);

pub fn run(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
) Allocator.Error!void {
    const config: core.PreferImportFromStdlibConfig = .{};
    return runWithOptions(allocator, io, diagnostics, tree, file_path, &config);
}

pub fn runWithOptions(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
    options: *const core.PreferImportFromStdlibConfig,
) Allocator.Error!void {
    const project_root = try findProjectRoot(allocator, io, file_path);
    defer allocator.free(project_root);

    const project_type = detectProjectType(allocator, io, project_root) catch .other;
    const stdlib_package = switch (project_type) {
        .appfw => "appfw:stdlib",
        .appmini => "@example/stdlib",
        .smallfish => "smallfish:stdlib",
        .other => return,
    };

    var versions = try readPackageVersions(allocator, io, project_root);
    defer freeVersions(allocator, &versions);
    if (versions.count() == 0) return;

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .versions = &versions,
        .stdlib_package = stdlib_package,
        .external_packages = &options.external_packages,
    };
    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    versions: *const VersionMap,
    stdlib_package: []const u8,
    external_packages: *const core.StdlibExternalPackages,

    pub fn enter_program(
        self: *Visitor,
        program: ast.Program,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        for (ctx.tree.extra(program.body)) |statement_index| {
            const declaration = switch (ctx.tree.data(statement_index)) {
                .import_declaration => |declaration| declaration,
                else => continue,
            };
            try self.checkImport(ctx.tree, statement_index, importSource(ctx.tree, declaration));
        }
        return .proceed;
    }

    fn checkImport(
        self: *Visitor,
        tree: *const ast.Tree,
        node_index: ast.NodeIndex,
        source: ?[]const u8,
    ) Allocator.Error!void {
        const import_source = source orelse return;
        const package_name = parsePackageNameFromImport(import_source) orelse return;
        const stdlib = stdlibPackage(package_name, self.external_packages) orelse return;
        const version = self.versions.get(package_name) orelse return;
        if (version != stdlib.version) return;

        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .warning,
            id,
            tree.span(node_index),
            "推荐通过 {s}/{s} 使用 {s}, 可以统一依赖版本，防止 tree-shaking 失效。",
            .{ self.stdlib_package, stdlib.stdlib_path, package_name },
        );
    }
};

fn importSource(tree: *const ast.Tree, declaration: ast.ImportDeclaration) ?[]const u8 {
    return switch (tree.data(declaration.source)) {
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn stdlibPackage(package_name: []const u8, external_packages: *const core.StdlibExternalPackages) ?StdlibPackage {
    for (0..external_packages.count) |index| {
        const package = external_packages.at(index);
        if (std.mem.eql(u8, package.name(), package_name)) {
            return .{ .name = package.name(), .stdlib_path = package.stdlibPath(), .version = package.version };
        }
    }
    for (stdlib_packages) |package| {
        if (std.mem.eql(u8, package.name, package_name)) return package;
    }
    return null;
}

fn parsePackageNameFromImport(source: []const u8) ?[]const u8 {
    if (source.len == 0 or
        std.mem.startsWith(u8, source, "~") or
        std.mem.startsWith(u8, source, "/") or
        std.mem.startsWith(u8, source, "#") or
        std.mem.startsWith(u8, source, "@/") or
        std.mem.startsWith(u8, source, "./") or
        std.mem.startsWith(u8, source, "../") or
        std.mem.startsWith(u8, source, "@appfw/") or
        std.mem.startsWith(u8, source, "appfw:") or
        std.mem.startsWith(u8, source, "appmini:") or
        std.mem.startsWith(u8, source, "@smallfish/") or
        std.mem.startsWith(u8, source, "smallfish:") or
        std.mem.startsWith(u8, source, "@example-fw/") or
        std.mem.eql(u8, source, "@example-runtime") or
        std.mem.startsWith(u8, source, "@example-runtime/"))
    {
        return null;
    }

    if (source[0] == '@') {
        const first_slash = std.mem.indexOfScalarPos(u8, source, 1, '/') orelse return source;
        const second_slash = std.mem.indexOfScalarPos(u8, source, first_slash + 1, '/') orelse return source;
        return source[0..second_slash];
    }

    const slash = std.mem.indexOfScalar(u8, source, '/') orelse return source;
    return source[0..slash];
}

fn readPackageVersions(
    allocator: Allocator,
    io: std.Io,
    project_root: []const u8,
) Allocator.Error!VersionMap {
    var versions = VersionMap.init(allocator);
    errdefer versions.deinit();

    const package_path = try std.fs.path.join(allocator, &.{ project_root, "package.json" });
    defer allocator.free(package_path);

    const source = readConfigFile(allocator, io, package_path) orelse return versions;
    defer allocator.free(source);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch return versions;
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return versions,
    };

    try readDependencyVersions(allocator, &versions, root.get("devDependencies"));
    try readDependencyVersions(allocator, &versions, root.get("dependencies"));
    return versions;
}

fn readDependencyVersions(
    allocator: Allocator,
    versions: *VersionMap,
    value: ?std.json.Value,
) Allocator.Error!void {
    const object = switch (value orelse return) {
        .object => |object| object,
        else => return,
    };

    var iter = object.iterator();
    while (iter.next()) |entry| {
        const version_source = switch (entry.value_ptr.*) {
            .string => |version| version,
            else => continue,
        };
        const major = getMajorVersion(version_source) orelse continue;
        try putVersion(allocator, versions, entry.key_ptr.*, major);
    }
}

fn putVersion(
    allocator: Allocator,
    versions: *VersionMap,
    name: []const u8,
    major: u32,
) Allocator.Error!void {
    const result = try versions.getOrPut(name);
    if (result.found_existing) {
        result.value_ptr.* = major;
        return;
    }

    const owned_name = try allocator.dupe(u8, name);
    result.key_ptr.* = owned_name;
    result.value_ptr.* = major;
}

fn freeVersions(allocator: Allocator, versions: *VersionMap) void {
    var iter = versions.iterator();
    while (iter.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
    versions.deinit();
}

fn getMajorVersion(version: []const u8) ?u32 {
    for (version, 0..) |char, index| {
        if (!std.ascii.isDigit(char)) continue;
        var end = index + 1;
        while (end < version.len and std.ascii.isDigit(version[end])) : (end += 1) {}
        return std.fmt.parseUnsigned(u32, version[index..end], 10) catch null;
    }
    return null;
}

fn detectProjectType(allocator: Allocator, io: std.Io, project_root: []const u8) Allocator.Error!ProjectType {
    const appfw_js = try std.fs.path.join(allocator, &.{ project_root, "appfw.config.js" });
    defer allocator.free(appfw_js);
    if (exists(io, appfw_js)) return .appfw;

    const appfw_ts = try std.fs.path.join(allocator, &.{ project_root, "appfw.config.ts" });
    defer allocator.free(appfw_ts);
    if (exists(io, appfw_ts)) return .appfw;

    const appmini_js = try std.fs.path.join(allocator, &.{ project_root, "appmini.config.js" });
    defer allocator.free(appmini_js);
    if (exists(io, appmini_js)) return .appmini;

    const appmini_ts = try std.fs.path.join(allocator, &.{ project_root, "appmini.config.ts" });
    defer allocator.free(appmini_ts);
    if (exists(io, appmini_ts)) return .appmini;

    const smallfish_js = try std.fs.path.join(allocator, &.{ project_root, "smallfish.config.js" });
    defer allocator.free(smallfish_js);
    if (exists(io, smallfish_js)) return .smallfish;

    const smallfish_ts = try std.fs.path.join(allocator, &.{ project_root, "smallfish.config.ts" });
    defer allocator.free(smallfish_ts);
    if (exists(io, smallfish_ts)) return .smallfish;

    return .other;
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

        const parent = std.fs.path.dirname(current) orelse break;
        if (std.mem.eql(u8, parent, current)) break;
        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }

    return current;
}

fn exists(io: std.Io, path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        const directory_path = std.fs.path.dirname(path) orelse return false;
        const basename = std.fs.path.basename(path);
        var directory = std.Io.Dir.openDirAbsolute(io, directory_path, .{}) catch return false;
        defer directory.close(io);
        const stat = directory.statFile(io, basename, .{}) catch return false;
        return stat.kind == .file;
    }

    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .file;
}
