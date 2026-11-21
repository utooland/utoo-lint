const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const export_map = @import("import_export_map.zig");

const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "import/no-cycle";

const max_source_size = 1024 * 1024;

pub const Options = struct {
    amd: bool = false,
    commonjs: bool = false,
    max_depth: usize = 1024,
};

const Dependency = struct {
    source: []const u8,
    resolved: []const u8,
    node: ast.NodeIndex,
    line: usize,

    fn deinit(self: Dependency, allocator: Allocator) void {
        allocator.free(self.source);
        allocator.free(self.resolved);
    }
};

const RouteStep = struct {
    source: []const u8,
    line: usize,

    fn deinit(self: RouteStep, allocator: Allocator) void {
        allocator.free(self.source);
    }
};

pub fn run(
    allocator: Allocator,
    io: std.Io,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    file_path: []const u8,
    options: Options,
) Allocator.Error!void {
    const normalized_file_path = try std.fs.path.resolve(allocator, &.{file_path});
    defer allocator.free(normalized_file_path);

    var dependencies = try collectDependencies(allocator, io, tree, normalized_file_path, options);
    defer deinitDependencies(allocator, &dependencies);

    for (dependencies.items) |dependency| {
        if (std.mem.eql(u8, dependency.resolved, normalized_file_path)) continue;

        var visited = std.StringHashMap(void).init(allocator);
        defer freeVisited(allocator, &visited);

        var route: std.ArrayList(RouteStep) = .empty;
        defer deinitRoute(allocator, &route);

        if (try hasCycle(allocator, io, dependency.resolved, normalized_file_path, &visited, &route, 0, options)) {
            try reportCycle(allocator, diagnostics, tree, dependency.node, &route);
        }
    }
}

fn hasCycle(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    target: []const u8,
    visited: *std.StringHashMap(void),
    route: *std.ArrayList(RouteStep),
    depth: usize,
    options: Options,
) Allocator.Error!bool {
    if (depth >= options.max_depth) return false;
    if (visited.contains(path)) return false;

    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    try visited.put(owned_path, {});

    var dependencies = try collectFileDependencies(allocator, io, path, options);
    defer deinitDependencies(allocator, &dependencies);

    for (dependencies.items) |dependency| {
        if (std.mem.eql(u8, dependency.resolved, target)) {
            return true;
        }
    }

    for (dependencies.items) |dependency| {
        const source = try allocator.dupe(u8, dependency.source);
        errdefer allocator.free(source);
        try route.append(allocator, .{
            .source = source,
            .line = dependency.line,
        });

        if (try hasCycle(allocator, io, dependency.resolved, target, visited, route, depth + 1, options)) {
            return true;
        }

        const removed = route.pop() orelse unreachable;
        removed.deinit(allocator);
    }

    return false;
}

fn reportCycle(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    node: ast.NodeIndex,
    route: *const std.ArrayList(RouteStep),
) Allocator.Error!void {
    if (route.items.len == 0) {
        try core.addDiagnostic(
            allocator,
            diagnostics,
            .@"error",
            id,
            "Dependency cycle detected.",
            tree.span(node),
        );
        return;
    }

    const route_text = try formatRoute(allocator, route);
    defer allocator.free(route_text);

    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        .@"error",
        id,
        tree.span(node),
        "Dependency cycle via {s}",
        .{route_text},
    );
}

fn formatRoute(allocator: Allocator, route: *const std.ArrayList(RouteStep)) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    for (route.items, 0..) |step, index| {
        if (index > 0) try out.appendSlice(allocator, "=>");
        const part = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ step.source, step.line });
        defer allocator.free(part);
        try out.appendSlice(allocator, part);
    }

    return out.toOwnedSlice(allocator);
}

fn collectFileDependencies(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
    options: Options,
) Allocator.Error!std.ArrayList(Dependency) {
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_source_size)) catch return .empty;
    defer allocator.free(source);

    var tree = try parser.parse(allocator, source, .{
        .source_type = ast.SourceType.fromPath(path),
        .lang = ast.Lang.fromPath(path),
    });
    defer tree.deinit();
    if (tree.hasErrors()) return .empty;

    return collectDependenciesFromSource(allocator, io, &tree, path, source, options);
}

fn collectDependencies(
    allocator: Allocator,
    io: std.Io,
    tree: *const ast.Tree,
    path: []const u8,
    options: Options,
) Allocator.Error!std.ArrayList(Dependency) {
    return collectDependenciesFromSource(allocator, io, tree, path, "", options);
}

