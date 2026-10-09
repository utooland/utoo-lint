const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-use-before-define";

const SymbolId = traverser.semantic.SymbolId;
const DeclSymbolMap = std.AutoHashMap(ast.NodeIndex, SymbolId);
const NodeSet = std.AutoHashMap(ast.NodeIndex, void);

pub const Options = struct {
    rule_id: []const u8 = id,
    severity: core.Severity = .warning,
    check_functions: bool = true,
    check_classes: bool = true,
    check_variables: bool = true,
    check_type_references: bool = false,
    check_typedefs: bool = true,
    check_enums: bool = true,
    allow_named_exports: bool = false,
};

const InitRange = struct {
    symbol_id: SymbolId,
    span: ast.Span,
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
    var decl_symbols = DeclSymbolMap.init(allocator);
    defer decl_symbols.deinit();

    var symbol_iter = symbol_table.iterSymbols();
    while (symbol_iter.next()) |entry| {
        if (!isLintableSymbol(entry.symbol.flags, options)) continue;
        for (symbol_table.symbolDecls(entry.id)) |decl| {
            try decl_symbols.put(decl, entry.id);
        }
    }

    var init_ranges: std.ArrayList(InitRange) = .empty;
    defer init_ranges.deinit(allocator);

    var deferred_initializer_ranges: std.ArrayList(ast.Span) = .empty;
    defer deferred_initializer_ranges.deinit(allocator);

    var visitor = InitVisitor{
        .allocator = allocator,
        .decl_symbols = &decl_symbols,
        .init_ranges = &init_ranges,
        .deferred_initializer_ranges = &deferred_initializer_ranges,
    };
    try traverser.basic.traverse(InitVisitor, tree, &visitor);
    std.mem.sort(InitRange, init_ranges.items, {}, lessThanInitRange);

    var named_export_refs = NodeSet.init(allocator);
    defer named_export_refs.deinit();

    if (options.allow_named_exports) {
        var named_export_visitor = NamedExportVisitor{
            .refs = &named_export_refs,
        };
        try traverser.basic.traverse(NamedExportVisitor, tree, &named_export_visitor);
    }

    var reference_iter = symbol_table.iterReferences();
    while (reference_iter.next()) |entry| {
        const reference = entry.reference;
        if (reference.type_position and !options.check_type_references) continue;
        if (options.allow_named_exports and named_export_refs.contains(reference.node)) continue;

        const symbol_id = symbol_table.referenceSymbol(entry.id);
        if (symbol_id == .none) continue;

        const symbol = symbol_table.getSymbol(symbol_id);
        if (!isLintableReferenceSymbol(symbol.flags, reference, options)) continue;
        if (reference.kind == .value and shouldIgnoreVariableReference(scope_tree, reference.scope, symbol.scope, symbol.flags, options)) continue;

        const decls = symbol_table.symbolDecls(symbol_id);
        if (decls.len == 0) continue;

        const reference_span = tree.span(reference.node);
        const definition_span = tree.span(decls[0]);
        const is_deferred_initializer_reference = crossesFunctionScope(scope_tree, reference.scope, symbol.scope) or
            isInSpan(reference_span, deferred_initializer_ranges.items);
        const is_direct_initializer_reference = isInInitializer(symbol_id, reference_span, init_ranges.items) and
            !is_deferred_initializer_reference;
        if (reference_span.end >= definition_span.end and !is_direct_initializer_reference) {
            continue;
        }

        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            options.severity,
            options.rule_id,
            reference_span,
            "'{s}' was used before it was defined.",
            .{tree.string(reference.name)},
        );
    }
}

const InitVisitor = struct {
    allocator: Allocator,
    decl_symbols: *const DeclSymbolMap,
    init_ranges: *std.ArrayList(InitRange),
    deferred_initializer_ranges: *std.ArrayList(ast.Span),

    pub fn enter_variable_declarator(
        self: *InitVisitor,
        declarator: ast.VariableDeclarator,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (declarator.init == .null) return .proceed;
        try self.collectBinding(ctx.tree, declarator.id, ctx.tree.span(declarator.init));
        return .proceed;
    }

    pub fn enter_property_definition(
        self: *InitVisitor,
        property: ast.PropertyDefinition,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (!property.static and property.value != .null) {
            try self.deferred_initializer_ranges.append(self.allocator, ctx.tree.span(property.value));
        }
        return .proceed;
    }

    fn collectBinding(
        self: *InitVisitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        init_span: ast.Span,
    ) Allocator.Error!void {
        if (index == .null) return;

        switch (tree.data(index)) {
            .binding_identifier => {
                const symbol_id = self.decl_symbols.get(index) orelse return;
                try self.init_ranges.append(self.allocator, .{
                    .symbol_id = symbol_id,
                    .span = init_span,
                });
            },
            .assignment_pattern => |pattern| try self.collectBinding(tree, pattern.left, init_span),
            .binding_rest_element => |element| try self.collectBinding(tree, element.argument, init_span),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    try self.collectBinding(tree, element, init_span);
                }
                try self.collectBinding(tree, pattern.rest, init_span);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    try self.collectBinding(tree, property.value, init_span);
                }
                try self.collectBinding(tree, pattern.rest, init_span);
            },
            else => {},
        }
    }
};

