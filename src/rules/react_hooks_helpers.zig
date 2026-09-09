const std = @import("std");
const parser = @import("parser");
const ast = parser.ast;
pub const SymbolTable = @import("../semantic_compat.zig").SymbolTable;

pub fn unwrap(tree: *const ast.Tree, node: ast.NodeIndex) ast.NodeIndex {
    var current = node;
    while (current != .null) {
        current = switch (tree.data(current)) {
            .parenthesized_expression => |e| e.expression,
            .chain_expression => |e| e.expression,
            .ts_as_expression => |e| e.expression,
            .ts_satisfies_expression => |e| e.expression,
            .ts_non_null_expression => |e| e.expression,
            .ts_type_assertion => |e| e.expression,
            else => return current,
        };
    }
    return current;
}

pub fn name(tree: *const ast.Tree, node: ast.NodeIndex) ?[]const u8 {
    if (node == .null) return null;
    return switch (tree.data(unwrap(tree, node))) {
        .binding_identifier => |n| tree.string(n.name),
        .identifier_reference => |n| tree.string(n.name),
        .identifier_name => |n| tree.string(n.name),
        .string_literal => |n| tree.string(n.value),
        else => null,
    };
}

pub fn memberName(tree: *const ast.Tree, member: ast.MemberExpression) ?[]const u8 {
    if (member.computed and tree.data(member.property) != .string_literal) return null;
    return name(tree, member.property);
}

pub const Property = union(enum) { field: []const u8, index: usize };
pub const Value = struct {
    node: ast.NodeIndex,
    properties: [16]Property = undefined,
    len: usize = 0,

    fn append(self: *Value, property: Property) bool {
        if (self.len == self.properties.len) return false;
        self.properties[self.len] = property;
        self.len += 1;
        return true;
    }
};
pub const MemoCall = struct { node: ast.NodeIndex, callback: ast.NodeIndex };

