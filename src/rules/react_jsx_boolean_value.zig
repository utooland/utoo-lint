const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "react/jsx-boolean-value";

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    attribute: ast.JSXAttribute,
    index: ast.NodeIndex,
) Allocator.Error!void {
    return checkWithStyle(allocator, diagnostics, tree, attribute, index, .never);
}

pub fn checkWithStyle(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    attribute: ast.JSXAttribute,
    index: ast.NodeIndex,
    style: core.ReactJsxBooleanValueStyle,
) Allocator.Error!void {
    const name = attributeName(tree, attribute.name) orelse return;
    if (style == .never) {
        if (!isExplicitTrue(tree, attribute.value)) return;

        const span = ast.Span{ .start = tree.span(attribute.name).end, .end = tree.span(attribute.value).end };
        const message = try std.fmt.allocPrint(allocator, "Value must be omitted for boolean attribute `{s}`", .{name});
        defer allocator.free(message);
        const fix = core.Fix{ .span = span, .replacement = "" };
        try core.addDiagnosticWithFixes(allocator, diagnostics, .@"error", id, message, tree.span(index), if (hasComments(tree, span)) &.{} else &.{fix});
        return;
    }

    if (attribute.value != .null) return;

    const end = tree.span(attribute.name).end;
    const message = try std.fmt.allocPrint(allocator, "Value must be set for boolean attribute `{s}`", .{name});
    defer allocator.free(message);
    try core.addDiagnosticWithFix(allocator, diagnostics, .@"error", id, message, tree.span(index), .{
        .span = .{ .start = end, .end = end },
        .replacement = "={true}",
    });
}

fn attributeName(tree: *const ast.Tree, name_index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(name_index)) {
        .jsx_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn isExplicitTrue(tree: *const ast.Tree, value_index: ast.NodeIndex) bool {
    if (value_index == .null) return false;

    const container = switch (tree.data(value_index)) {
        .jsx_expression_container => |container| container,
        else => return false,
    };

    return switch (tree.data(container.expression)) {
        .boolean_literal => |literal| literal.value,
        else => false,
    };
}

fn hasComments(tree: *const ast.Tree, span: ast.Span) bool {
    for (tree.comments) |comment| {
        if (comment.span.start < span.end and comment.span.end > span.start) return true;
    }
    return false;
}