fn collectDependenciesFromSource(
    allocator: Allocator,
    io: std.Io,
    tree: *const ast.Tree,
    path: []const u8,
    source_text: []const u8,
    options: Options,
) Allocator.Error!std.ArrayList(Dependency) {
    var dependencies: std.ArrayList(Dependency) = .empty;
    errdefer deinitDependencies(allocator, &dependencies);

    const program = switch (tree.data(tree.root)) {
        .program => |program| program,
        else => return dependencies,
    };

    for (tree.extra(program.body)) |statement_index| {
        switch (tree.data(statement_index)) {
            .import_declaration => |declaration| {
                if (declaration.import_kind == .type) continue;
                if (declaration.specifiers.len == 0) continue;
                if (isOnlyTypeImport(tree, declaration)) continue;
                const source = export_map.importSource(tree, declaration) orelse continue;
                try appendDependency(allocator, io, &dependencies, tree, source_text, path, source, statement_index);
            },
            .export_named_declaration => |declaration| {
                if (declaration.export_kind == .type) continue;
                const source = exportNamedSource(tree, declaration) orelse continue;
                try appendDependency(allocator, io, &dependencies, tree, source_text, path, source, statement_index);
            },
            .export_all_declaration => |declaration| {
                if (declaration.export_kind == .type) continue;
                const source = exportAllSource(tree, declaration) orelse continue;
                try appendDependency(allocator, io, &dependencies, tree, source_text, path, source, statement_index);
            },
            else => {},
        }
    }

    if (options.commonjs or options.amd) {
        var visitor = CallDependencyVisitor{
            .allocator = allocator,
            .io = io,
            .dependencies = &dependencies,
            .path = path,
            .source_text = source_text,
            .options = options,
        };
        try traverser.basic.traverse(CallDependencyVisitor, tree, &visitor);
    }

    return dependencies;
}

const CallDependencyVisitor = struct {
    allocator: Allocator,
    io: std.Io,
    dependencies: *std.ArrayList(Dependency),
    path: []const u8,
    source_text: []const u8,
    options: Options,

    pub fn enter_call_expression(
        self: *CallDependencyVisitor,
        call: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const arguments = ctx.tree.extra(call.arguments);

        if (self.options.commonjs and isRequireCall(ctx.tree, call) and arguments.len == 1) {
            if (stringLiteralValue(ctx.tree, arguments[0])) |source| {
                try appendDependency(self.allocator, self.io, self.dependencies, ctx.tree, self.source_text, self.path, source, index);
            }
        }

        if (self.options.amd and isAmdCall(ctx.tree, call)) {
            try self.appendAmdDependencies(ctx.tree, arguments, index);
        }

        return .proceed;
    }

    fn appendAmdDependencies(
        self: *CallDependencyVisitor,
        tree: *const ast.Tree,
        arguments: []const ast.NodeIndex,
        index: ast.NodeIndex,
    ) Allocator.Error!void {
        if (arguments.len == 0) return;

        const dependencies = switch (tree.data(unwrapTransparent(tree, arguments[0]))) {
            .array_expression => |array| array,
            else => return,
        };

        for (tree.extra(dependencies.elements)) |element| {
            if (element == .null) continue;
            const source = stringLiteralValue(tree, element) orelse continue;
            try appendDependency(self.allocator, self.io, self.dependencies, tree, self.source_text, self.path, source, index);
        }
    }
};

fn appendDependency(
    allocator: Allocator,
    io: std.Io,
    dependencies: *std.ArrayList(Dependency),
    tree: *const ast.Tree,
    source_text: []const u8,
    path: []const u8,
    source: []const u8,
    statement_index: ast.NodeIndex,
) Allocator.Error!void {
    const resolved = try export_map.resolveRelativeModule(allocator, io, path, source) orelse return;
    errdefer allocator.free(resolved);
    const owned_source = try allocator.dupe(u8, source);
    errdefer allocator.free(owned_source);

    try dependencies.append(allocator, .{
        .source = owned_source,
        .resolved = resolved,
        .node = statement_index,
        .line = lineForOffset(source_text, tree.span(statement_index).start),
    });
}

fn isOnlyTypeImport(tree: *const ast.Tree, declaration: ast.ImportDeclaration) bool {
    if (declaration.specifiers.len == 0) return false;
    for (tree.extra(declaration.specifiers)) |specifier_index| {
        switch (tree.data(specifier_index)) {
            .import_specifier => |specifier| {
                if (specifier.import_kind != .type) return false;
            },
            else => return false,
        }
    }
    return true;
}

fn lineForOffset(source: []const u8, offset: u32) usize {
    const end = @min(@as(usize, @intCast(offset)), source.len);
    var line: usize = 1;
    for (source[0..end]) |char| {
        if (char == '\n') line += 1;
    }
    return line;
}

fn deinitDependencies(allocator: Allocator, dependencies: *std.ArrayList(Dependency)) void {
    for (dependencies.items) |dependency| dependency.deinit(allocator);
    dependencies.deinit(allocator);
}

fn deinitRoute(allocator: Allocator, route: *std.ArrayList(RouteStep)) void {
    for (route.items) |step| step.deinit(allocator);
    route.deinit(allocator);
}

fn freeVisited(allocator: Allocator, visited: *std.StringHashMap(void)) void {
    var iter = visited.iterator();
    while (iter.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
    visited.deinit();
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

fn isRequireCall(tree: *const ast.Tree, call: ast.CallExpression) bool {
    return isIdentifierReferenceNamed(tree, unwrapTransparent(tree, call.callee), "require");
}

fn isAmdCall(tree: *const ast.Tree, call: ast.CallExpression) bool {
    const callee = unwrapTransparent(tree, call.callee);
    return isIdentifierReferenceNamed(tree, callee, "define") or
        isIdentifierReferenceNamed(tree, callee, "require");
}

fn isIdentifierReferenceNamed(tree: *const ast.Tree, index: ast.NodeIndex, expected: []const u8) bool {
    return switch (tree.data(index)) {
        .identifier_reference => |identifier| std.mem.eql(u8, tree.string(identifier.name), expected),
        else => false,
    };
}

fn stringLiteralValue(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(unwrapTransparent(tree, index))) {
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
