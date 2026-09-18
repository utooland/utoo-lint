const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "@alipay/ant/exhaustive-deps";

pub const Options = struct {
    rule_id: []const u8 = id,
    additional_hooks: core.ReactHooksAdditionalHooksPattern = .{},
    report_unnecessary_dependencies: bool = false,
    report_unstable_dependencies: bool = false,
};

const SymbolId = traverser.semantic.SymbolId;
const ReferenceLookup = std.AutoHashMap(ast.NodeIndex, SymbolId);
const DeclSymbolMap = std.AutoHashMap(ast.NodeIndex, SymbolId);
const SymbolSet = std.AutoHashMap(SymbolId, void);

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    return runWithOptions(allocator, diagnostics, tree, symbol_table, .{});
}

pub fn runWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    var reference_lookup = ReferenceLookup.init(allocator);
    defer reference_lookup.deinit();

    var decl_symbols = DeclSymbolMap.init(allocator);
    defer decl_symbols.deinit();

    var symbol_iter = symbol_table.iterSymbols();
    while (symbol_iter.next()) |entry| {
        for (symbol_table.symbolDecls(entry.id)) |decl| {
            try decl_symbols.put(decl, entry.id);
        }
    }

    var reference_iter = symbol_table.iterReferences();
    while (reference_iter.next()) |entry| {
        if (entry.reference.kind != .value) continue;
        try reference_lookup.put(entry.reference.node, symbol_table.referenceSymbol(entry.id));
    }

    var stable_symbols = SymbolSet.init(allocator);
    defer stable_symbols.deinit();

    // Bindings outside render scopes cannot change as a result of a render.
    var external_iter = symbol_table.iterSymbols();
    while (external_iter.next()) |entry| {
        if (entry.symbol.flags.import or entry.symbol.flags.type_import or
            entry.symbol.scope == .root or entry.symbol.scope == .module)
        {
            try stable_symbols.put(entry.id, {});
        }
    }

    var unstable_symbols = SymbolSet.init(allocator);
    defer unstable_symbols.deinit();

    var stable_visitor = StableSymbolVisitor{
        .decl_symbols = &decl_symbols,
        .stable_symbols = &stable_symbols,
        .unstable_symbols = &unstable_symbols,
    };
    try traverser.basic.traverse(StableSymbolVisitor, tree, &stable_visitor);

    var changed = true;
    while (changed) {
        changed = false;
        for (tree.nodes.items(.data), 0..) |data, raw_index| {
            const function: ast.NodeIndex, const binding: ast.NodeIndex = switch (data) {
                .function => |value| .{ @enumFromInt(raw_index), value.id },
                .variable_declarator => |value| .{ unwrapTransparent(tree, value.init), value.id },
                else => continue,
            };
            if (function == .null or binding == .null or !isFunctionLike(tree, function)) continue;
            const symbol = symbol_table.symbolOf(binding) orelse continue;
            if (stable_symbols.contains(symbol)) continue;
            if (functionCapturesReactiveValues(tree, symbol_table, function, symbol, &stable_symbols)) continue;
            try stable_symbols.put(symbol, {});
            changed = true;
        }
    }

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .symbol_table = symbol_table,
        .reference_lookup = &reference_lookup,
        .stable_symbols = &stable_symbols,
        .unstable_symbols = &unstable_symbols,
        .options = options,
    };
    try traverser.basic.traverse(Visitor, tree, &visitor);
}

