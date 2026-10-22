const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "react/no-access-state-in-setstate";
const message = "Use callback in setState when referencing the previous state.";

const MethodUse = struct {
    method_name: []const u8,
    node: ast.NodeIndex,
};

const VariableUse = struct {
    scope_node: ast.NodeIndex,
    variable_name: []const u8,
    node: ast.NodeIndex,
};

pub const State = struct {
    methods: std.ArrayList(MethodUse) = .empty,
    variables: std.ArrayList(VariableUse) = .empty,

    pub fn deinit(self: *State, allocator: Allocator) void {
        self.methods.deinit(allocator);
        self.variables.deinit(allocator);
        self.* = .{};
    }
};

pub fn checkMemberExpression(
    allocator: Allocator,
    tree: *const ast.Tree,
    member: ast.MemberExpression,
    index: ast.NodeIndex,
    ctx: *traverser.basic.Ctx,
    state: *State,
) Allocator.Error!void {
    if (!isThisStateMember(tree, member)) return;
    if (componentAncestor(tree, ctx) == null) return;
    if (isInsideSetStateFirstArgument(tree, ctx)) return;
    if (methodAncestorName(tree, ctx)) |method| {
        try rememberMethod(allocator, state, method.name, index);
    }
}

pub fn checkVariableDeclarator(
    allocator: Allocator,
    tree: *const ast.Tree,
    declarator: ast.VariableDeclarator,
    index: ast.NodeIndex,
    ctx: *traverser.basic.Ctx,
    state: *State,
) Allocator.Error!void {
    if (componentAncestor(tree, ctx) == null) return;

    const scope_node = scopeAncestor(ctx) orelse return;
    if (isThisExpression(tree, declarator.init)) {
        try rememberDestructuredState(allocator, tree, declarator.id, scope_node, state);
        return;
    }

    const state_node = firstThisStateNode(tree, declarator.init) orelse return;
    try rememberBindingNames(allocator, tree, declarator.id, scope_node, state_node, state);

    const method = methodAncestorName(tree, ctx) orelse return;
    try rememberMethod(allocator, state, method.name, state_node);
    _ = index;
}

pub fn checkCallExpression(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    call: ast.CallExpression,
    index: ast.NodeIndex,
    ctx: *traverser.basic.Ctx,
    state: *State,
) Allocator.Error!void {
    if (componentAncestor(tree, ctx) == null) return;

    if (bareCalleeName(tree, call.callee)) |callee_name| {
        if (stateMethodNode(state, callee_name)) |state_node| {
            if (methodAncestorName(tree, ctx)) |method| {
                try rememberMethod(allocator, state, method.name, state_node);
            }
        }
    }

    if (!isThisSetStateCall(tree, call.callee)) return;
    const arguments = tree.extra(call.arguments);
    if (arguments.len == 0) return;

    const scope_node = scopeAncestor(ctx) orelse index;
    var reported = std.AutoHashMap(ast.NodeIndex, void).init(allocator);
    defer reported.deinit();
    try scanSetStateArgument(allocator, diagnostics, tree, arguments[0], scope_node, state, &reported);
}

fn scanSetStateArgument(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    scope_node: ast.NodeIndex,
    state: *const State,
    reported: *std.AutoHashMap(ast.NodeIndex, void),
) Allocator.Error!void {
    if (index == .null) return;
    const current = unwrapTransparent(tree, index);
    if (current == .null) return;

    const data = tree.data(current);
    switch (data) {
        .member_expression => |member| {
            if (isThisStateMember(tree, member)) {
                try reportOnce(allocator, diagnostics, tree, current, reported);
            }
        },
        .identifier_reference => |identifier| {
            const name = tree.string(identifier.name);
            if (stateVariableNode(state, scope_node, name)) |state_node| {
                try reportOnce(allocator, diagnostics, tree, state_node, reported);
            }
        },
        .call_expression => |call| {
            if (bareCalleeName(tree, call.callee)) |callee_name| {
                if (stateMethodNode(state, callee_name)) |state_node| {
                    try reportOnce(allocator, diagnostics, tree, state_node, reported);
                }
            }
        },
        else => {},
    }

    try scanChildren(allocator, diagnostics, tree, data, scope_node, state, reported);
}

fn scanChildren(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    data: ast.NodeData,
    scope_node: ast.NodeIndex,
    state: *const State,
    reported: *std.AutoHashMap(ast.NodeIndex, void),
) Allocator.Error!void {
    switch (data) {
        inline else => |node| {
            const T = @TypeOf(node);
            if (@typeInfo(T) != .@"struct") return;

            inline for (@typeInfo(T).@"struct".field_names) |field_name| {
                if (@FieldType(T, field_name) == ast.NodeIndex) {
                    try scanSetStateArgument(
                        allocator,
                        diagnostics,
                        tree,
                        @field(node, field_name),
                        scope_node,
                        state,
                        reported,
                    );
                } else if (@FieldType(T, field_name) == ast.IndexRange) {
                    const range = @field(node, field_name);
                    for (tree.extra(range)) |child| {
                        try scanSetStateArgument(allocator, diagnostics, tree, child, scope_node, state, reported);
                    }
                }
            }
        },
    }
}

