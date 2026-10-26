const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "react/jsx-no-target-blank";

pub const Options = struct {
    allow_referrer: bool = false,
    enforce_dynamic_links: bool = true,
    warn_on_spread_attributes: bool = false,
    links: bool = true,
    forms: bool = false,
};

const CheckedElement = enum {
    link,
    form,
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    opening: ast.JSXOpeningElement,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    const element = checkedElement(tree, opening.name, options) orelse return;
    const url_attribute = switch (element) {
        .link => "href",
        .form => "action",
    };

    if (options.warn_on_spread_attributes and hasUnsafeSpreadAttribute(tree, opening, options.allow_referrer, url_attribute)) {
        try addDiagnostic(allocator, diagnostics, tree, index, null);
        return;
    }

    const target = lastAttributeNamed(tree, opening, "target") orelse return;
    if (!attributeValuePossiblyBlank(tree, target.attribute)) return;
    if (!hasDangerousUrl(tree, opening, url_attribute, options.enforce_dynamic_links)) return;
    if (hasSecureRel(tree, opening, target.attribute.value, options.allow_referrer)) return;

    try addDiagnostic(allocator, diagnostics, tree, index, safeRelFix(tree, opening, target.attribute, options.allow_referrer));
}

fn addDiagnostic(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    fix: ?core.Fix,
) Allocator.Error!void {
    try core.addDiagnosticWithFixes(
        allocator,
        diagnostics,
        .@"error",
        id,
        "Using target=\"_blank\" without rel=\"noreferrer\" (which implies rel=\"noopener\") is a security risk in older browsers: see https://mathiasbynens.github.io/rel-noopener/#recommendations",
        tree.span(index),
        if (fix) |value| &.{value} else &.{},
    );
}

fn safeRelFix(tree: *const ast.Tree, opening: ast.JSXOpeningElement, target: ast.JSXAttribute, allow_referrer: bool) ?core.Fix {
    _ = literalAttributeValueIndex(tree, target.value) orelse return null;
    const target_value = stringValue(tree, target.value) orelse return null;
    if (!std.ascii.eqlIgnoreCase(target_value, "_blank")) return null;

    const attributes = tree.extra(opening.attributes);
    var rel_attribute: ?ast.JSXAttribute = null;
    for (attributes) |attribute_index| {
        const attribute = switch (tree.data(attribute_index)) {
            // A spread may supply or override rel with a value we cannot preserve.
            .jsx_spread_attribute => return null,
            .jsx_attribute => |value| value,
            else => continue,
        };
        const name = attributeName(tree, attribute.name) orelse continue;
        if (!std.mem.eql(u8, name, "rel")) continue;
        if (rel_attribute != null) return null;
        rel_attribute = attribute;
    }

    if (rel_attribute) |attribute| {
        const literal_index = literalAttributeValueIndex(tree, attribute.value) orelse return null;
        const span = tree.span(literal_index);
        if (span.end < span.start + 2 or span.end > tree.source.len) return null;
        const quote = tree.source[span.start];
        if (quote != '"' and quote != '\'' and quote != '`') return null;
        if (tree.source[span.end - 1] != quote) return null;
        const end = span.end - 1;
        const empty = span.end == span.start + 2;
        return .{
            .span = .{ .start = end, .end = end },
            .replacement = if (allow_referrer)
                (if (empty) "noopener" else " noopener")
            else
                (if (empty) "noreferrer" else " noreferrer"),
        };
    }

    const end = tree.span(attributes[attributes.len - 1]).end;
    return .{
        .span = .{ .start = end, .end = end },
        .replacement = if (allow_referrer) " rel=\"noopener\"" else " rel=\"noreferrer\"",
    };
}

fn literalAttributeValueIndex(tree: *const ast.Tree, value: ast.NodeIndex) ?ast.NodeIndex {
    if (value == .null) return null;
    return switch (tree.data(value)) {
        .string_literal => value,
        .jsx_expression_container => |container| switch (tree.data(container.expression)) {
            .string_literal => container.expression,
            .template_literal => |literal| if (literal.expressions.len == 0) container.expression else null,
            else => null,
        },
        else => null,
    };
}

const AttributeMatch = struct {
    attribute: ast.JSXAttribute,
};