fn functionCapturesReactiveValues(tree: *const ast.Tree, symbols: traverser.semantic.SymbolTable, function: ast.NodeIndex, function_symbol: SymbolId, stable: *const SymbolSet) bool {
    const span = tree.span(function);
    var references = symbols.iterReferences();
    while (references.next()) |entry| {
        if (entry.reference.kind != .value) continue;
        if (symbols.referenceSymbol(entry.id) == function_symbol and symbols.isWriteReference(entry.id)) return true;
        const reference_span = tree.span(entry.reference.node);
        if (reference_span.start < span.start or reference_span.end > span.end) continue;
        const symbol = symbols.referenceSymbol(entry.id);
        if (symbol == .none or symbol == function_symbol or stable.contains(symbol)) continue;
        const info = symbols.getSymbol(symbol);
        if (info.flags.import or info.flags.type_import or info.scope == .root or info.scope == .module) continue;
        var local = false;
        for (symbols.symbolDecls(symbol)) |declaration| {
            const declaration_span = tree.span(declaration);
            if (declaration_span.start >= span.start and declaration_span.end <= span.end) {
                local = true;
                break;
            }
        }
        if (!local) return true;
    }
    return false;
}

const StableSymbolVisitor = struct {
    decl_symbols: *const DeclSymbolMap,
    stable_symbols: *SymbolSet,
    unstable_symbols: *SymbolSet,

    pub fn enter_variable_declarator(
        self: *StableSymbolVisitor,
        declarator: ast.VariableDeclarator,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const declaration = switch (ctx.tree.data(ctx.path.ancestor(1) orelse .null)) {
            .variable_declaration => |declaration| declaration,
            else => return .proceed,
        };

        const stable = ctx.path.depth() <= 3 or
            (declaration.kind == .@"const" and isLiteralLike(ctx.tree, declarator.init)) or
            isUseRefCall(ctx.tree, declarator.init);
        if (stable) {
            try self.collectBinding(self.stable_symbols, declarator.id);
        } else if (declaration.kind == .@"const" and isUnstableInitializer(ctx.tree, declarator.init)) {
            try self.collectBinding(self.unstable_symbols, declarator.id);
        }

        if (declaration.kind == .@"const") {
            try self.collectStableHookTuple(ctx.tree, declarator);
        }

        _ = index;
        return .proceed;
    }

    pub fn enter_function(
        self: *StableSymbolVisitor,
        function: ast.Function,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (ctx.path.depth() <= 2 and function.id != .null) {
            try self.collectBinding(self.stable_symbols, function.id);
        }
        return .proceed;
    }

    fn collectStableHookTuple(
        self: *StableSymbolVisitor,
        tree: *const ast.Tree,
        declarator: ast.VariableDeclarator,
    ) Allocator.Error!void {
        const pattern = switch (tree.data(declarator.id)) {
            .array_pattern => |pattern| pattern,
            else => return,
        };
        const hook_name = hookNameForCall(tree, declarator.init) orelse return;
        if (!std.mem.eql(u8, hook_name, "useState") and
            !std.mem.eql(u8, hook_name, "useReducer") and
            !std.mem.eql(u8, hook_name, "useTransition"))
        {
            return;
        }

        const elements = tree.extra(pattern.elements);
        if (elements.len < 2) return;
        try self.collectBinding(self.stable_symbols, elements[1]);
    }

    fn collectBinding(self: *StableSymbolVisitor, symbols: *SymbolSet, index: ast.NodeIndex) Allocator.Error!void {
        if (index == .null) return;
        const symbol_id = self.decl_symbols.get(index) orelse return;
        if (symbol_id != .none) try symbols.put(symbol_id, {});
    }
};

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    symbol_table: traverser.semantic.SymbolTable,
    reference_lookup: *const ReferenceLookup,
    stable_symbols: *const SymbolSet,
    unstable_symbols: *const SymbolSet,
    options: Options,

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const hook = reactiveHook(ctx.tree, call, self.options.additional_hooks) orelse return .proceed;
        const args = ctx.tree.extra(call.arguments);
        if (args.len <= hook.callback_index) {
            try self.reportFmt(
                ctx.tree,
                call.callee,
                "React Hook {s} requires an effect callback. Did you forget to pass a callback to the hook?",
                .{hook.source},
            );
            return .proceed;
        }

        const callback = unwrapTransparent(ctx.tree, args[hook.callback_index]);
        if (hook.is_effect and isAsyncFunction(ctx.tree, callback)) {
            try core.addDiagnostic(
                self.allocator,
                self.diagnostics,
                .@"error",
                self.options.rule_id,
                asyncEffectMessage,
                ctx.tree.span(callback),
            );
        }

        if (!isFunctionLike(ctx.tree, callback)) {
            try self.reportFmt(
                ctx.tree,
                callback,
                "React Hook {s} received a function whose dependencies are unknown. Pass an inline function instead.",
                .{hook.source},
            );
            return .proceed;
        }

        if (args.len <= hook.callback_index + 1) {
            if (std.mem.eql(u8, hook.name, "useMemo") or std.mem.eql(u8, hook.name, "useCallback")) {
                try self.reportFmt(
                    ctx.tree,
                    call.callee,
                    "React Hook {s} does nothing when called with only one argument. Did you forget to pass an array of dependencies?",
                    .{hook.source},
                );
            }
            return .proceed;
        }

        const deps_node = unwrapTransparent(ctx.tree, args[hook.callback_index + 1]);
        var declared = std.StringHashMap(ast.NodeIndex).init(self.allocator);
        defer declared.deinit();

        var duplicate: ?[]const u8 = null;
        switch (ctx.tree.data(deps_node)) {
            .array_expression => |array| {
                for (ctx.tree.extra(array.elements)) |element| {
                    if (element == .null) continue;
                    const unwrapped = unwrapTransparent(ctx.tree, element);
                    switch (ctx.tree.data(unwrapped)) {
                        .spread_element => {
                            try self.reportFmt(
                                ctx.tree,
                                unwrapped,
                                "React Hook {s} has a spread element in its dependency array. This means we can't statically verify whether you've passed the correct dependencies.",
                                .{hook.source},
                            );
                        },
                        .string_literal, .numeric_literal, .bigint_literal, .boolean_literal, .null_literal => {
                            try self.reportFmt(
                                ctx.tree,
                                unwrapped,
                                "The {s} literal is not a valid dependency because it never changes. You can safely remove it.",
                                .{nodeSource(ctx.tree, unwrapped)},
                            );
                        },
                        else => {
                            const key = dependencyKey(ctx.tree, unwrapped) orelse {
                                try self.reportFmt(
                                    ctx.tree,
                                    unwrapped,
                                    "React Hook {s} has a complex expression in the dependency array. Extract it to a separate variable so it can be statically checked.",
                                    .{hook.source},
                                );
                                continue;
                            };
                            if (declared.contains(key)) {
                                if (duplicate == null) duplicate = key;
                            } else {
                                try declared.put(key, unwrapped);
                            }
                        },
                    }
                }
            },
            else => {
                try self.reportFmt(
                    ctx.tree,
                    deps_node,
                    "React Hook {s} was passed a dependency list that is not an array literal. This means we can't statically verify whether you've passed the correct dependencies.",
                    .{hook.source},
                );
            },
        }

        var used = std.StringHashMap(ast.NodeIndex).init(self.allocator);
        defer used.deinit();
        var dep_visitor = DependencyVisitor{
            .allocator = self.allocator,
            .callback_span = ctx.tree.span(callback),
            .used = &used,
            .symbol_table = self.symbol_table,
            .reference_lookup = self.reference_lookup,
            .stable_symbols = self.stable_symbols,
        };
        var callback_tree = ctx.tree.*;
        callback_tree.root = callback;
        try traverser.basic.traverse(DependencyVisitor, &callback_tree, &dep_visitor);

        if (duplicate) |name| {
            try self.reportFmt(
                ctx.tree,
                deps_node,
                "React Hook {s} has a duplicate dependency: '{s}'. Either omit it or remove the dependency array.",
                .{ hook.source, name },
            );
        }

        var missing_iter = used.iterator();
        while (missing_iter.next()) |entry| {
            const used_key = entry.key_ptr.*;
            if (declaredSatisfies(&declared, used_key)) continue;
            try self.reportFmt(
                ctx.tree,
                deps_node,
                "React Hook {s} has a missing dependency: '{s}'. Either include it or remove the dependency array.",
                .{ hook.source, used_key },
            );
        }

        var declared_iter = declared.iterator();
        while (declared_iter.next()) |entry| {
            const declared_key = entry.key_ptr.*;
            const declared_node = entry.value_ptr.*;
            if (self.options.report_unstable_dependencies and self.isUnstableDependency(ctx.tree, declared_node)) {
                try self.reportFmt(
                    ctx.tree,
                    declared_node,
                    "React Hook {s} has an unstable dependency: '{s}' is recreated on every render. Move it inside the Hook callback or wrap its initialization in useMemo or useCallback.",
                    .{ hook.source, declared_key },
                );
                continue;
            }
            if (self.options.report_unnecessary_dependencies and !hook.is_effect and !usedSatisfiesDeclared(&used, declared_key)) {
                try self.reportFmt(
                    ctx.tree,
                    declared_node,
                    "React Hook {s} has an unnecessary dependency: '{s}'. Either exclude it or remove the dependency array.",
                    .{ hook.source, declared_key },
                );
            }
        }

        return .proceed;
    }

    fn isUnstableDependency(self: *Visitor, tree: *const ast.Tree, index: ast.NodeIndex) bool {
        if (tree.data(unwrapTransparent(tree, index)) != .identifier_reference) return false;
        const root = dependencyRootReference(tree, index) orelse return false;
        const symbol_id = self.reference_lookup.get(root) orelse return false;
        return symbol_id != .none and self.unstable_symbols.contains(symbol_id);
    }

    fn reportFmt(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        comptime fmt: []const u8,
        args: anytype,
    ) Allocator.Error!void {
        try core.addDiagnosticFmt(self.allocator, self.diagnostics, .@"error", self.options.rule_id, tree.span(index), fmt, args);
    }
};

