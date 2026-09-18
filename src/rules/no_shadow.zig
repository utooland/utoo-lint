const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-shadow";

pub const Options = struct {
    rule_id: []const u8 = id,
    severity: core.Severity = .warning,
    mode: Mode = .javascript,
    allow: core.NoShadowAllowNames = .{},
    builtin_globals: bool = false,
    hoist: core.NoShadowHoist = .functions,
    ignore_on_initialization: bool = false,
    ignore_type_value_shadow: bool = false,
    ignore_function_type_parameter_name_value_shadow: bool = true,
};

pub const Mode = enum {
    javascript,
    typescript,
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
    var iter = symbol_table.iterSymbols();

    while (iter.next()) |entry| {
        const symbol = entry.symbol;
        if (!isLintableSymbol(symbol.flags, options)) continue;
        if (symbol.scope == .root or symbol.scope == .module) continue;

        const name = tree.string(symbol.name);
        if (options.allow.contains(name)) continue;

        const decls = symbol_table.symbolDecls(entry.id);
        if (decls.len == 0) continue;

        if (options.builtin_globals and core.isKnownGlobal(name)) {
            try core.addDiagnosticFmt(
                allocator,
                diagnostics,
                options.severity,
                options.rule_id,
                tree.span(decls[0]),
                "'{s}' is already a global variable.",
                .{name},
            );
            continue;
        }

        const shadowed_id = findShadowedSymbol(scope_tree, symbol_table, symbol.scope, name, entry.id, symbol.flags, options) orelse continue;
        const shadowed_decls = symbol_table.symbolDecls(shadowed_id);
        if (shadowed_decls.len == 0) continue;
        const shadowed_flags = symbol_table.getSymbol(shadowed_id).flags;
        if (isAllowedByHoist(tree, decls[0], shadowed_decls[0], shadowed_flags, options)) continue;
        if (options.ignore_on_initialization and isAllowedOnInitialization(tree, decls[0], shadowed_decls[0])) continue;

        const shadowed_position = offsetToLineColumn(tree.source, tree.span(shadowed_decls[0]).start);
        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            options.severity,
            options.rule_id,
            tree.span(decls[0]),
            "'{s}' is already declared in the upper scope on line {d} column {d}.",
            .{ name, shadowed_position.line, shadowed_position.column },
        );
    }

    if (options.mode == .typescript and !options.ignore_function_type_parameter_name_value_shadow) {
        try checkFunctionTypeParameterNameValueShadows(allocator, diagnostics, tree, scope_tree, symbol_table, options);
    }
}

fn findShadowedSymbol(
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    scope: traverser.semantic.ScopeId,
    name: []const u8,
    self_id: traverser.semantic.SymbolId,
    self_flags: traverser.semantic.Symbol.Flags,
    options: Options,
) ?traverser.semantic.SymbolId {
    var current = scope_tree.getScope(scope).parent;
    while (current != .none) {
        if (symbol_table.findInScope(current, name)) |candidate_id| {
            const candidate_flags = symbol_table.getSymbol(candidate_id).flags;
            if (candidate_id != self_id and isLintableSymbol(candidate_flags, options) and !isAllowedTypescriptShadow(self_flags, candidate_flags, options)) {
                return candidate_id;
            }
        }
        current = scope_tree.getScope(current).parent;
    }
    return null;
}

fn isLintableSymbol(flags: traverser.semantic.Symbol.Flags, options: Options) bool {
    if (options.mode == .typescript) {
        return flags.inValueSpace() or
            flags.import or
            flags.type_import or
            flags.interface or
            flags.type_alias or
            flags.type_parameter or
            flags.namespace_module;
    }

    if (flags.ambient) return false;
    if (flags.type_import or flags.interface or flags.type_alias or flags.type_parameter) return false;
    return flags.inValueSpace() or flags.import;
}

fn isAllowedTypescriptShadow(
    self_flags: traverser.semantic.Symbol.Flags,
    candidate_flags: traverser.semantic.Symbol.Flags,
    options: Options,
) bool {
    if (options.mode != .typescript) return false;
    if (options.ignore_type_value_shadow and isTypeValueShadow(self_flags, candidate_flags)) return true;
    return (self_flags.interface and candidate_flags.class) or
        (self_flags.class and candidate_flags.interface);
}

fn isTypeValueShadow(self_flags: traverser.semantic.Symbol.Flags, candidate_flags: traverser.semantic.Symbol.Flags) bool {
    return (isTypeOnlySymbol(self_flags) and isValueOnlySymbol(candidate_flags)) or
        (isValueOnlySymbol(self_flags) and isTypeOnlySymbol(candidate_flags));
}

fn isTypeOnlySymbol(flags: traverser.semantic.Symbol.Flags) bool {
    return (flags.type_import or flags.inTypeSpace()) and !flags.inValueSpace();
}