fn checkedElement(tree: *const ast.Tree, name_index: ast.NodeIndex, options: Options) ?CheckedElement {
    const name = switch (tree.data(name_index)) {
        .jsx_identifier => |identifier| tree.string(identifier.name),
        else => return null,
    };
    if (options.links and std.mem.eql(u8, name, "a")) return .link;
    if (options.forms and std.mem.eql(u8, name, "form")) return .form;
    return null;
}

fn lastAttributeNamed(tree: *const ast.Tree, opening: ast.JSXOpeningElement, name: []const u8) ?AttributeMatch {
    const attributes = tree.extra(opening.attributes);
    var cursor = attributes.len;
    while (cursor > 0) {
        cursor -= 1;
        const attribute = switch (tree.data(attributes[cursor])) {
            .jsx_attribute => |attribute| attribute,
            else => continue,
        };
        if (attributeName(tree, attribute.name)) |attribute_name| {
            if (std.mem.eql(u8, attribute_name, name)) return .{ .attribute = attribute };
        }
    }
    return null;
}

fn hasUnsafeSpreadAttribute(tree: *const ast.Tree, opening: ast.JSXOpeningElement, allow_referrer: bool, url_attribute: []const u8) bool {
    const attributes = tree.extra(opening.attributes);
    var last_spread: ?usize = null;
    for (attributes, 0..) |attribute_index, index| {
        switch (tree.data(attribute_index)) {
            .jsx_spread_attribute => last_spread = index,
            else => {},
        }
    }

    const spread_index = last_spread orelse return false;
    for (attributes[spread_index + 1 ..]) |attribute_index| {
        const attribute = switch (tree.data(attribute_index)) {
            .jsx_attribute => |attribute| attribute,
            else => continue,
        };
        const name = attributeName(tree, attribute.name) orelse continue;

        if (std.mem.eql(u8, name, "rel") and attributeRelValueIsSecure(tree, attribute, allow_referrer)) return false;
        if (std.mem.eql(u8, name, "target") and !attributeValuePossiblyBlank(tree, attribute)) return false;
        if (std.mem.eql(u8, name, url_attribute) and attributeValueIsSafeUrl(tree, attribute)) return false;
    }
    return true;
}

fn attributeName(tree: *const ast.Tree, name_index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(name_index)) {
        .jsx_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn attributeValuePossiblyBlank(tree: *const ast.Tree, attribute: ast.JSXAttribute) bool {
    if (attribute.value == .null) return false;
    if (stringValue(tree, attribute.value)) |value| return std.ascii.eqlIgnoreCase(value, "_blank");

    const container = switch (tree.data(attribute.value)) {
        .jsx_expression_container => |container| container,
        else => return false,
    };
    const conditional = switch (tree.data(container.expression)) {
        .conditional_expression => |conditional| conditional,
        else => return false,
    };
    return isStringLiteralIgnoreCase(tree, conditional.consequent, "_blank") or
        isStringLiteralIgnoreCase(tree, conditional.alternate, "_blank");
}

fn hasDangerousUrl(tree: *const ast.Tree, opening: ast.JSXOpeningElement, url_attribute: []const u8, enforce_dynamic_links: bool) bool {
    const url = lastAttributeNamed(tree, opening, url_attribute) orelse return false;
    if (url.attribute.value == .null) return false;
    if (stringValue(tree, url.attribute.value)) |value| return isExternalHref(value);
    return enforce_dynamic_links and tree.data(url.attribute.value) == .jsx_expression_container;
}

fn hasSecureRel(tree: *const ast.Tree, opening: ast.JSXOpeningElement, target_value: ast.NodeIndex, allow_referrer: bool) bool {
    const rel = lastAttributeNamed(tree, opening, "rel") orelse return false;
    if (rel.attribute.value == .null) return false;

    var values: [2]?[]const u8 = .{ null, null };
    const count = relValues(tree, rel.attribute.value, target_value, &values);
    if (count == 0) return false;

    for (values[0..count]) |value| {
        if (!valueIsSecureRel(value orelse return false, allow_referrer)) return false;
    }
    return true;
}

fn attributeRelValueIsSecure(tree: *const ast.Tree, attribute: ast.JSXAttribute, allow_referrer: bool) bool {
    if (attribute.value == .null) return false;
    const value = stringValue(tree, attribute.value) orelse return false;
    return valueIsSecureRel(value, allow_referrer);
}

fn attributeValueIsSafeUrl(tree: *const ast.Tree, attribute: ast.JSXAttribute) bool {
    if (attribute.value == .null) return false;
    const value = stringValue(tree, attribute.value) orelse return false;
    return !isExternalHref(value);
}

fn relValues(tree: *const ast.Tree, rel_value: ast.NodeIndex, target_value: ast.NodeIndex, values: *[2]?[]const u8) usize {
    if (stringValue(tree, rel_value)) |value| {
        values[0] = value;
        return 1;
    }

    const rel_container = switch (tree.data(rel_value)) {
        .jsx_expression_container => |container| container,
        else => return 0,
    };
    const rel_conditional = switch (tree.data(rel_container.expression)) {
        .conditional_expression => |conditional| conditional,
        else => return 0,
    };

    if (matchingTargetBlankBranch(tree, target_value, rel_conditional)) |branch| {
        values[0] = switch (branch) {
            .consequent => stringValue(tree, rel_conditional.consequent),
            .alternate => stringValue(tree, rel_conditional.alternate),
        };
        return 1;
    }

    values[0] = stringValue(tree, rel_conditional.consequent);
    values[1] = stringValue(tree, rel_conditional.alternate);
    return 2;
}

const Branch = enum { consequent, alternate };

fn matchingTargetBlankBranch(tree: *const ast.Tree, target_value: ast.NodeIndex, rel_conditional: ast.ConditionalExpression) ?Branch {
    const target_container = switch (tree.data(target_value)) {
        .jsx_expression_container => |container| container,
        else => return null,
    };
    const target_conditional = switch (tree.data(target_container.expression)) {
        .conditional_expression => |conditional| conditional,
        else => return null,
    };
    if (!sameIdentifierReference(tree, target_conditional.@"test", rel_conditional.@"test")) return null;
    if (isStringLiteral(tree, target_conditional.consequent, "_blank")) return .consequent;
    if (isStringLiteral(tree, target_conditional.alternate, "_blank")) return .alternate;
    return null;
}

fn stringValue(tree: *const ast.Tree, value_index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(value_index)) {
        .string_literal => |literal| tree.string(literal.value),
        .jsx_expression_container => |container| switch (tree.data(container.expression)) {
            .string_literal => |literal| tree.string(literal.value),
            .template_literal => |literal| firstTemplateQuasi(tree, literal),
            else => null,
        },
        else => null,
    };
}