const DependencyVisitor = struct {
    allocator: Allocator,
    callback_span: ast.Span,
    used: *std.StringHashMap(ast.NodeIndex),
    symbol_table: traverser.semantic.SymbolTable,
    reference_lookup: *const ReferenceLookup,
    stable_symbols: *const SymbolSet,

    pub fn enter_identifier_reference(
        self: *DependencyVisitor,
        identifier: ast.IdentifierReference,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const span = ctx.tree.span(index);
        if (span.start < self.callback_span.start or span.end > self.callback_span.end) return .proceed;

        const symbol_id = self.reference_lookup.get(index) orelse return .proceed;
        if (symbol_id == .none or self.stable_symbols.contains(symbol_id)) return .proceed;
        if (self.symbolDeclaredInsideCallback(ctx.tree, symbol_id)) return .proceed;

        if (!isTopDependencyReference(ctx.tree, index, ctx)) return .proceed;

        const key = dependencyKey(ctx.tree, topDependencyNode(ctx.tree, index, ctx)) orelse ctx.tree.string(identifier.name);
        if (!self.used.contains(key)) try self.used.put(key, index);
        return .proceed;
    }

    fn symbolDeclaredInsideCallback(self: *DependencyVisitor, tree: *const ast.Tree, symbol_id: SymbolId) bool {
        for (self.symbol_table.symbolDecls(symbol_id)) |declaration| {
            const span = tree.span(declaration);
            if (span.start >= self.callback_span.start and span.end <= self.callback_span.end) return true;
        }
        return false;
    }
};

