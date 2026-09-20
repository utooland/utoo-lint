const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "@typescript-eslint/prefer-as-const";

pub fn checkAsExpression(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    expression: ast.TSAsExpression,
) Allocator.Error!void {
    try compareTypes(allocator, diagnostics, tree, expression.expression, expression.type_annotation, true);
}

pub fn checkTypeAssertion(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    assertion: ast.TSTypeAssertion,
) Allocator.Error!void {
    try compareTypes(allocator, diagnostics, tree, assertion.expression, assertion.type_annotation, true);
}

pub fn checkPropertyDefinition(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    property: ast.PropertyDefinition,
) Allocator.Error!void {
    if (property.value == .null or property.type_annotation == .null) return;
    try compareTypes(allocator, diagnostics, tree, property.value, annotationType(tree, property.type_annotation), false);
}

pub fn checkVariableDeclarator(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    declarator: ast.VariableDeclarator,
) Allocator.Error!void {
    if (declarator.init == .null) return;
    const type_annotation = bindingTypeAnnotation(tree, declarator.id);
    if (type_annotation == .null) return;
    try compareTypes(allocator, diagnostics, tree, declarator.init, annotationType(tree, type_annotation), false);
}

fn compareTypes(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    value_node: ast.NodeIndex,
    type_node: ast.NodeIndex,
    can_fix: bool,
) Allocator.Error!void {
    if (type_node == .null) return;

    const value_raw = literalRaw(tree, value_node) orelse return;
    const type_literal = switch (tree.data(type_node)) {
        .ts_literal_type => |literal_type| literal_type.literal,
        else => return,
    };
    const type_raw = literalRaw(tree, type_literal) orelse return;

    if (!std.mem.eql(u8, value_raw, type_raw)) return;

    const fix = core.Fix{ .span = tree.span(type_node), .replacement = "const" };
    try core.addDiagnosticWithFixes(
        allocator,
        diagnostics,
        .warning,
        id,
        if (can_fix)
            "Expected a `const` instead of a literal type assertion."
        else
            "Expected a `const` assertion instead of a literal type annotation.",
        tree.span(type_node),
        if (can_fix and tree.data(unwrapParenthesized(tree, value_node)) != .null_literal and !hasComments(tree, tree.span(type_node))) &.{fix} else &.{},
    );
}

fn annotationType(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    return switch (tree.data(index)) {
        .ts_type_annotation => |annotation| annotation.type_annotation,
        else => .null,
    };
}

fn bindingTypeAnnotation(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    return switch (tree.data(index)) {
        .binding_identifier => |identifier| identifier.type_annotation,
        else => .null,
    };
}

fn literalRaw(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    const literal = unwrapParenthesized(tree, index);
    switch (tree.data(literal)) {
        .string_literal,
        .numeric_literal,
        .bigint_literal,
        .boolean_literal,
        .null_literal,
        => {},
        else => return null,
    }

    const span = tree.span(literal);
    if (span.end > tree.source.len or span.start > span.end) return null;
    return tree.source[span.start..span.end];
}

fn unwrapParenthesized(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    var current = index;

    while (current != .null) {
        switch (tree.data(current)) {
            .parenthesized_expression => |parenthesized| current = parenthesized.expression,
            else => return current,
        }
    }

    return current;
}

fn hasComments(tree: *const ast.Tree, span: ast.Span) bool {
    for (tree.comments) |comment| {
        if (comment.span.start < span.end and comment.span.end > span.start) return true;
    }
    return false;
}