fn firstTemplateQuasi(tree: *const ast.Tree, literal: ast.TemplateLiteral) ?[]const u8 {
    const quasis = tree.extra(literal.quasis);
    if (quasis.len == 0) return null;
    return switch (tree.data(quasis[0])) {
        .template_element => |element| tree.string(element.cooked),
        else => null,
    };
}

fn isExternalHref(value: []const u8) bool {
    if (std.mem.startsWith(u8, value, "//")) return true;
    const colon_index = std.mem.indexOfScalar(u8, value, ':') orelse return false;
    if (colon_index == 0) return false;

    for (value[0..colon_index]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn valueHasNoreferrer(value: []const u8) bool {
    var iter = std.mem.tokenizeScalar(u8, value, ' ');
    while (iter.next()) |token| {
        if (std.ascii.eqlIgnoreCase(token, "noreferrer")) return true;
    }
    return false;
}

fn valueIsSecureRel(value: []const u8, allow_referrer: bool) bool {
    if (valueHasNoreferrer(value)) return true;
    if (!allow_referrer) return false;

    var iter = std.mem.tokenizeScalar(u8, value, ' ');
    while (iter.next()) |token| {
        if (std.ascii.eqlIgnoreCase(token, "noopener")) return true;
    }
    return false;
}

fn isStringLiteralIgnoreCase(tree: *const ast.Tree, index: ast.NodeIndex, expected: []const u8) bool {
    const value = stringValue(tree, index) orelse return false;
    return std.ascii.eqlIgnoreCase(value, expected);
}

fn isStringLiteral(tree: *const ast.Tree, index: ast.NodeIndex, expected: []const u8) bool {
    const value = stringValue(tree, index) orelse return false;
    return std.mem.eql(u8, value, expected);
}

fn sameIdentifierReference(tree: *const ast.Tree, left: ast.NodeIndex, right: ast.NodeIndex) bool {
    const left_name = identifierReferenceName(tree, left) orelse return false;
    const right_name = identifierReferenceName(tree, right) orelse return false;
    return std.mem.eql(u8, left_name, right_name);
}

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}
