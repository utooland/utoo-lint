const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-unused-vars";

const SymbolId = traverser.semantic.SymbolId;
const IgnoredDecls = std.AutoHashMap(ast.NodeIndex, void);

pub const Options = struct {
    rule_id: []const u8 = id,
    severity: core.Severity = .warning,
    check_parameters: bool = false,
    args_after_used: bool = false,
    vars: core.NoUnusedVarsVars = .all,
    check_caught_errors: bool = false,
    ignore_rest_siblings: bool = false,
    ignore_class_with_static_init_block: bool = false,
    ignore_using_declarations: bool = false,
    check_type_parameters: bool = false,
    check_imports: bool = true,
    react_jsx_uses_react: bool = false,
    args_ignore_pattern: core.NoUnusedVarsIgnorePattern = .{},
    caught_errors_ignore_pattern: core.NoUnusedVarsIgnorePattern = .{},
    destructured_array_ignore_pattern: core.NoUnusedVarsIgnorePattern = .{},
    report_used_ignore_pattern: bool = false,
    vars_ignore_pattern: core.NoUnusedVarsIgnorePattern = .{},
};

const JSXReactUsage = struct {
    pragma: []const u8 = "React",
    has_jsx: bool = false,
    has_fragment: bool = false,

    pub fn enter_jsx_opening_element(
        usage: *JSXReactUsage,
        _: ast.JSXOpeningElement,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        usage.has_jsx = true;
        return .proceed;
    }

    pub fn enter_jsx_opening_fragment(
        usage: *JSXReactUsage,
        _: ast.JSXOpeningFragment,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        usage.has_jsx = true;
        return .proceed;
    }

    pub fn enter_jsx_fragment(
        usage: *JSXReactUsage,
        _: ast.JSXFragment,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        usage.has_fragment = true;
        return .proceed;
    }
};

const Parameter = struct {
    symbol_id: SymbolId,
    scope: traverser.semantic.ScopeId,
    start: u32,
    used: bool,
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    try runWithOptions(allocator, diagnostics, tree, scope_tree, symbol_table, .{});
}

pub fn runWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    var parameters: std.ArrayList(Parameter) = .empty;
    defer parameters.deinit(allocator);

    if (options.check_parameters and options.args_after_used) {
        try collectParameters(allocator, tree, symbol_table, &parameters);
        std.mem.sort(Parameter, parameters.items, {}, lessThanParameter);
    }

    var ignored_decls = IgnoredDecls.init(allocator);
    defer ignored_decls.deinit();

    var destructured_array_ignored_decls = IgnoredDecls.init(allocator);
    defer destructured_array_ignored_decls.deinit();

    var implicitly_used_visitor = ImplicitlyUsedBindingVisitor{ .ignored_decls = &ignored_decls };
    try traverser.basic.traverse(ImplicitlyUsedBindingVisitor, tree, &implicitly_used_visitor);

    if (options.ignore_rest_siblings) {
        var visitor = RestSiblingVisitor{ .ignored_decls = &ignored_decls };
        try traverser.basic.traverse(RestSiblingVisitor, tree, &visitor);
    }

    if (options.ignore_class_with_static_init_block) {
        var visitor = ClassWithStaticBlockVisitor{ .ignored_decls = &ignored_decls };
        try traverser.basic.traverse(ClassWithStaticBlockVisitor, tree, &visitor);
    }

    if (options.ignore_using_declarations) {
        var visitor = UsingDeclarationVisitor{ .ignored_decls = &ignored_decls };
        try traverser.basic.traverse(UsingDeclarationVisitor, tree, &visitor);
    }

    if (options.destructured_array_ignore_pattern.pattern() != null) {
        var visitor = DestructuredArrayVisitor{
            .ignored_decls = &ignored_decls,
            .destructured_array_ignored_decls = &destructured_array_ignored_decls,
            .pattern = options.destructured_array_ignore_pattern,
        };
        try traverser.basic.traverse(DestructuredArrayVisitor, tree, &visitor);
    }

    const jsx_react_usage = if (options.react_jsx_uses_react) collectJSXReactUsage(tree) else JSXReactUsage{};

    var iter = symbol_table.iterSymbols();

    while (iter.next()) |entry| {
        const symbol = entry.symbol;
        const flags = symbol.flags;

        // Enum members are property-like names, not standalone variables.
        if (flags.enum_member) continue;
        if (!isLintableSymbol(flags, options)) continue;
        if (!options.check_imports and (flags.import or flags.type_import)) continue;
        if (flags.exported or flags.ambient) continue;
        if (options.vars == .local and isGlobalVariable(scope_tree, symbol.scope, flags)) continue;
        if (flags.catch_var and !options.check_caught_errors) continue;
        if (flags.parameter) {
            if (!options.check_parameters) continue;
            if (options.args_after_used and !shouldCheckParameter(entry.id, symbol.scope, parameters.items)) continue;
        }

        const name = tree.string(symbol.name);
        const decls = symbol_table.symbolDecls(entry.id);
        if (decls.len == 0) continue;

        if (symbol_table.isReferenced(entry.id) or isParameterProperty(tree, symbol_table, decls[0])) {
            if (options.report_used_ignore_pattern and isReportedUsedIgnoredName(name, flags, decls, &destructured_array_ignored_decls, options)) {
                try core.addDiagnosticFmt(
                    allocator,
                    diagnostics,
                    options.severity,
                    options.rule_id,
                    tree.span(decls[0]),
                    "'{s}' is marked as ignored but is used.",
                    .{name},
                );
            }
            continue;
        }

        if (!flags.parameter and std.mem.startsWith(u8, name, "_")) continue;
        if (isIgnoredVariableName(name, flags, options)) continue;
        if (isUsedByReactJSX(name, jsx_react_usage)) continue;
        if (ignored_decls.contains(decls[0])) continue;

        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            options.severity,
            options.rule_id,
            tree.span(decls[0]),
            "'{s}' is declared but never used.",
            .{name},
        );
    }
}