const ReactiveHook = struct {
    name: []const u8,
    source: []const u8,
    callback_index: usize,
    is_effect: bool,
};

fn reactiveHook(tree: *const ast.Tree, call: ast.CallExpression, additional_hooks: core.ReactHooksAdditionalHooksPattern) ?ReactiveHook {
    const name = hookNameForCallee(tree, call.callee) orelse return null;
    const callback_index: usize = if (std.mem.eql(u8, name, "useImperativeHandle")) 1 else 0;
    const built_in = std.mem.eql(u8, name, "useEffect") or
        std.mem.eql(u8, name, "useLayoutEffect") or
        std.mem.eql(u8, name, "useCallback") or
        std.mem.eql(u8, name, "useMemo") or
        std.mem.eql(u8, name, "useImperativeHandle");
    const additional = if (additional_hooks.pattern()) |pattern| matchesHookPattern(name, pattern) else false;
    if (!built_in and !additional) {
        return null;
    }
    return .{
        .name = name,
        .source = nodeSource(tree, call.callee),
        .callback_index = callback_index,
        .is_effect = additional or std.mem.eql(u8, name, "useEffect") or std.mem.eql(u8, name, "useLayoutEffect"),
    };
}

fn hookNameForCall(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    const call = switch (tree.data(unwrapTransparent(tree, index))) {
        .call_expression => |call| call,
        else => return null,
    };
    return hookNameForCallee(tree, call.callee);
}