fn reportOnce(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    node: ast.NodeIndex,
    reported: *std.AutoHashMap(ast.NodeIndex, void),
) Allocator.Error!void {
    if (reported.contains(node)) return;
    try reported.put(node, {});
    try core.addDiagnostic(allocator, diagnostics, .@"error", id, message, tree.span(node));
}

fn rememberMethod(allocator: Allocator, state: *State, method_name: []const u8, node: ast.NodeIndex) Allocator.Error!void {
    for (state.methods.items) |entry| {
        if (entry.node == node and std.mem.eql(u8, entry.method_name, method_name)) return;
    }
    try state.methods.append(allocator, .{ .method_name = method_name, .node = node });
}

fn rememberBindingNames(
    allocator: Allocator,
    tree: *const ast.Tree,
    binding: ast.NodeIndex,
    scope_node: ast.NodeIndex,
    node: ast.NodeIndex,
    state: *State,
) Allocator.Error!void {
    if (bindingIdentifierName(tree, binding)) |name| {
        return rememberVariable(allocator, state, scope_node, name, node);
    }

    switch (tree.data(binding)) {
        .object_pattern => |pattern| {
            for (tree.extra(pattern.properties)) |property_index| {
                const property = switch (tree.data(property_index)) {
                    .binding_property => |property| property,
                    else => continue,
                };
                try rememberBindingNames(allocator, tree, property.value, scope_node, node, state);
            }
        },
        .array_pattern => |pattern| {
            for (tree.extra(pattern.elements)) |element| {
                try rememberBindingNames(allocator, tree, element, scope_node, node, state);
            }
        },
        .assignment_pattern => |pattern| try rememberBindingNames(allocator, tree, pattern.left, scope_node, node, state),
        .binding_rest_element => |rest| try rememberBindingNames(allocator, tree, rest.argument, scope_node, node, state),
        else => {},
    }
}

fn rememberDestructuredState(
    allocator: Allocator,
    tree: *const ast.Tree,
    binding: ast.NodeIndex,
    scope_node: ast.NodeIndex,
    state: *State,
) Allocator.Error!void {
    const pattern = switch (tree.data(binding)) {
        .object_pattern => |pattern| pattern,
        else => return,
    };

    for (tree.extra(pattern.properties)) |property_index| {
        const property = switch (tree.data(property_index)) {
            .binding_property => |property| property,
            else => continue,
        };
        const key = propertyName(tree, property.key, property.computed) orelse continue;
        if (!std.mem.eql(u8, key, "state")) continue;

        if (bindingIdentifierName(tree, property.value)) |name| {
            try rememberVariable(allocator, state, scope_node, name, property.key);
        }
    }
}

fn rememberVariable(
    allocator: Allocator,
    state: *State,
    scope_node: ast.NodeIndex,
    variable_name: []const u8,
    node: ast.NodeIndex,
) Allocator.Error!void {
    for (state.variables.items) |entry| {
        if (entry.scope_node == scope_node and
            entry.node == node and
            std.mem.eql(u8, entry.variable_name, variable_name))
        {
            return;
        }
    }
    try state.variables.append(allocator, .{
        .scope_node = scope_node,
        .variable_name = variable_name,
        .node = node,
    });
}

fn stateMethodNode(state: *const State, name: []const u8) ?ast.NodeIndex {
    for (state.methods.items) |entry| {
        if (std.mem.eql(u8, entry.method_name, name)) return entry.node;
    }
    return null;
}

fn stateVariableNode(state: *const State, scope_node: ast.NodeIndex, name: []const u8) ?ast.NodeIndex {
    for (state.variables.items) |entry| {
        if (entry.scope_node == scope_node and std.mem.eql(u8, entry.variable_name, name)) return entry.node;
    }
    return null;
}

fn firstThisStateNode(tree: *const ast.Tree, index: ast.NodeIndex) ?ast.NodeIndex {
    if (index == .null) return null;
    const current = unwrapTransparent(tree, index);
    if (current == .null) return null;

    const data = tree.data(current);
    switch (data) {
        .member_expression => |member| {
            if (isThisStateMember(tree, member)) return current;
        },
        else => {},
    }

    return firstThisStateChild(tree, data);
}

fn firstThisStateChild(tree: *const ast.Tree, data: ast.NodeData) ?ast.NodeIndex {
    switch (data) {
        inline else => |node| {
            const T = @TypeOf(node);
            if (@typeInfo(T) != .@"struct") return null;

            inline for (@typeInfo(T).@"struct".field_names) |field_name| {
                if (@FieldType(T, field_name) == ast.NodeIndex) {
                    if (firstThisStateNode(tree, @field(node, field_name))) |found| return found;
                } else if (@FieldType(T, field_name) == ast.IndexRange) {
                    const range = @field(node, field_name);
                    for (tree.extra(range)) |child| {
                        if (firstThisStateNode(tree, child)) |found| return found;
                    }
                }
            }
        },
    }
    return null;
}

