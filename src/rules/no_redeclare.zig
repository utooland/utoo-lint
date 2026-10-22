const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-redeclare";

pub const Options = struct {
    rule_id: []const u8 = id,
    severity: core.Severity = .warning,
    mode: Mode = .javascript,
    builtin_globals: bool = false,
    ignore_declaration_merge: bool = true,
};

pub const Mode = enum {
    javascript,
    typescript,
};

const DeclKind = enum {
    variable,
    function,
    class,
    interface,
    type_alias,
    @"enum",
    namespace,
    other,
};

const DeclInfo = struct {
    kind: DeclKind,
    function_has_body: bool = false,
};

const DeclInfoMap = std.AutoHashMap(ast.NodeIndex, DeclInfo);

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    try runWithOptions(allocator, diagnostics, tree, symbol_table, .{});
}

pub fn runWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    var decl_info = DeclInfoMap.init(allocator);
    defer decl_info.deinit();

    if (options.mode == .typescript) {
        var visitor = DeclInfoVisitor{ .decl_info = &decl_info };
        try traverser.basic.traverse(DeclInfoVisitor, tree, &visitor);
    }

    var iter = symbol_table.iterSymbols();

    while (iter.next()) |entry| {
        const symbol = entry.symbol;
        if (!isLintableSymbol(symbol.flags, options)) continue;

        const decls = symbol_table.symbolDecls(entry.id);
        if (decls.len == 0) continue;

        const name = tree.string(symbol.name);
        if (isBuiltinGlobalRedeclaration(tree, symbol, name, options)) {
            for (decls) |decl| {
                try addBuiltinGlobalRedeclaration(allocator, diagnostics, tree, decl, name, options);
            }
            continue;
        }

        if (decls.len <= 1) continue;

        if (options.mode == .typescript) {
            try checkTypescriptRedeclarations(allocator, diagnostics, tree, decls, name, decl_info, options);
        } else {
            for (decls[1..]) |decl| {
                try addAlreadyDefined(allocator, diagnostics, tree, decl, name, options);
            }
        }
    }
}

fn isLintableSymbol(flags: traverser.semantic.Symbol.Flags, options: Options) bool {
    if (options.mode == .typescript) {
        if (flags.type_parameter or flags.type_import) return false;
        return flags.intersects(traverser.semantic.Symbol.value_space) or flags.import or flags.interface or flags.type_alias or flags.namespace_module;
    }

    if (flags.ambient) return false;
    if (flags.type_import or flags.interface or flags.type_alias or flags.type_parameter) return false;
    return flags.intersects(traverser.semantic.Symbol.value_space) or flags.import;
}

fn isBuiltinGlobalRedeclaration(
    tree: *const ast.Tree,
    symbol: traverser.semantic.Symbol,
    name: []const u8,
    options: Options,
) bool {
    return options.builtin_globals and
        tree.source_type != .module and
        symbol.scope == .root and
        core.isKnownGlobal(name);
}

fn checkTypescriptRedeclarations(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    decls: []const ast.NodeIndex,
    name: []const u8,
    decl_info: DeclInfoMap,
    options: Options,
) Allocator.Error!void {
    var seen: std.ArrayList(DeclInfo) = .empty;
    defer seen.deinit(allocator);

    for (decls) |decl| {
        const current = decl_info.get(decl) orelse DeclInfo{ .kind = .other };
        if (isAllowedAfterSeen(current, seen.items, options)) {
            try seen.append(allocator, current);
            continue;
        }

        try addAlreadyDefined(allocator, diagnostics, tree, decl, name, options);
        try seen.append(allocator, current);
    }
}

fn isAllowedAfterSeen(current: DeclInfo, seen: []const DeclInfo, options: Options) bool {
    if (seen.len == 0) return true;

    for (seen) |previous| {
        if (!isAllowedTypescriptMerge(previous, current, seen, options)) return false;
    }
    return true;
}

