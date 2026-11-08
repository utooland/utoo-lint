const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "react/no-danger-with-children";

const message = "Only set one of `children` or `props.dangerouslySetInnerHTML`";

pub const ObjectBindings = struct {
    const capacity = 128;

    names: [capacity][]const u8 = undefined,
    values: [capacity]ast.NodeIndex = undefined,
    len: usize = 0,

    pub fn add(self: *ObjectBindings, name: []const u8, object_index: ast.NodeIndex) void {
        for (self.names[0..self.len], 0..) |existing, index| {
            if (std.mem.eql(u8, existing, name)) {
                self.values[index] = object_index;
                return;
            }
        }
        if (self.len >= capacity) return;
        self.names[self.len] = name;
        self.values[self.len] = object_index;
        self.len += 1;
    }

    pub fn find(self: *const ObjectBindings, name: []const u8) ?ast.NodeIndex {
        var index = self.len;
        while (index > 0) {
            index -= 1;
            if (std.mem.eql(u8, self.names[index], name)) return self.values[index];
        }
        return null;
    }
};

pub fn checkVariableDeclarator(tree: *const ast.Tree, declarator: ast.VariableDeclarator, bindings: *ObjectBindings) void {
    const name = bindingIdentifierName(tree, declarator.id) orelse return;
    if (declarator.init == .null) return;

    switch (tree.data(declarator.init)) {
        .object_expression => bindings.add(name, declarator.init),
        else => {},
    }
}

pub fn checkJSXElement(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    element: ast.JSXElement,
    index: ast.NodeIndex,
    bindings: *const ObjectBindings,
) Allocator.Error!void {
    const opening = switch (tree.data(element.opening_element)) {
        .jsx_opening_element => |opening| opening,
        else => return,
    };

    const has_children = hasJSXChildren(tree, element) or findJSXProp(tree, opening, "children", bindings);
    if (!has_children) return;
    if (!findJSXProp(tree, opening, "dangerouslySetInnerHTML", bindings)) return;

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .@"error",
        id,
        message,
        tree.span(index),
    );
}

pub fn checkCallExpression(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    call: ast.CallExpression,
    index: ast.NodeIndex,
    bindings: *const ObjectBindings,
) Allocator.Error!void {
    if (!isCreateElementMemberCall(tree, call)) return;

    const arguments = tree.extra(call.arguments);
    if (arguments.len <= 1) return;

    const props_index = resolvePropsObject(tree, arguments[1], bindings) orelse arguments[1];
    if (!findObjectProp(tree, props_index, "dangerouslySetInnerHTML", bindings)) return;

    const has_children = if (arguments.len == 2)
        findObjectProp(tree, props_index, "children", bindings)
    else
        true;

    if (!has_children) return;

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .@"error",
        id,
        message,
        tree.span(index),
    );
}

fn hasJSXChildren(tree: *const ast.Tree, element: ast.JSXElement) bool {
    const children = tree.extra(element.children);
    if (children.len == 0) return false;
    return !isLineBreak(tree, children[0]);
}

fn findJSXProp(
    tree: *const ast.Tree,
    opening: ast.JSXOpeningElement,
    prop_name: []const u8,
    bindings: *const ObjectBindings,
) bool {
    for (tree.extra(opening.attributes)) |attribute_index| {
        switch (tree.data(attribute_index)) {
            .jsx_attribute => |attribute| {
                const name = jsxIdentifierName(tree, attribute.name) orelse continue;
                if (std.mem.eql(u8, name, prop_name)) return true;
            },
            .jsx_spread_attribute => |attribute| {
                const name = identifierReferenceName(tree, attribute.argument) orelse continue;
                const object_index = bindings.find(name) orelse continue;
                var seen = SeenProps{};
                if (findObjectPropRecursive(tree, object_index, prop_name, bindings, &seen)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn findObjectProp(
    tree: *const ast.Tree,
    object_index: ast.NodeIndex,
    prop_name: []const u8,
    bindings: *const ObjectBindings,
) bool {
    var seen = SeenProps{};
    return findObjectPropRecursive(tree, object_index, prop_name, bindings, &seen);
}

const SeenProps = struct {
    const capacity = 32;

    names: [capacity][]const u8 = undefined,
    len: usize = 0,

    fn contains(self: *const SeenProps, name: []const u8) bool {
        for (self.names[0..self.len]) |seen| {
            if (std.mem.eql(u8, seen, name)) return true;
        }
        return false;
    }

    fn add(self: *SeenProps, name: []const u8) void {
        if (self.len >= capacity) return;
        self.names[self.len] = name;
        self.len += 1;
    }
};

fn findObjectPropRecursive(
    tree: *const ast.Tree,
    object_index: ast.NodeIndex,
    prop_name: []const u8,
    bindings: *const ObjectBindings,
    seen: *SeenProps,
) bool {
    const object = switch (tree.data(object_index)) {
        .object_expression => |object| object,
        else => return false,
    };

    for (tree.extra(object.properties)) |property_index| {
        switch (tree.data(property_index)) {
            .object_property => |property| {
                const key = objectPropertyKeyName(tree, property) orelse continue;
                if (std.mem.eql(u8, key, prop_name)) return true;
            },
            .spread_element => |spread| {
                const name = identifierReferenceName(tree, spread.argument) orelse continue;
                if (seen.contains(name)) continue;
                const spread_object = bindings.find(name) orelse continue;
                seen.add(name);
                if (findObjectPropRecursive(tree, spread_object, prop_name, bindings, seen)) return true;
            },
            else => {},
        }
    }

    return false;
}

fn resolvePropsObject(tree: *const ast.Tree, index: ast.NodeIndex, bindings: *const ObjectBindings) ?ast.NodeIndex {
    if (tree.data(index) == .object_expression) return index;
    const name = identifierReferenceName(tree, index) orelse return null;
    return bindings.find(name);
}

fn isCreateElementMemberCall(tree: *const ast.Tree, call: ast.CallExpression) bool {
    const member = switch (tree.data(unwrapTransparent(tree, call.callee))) {
        .member_expression => |member| member,
        else => return false,
    };
    if (member.computed) return false;

    const property = objectPropertyKeyNameFromIndex(tree, member.property) orelse return false;
    return std.mem.eql(u8, property, "createElement");
}

fn isLineBreak(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const value = switch (tree.data(index)) {
        .jsx_text => |text| tree.string(text.value),
        .string_literal => |literal| tree.string(literal.value),
        else => return false,
    };
    if (!containsLineBreak(value)) return false;
    for (value) |byte| {
        if (!isWhitespace(byte)) return false;
    }
    return true;
}

fn objectPropertyKeyName(tree: *const ast.Tree, property: ast.ObjectProperty) ?[]const u8 {
    if (property.computed) return null;
    return objectPropertyKeyNameFromIndex(tree, property.key);
}

fn objectPropertyKeyNameFromIndex(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(index)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn bindingIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(index)) {
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

fn jsxIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(index)) {
        .jsx_identifier => |identifier| tree.string(identifier.name),
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

fn containsLineBreak(value: []const u8) bool {
    return std.mem.indexOfScalar(u8, value, '\n') != null or std.mem.indexOfScalar(u8, value, '\r') != null;
}

fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}