fn isReportedUsedIgnoredName(
    name: []const u8,
    flags: traverser.semantic.Symbol.Flags,
    decls: []const ast.NodeIndex,
    destructured_array_ignored_decls: *IgnoredDecls,
    options: Options,
) bool {
    if (flags.parameter) return matchesPatternOption(name, options.args_ignore_pattern);
    if (flags.catch_var) return matchesPatternOption(name, options.caught_errors_ignore_pattern);
    if (decls.len > 0 and destructured_array_ignored_decls.contains(decls[0])) return true;
    return matchesPatternOption(name, options.vars_ignore_pattern);
}

fn isIgnoredVariableName(name: []const u8, flags: traverser.semantic.Symbol.Flags, options: Options) bool {
    if (flags.parameter) return matchesPatternOption(name, options.args_ignore_pattern);
    if (flags.catch_var) return matchesPatternOption(name, options.caught_errors_ignore_pattern);
    return matchesPatternOption(name, options.vars_ignore_pattern);
}

fn matchesPatternOption(name: []const u8, pattern: core.NoUnusedVarsIgnorePattern) bool {
    const custom_pattern = pattern.pattern() orelse return false;
    return matchesPattern(name, custom_pattern);
}

fn matchesPattern(value: []const u8, pattern: []const u8) bool {
    return @import("jest_valid_title.zig").regexMatches(pattern, value);
}

fn isGlobalVariable(
    scope_tree: traverser.semantic.ScopeTree,
    scope_id: traverser.semantic.ScopeId,
    flags: traverser.semantic.Symbol.Flags,
) bool {
    if (flags.catch_var or flags.parameter) return false;
    if (flags.type_parameter) return false;
    if (scope_id == .none) return false;
    const scope = scope_tree.getScope(scope_id);
    return scope.kind == .global;
}

fn isLintableSymbol(flags: traverser.semantic.Symbol.Flags, options: Options) bool {
    return flags.inValueSpace() or
        flags.catch_var or
        flags.import or
        flags.type_import or
        flags.interface or
        flags.type_alias or
        (options.check_type_parameters and flags.type_parameter);
}

fn isParameterProperty(tree: *const ast.Tree, symbol_table: traverser.semantic.SymbolTable, declaration: ast.NodeIndex) bool {
    var parent = symbol_table.parentOf(declaration) orelse return false;
    if (tree.data(parent) == .assignment_pattern) {
        parent = symbol_table.parentOf(parent) orelse return false;
    }
    return tree.data(parent) == .ts_parameter_property;
}

fn collectParameters(
    allocator: Allocator,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    parameters: *std.ArrayList(Parameter),
) Allocator.Error!void {
    var iter = symbol_table.iterSymbols();
    while (iter.next()) |entry| {
        const symbol = entry.symbol;
        if (!symbol.flags.parameter) continue;

        const decls = symbol_table.symbolDecls(entry.id);
        if (decls.len == 0) continue;

        try parameters.append(allocator, .{
            .symbol_id = entry.id,
            .scope = symbol.scope,
            .start = tree.span(decls[0]).start,
            .used = symbol_table.isReferenced(entry.id) or isParameterProperty(tree, symbol_table, decls[0]),
        });
    }
}

