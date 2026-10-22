const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "jsx-a11y/alt-text";

pub const Options = struct {
    img: bool = true,
    object: bool = true,
    area: bool = true,
    input_image: bool = true,
    img_components: core.JsxA11yImgRedundantAltNames = .{},
    object_components: core.JsxA11yImgRedundantAltNames = .{},
    area_components: core.JsxA11yImgRedundantAltNames = .{},
    input_image_components: core.JsxA11yImgRedundantAltNames = .{},
};

const CheckedElement = enum {
    img,
    object,
    area,
    input_image,
};

pub fn checkOpeningElement(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    opening: ast.JSXOpeningElement,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    const tag_name = elementName(tree, opening.name) orelse return;
    switch (checkedElement(tag_name, options) orelse return) {
        .img => try checkImg(allocator, diagnostics, tree, opening, index, tag_name),
        .object => {},
        .area => try checkArea(allocator, diagnostics, tree, opening, index),
        .input_image => try checkInputImage(allocator, diagnostics, tree, opening, index, std.mem.eql(u8, tag_name, "input")),
    }
}

pub fn checkElement(
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
    if (checkedElement(tag_name, options) != .object) return;

    if (ariaLabelHasValue(tree, attributeNamed(tree, opening, "aria-label")) or
        ariaLabelHasValue(tree, attributeNamed(tree, opening, "aria-labelledby")) or
        titleHasValue(tree, attributeNamed(tree, opening, "title")) or
        hasAccessibleChild(tree, element))
    {
        return;
    }

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .warning,
        id,
        "Embedded <object> elements must have alternative text by providing inner text, aria-label or aria-labelledby props.",
        tree.span(index),
    );
}

fn checkedElement(tag_name: []const u8, options: Options) ?CheckedElement {
    if (options.img and (std.mem.eql(u8, tag_name, "img") or options.img_components.contains(tag_name))) {
        return .img;
    }
    if (options.object and (std.mem.eql(u8, tag_name, "object") or options.object_components.contains(tag_name))) {
        return .object;
    }
    if (options.area and (std.mem.eql(u8, tag_name, "area") or options.area_components.contains(tag_name))) {
        return .area;
    }
    if (options.input_image and (std.mem.eql(u8, tag_name, "input") or options.input_image_components.contains(tag_name))) {
        return .input_image;
    }
    return null;
}

fn checkArea(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    opening: ast.JSXOpeningElement,
    index: ast.NodeIndex,
) Allocator.Error!void {
    if (ariaLabelHasValue(tree, attributeNamed(tree, opening, "aria-label")) or
        ariaLabelHasValue(tree, attributeNamed(tree, opening, "aria-labelledby")))
    {
        return;
    }

    const alt = attributeNamed(tree, opening, "alt");
    if (alt != null and altValueIsValid(tree, alt.?)) return;
    try core.addDiagnostic(
        allocator,
        diagnostics,
        .warning,
        id,
        "Each area of an image map must have a text alternative through the `alt`, `aria-label`, or `aria-labelledby` prop.",
        tree.span(index),
    );
}

fn checkInputImage(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    opening: ast.JSXOpeningElement,
    index: ast.NodeIndex,
    require_image_type: bool,
) Allocator.Error!void {
    if (require_image_type) {
        const typ = attributeNamed(tree, opening, "type") orelse return;
        const type_value = propValue(tree, typ.value) orelse return;
        switch (type_value) {
            .string => |string| if (!std.mem.eql(u8, string, "image")) return,
            else => return,
        }
    }

    if (ariaLabelHasValue(tree, attributeNamed(tree, opening, "aria-label")) or
        ariaLabelHasValue(tree, attributeNamed(tree, opening, "aria-labelledby")))
    {
        return;
    }

    const alt = attributeNamed(tree, opening, "alt");
    if (alt != null and altValueIsValid(tree, alt.?)) return;
    try core.addDiagnostic(
        allocator,
        diagnostics,
        .warning,
        id,
        "<input> elements with type=\"image\" must have a text alternative through the `alt`, `aria-label`, or `aria-labelledby` prop.",
        tree.span(index),
    );
}

fn checkImg(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    opening: ast.JSXOpeningElement,
    index: ast.NodeIndex,
    tag_name: []const u8,
) Allocator.Error!void {
    const alt = attributeNamed(tree, opening, "alt");
    if (alt == null) {
        if (isPresentationRole(tree, opening)) {
            try core.addDiagnostic(
                allocator,
                diagnostics,
                .warning,
                id,
                "Prefer alt=\"\" over a presentational role. First rule of aria is to not use aria if it can be achieved via native HTML.",
                tree.span(index),
            );
            return;
        }
        if (attributeNamed(tree, opening, "aria-label")) |attribute| {
            if (!ariaLabelHasValue(tree, attribute)) {
                try core.addDiagnostic(
                    allocator,
                    diagnostics,
                    .warning,
                    id,
                    "The aria-label attribute must have a value. The alt attribute is preferred over aria-label for images.",
                    tree.span(index),
                );
            }
            return;
        }
        if (attributeNamed(tree, opening, "aria-labelledby")) |attribute| {
            if (!ariaLabelHasValue(tree, attribute)) {
                try core.addDiagnostic(
                    allocator,
                    diagnostics,
                    .warning,
                    id,
                    "The aria-labelledby attribute must have a value. The alt attribute is preferred over aria-labelledby for images.",
                    tree.span(index),
                );
            }
            return;
        }
        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            .warning,
            id,
            tree.span(index),
            "{s} elements must have an alt prop, either with meaningful text, or an empty string for decorative images.",
            .{tag_name},
        );
        return;
    }

    if (altValueIsValid(tree, alt.?)) return;
    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        .warning,
        id,
        tree.span(index),
        "Invalid alt value for {s}. Use alt=\"\" for presentational images.",
        .{tag_name},
    );
}