const NamedExportVisitor = struct {
    refs: *NodeSet,

    pub fn enter_export_specifier(
        self: *NamedExportVisitor,
        specifier: ast.ExportSpecifier,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (specifier.export_kind == .type) return .proceed;

        if (ctx.path.parent()) |parent| {
            const parent_data = ctx.tree.data(parent);
            if (parent_data == .export_named_declaration and
                parent_data.export_named_declaration.source == .null and
                parent_data.export_named_declaration.export_kind != .type)
            {
                try self.refs.put(specifier.local, {});
            }
        }

        return .proceed;
    }
};

fn isInInitializer(symbol_id: SymbolId, reference_span: ast.Span, init_ranges: []const InitRange) bool {
    const start = lowerBoundInitRange(init_ranges, symbol_id);

    for (init_ranges[start..]) |range| {
        if (range.symbol_id != symbol_id) break;
        if (spanInside(reference_span, range.span)) return true;
    }
    return false;
}

fn lessThanInitRange(_: void, lhs: InitRange, rhs: InitRange) bool {
    return @intFromEnum(lhs.symbol_id) < @intFromEnum(rhs.symbol_id);
}

fn lowerBoundInitRange(init_ranges: []const InitRange, symbol_id: SymbolId) usize {
    const needle = @intFromEnum(symbol_id);
    var low: usize = 0;
    var high: usize = init_ranges.len;

    while (low < high) {
        const middle = low + (high - low) / 2;
        if (@intFromEnum(init_ranges[middle].symbol_id) < needle) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }

    return low;
}

fn spanInside(span: ast.Span, container: ast.Span) bool {
    return span.start >= container.start and span.end <= container.end;
}

fn isInSpan(span: ast.Span, containers: []const ast.Span) bool {
    for (containers) |container| {
        if (spanInside(span, container)) return true;
    }
    return false;
}

fn shouldIgnoreVariableReference(
    scope_tree: traverser.semantic.ScopeTree,
    reference_scope: traverser.semantic.ScopeId,
    symbol_scope: traverser.semantic.ScopeId,
    flags: traverser.semantic.Symbol.Flags,
    options: Options,
) bool {
    if (options.check_variables) return false;
    if (!isVariableSymbol(flags)) return false;
    if (reference_scope == symbol_scope) return false;
    return crossesFunctionScope(scope_tree, reference_scope, symbol_scope);
}

fn isVariableSymbol(flags: traverser.semantic.Symbol.Flags) bool {
    if (flags.function or flags.class or flags.import) return false;
    return flags.function_scoped_var or flags.block_scoped_var;
}

fn crossesFunctionScope(
    scope_tree: traverser.semantic.ScopeTree,
    reference_scope: traverser.semantic.ScopeId,
    symbol_scope: traverser.semantic.ScopeId,
) bool {
    var current = reference_scope;
    while (current != .none and current != symbol_scope) {
        const scope = scope_tree.getScope(current);
        if (scope.kind == .function) return true;
        current = scope.parent;
    }
    return false;
}

fn isLintableSymbol(flags: traverser.semantic.Symbol.Flags, options: Options) bool {
    return isLintableValueSymbol(flags, options);
}

fn isLintableReferenceSymbol(
    flags: traverser.semantic.Symbol.Flags,
    reference: traverser.semantic.Reference,
    options: Options,
) bool {
    // Type-only exports can name a value that consumers use in a typeof query.
    if (reference.space == .any and reference.type_position and !flags.inTypeSpace() and !flags.type_import) {
        return isLintableValueSymbol(flags, options);
    }
    return switch (reference.kind) {
        .value => isLintableValueSymbol(flags, options),
        .type => isLintableTypeSymbol(flags, options),
    };
}

fn isLintableValueSymbol(flags: traverser.semantic.Symbol.Flags, options: Options) bool {
    if (flags.ambient) return false;
    if (flags.type_import or flags.interface or flags.type_alias or flags.type_parameter) return false;
    if (!options.check_functions and flags.function) return false;
    if (!options.check_classes and flags.class) return false;
    return flags.inValueSpace() or flags.import;
}

fn isLintableTypeSymbol(flags: traverser.semantic.Symbol.Flags, options: Options) bool {
    if (flags.ambient) return false;
    if (!options.check_typedefs and isTypedefSymbol(flags)) return false;
    if (!options.check_enums and isEnumSymbol(flags)) return false;
    if (!options.check_classes and flags.class) return false;
    return flags.inTypeSpace() or flags.type_import;
}

fn isTypedefSymbol(flags: traverser.semantic.Symbol.Flags) bool {
    return flags.interface or flags.type_alias or flags.type_import;
}

fn isEnumSymbol(flags: traverser.semantic.Symbol.Flags) bool {
    return flags.regular_enum or flags.const_enum;
}