fn isAllowedTypescriptMerge(previous: DeclInfo, current: DeclInfo, seen: []const DeclInfo, options: Options) bool {
    if (previous.kind == .function and current.kind == .function) {
        return functionBodyCount(seen) + @intFromBool(current.function_has_body) <= 1;
    }

    if ((previous.kind == .interface and current.kind == .interface) or
        (previous.kind == .interface and current.kind == .class) or
        (previous.kind == .class and current.kind == .interface))
    {
        return options.ignore_declaration_merge;
    }

    if (previous.kind == .namespace or current.kind == .namespace) {
        const other = if (previous.kind == .namespace) current.kind else previous.kind;
        if (!options.ignore_declaration_merge) return false;
        return switch (other) {
            .class, .function, .@"enum", .namespace => true,
            else => false,
        };
    }

    return false;
}

fn functionBodyCount(seen: []const DeclInfo) usize {
    var count: usize = 0;
    for (seen) |info| {
        if (info.kind == .function and info.function_has_body) count += 1;
    }
    return count;
}

fn addAlreadyDefined(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    decl: ast.NodeIndex,
    name: []const u8,
    options: Options,
) Allocator.Error!void {
    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        options.severity,
        options.rule_id,
        tree.span(decl),
        "'{s}' is already defined.",
        .{name},
    );
}

fn addBuiltinGlobalRedeclaration(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    decl: ast.NodeIndex,
    name: []const u8,
    options: Options,
) Allocator.Error!void {
    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        options.severity,
        options.rule_id,
        tree.span(decl),
        "'{s}' is already defined as a built-in global variable.",
        .{name},
    );
}

const DeclInfoVisitor = struct {
    decl_info: *DeclInfoMap,

    pub fn enter_variable_declarator(
        self: *DeclInfoVisitor,
        declarator: ast.VariableDeclarator,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectBinding(ctx.tree, declarator.id, .{ .kind = .variable });
        return .proceed;
    }

    pub fn enter_function(
        self: *DeclInfoVisitor,
        function: ast.Function,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (function.id != .null) {
            try self.decl_info.put(function.id, .{
                .kind = .function,
                .function_has_body = function.body != .null,
            });
        }
        return .proceed;
    }

    pub fn enter_class(
        self: *DeclInfoVisitor,
        class: ast.Class,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (class.id != .null) {
            try self.decl_info.put(class.id, .{ .kind = .class });
        }
        return .proceed;
    }

    pub fn enter_ts_interface_declaration(
        self: *DeclInfoVisitor,
        declaration: ast.TSInterfaceDeclaration,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.decl_info.put(declaration.id, .{ .kind = .interface });
        return .proceed;
    }

    pub fn enter_ts_type_alias_declaration(
        self: *DeclInfoVisitor,
        declaration: ast.TSTypeAliasDeclaration,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.decl_info.put(declaration.id, .{ .kind = .type_alias });
        return .proceed;
    }

    pub fn enter_ts_enum_declaration(
        self: *DeclInfoVisitor,
        declaration: ast.TSEnumDeclaration,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.decl_info.put(declaration.id, .{ .kind = .@"enum" });
        return .proceed;
    }

    pub fn enter_ts_module_declaration(
        self: *DeclInfoVisitor,
        declaration: ast.TSModuleDeclaration,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectBindingByNodeKind(declaration.id, .{ .kind = .namespace });
        return .proceed;
    }

    fn collectBinding(self: *DeclInfoVisitor, tree: *const ast.Tree, index: ast.NodeIndex, info: DeclInfo) Allocator.Error!void {
        if (index == .null) return;

        switch (tree.data(index)) {
            .binding_identifier => try self.decl_info.put(index, info),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    try self.collectBinding(tree, element, info);
                }
                try self.collectBinding(tree, pattern.rest, info);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = tree.data(property_index).binding_property;
                    try self.collectBinding(tree, property.value, info);
                }
                try self.collectBinding(tree, pattern.rest, info);
            },
            .assignment_pattern => |assignment| try self.collectBinding(tree, assignment.left, info),
            else => {},
        }
    }

    fn collectBindingByNodeKind(self: *DeclInfoVisitor, index: ast.NodeIndex, info: DeclInfo) Allocator.Error!void {
        if (index == .null) return;
        try self.decl_info.put(index, info);
    }
};