fn componentAncestor(tree: *const ast.Tree, ctx: *traverser.basic.Ctx) ?ast.NodeIndex {
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        switch (tree.data(ancestor)) {
            .class => |class| if (isReactComponentClass(tree, class)) return ancestor,
            .object_expression => if (isCreateClassObject(tree, ancestor, ctx.path.ancestor(depth + 1))) return ancestor,
            else => {},
        }
    }
    return null;
}

const NamedNode = struct {
    name: []const u8,
    node: ast.NodeIndex,
};

fn methodAncestorName(tree: *const ast.Tree, ctx: *traverser.basic.Ctx) ?NamedNode {
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        switch (tree.data(ancestor)) {
            .method_definition => |method| {
                const name = propertyName(tree, method.key, method.computed) orelse continue;
                return .{ .name = name, .node = ancestor };
            },
            .object_property => |property| {
                const name = propertyName(tree, property.key, property.computed) orelse continue;
                return .{ .name = name, .node = ancestor };
            },
            else => {},
        }
    }
    return null;
}

fn scopeAncestor(ctx: *traverser.basic.Ctx) ?ast.NodeIndex {
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        switch (ctx.tree.data(ancestor)) {
            .function,
            .arrow_function_expression,
            .method_definition,
            .object_property,
            .property_definition,
            => return ancestor,
            else => {},
        }
    }
    return null;
}

fn isThisSetStateCall(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const member = switch (tree.data(unwrapTransparent(tree, index))) {
        .member_expression => |member| member,
        else => return false,
    };
    if (member.computed) return false;
    if (!isThisExpression(tree, member.object)) return false;
    const name = propertyName(tree, member.property, false) orelse return false;
    return std.mem.eql(u8, name, "setState");
}

fn isInsideSetStateFirstArgument(tree: *const ast.Tree, ctx: *traverser.basic.Ctx) bool {
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        const call = switch (tree.data(ancestor)) {
            .call_expression => |call| call,
            else => continue,
        };
        if (!isThisSetStateCall(tree, call.callee)) continue;

        const arguments = tree.extra(call.arguments);
        if (arguments.len == 0) return false;
        const direct_child = ctx.path.ancestor(depth - 1) orelse return false;
        return direct_child == arguments[0];
    }
    return false;
}

fn isThisStateMember(tree: *const ast.Tree, member: ast.MemberExpression) bool {
    if (member.computed) return false;
    if (!isThisExpression(tree, member.object)) return false;
    const name = propertyName(tree, member.property, false) orelse return false;
    return std.mem.eql(u8, name, "state");
}

fn isThisExpression(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .this_expression => true,
        else => false,
    };
}

fn bareCalleeName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return identifierReferenceName(tree, unwrapTransparent(tree, index));
}

fn isCreateClassObject(tree: *const ast.Tree, index: ast.NodeIndex, parent_index: ?ast.NodeIndex) bool {
    const parent = parent_index orelse return false;
    const call = switch (tree.data(parent)) {
        .call_expression => |call| call,
        else => return false,
    };
    const arguments = tree.extra(call.arguments);
    if (arguments.len == 0 or arguments[0] != index) return false;
    return isCreateClassCallee(tree, call.callee);
}

fn isCreateClassCallee(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const callee = unwrapTransparent(tree, index);
    if (identifierReferenceName(tree, callee)) |name| {
        return std.mem.eql(u8, name, "createReactClass");
    }
    const member = switch (tree.data(callee)) {
        .member_expression => |member| member,
        else => return false,
    };
    if (member.computed) return false;
    if (!identifierReferenceEquals(tree, unwrapTransparent(tree, member.object), "React")) return false;
    const property = propertyName(tree, member.property, false) orelse return false;
    return std.mem.eql(u8, property, "createClass");
}

fn isReactComponentClass(tree: *const ast.Tree, class: ast.Class) bool {
    if (class.super_class == .null) return false;
    const super_class = unwrapTransparent(tree, class.super_class);

    if (identifierReferenceName(tree, super_class)) |name| {
        return std.mem.eql(u8, name, "Component") or std.mem.eql(u8, name, "PureComponent");
    }

    const member = switch (tree.data(super_class)) {
        .member_expression => |member| member,
        else => return false,
    };
    if (member.computed) return false;
    if (!identifierReferenceEquals(tree, unwrapTransparent(tree, member.object), "React")) return false;
    const property = propertyName(tree, member.property, false) orelse return false;
    return std.mem.eql(u8, property, "Component") or std.mem.eql(u8, property, "PureComponent");
}

fn propertyName(tree: *const ast.Tree, index: ast.NodeIndex, computed: bool) ?[]const u8 {
    if (computed or index == .null) return null;
    return switch (tree.data(index)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn bindingIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .binding_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn identifierReferenceEquals(tree: *const ast.Tree, index: ast.NodeIndex, expected: []const u8) bool {
    const name = identifierReferenceName(tree, index) orelse return false;
    return std.mem.eql(u8, name, expected);
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