fn lessThanParameter(_: void, a: Parameter, b: Parameter) bool {
    const a_scope = @intFromEnum(a.scope);
    const b_scope = @intFromEnum(b.scope);
    if (a_scope != b_scope) return a_scope < b_scope;
    return a.start < b.start;
}

fn shouldCheckParameter(
    symbol_id: SymbolId,
    scope: traverser.semantic.ScopeId,
    parameters: []const Parameter,
) bool {
    var index: ?usize = null;
    var last_used: ?usize = null;

    for (parameters, 0..) |parameter, i| {
        if (parameter.scope != scope) continue;
        if (parameter.symbol_id == symbol_id) index = i;
        if (parameter.used) last_used = i;
    }

    const current = index orelse return true;
    const last = last_used orelse return true;
    return current > last;
}

const ImplicitlyUsedBindingVisitor = struct {
    ignored_decls: *IgnoredDecls,

    pub fn enter_function(
        self: *ImplicitlyUsedBindingVisitor,
        function: ast.Function,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (function.type == .function_expression and function.id != .null) {
            try self.ignored_decls.put(function.id, {});
        }
        return .proceed;
    }

    pub fn enter_class(
        self: *ImplicitlyUsedBindingVisitor,
        class: ast.Class,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (class.type == .class_expression and class.id != .null) {
            try self.ignored_decls.put(class.id, {});
        }
        return .proceed;
    }

    pub fn enter_ts_mapped_type(
        self: *ImplicitlyUsedBindingVisitor,
        mapped_type: ast.TSMappedType,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.ignored_decls.put(mapped_type.key, {});
        return .proceed;
    }
};