fn hookNameForCallee(tree: *const ast.Tree, callee: ast.NodeIndex) ?[]const u8 {
    if (identifierReferenceName(tree, callee)) |name| return if (isHookName(name)) name else null;
    const member = switch (tree.data(unwrapTransparent(tree, callee))) {
        .member_expression => |member| member,
        else => return null,
    };
    if (member.computed) return null;
    if (!isIdentifierReferenceNamed(tree, unwrapTransparent(tree, member.object), "React")) return null;
    const name = propertyName(tree, member) orelse return null;
    return if (isHookName(name)) name else null;
}

fn isUseRefCall(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const name = hookNameForCall(tree, index) orelse return false;
    return std.mem.eql(u8, name, "useRef");
}

fn isHookName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "use")) return false;
    return name.len == 3 or (name.len > 3 and !std.ascii.isLower(name[3]));
}

fn isAsyncFunction(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(index)) {
        .function => |function| function.async,
        .arrow_function_expression => |function| function.async,
        else => false,
    };
}

fn isFunctionLike(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(index)) {
        .function, .arrow_function_expression => true,
        else => false,
    };
}

fn isLiteralLike(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;
    return tree.data(unwrapTransparent(tree, index)).isLiteral();
}

fn isUnstableInitializer(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .array_expression, .object_expression, .arrow_function_expression, .new_expression => true,
        .function => |function| function.type == .function_expression or function.type == .ts_empty_body_function_expression,
        .class => |class| class.type == .class_expression,
        else => false,
    };
}

fn dependencyKey(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    const unwrapped = unwrapTransparent(tree, index);
    return switch (tree.data(unwrapped)) {
        .identifier_reference => nodeSource(tree, unwrapped),
        .member_expression => |member| if (isStaticMemberChain(tree, member)) nodeSource(tree, unwrapped) else null,
        .chain_expression => |chain| dependencyKey(tree, chain.expression),
        else => null,
    };
}

fn isStaticMemberChain(tree: *const ast.Tree, member: ast.MemberExpression) bool {
    if (member.computed) return false;
    if (propertyName(tree, member) == null) return false;
    const object = unwrapTransparent(tree, member.object);
    return switch (tree.data(object)) {
        .identifier_reference => true,
        .member_expression => |inner| isStaticMemberChain(tree, inner),
        else => false,
    };
}

fn declaredSatisfies(declared: *const std.StringHashMap(ast.NodeIndex), used_key: []const u8) bool {
    var iter = declared.iterator();
    while (iter.next()) |entry| {
        if (declaredKeySatisfiesUsed(entry.key_ptr.*, used_key)) return true;
    }
    return false;
}

fn usedSatisfiesDeclared(used: *const std.StringHashMap(ast.NodeIndex), declared_key: []const u8) bool {
    var iter = used.iterator();
    while (iter.next()) |entry| {
        if (declaredKeySatisfiesUsed(declared_key, entry.key_ptr.*)) return true;
    }
    return false;
}

fn declaredKeySatisfiesUsed(declared_key: []const u8, used_key: []const u8) bool {
    if (std.mem.eql(u8, declared_key, used_key)) return true;
    return used_key.len > declared_key.len and
        std.mem.startsWith(u8, used_key, declared_key) and
        used_key[declared_key.len] == '.';
}