fn isValueOnlySymbol(flags: traverser.semantic.Symbol.Flags) bool {
    return flags.inValueSpace() and !flags.inTypeSpace();
}

fn isAllowedOnInitialization(tree: *const ast.Tree, self_decl: ast.NodeIndex, shadowed_decl: ast.NodeIndex) bool {
    const init = initializerForBinding(tree, shadowed_decl) orelse return false;
    if (!containsNode(tree, init, self_decl)) return false;

    const function_node = initializationFunctionContaining(tree, init, self_decl) orelse return false;
    return functionIsCalledDuringInitialization(tree, init, function_node);
}

fn initializerForBinding(tree: *const ast.Tree, binding: ast.NodeIndex) ?ast.NodeIndex {
    for (tree.nodes.items(.data)) |data| {
        const declarator = switch (data) {
            .variable_declarator => |declarator| declarator,
            else => continue,
        };
        if (declarator.init != .null and containsNode(tree, declarator.id, binding)) return declarator.init;
    }
    return null;
}

fn initializationFunctionContaining(tree: *const ast.Tree, init: ast.NodeIndex, target: ast.NodeIndex) ?ast.NodeIndex {
    var result: ?ast.NodeIndex = null;

    for (tree.nodes.items(.data), 0..) |data, raw_index| {
        const index: ast.NodeIndex = @enumFromInt(@as(u32, @intCast(raw_index)));
        if (!containsNode(tree, init, index) or !containsNode(tree, index, target)) continue;

        switch (data) {
            .function, .arrow_function_expression => result = index,
            else => {},
        }
    }

    return result;
}

fn functionIsCalledDuringInitialization(tree: *const ast.Tree, init: ast.NodeIndex, function_node: ast.NodeIndex) bool {
    for (tree.nodes.items(.data), 0..) |data, raw_index| {
        const call = switch (data) {
            .call_expression => |call| call,
            else => continue,
        };
        const call_index: ast.NodeIndex = @enumFromInt(@as(u32, @intCast(raw_index)));
        if (!containsNode(tree, init, call_index)) continue;

        if (unwrapCallTarget(tree, call.callee) == function_node) return true;

        for (tree.extra(call.arguments)) |argument| {
            if (unwrapCallTarget(tree, argument) == function_node) return true;
        }
    }

    return false;
}

fn unwrapCallTarget(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    if (index == .null) return index;

    var current = index;
    while (true) {
        switch (tree.data(current)) {
            .parenthesized_expression => |expression| current = expression.expression,
            .chain_expression => |expression| current = expression.expression,
            else => return current,
        }
    }
}

fn containsNode(tree: *const ast.Tree, container: ast.NodeIndex, node: ast.NodeIndex) bool {
    if (container == .null or node == .null) return false;
    if (container == node) return true;

    const container_span = tree.span(container);
    const node_span = tree.span(node);
    return container_span.start <= node_span.start and node_span.end <= container_span.end;
}

fn checkFunctionTypeParameterNameValueShadows(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    for (tree.nodes.items(.data), 0..) |data, raw_index| {
        const function_type = switch (data) {
            .ts_function_type => |function_type| function_type,
            else => continue,
        };

        const scope_id = scopeIdForNode(scope_tree, @enumFromInt(@as(u32, @intCast(raw_index)))) orelse continue;
        try checkFunctionTypeParameters(
            allocator,
            diagnostics,
            tree,
            scope_tree,
            symbol_table,
            function_type.params,
            scope_id,
            options,
        );
    }
}

fn checkFunctionTypeParameters(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    params_index: ast.NodeIndex,
    scope_id: traverser.semantic.ScopeId,
    options: Options,
) Allocator.Error!void {
    if (params_index == .null) return;

    const params = switch (tree.data(params_index)) {
        .formal_parameters => |params| params,
        else => return,
    };

    for (tree.extra(params.items)) |item_index| {
        switch (tree.data(item_index)) {
            .formal_parameter => |parameter| try checkFunctionTypeParameterBinding(
                allocator,
                diagnostics,
                tree,
                scope_tree,
                symbol_table,
                parameter.pattern,
                scope_id,
                options,
            ),
            else => {},
        }
    }

    try checkFunctionTypeParameterBinding(
        allocator,
        diagnostics,
        tree,
        scope_tree,
        symbol_table,
        params.rest,
        scope_id,
        options,
    );
}

