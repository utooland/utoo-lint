const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "jsx-a11y/anchor-has-content";

const message = "Anchors must have content and the content must be accessible by a screen reader.";

pub const Options = struct {
    components: core.JsxA11yImgRedundantAltNames = .{},
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    element: ast.JSXElement,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    const opening = switch (tree.data(element.opening_element)) {
        .jsx_opening_element => |opening| opening,
        else => return,
    };
    const tag_name = elementName(tree, opening.name) orelse return;
    if (!isCheckedElement(tag_name, options.components)) return;

    if (hasAccessibleChild(tree, element) or hasAnyAttribute(tree, opening, &.{ "title", "aria-label" })) return;

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .warning,
        id,
        message,
        tree.span(index),
    );
}

fn isCheckedElement(tag_name: []const u8, components: core.JsxA11yImgRedundantAltNames) bool {
    return std.mem.eql(u8, tag_name, "a") or components.contains(tag_name);
}

fn hasAccessibleChild(tree: *const ast.Tree, element: ast.JSXElement) bool {
    for (tree.extra(element.children)) |child_index| {
        switch (tree.data(child_index)) {
            .jsx_text => |text| {
                if (tree.string(text.raw).len != 0) return true;
            },
            .jsx_element => |child| {
                if (!isHiddenFromScreenReader(tree, child)) return true;
            },
            .jsx_expression_container => |container| {
                if (tree.data(container.expression) == .identifier_reference) {
                    const identifier = tree.data(container.expression).identifier_reference;
                    if (!std.mem.eql(u8, tree.string(identifier.name), "undefined")) return true;
                } else {
                    return true;
                }
            },
            else => {},
        }
    }

    const opening = switch (tree.data(element.opening_element)) {
        .jsx_opening_element => |opening| opening,
        else => return false,
    };
    return hasAnyAttribute(tree, opening, &.{ "dangerouslySetInnerHTML", "children" });
}

fn isHiddenFromScreenReader(tree: *const ast.Tree, element: ast.JSXElement) bool {
    const opening = switch (tree.data(element.opening_element)) {
        .jsx_opening_element => |opening| opening,
        else => return false,
    };
    const tag_name = elementName(tree, opening.name) orelse return false;

    if (std.mem.eql(u8, tag_name, "input")) {
        if (attributeNamed(tree, opening, "type")) |attribute| {
            if (literalStringValue(tree, attribute.value)) |value| {
                if (std.ascii.eqlIgnoreCase(value, "hidden")) return true;
            }
        }
    }

    const aria_hidden = attributeNamed(tree, opening, "aria-hidden") orelse return false;
    return propValueIsTrue(tree, aria_hidden.value);
}

fn propValueIsTrue(tree: *const ast.Tree, value_index: ast.NodeIndex) bool {
    if (value_index == .null) return true;
    return switch (tree.data(value_index)) {
        .string_literal => |literal| std.ascii.eqlIgnoreCase(tree.string(literal.value), "true"),
        .jsx_expression_container => |container| switch (tree.data(container.expression)) {
            .boolean_literal => |literal| literal.value,
            else => false,
        },
        else => false,
    };
}

fn literalStringValue(tree: *const ast.Tree, value_index: ast.NodeIndex) ?[]const u8 {
    if (value_index == .null) return null;
    return switch (tree.data(value_index)) {
        .string_literal => |literal| tree.string(literal.value),
        .jsx_expression_container => |container| switch (tree.data(container.expression)) {
            .string_literal => |literal| tree.string(literal.value),
            else => null,
        },
        else => null,
    };
}

fn hasAnyAttribute(tree: *const ast.Tree, opening: ast.JSXOpeningElement, names: []const []const u8) bool {
    for (tree.extra(opening.attributes)) |attribute_index| {
        const attribute = switch (tree.data(attribute_index)) {
            .jsx_attribute => |attribute| attribute,
            else => continue,
        };
        const name = attributeName(tree, attribute.name) orelse continue;
        for (names) |expected| {
            if (std.mem.eql(u8, name, expected)) return true;
        }
    }
    return false;
}

fn attributeNamed(tree: *const ast.Tree, opening: ast.JSXOpeningElement, expected: []const u8) ?ast.JSXAttribute {
    for (tree.extra(opening.attributes)) |attribute_index| {
        const attribute = switch (tree.data(attribute_index)) {
            .jsx_attribute => |attribute| attribute,
            else => continue,
        };
        const name = attributeName(tree, attribute.name) orelse continue;
        if (std.mem.eql(u8, name, expected)) return attribute;
    }
    return null;
}

fn elementName(tree: *const ast.Tree, name_index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(name_index)) {
        .jsx_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn attributeName(tree: *const ast.Tree, name_index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(name_index)) {
        .jsx_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}