fn dependencyRootReference(tree: *const ast.Tree, index: ast.NodeIndex) ?ast.NodeIndex {
    const unwrapped = unwrapTransparent(tree, index);
    return switch (tree.data(unwrapped)) {
        .identifier_reference => unwrapped,
        .member_expression => |member| dependencyRootReference(tree, member.object),
        .chain_expression => |chain| dependencyRootReference(tree, chain.expression),
        else => null,
    };
}

fn matchesHookPattern(value: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return false;

    var body = pattern;
    var anchored_start = false;
    var anchored_end = false;
    if (std.mem.startsWith(u8, body, "^")) {
        anchored_start = true;
        body = body[1..];
    }
    if (body.len > 0 and std.mem.endsWith(u8, body, "$") and !isPatternCharacterEscaped(body, body.len - 1)) {
        anchored_end = true;
        body = body[0 .. body.len - 1];
    }
    if (body.len >= 2 and body[0] == '(' and body[body.len - 1] == ')') {
        body = body[1 .. body.len - 1];
    }

    var start: usize = 0;
    while (start <= body.len) {
        const separator = indexOfUnescapedPatternPipe(body[start..]);
        const end = if (separator) |offset| start + offset else body.len;
        if (matchesHookAlternative(value, body[start..end], anchored_start, anchored_end)) return true;
        if (separator == null) break;
        start = end + 1;
    }
    return false;
}

fn indexOfUnescapedPatternPipe(pattern: []const u8) ?usize {
    var index: usize = 0;
    var escaped = false;
    while (index < pattern.len) : (index += 1) {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (pattern[index] == '\\') {
            escaped = true;
            continue;
        }
        if (pattern[index] == '|') return index;
    }
    return null;
}

fn matchesHookAlternative(value: []const u8, pattern: []const u8, anchored_start: bool, anchored_end: bool) bool {
    if (pattern.len == 0) return false;
    if (anchored_start) return matchHookPatternAt(value, pattern, 0, 0, anchored_end);

    var start: usize = 0;
    while (start <= value.len) : (start += 1) {
        if (matchHookPatternAt(value, pattern, start, 0, anchored_end)) return true;
    }
    return false;
}

fn isPatternCharacterEscaped(pattern: []const u8, index: usize) bool {
    if (index == 0) return false;
    var backslashes: usize = 0;
    var cursor = index;
    while (cursor > 0 and pattern[cursor - 1] == '\\') : (cursor -= 1) {
        backslashes += 1;
    }
    return backslashes % 2 == 1;
}

fn matchHookPatternAt(value: []const u8, pattern: []const u8, value_index: usize, pattern_index: usize, anchored_end: bool) bool {
    if (pattern_index >= pattern.len) return !anchored_end or value_index == value.len;
    if (value_index > value.len) return false;

    const token = readHookPatternToken(pattern, pattern_index);
    const quantifier_index = pattern_index + token.pattern_len;
    const quantifier = if (quantifier_index < pattern.len and (pattern[quantifier_index] == '*' or pattern[quantifier_index] == '+')) pattern[quantifier_index] else 0;
    const next_pattern_index = quantifier_index + if (quantifier == 0) @as(usize, 0) else @as(usize, 1);

    if (quantifier == 0) {
        if (value_index >= value.len or !token.matches(value[value_index])) return false;
        return matchHookPatternAt(value, pattern, value_index + 1, next_pattern_index, anchored_end);
    }

    var max_count: usize = 0;
    while (value_index + max_count < value.len and token.matches(value[value_index + max_count])) : (max_count += 1) {}

    const min_count: usize = if (quantifier == '+') 1 else 0;
    if (max_count < min_count) return false;

    var count = max_count + 1;
    while (count > min_count) {
        count -= 1;
        if (matchHookPatternAt(value, pattern, value_index + count, next_pattern_index, anchored_end)) return true;
    }
    return false;
}

const HookPatternToken = struct {
    kind: enum { literal, any },
    literal: u8 = 0,
    pattern_len: usize,

    fn matches(self: HookPatternToken, value: u8) bool {
        return switch (self.kind) {
            .literal => self.literal == value,
            .any => true,
        };
    }
};