const PropValue = union(enum) {
    string: []const u8,
    boolean: bool,
    number: []const u8,
};

fn propValue(tree: *const ast.Tree, value_index: ast.NodeIndex) ?PropValue {
    if (value_index == .null) return .{ .boolean = true };
    return switch (tree.data(value_index)) {
        .string_literal => |literal| valueFromString(tree.string(literal.value)),
        .jsx_expression_container => |container| expressionValue(tree, container.expression),
        else => null,
    };
}

fn expressionValue(tree: *const ast.Tree, expression_index: ast.NodeIndex) ?PropValue {
    return switch (tree.data(expression_index)) {
        .string_literal => |literal| valueFromString(tree.string(literal.value)),
        .boolean_literal => |literal| .{ .boolean = literal.value },
        .numeric_literal => |literal| .{ .number = tree.string(literal.raw) },
        .identifier_reference => |identifier| if (std.mem.eql(u8, tree.string(identifier.name), "undefined")) null else null,
        .null_literal => null,
        .template_literal => |literal| templateValue(tree, literal),
        else => null,
    };
}

fn valueFromString(value: []const u8) PropValue {
    if (std.ascii.eqlIgnoreCase(value, "true")) return .{ .boolean = true };
    if (std.ascii.eqlIgnoreCase(value, "false")) return .{ .boolean = false };
    return .{ .string = value };
}

fn templateValue(tree: *const ast.Tree, literal: ast.TemplateLiteral) ?PropValue {
    if (literal.expressions.len != 0) return .{ .string = "{expression}" };
    const quasis = tree.extra(literal.quasis);
    if (quasis.len == 0) return .{ .string = "" };
    return switch (tree.data(quasis[0])) {
        .template_element => |element| valueFromString(tree.string(element.cooked)),
        else => null,
    };
}

fn ariaLabelHasValue(tree: *const ast.Tree, attribute: ?ast.JSXAttribute) bool {
    const attr = attribute orelse return false;
    const value = propValue(tree, attr.value) orelse return false;
    return switch (value) {
        .string => |string| string.len != 0,
        else => true,
    };
}

fn titleHasValue(tree: *const ast.Tree, attribute: ?ast.JSXAttribute) bool {
    const attr = attribute orelse return false;
    const value = propValue(tree, attr.value) orelse return false;
    return switch (value) {
        .string => |string| string.len != 0,
        else => true,
    };
}

fn altValueIsValid(tree: *const ast.Tree, attribute: ast.JSXAttribute) bool {
    if (attribute.value == .null) return false;
    const value = propValue(tree, attribute.value) orelse return false;
    return switch (value) {
        .string => true,
        .boolean => |boolean| boolean,
        .number => |number| number.len != 0,
    };
}

fn isPresentationRole(tree: *const ast.Tree, opening: ast.JSXOpeningElement) bool {
    const role = attributeNamed(tree, opening, "role") orelse return false;
    const value = propValue(tree, role.value) orelse return false;
    return switch (value) {
        .string => |string| std.mem.eql(u8, string, "presentation") or std.mem.eql(u8, string, "none"),
        else => false,
    };
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
                switch (tree.data(container.expression)) {
                    .identifier_reference => |identifier| {
                        if (!std.mem.eql(u8, tree.string(identifier.name), "undefined")) return true;
                    },
                    else => return true,
                }
            },
            else => {},
        }
    }

    const opening = switch (tree.data(element.opening_element)) {
        .jsx_opening_element => |opening| opening,
        else => return false,
    };
    return attributeNamed(tree, opening, "dangerouslySetInnerHTML") != null or attributeNamed(tree, opening, "children") != null;
}

fn isHiddenFromScreenReader(tree: *const ast.Tree, element: ast.JSXElement) bool {
    const opening = switch (tree.data(element.opening_element)) {
        .jsx_opening_element => |opening| opening,
        else => return false,
    };
    const tag_name = elementName(tree, opening.name) orelse return false;

    if (std.mem.eql(u8, tag_name, "input")) {
        if (attributeNamed(tree, opening, "type")) |attribute| {
            if (propValue(tree, attribute.value)) |value| {
                switch (value) {
                    .string => |string| if (std.ascii.eqlIgnoreCase(string, "hidden")) return true,
                    else => {},
                }
            }
        }
    }

    const aria_hidden = attributeNamed(tree, opening, "aria-hidden") orelse return false;
    const value = propValue(tree, aria_hidden.value) orelse return false;
    return switch (value) {
        .boolean => |boolean| boolean,
        else => false,
    };
}

fn attributeNamed(tree: *const ast.Tree, opening: ast.JSXOpeningElement, expected: []const u8) ?ast.JSXAttribute {
    for (tree.extra(opening.attributes)) |attribute_index| {
        const attribute = switch (tree.data(attribute_index)) {
            .jsx_attribute => |attribute| attribute,
            else => continue,
        };
        const name = attributeName(tree, attribute.name) orelse continue;
        if (std.ascii.eqlIgnoreCase(name, expected)) return attribute;
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