const RestSiblingVisitor = struct {
    ignored_decls: *IgnoredDecls,

    pub fn enter_object_pattern(
        self: *RestSiblingVisitor,
        pattern: ast.ObjectPattern,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (pattern.rest == .null) return .proceed;

        for (ctx.tree.extra(pattern.properties)) |property_index| {
            const property = ctx.tree.data(property_index).binding_property;
            try self.collectBinding(property.value, ctx);
        }

        return .proceed;
    }

    fn collectBinding(
        self: *RestSiblingVisitor,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!void {
        if (index == .null) return;

        switch (ctx.tree.data(index)) {
            .binding_identifier => try self.ignored_decls.put(index, {}),
            .assignment_pattern => |assignment| try self.collectBinding(assignment.left, ctx),
            .binding_rest_element => |rest| try self.collectBinding(rest.argument, ctx),
            .array_pattern => |array| {
                for (ctx.tree.extra(array.elements)) |element| {
                    try self.collectBinding(element, ctx);
                }
                try self.collectBinding(array.rest, ctx);
            },
            .object_pattern => |object| {
                for (ctx.tree.extra(object.properties)) |property_index| {
                    const property = ctx.tree.data(property_index).binding_property;
                    try self.collectBinding(property.value, ctx);
                }
                try self.collectBinding(object.rest, ctx);
            },
            else => {},
        }
    }
};

const UsingDeclarationVisitor = struct {
    ignored_decls: *IgnoredDecls,

    pub fn enter_variable_declaration(
        self: *UsingDeclarationVisitor,
        declaration: ast.VariableDeclaration,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (declaration.kind != .using and declaration.kind != .await_using) return .proceed;

        for (ctx.tree.extra(declaration.declarators)) |declarator_index| {
            const declarator = switch (ctx.tree.data(declarator_index)) {
                .variable_declarator => |declarator| declarator,
                else => continue,
            };
            try self.collectBinding(declarator.id, ctx);
        }

        return .proceed;
    }

    fn collectBinding(
        self: *UsingDeclarationVisitor,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!void {
        if (index == .null) return;

        switch (ctx.tree.data(index)) {
            .binding_identifier => try self.ignored_decls.put(index, {}),
            .assignment_pattern => |assignment| try self.collectBinding(assignment.left, ctx),
            .binding_rest_element => |rest| try self.collectBinding(rest.argument, ctx),
            .array_pattern => |array| {
                for (ctx.tree.extra(array.elements)) |element| {
                    try self.collectBinding(element, ctx);
                }
                try self.collectBinding(array.rest, ctx);
            },
            .object_pattern => |object| {
                for (ctx.tree.extra(object.properties)) |property_index| {
                    const property = ctx.tree.data(property_index).binding_property;
                    try self.collectBinding(property.value, ctx);
                }
                try self.collectBinding(object.rest, ctx);
            },
            else => {},
        }
    }
};

const ClassWithStaticBlockVisitor = struct {
    ignored_decls: *IgnoredDecls,

    pub fn enter_class(
        self: *ClassWithStaticBlockVisitor,
        class: ast.Class,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (class.type != .class_declaration or class.id == .null) return .proceed;
        if (!hasStaticBlock(ctx.tree, class.body)) return .proceed;

        try self.ignored_decls.put(class.id, {});
        return .proceed;
    }
};

fn hasStaticBlock(tree: *const ast.Tree, body_index: ast.NodeIndex) bool {
    if (body_index == .null) return false;

    const body = switch (tree.data(body_index)) {
        .class_body => |body| body,
        else => return false,
    };

    for (tree.extra(body.body)) |element_index| {
        if (tree.data(element_index) == .static_block) return true;
    }
    return false;
}

const DestructuredArrayVisitor = struct {
    ignored_decls: *IgnoredDecls,
    destructured_array_ignored_decls: *IgnoredDecls,
    pattern: core.NoUnusedVarsIgnorePattern,

    pub fn enter_array_pattern(
        self: *DestructuredArrayVisitor,
        pattern: ast.ArrayPattern,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        for (ctx.tree.extra(pattern.elements)) |element| {
            try self.collectBinding(element, ctx);
        }
        try self.collectBinding(pattern.rest, ctx);

        return .proceed;
    }

    fn collectBinding(
        self: *DestructuredArrayVisitor,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!void {
        if (index == .null) return;

        switch (ctx.tree.data(index)) {
            .binding_identifier => |identifier| {
                const name = ctx.tree.string(identifier.name);
                if (matchesPatternOption(name, self.pattern)) {
                    try self.ignored_decls.put(index, {});
                    try self.destructured_array_ignored_decls.put(index, {});
                }
            },
            .assignment_pattern => |assignment| try self.collectBinding(assignment.left, ctx),
            .binding_rest_element => |rest| try self.collectBinding(rest.argument, ctx),
            .array_pattern => |array| {
                for (ctx.tree.extra(array.elements)) |element| {
                    try self.collectBinding(element, ctx);
                }
                try self.collectBinding(array.rest, ctx);
            },
            .object_pattern => |object| {
                for (ctx.tree.extra(object.properties)) |property_index| {
                    const property = ctx.tree.data(property_index).binding_property;
                    try self.collectBinding(property.value, ctx);
                }
                try self.collectBinding(object.rest, ctx);
            },
            else => {},
        }
    }
};

fn collectJSXReactUsage(tree: *const ast.Tree) JSXReactUsage {
    var usage = JSXReactUsage{
        .pragma = pragmaFromComments(tree) orelse "React",
    };
    traverser.basic.traverse(JSXReactUsage, tree, &usage) catch unreachable;
    return usage;
}

fn isUsedByReactJSX(name: []const u8, usage: JSXReactUsage) bool {
    return (usage.has_jsx and std.mem.eql(u8, name, usage.pragma)) or
        (usage.has_fragment and std.mem.eql(u8, name, "Fragment"));
}

fn pragmaFromComments(tree: *const ast.Tree) ?[]const u8 {
    for (tree.comments) |comment| {
        const value = tree.string(comment.value);
        const marker_index = std.mem.indexOf(u8, value, "@jsx") orelse continue;
        var cursor = marker_index + "@jsx".len;

        if (cursor >= value.len or !isWhitespace(value[cursor])) continue;
        while (cursor < value.len and isWhitespace(value[cursor])) : (cursor += 1) {}

        const start = cursor;
        while (cursor < value.len and !isWhitespace(value[cursor])) : (cursor += 1) {}
        var pragma = value[start..cursor];
        if (std.mem.indexOfScalar(u8, pragma, '.')) |dot_index| {
            pragma = pragma[0..dot_index];
        }
        if (isIdentifier(pragma)) return pragma;
    }
    return null;
}

fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
}

fn isIdentifier(value: []const u8) bool {
    if (value.len == 0) return false;
    if (!isIdentifierStart(value[0])) return false;
    for (value[1..]) |byte| {
        if (!isIdentifierContinue(byte)) return false;
    }
    return true;
}

fn isIdentifierStart(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or byte == '_' or byte == '$';
}

fn isIdentifierContinue(byte: u8) bool {
    return isIdentifierStart(byte) or std.ascii.isDigit(byte);
}