fn readHookPatternToken(pattern: []const u8, index: usize) HookPatternToken {
    if (pattern[index] == '.') return .{ .kind = .any, .pattern_len = 1 };
    if (pattern[index] == '\\' and index + 1 < pattern.len) {
        return .{ .kind = .literal, .literal = pattern[index + 1], .pattern_len = 2 };
    }
    return .{ .kind = .literal, .literal = pattern[index], .pattern_len = 1 };
}

fn isTopDependencyReference(tree: *const ast.Tree, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) bool {
    var current = index;
    var depth: usize = 1;
    while (true) : (depth += 1) {
        const parent_index = ctx.path.ancestor(depth) orelse return true;
        const parent = switch (tree.data(parent_index)) {
            .member_expression => |member| member,
            .chain_expression => continue,
            else => return true,
        };
        if (unwrapTransparent(tree, parent.object) != current) return true;
        current = parent_index;
    }
}

fn topDependencyNode(tree: *const ast.Tree, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) ast.NodeIndex {
    var current = index;
    var depth: usize = 1;
    while (true) : (depth += 1) {
        const parent_index = ctx.path.ancestor(depth) orelse return current;
        switch (tree.data(parent_index)) {
            .member_expression => |member| {
                if (unwrapTransparent(tree, member.object) != current) return current;
                if (member.computed) return current;
                if (propertyName(tree, member)) |name| {
                    if (std.mem.eql(u8, name, "current")) return current;
                }
                var outer_depth = depth + 1;
                while (ctx.path.ancestor(outer_depth)) |outer| : (outer_depth += 1) {
                    switch (tree.data(outer)) {
                        .chain_expression, .parenthesized_expression, .ts_non_null_expression => continue,
                        .call_expression => |call| {
                            if (unwrapTransparent(tree, call.callee) == parent_index) return current;
                        },
                        .assignment_expression => |assignment| {
                            if (unwrapTransparent(tree, assignment.left) == parent_index) return current;
                        },
                        else => {},
                    }
                    break;
                }
                current = parent_index;
            },
            .chain_expression => current = parent_index,
            else => return current,
        }
    }
}

fn bindingName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .binding_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn isIdentifierReferenceNamed(tree: *const ast.Tree, index: ast.NodeIndex, name: []const u8) bool {
    const actual = identifierReferenceName(tree, index) orelse return false;
    return std.mem.eql(u8, actual, name);
}

fn propertyName(tree: *const ast.Tree, member: ast.MemberExpression) ?[]const u8 {
    if (member.property == .null) return null;
    return if (member.computed)
        switch (tree.data(member.property)) {
            .string_literal => |literal| tree.string(literal.value),
            else => null,
        }
    else switch (tree.data(member.property)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn unwrapTransparent(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    var current = index;
    while (current != .null) {
        switch (tree.data(current)) {
            .chain_expression => |chain| current = chain.expression,
            .parenthesized_expression => |parenthesized| current = parenthesized.expression,
            .ts_non_null_expression => |expression| current = expression.expression,
            else => return current,
        }
    }
    return current;
}

fn nodeSource(tree: *const ast.Tree, index: ast.NodeIndex) []const u8 {
    const span = tree.span(index);
    if (span.start >= span.end or span.end > tree.source.len) return "";
    return std.mem.trim(u8, tree.source[span.start..span.end], " \t\r\n");
}

const asyncEffectMessage =
    "Effect callbacks are synchronous to prevent race conditions. Put the async function inside:\n\n" ++
    "useEffect(() => {\n" ++
    "  async function fetchData() {\n" ++
    "    // You can await here\n" ++
    "    const response = await MyAPI.getData(someId);\n" ++
    "    // ...\n" ++
    "  }\n" ++
    "  fetchData();\n" ++
    "}, [someId]); // Or [] if effect doesn't need props or state\n\n" ++
    "Learn more about data fetching with Hooks: https://reactjs.org/link/hooks-data-fetching";