pub const Context = struct {
    tree: *const ast.Tree,
    symbols: SymbolTable,
    memo_calls: std.ArrayList(MemoCall) = .empty,

    pub fn init(allocator: std.mem.Allocator, tree: *const ast.Tree, symbols: SymbolTable) std.mem.Allocator.Error!Context {
        var context = Context{ .tree = tree, .symbols = symbols };
        errdefer context.memo_calls.deinit(allocator);
        const Collector = struct {
            context: *Context,
            allocator: std.mem.Allocator,
            pub fn enter_call_expression(self: *@This(), call: ast.CallExpression, node: ast.NodeIndex, _: *parser.traverser.basic.Ctx) std.mem.Allocator.Error!parser.traverser.Action {
                if (call.arguments.len > 0 and self.context.isReactApi(call.callee, "useMemo")) {
                    if (self.context.resolve(self.context.tree.extra(call.arguments)[0])) |value| {
                        if (value.len == 0 and (self.context.tree.data(value.node) == .function or self.context.tree.data(value.node) == .arrow_function_expression)) {
                            try self.context.memo_calls.append(self.allocator, .{ .node = node, .callback = value.node });
                        }
                    }
                }
                return .proceed;
            }
        };
        var collector = Collector{ .context = &context, .allocator = allocator };
        try parser.traverser.basic.traverse(Collector, tree, &collector);
        return context;
    }

    // Follow only stable bindings. Bounded paths also terminate cyclic aliases.
    pub fn resolve(self: Context, node: ast.NodeIndex) ?Value {
        return self.resolveDepth(node, 0);
    }

    fn resolveDepth(self: Context, expression: ast.NodeIndex, depth: usize) ?Value {
        if (depth >= 64) return null;
        const node = unwrap(self.tree, expression);
        if (node == .null) return null;
        if (self.tree.data(node) == .member_expression) {
            const member = self.tree.data(node).member_expression;
            const property = memberName(self.tree, member) orelse return null;
            var value = self.resolveDepth(member.object, depth + 1) orelse return null;
            if (!value.append(.{ .field = property })) return null;
            return value;
        }
        if (self.tree.data(node) != .identifier_reference) return .{ .node = node };
        const symbol = self.symbols.symbolOf(node) orelse return .{ .node = node };
        var uses = self.symbols.symbolUses(symbol);
        while (uses.next()) |use| {
            if (self.symbols.isWriteReference(self.symbols.model.referenceOf(use).?)) return null;
        }
        if (self.symbols.getSymbol(symbol).flags.import) return .{ .node = node };
        const declarations = self.symbols.symbolDecls(symbol);
        if (declarations.len != 1) return null;
        var current = declarations[0];
        var path: [16]Property = undefined;
        var count: usize = 0;
        while (self.symbols.parentOf(current)) |parent| {
            switch (self.tree.data(parent)) {
                .function => return .{ .node = parent },
                .variable_declarator => |variable| {
                    if (variable.id != current) return null;
                    var value = self.resolveDepth(variable.init, depth + 1) orelse return null;
                    while (count > 0) {
                        count -= 1;
                        if (!value.append(path[count])) return null;
                    }
                    return value;
                },
                .array_pattern => |pattern| {
                    if (count == path.len) return null;
                    var found = false;
                    for (self.tree.extra(pattern.elements), 0..) |element, index| {
                        if (element == current) {
                            path[count] = .{ .index = index };
                            count += 1;
                            found = true;
                            break;
                        }
                    }
                    if (!found) return null;
                },
                .binding_property => |property| {
                    if (property.value != current or count == path.len or
                        (property.computed and self.tree.data(property.key) != .string_literal)) return null;
                    path[count] = .{ .field = name(self.tree, property.key) orelse return null };
                    count += 1;
                },
                .object_pattern => {},
                else => return null,
            }
            current = parent;
        }
        return null;
    }

    pub fn isMemoCallback(self: Context, node: ast.NodeIndex) bool {
        for (self.memo_calls.items) |call| {
            if (call.callback == node and self.renderOwner(call.node) != null) return true;
        }
        return false;
    }

    // Resolve React imports by symbol, so aliases work and local shadows do not.
    // Stable local aliases and literal CommonJS imports use the same provenance.
    // Also accept conventional unresolved useX/React names, as rules-of-hooks does.
    pub fn isReactApi(self: Context, callee: ast.NodeIndex, api: []const u8) bool {
        const value = self.resolve(callee) orelse return false;
        if (value.len == 0) return self.isReactImport(value.node, api);
        if (value.len != 1 or value.properties[0] != .field or !std.mem.eql(u8, value.properties[0].field, api)) return false;
        if (self.isReactImport(value.node, null)) return true;
        if (self.tree.data(value.node) != .call_expression) return false;
        const call = self.tree.data(value.node).call_expression;
        const require = unwrap(self.tree, call.callee);
        return call.arguments.len == 1 and self.tree.data(self.tree.extra(call.arguments)[0]) == .string_literal and
            self.symbols.isUnresolvedReference(require) and
            std.mem.eql(u8, name(self.tree, require) orelse "", "require") and
            std.mem.eql(u8, name(self.tree, self.tree.extra(call.arguments)[0]) orelse "", "react");
    }

    fn isReactImport(self: Context, node: ast.NodeIndex, api: ?[]const u8) bool {
        if (self.tree.data(node) != .identifier_reference) return false;
        const symbol = self.symbols.symbolOf(node) orelse {
            return self.symbols.isUnresolvedReference(node) and
                std.mem.eql(u8, name(self.tree, node) orelse return false, api orelse "React");
        };
        if (!self.symbols.getSymbol(symbol).flags.import) return false;
        for (self.symbols.symbolDecls(symbol)) |declaration| {
            var current = declaration;
            var matches = false;
            while (true) {
                switch (self.tree.data(current)) {
                    .import_specifier => |s| {
                        matches = s.import_kind != .type and api != null and
                            std.mem.eql(u8, name(self.tree, s.imported) orelse "", api.?);
                    },
                    .import_default_specifier, .import_namespace_specifier => matches = api == null,
                    .import_declaration => |d| return matches and d.import_kind != .type and
                        std.mem.eql(u8, name(self.tree, d.source) orelse "", "react"),
                    else => {},
                }
                current = self.symbols.parentOf(current) orelse break;
            }
        }
        return false;
    }

    pub fn outerExpression(self: Context, node: ast.NodeIndex) ast.NodeIndex {
        var current = node;
        while (self.symbols.parentOf(current)) |parent| {
            if (unwrap(self.tree, parent) != node) break;
            current = parent;
        }
        return current;
    }

    pub fn callbackCall(self: Context, node: ast.NodeIndex) ?ast.CallExpression {
        const outer = self.outerExpression(node);
        const parent = self.symbols.parentOf(outer) orelse return null;
        const call = switch (self.tree.data(parent)) {
            .call_expression => |c| c,
            else => return null,
        };
        if (call.arguments.len == 0 or self.tree.extra(call.arguments)[0] != outer) return null;
        return call;
    }

    pub fn nearestFunction(self: Context, node: ast.NodeIndex) ?ast.NodeIndex {
        var current = node;
        while (self.symbols.parentOf(current)) |parent| {
            switch (self.tree.data(parent)) {
                .function, .arrow_function_expression => return parent,
                .class, .method_definition, .property_definition => return null,
                else => current = parent,
            }
        }
        return null;
    }

    // Deferred callbacks (events, effects, lazy initializers) are boundaries.
    // Resolved useMemo callbacks and synchronous IIFEs execute during render.
    pub fn renderOwner(self: Context, node: ast.NodeIndex) ?ast.NodeIndex {
        return self.renderOwnerDepth(node, undefined, 0);
    }

    fn renderOwnerDepth(self: Context, node: ast.NodeIndex, ancestors: [32]ast.NodeIndex, depth: usize) ?ast.NodeIndex {
        if (depth >= ancestors.len) return null;
        var path = ancestors;
        var current = node;
        while (self.nearestFunction(current)) |function| {
            for (ancestors[0..depth]) |ancestor| {
                if (ancestor == function) return null;
            }
            path[depth] = function;
            if (self.isReactFunction(function)) return function;
            const async_or_generator = switch (self.tree.data(function)) {
                .function => |f| f.async or f.generator,
                .arrow_function_expression => |f| f.async,
                else => unreachable,
            };
            if (async_or_generator) return null;
            if (self.callbackCall(function)) |call| {
                if (self.isReactApi(call.callee, "useMemo")) {
                    current = function;
                    continue;
                }
            }
            const outer = self.outerExpression(function);
            if (self.symbols.parentOf(outer)) |parent| {
                if (self.tree.data(parent) == .call_expression and self.tree.data(parent).call_expression.callee == outer) {
                    current = function;
                    continue;
                }
            }
            for (self.memo_calls.items) |call| {
                if (call.callback == function) {
                    if (self.renderOwnerDepth(call.node, path, depth + 1)) |owner| return owner;
                }
            }
            return null;
        }
        return null;
    }

    fn isReactFunction(self: Context, node: ast.NodeIndex) bool {
        const outer = self.outerExpression(node);
        const parent = self.symbols.parentOf(outer) orelse return false;
        if (self.tree.data(parent) == .method_definition or self.tree.data(parent) == .object_property or
            self.tree.data(parent) == .property_definition) return false;
        // A named callback is still deferred; only React wrappers define components.
        if (self.callbackCall(node)) |call| {
            return self.isReactApi(call.callee, "memo") or self.isReactApi(call.callee, "forwardRef");
        }
        if (self.tree.data(parent) == .call_expression and self.tree.data(parent).call_expression.callee != outer) return false;
        const function_name = switch (self.tree.data(parent)) {
            .variable_declarator => |d| name(self.tree, d.id),
            .assignment_expression => |a| name(self.tree, a.left),
            else => switch (self.tree.data(node)) {
                .function => |f| name(self.tree, f.id),
                else => null,
            },
        } orelse return false;
        return function_name.len > 0 and (std.ascii.isUpper(function_name[0]) or
            (std.mem.startsWith(u8, function_name, "use") and function_name.len > 3 and
                (std.ascii.isUpper(function_name[3]) or std.ascii.isDigit(function_name[3]))));
    }
};