fn checkFunctionTypeParameterBinding(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    index: ast.NodeIndex,
    scope_id: traverser.semantic.ScopeId,
    options: Options,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .binding_identifier => |identifier| try checkFunctionTypeParameterIdentifier(
            allocator,
            diagnostics,
            tree,
            scope_tree,
            symbol_table,
            index,
            tree.string(identifier.name),
            scope_id,
            options,
        ),
        .assignment_pattern => |pattern| try checkFunctionTypeParameterBinding(
            allocator,
            diagnostics,
            tree,
            scope_tree,
            symbol_table,
            pattern.left,
            scope_id,
            options,
        ),
        .binding_rest_element => |element| try checkFunctionTypeParameterBinding(
            allocator,
            diagnostics,
            tree,
            scope_tree,
            symbol_table,
            element.argument,
            scope_id,
            options,
        ),
        .array_pattern => |pattern| {
            for (tree.extra(pattern.elements)) |element| {
                try checkFunctionTypeParameterBinding(
                    allocator,
                    diagnostics,
                    tree,
                    scope_tree,
                    symbol_table,
                    element,
                    scope_id,
                    options,
                );
            }
            try checkFunctionTypeParameterBinding(
                allocator,
                diagnostics,
                tree,
                scope_tree,
                symbol_table,
                pattern.rest,
                scope_id,
                options,
            );
        },
        .object_pattern => |pattern| {
            for (tree.extra(pattern.properties)) |property_index| {
                const property = switch (tree.data(property_index)) {
                    .binding_property => |property| property,
                    else => continue,
                };
                try checkFunctionTypeParameterBinding(
                    allocator,
                    diagnostics,
                    tree,
                    scope_tree,
                    symbol_table,
                    property.value,
                    scope_id,
                    options,
                );
            }
            try checkFunctionTypeParameterBinding(
                allocator,
                diagnostics,
                tree,
                scope_tree,
                symbol_table,
                pattern.rest,
                scope_id,
                options,
            );
        },
        else => {},
    }
}

fn checkFunctionTypeParameterIdentifier(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    index: ast.NodeIndex,
    name: []const u8,
    scope_id: traverser.semantic.ScopeId,
    options: Options,
) Allocator.Error!void {
    if (options.allow.contains(name)) return;

    if (options.builtin_globals and core.isKnownGlobal(name)) {
        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            options.severity,
            options.rule_id,
            tree.span(index),
            "'{s}' is already a global variable.",
            .{name},
        );
        return;
    }

    const shadowed_id = findShadowedValueSymbol(scope_tree, symbol_table, scope_id, name) orelse return;
    const shadowed_decls = symbol_table.symbolDecls(shadowed_id);
    if (shadowed_decls.len == 0) return;

    const shadowed_flags = symbol_table.getSymbol(shadowed_id).flags;
    if (isAllowedByHoist(tree, index, shadowed_decls[0], shadowed_flags, options)) return;

    const shadowed_position = offsetToLineColumn(tree.source, tree.span(shadowed_decls[0]).start);
    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        options.severity,
        options.rule_id,
        tree.span(index),
        "'{s}' is already declared in the upper scope on line {d} column {d}.",
        .{ name, shadowed_position.line, shadowed_position.column },
    );
}

fn findShadowedValueSymbol(
    scope_tree: traverser.semantic.ScopeTree,
    symbol_table: traverser.semantic.SymbolTable,
    scope: traverser.semantic.ScopeId,
    name: []const u8,
) ?traverser.semantic.SymbolId {
    var current = scope_tree.getScope(scope).parent;
    while (current != .none) {
        if (symbol_table.findInScope(current, name)) |candidate_id| {
            const candidate_flags = symbol_table.getSymbol(candidate_id).flags;
            if (candidate_flags.inValueSpace() or candidate_flags.import or candidate_flags.namespace_module) {
                return candidate_id;
            }
        }
        current = scope_tree.getScope(current).parent;
    }
    return null;
}

fn scopeIdForNode(scope_tree: traverser.semantic.ScopeTree, node: ast.NodeIndex) ?traverser.semantic.ScopeId {
    for (scope_tree.scopes, 0..) |scope, index| {
        if (scope.node == node) return @enumFromInt(@as(u32, @intCast(index)));
    }
    return null;
}

fn isAllowedByHoist(
    tree: *const ast.Tree,
    self_decl: ast.NodeIndex,
    shadowed_decl: ast.NodeIndex,
    shadowed_flags: traverser.semantic.Symbol.Flags,
    options: Options,
) bool {
    if (tree.span(self_decl).start >= tree.span(shadowed_decl).start) return false;
    return switch (options.hoist) {
        .all => false,
        .functions => !shadowed_flags.function,
        .functions_and_types => !shadowed_flags.function and !isTypeSymbol(shadowed_flags),
        .never => true,
        .types => !isTypeSymbol(shadowed_flags),
    };
}

fn isTypeSymbol(flags: traverser.semantic.Symbol.Flags) bool {
    return flags.inTypeSpace() or flags.type_import;
}

fn offsetToLineColumn(source: []const u8, offset: u32) core.SourcePosition {
    const end = @min(@as(usize, @intCast(offset)), source.len);
    var line: usize = 1;
    var column: usize = 1;
    var index: usize = 0;

    while (index < end) : (index += 1) {
        if (source[index] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    return .{ .line = line, .column = column };
}
