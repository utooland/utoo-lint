const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "object-shorthand";

pub const Options = struct {
    style: core.ObjectShorthandStyle = .always,
    avoid_quotes: bool = false,
    ignore_constructors: bool = false,
    avoid_explicit_return_arrows: bool = false,
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    property: ast.ObjectProperty,
    index: ast.NodeIndex,
) Allocator.Error!void {
    return checkWithOptions(allocator, diagnostics, tree, property, index, .{});
}

pub fn checkWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    property: ast.ObjectProperty,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    if (property.kind != .init) return;

    if (options.style == .never) {
        const shorthand_kind: ?ShorthandKind = if (property.shorthand)
            .property
        else if (property.method)
            .method
        else
            null;
        if (shorthand_kind == null) return;
        return addDiagnostic(allocator, diagnostics, tree, property, index, shorthand_kind.?, options.style);
    }

    if (property.shorthand or property.method) return;
    if (options.avoid_quotes and isStringLiteralKey(tree, property.key)) return;

    const shorthand_kind = shorthandKind(tree, property, options) orelse return;
    if (options.ignore_constructors and shorthand_kind == .method and isConstructorKey(tree, property.key)) return;
    if (!styleAllowsKind(options.style, shorthand_kind)) return;

    try addDiagnostic(allocator, diagnostics, tree, property, index, shorthand_kind, options.style);
}

fn addDiagnostic(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    property: ast.ObjectProperty,
    index: ast.NodeIndex,
    shorthand_kind: ShorthandKind,
    style: core.ObjectShorthandStyle,
) Allocator.Error!void {
    const message = if (style == .never) switch (shorthand_kind) {
        .property => "Expected property longform.",
        .method => "Expected method longform.",
    } else switch (shorthand_kind) {
        .property => "Expected property shorthand.",
        .method => "Expected method shorthand.",
    };

    if (changesProtoSetterSemantics(tree, property)) {
        try core.addDiagnostic(allocator, diagnostics, .warning, id, message, tree.span(index));
        return;
    }

    if (style == .never) {
        const replacement = switch (shorthand_kind) {
            .property => try propertyLongformReplacement(allocator, tree, property, index),
            .method => try methodLongformReplacement(allocator, tree, property, index),
        };
        if (replacement) |value| {
            defer allocator.free(value);
            try core.addDiagnosticWithFix(
                allocator,
                diagnostics,
                .warning,
                id,
                message,
                tree.span(index),
                .{ .span = tree.span(index), .replacement = value },
            );
            return;
        }
    }

    if (style != .never and shorthand_kind == .method) {
        if (try methodShorthandReplacement(allocator, tree, property, index)) |replacement| {
            defer allocator.free(replacement);
            try core.addDiagnosticWithFix(
                allocator,
                diagnostics,
                .warning,
                id,
                message,
                tree.span(index),
                .{ .span = tree.span(index), .replacement = replacement },
            );
            return;
        }
    }

    if (style != .never and shorthand_kind == .property) {
        const property_span = tree.span(index);
        const value_span = tree.span(unwrapTransparent(tree, property.value));
        if (!hasComment(tree.source[property_span.start..value_span.start]) and
            !hasComment(tree.source[value_span.end..property_span.end]))
        {
            try core.addDiagnosticWithFix(
                allocator,
                diagnostics,
                .warning,
                id,
                message,
                property_span,
                .{
                    .span = property_span,
                    .replacement = tree.source[value_span.start..value_span.end],
                },
            );
            return;
        }
    }

    try core.addDiagnostic(allocator, diagnostics, .warning, id, message, tree.span(index));
}

fn hasComment(source: []const u8) bool {
    return std.mem.indexOf(u8, source, "//") != null or std.mem.indexOf(u8, source, "/*") != null;
}

fn changesProtoSetterSemantics(tree: *const ast.Tree, property: ast.ObjectProperty) bool {
    if (property.computed) return false;
    const name = propertyKeyName(tree, property.key) orelse return false;
    return std.mem.eql(u8, name, "__proto__");
}

fn methodShorthandReplacement(
    allocator: Allocator,
    tree: *const ast.Tree,
    property: ast.ObjectProperty,
    index: ast.NodeIndex,
) Allocator.Error!?[]u8 {
    const value_index = unwrapTransparent(tree, property.value);
    return switch (tree.data(value_index)) {
        .function => |function| functionMethodShorthandReplacement(allocator, tree, property, index, function),
        .arrow_function_expression => |arrow| arrowMethodShorthandReplacement(allocator, tree, property, index, value_index, arrow),
        else => return null,
    };
}

fn functionMethodShorthandReplacement(
    allocator: Allocator,
    tree: *const ast.Tree,
    property: ast.ObjectProperty,
    index: ast.NodeIndex,
    function: ast.Function,
) Allocator.Error!?[]u8 {
    const key_span = objectKeySourceSpan(tree, property, index) orelse return null;
    const tail_span = if (function.type_parameters != .null)
        tree.span(function.type_parameters)
    else
        tree.span(function.params);
    const property_span = tree.span(index);
    if (hasComment(tree.source[key_span.end..tail_span.start])) return null;

    return try std.fmt.allocPrint(
        allocator,
        "{s}{s}{s}{s}",
        .{
            if (function.async) "async " else "",
            if (function.generator) "*" else "",
            tree.source[key_span.start..key_span.end],
            tree.source[tail_span.start..property_span.end],
        },
    );
}

fn arrowMethodShorthandReplacement(
    allocator: Allocator,
    tree: *const ast.Tree,
    property: ast.ObjectProperty,
    index: ast.NodeIndex,
    arrow_index: ast.NodeIndex,
    arrow: ast.ArrowFunctionExpression,
) Allocator.Error!?[]u8 {
    const key_span = objectKeySourceSpan(tree, property, index) orelse return null;
    const arrow_span = tree.span(arrow_index);
    const params_span = tree.span(arrow.params);
    const body_span = tree.span(arrow.body);
    const property_span = tree.span(index);

    const arrow_search = tree.source[params_span.end..body_span.start];
    const arrow_offset = std.mem.lastIndexOf(u8, arrow_search, "=>") orelse return null;
    const arrow_start: usize = @as(usize, params_span.end) + arrow_offset;
    if (hasComment(tree.source[key_span.end..arrow_span.start]) or
        hasComment(tree.source[params_span.start..arrow_start]) or
        hasComment(tree.source[arrow_start + 2 .. body_span.start]) or
        hasComment(tree.source[body_span.end..property_span.end])) return null;

    const params_source = tree.source[params_span.start..params_span.end];
    const params_parenthesized = params_source.len >= 2 and params_source[0] == '(' and params_source[params_source.len - 1] == ')';
    const type_parameters_source = if (arrow.type_parameters != .null) source: {
        const type_parameters_span = tree.span(arrow.type_parameters);
        break :source tree.source[type_parameters_span.start..params_span.start];
    } else "";
    const return_type_source = trimRightWhitespace(tree.source[params_span.end..arrow_start]);

    return try std.fmt.allocPrint(
        allocator,
        "{s}{s}{s}{s}{s}{s}{s} {s}",
        .{
            if (arrow.async) "async " else "",
            tree.source[key_span.start..key_span.end],
            type_parameters_source,
            if (params_parenthesized) "" else "(",
            params_source,
            if (params_parenthesized) "" else ")",
            return_type_source,
            tree.source[body_span.start..body_span.end],
        },
    );
}

fn trimRightWhitespace(source: []const u8) []const u8 {
    var end = source.len;
    while (end > 0 and std.ascii.isWhitespace(source[end - 1])) end -= 1;
    return source[0..end];
}

fn propertyLongformReplacement(
    allocator: Allocator,
    tree: *const ast.Tree,
    property: ast.ObjectProperty,
    index: ast.NodeIndex,
) Allocator.Error!?[]u8 {
    const property_span = tree.span(index);
    const key_span = tree.span(property.key);
    if (property_span.start != key_span.start or property_span.end != key_span.end) return null;

    const key_source = tree.source[key_span.start..key_span.end];
    return try std.fmt.allocPrint(allocator, "{s}: {s}", .{ key_source, key_source });
}

fn methodLongformReplacement(
    allocator: Allocator,
    tree: *const ast.Tree,
    property: ast.ObjectProperty,
    index: ast.NodeIndex,
) Allocator.Error!?[]u8 {
    const function = switch (tree.data(unwrapTransparent(tree, property.value))) {
        .function => |function| function,
        else => return null,
    };
    if (containsSuperReference(tree, function.body)) return null;
    const key_span = objectKeySourceSpan(tree, property, index) orelse return null;
    const tail_span = if (function.type_parameters != .null)
        tree.span(function.type_parameters)
    else
        tree.span(function.params);
    const property_span = tree.span(index);
    if (hasComment(tree.source[property_span.start..key_span.start]) or
        hasComment(tree.source[key_span.end..tail_span.start])) return null;

    return try std.fmt.allocPrint(
        allocator,
        "{s}: {s}function{s}{s}",
        .{
            tree.source[key_span.start..key_span.end],
            if (function.async) "async " else "",
            if (function.generator) "*" else "",
            tree.source[tail_span.start..property_span.end],
        },
    );
}

fn containsSuperReference(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;

    switch (tree.data(index)) {
        .super => return true,
        .function, .class => return false,
        inline else => |node| return childrenContainSuperReference(tree, @TypeOf(node), node),
    }
}

fn childrenContainSuperReference(tree: *const ast.Tree, comptime T: type, node: T) bool {
    if (@typeInfo(T) != .@"struct") return false;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            if (containsSuperReference(tree, @field(node, field_name))) return true;
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                if (containsSuperReference(tree, child)) return true;
            }
        }
    }
    return false;
}

fn objectKeySourceSpan(tree: *const ast.Tree, property: ast.ObjectProperty, index: ast.NodeIndex) ?ast.Span {
    const key_span = tree.span(property.key);
    if (!property.computed) return key_span;

    const property_span = tree.span(index);
    var start: usize = @intCast(key_span.start);
    while (start > property_span.start and std.ascii.isWhitespace(tree.source[start - 1])) start -= 1;
    if (start == property_span.start or tree.source[start - 1] != '[') return null;
    start -= 1;

    var end: usize = @intCast(key_span.end);
    while (end < property_span.end and std.ascii.isWhitespace(tree.source[end])) end += 1;
    if (end >= property_span.end or tree.source[end] != ']') return null;

    return .{ .start = @intCast(start), .end = @intCast(end + 1) };
}

const ShorthandKind = enum {
    property,
    method,
};

fn shorthandKind(tree: *const ast.Tree, property: ast.ObjectProperty, options: Options) ?ShorthandKind {
    if (!property.computed) {
        const key_name = propertyKeyName(tree, property.key);
        if (key_name != null and identifierReferenceNamed(tree, property.value, key_name.?)) return .property;
    }

    if (isAnonymousFunctionExpression(tree, property.value)) return .method;
    if (options.avoid_explicit_return_arrows and isExplicitReturnArrowFunction(tree, property.value)) return .method;
    return null;
}

fn styleAllowsKind(style: core.ObjectShorthandStyle, shorthand_kind: ShorthandKind) bool {
    return switch (style) {
        .always => true,
        .methods => shorthand_kind == .method,
        .properties => shorthand_kind == .property,
        .never => false,
    };
}

fn isStringLiteralKey(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(index)) {
        .string_literal => true,
        else => false,
    };
}

fn isConstructorKey(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const name = propertyKeyName(tree, index) orelse return false;
    for (name) |char| {
        if (char == '_' or char == '$' or (char >= '0' and char <= '9')) continue;
        return std.ascii.toUpper(char) == char;
    }
    return false;
}

fn propertyKeyName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(index)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn identifierReferenceNamed(tree: *const ast.Tree, index: ast.NodeIndex, name: []const u8) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| std.mem.eql(u8, tree.string(identifier.name), name),
        else => false,
    };
}

fn isAnonymousFunctionExpression(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .function => |function| function.type == .function_expression and function.id == .null,
        else => false,
    };
}

fn isExplicitReturnArrowFunction(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const arrow = switch (tree.data(unwrapTransparent(tree, index))) {
        .arrow_function_expression => |arrow| arrow,
        else => return false,
    };
    if (arrow.expression) return false;
    if (containsLexicalReference(tree, arrow.body)) return false;

    const body = switch (tree.data(arrow.body)) {
        .function_body => |body| tree.extra(body.body),
        .block_statement => |block| tree.extra(block.body),
        else => return false,
    };
    if (body.len != 1) return false;
    return switch (tree.data(body[0])) {
        .return_statement => |statement| statement.argument != .null,
        else => false,
    };
}

fn containsLexicalReference(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;

    switch (tree.data(index)) {
        .this_expression, .super => return true,
        .identifier_reference => |identifier| return std.mem.eql(u8, tree.string(identifier.name), "arguments"),
        .meta_property => |property| return propertyNameEquals(tree, property.meta, "new") and propertyNameEquals(tree, property.property, "target"),
        .function, .class => return false,
        inline else => |node| return childrenContainLexicalReference(tree, @TypeOf(node), node),
    }
}

fn childrenContainLexicalReference(tree: *const ast.Tree, comptime T: type, node: T) bool {
    if (@typeInfo(T) != .@"struct") return false;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            if (containsLexicalReference(tree, @field(node, field_name))) return true;
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                if (containsLexicalReference(tree, child)) return true;
            }
        }
    }
    return false;
}

fn propertyNameEquals(tree: *const ast.Tree, index: ast.NodeIndex, expected: []const u8) bool {
    return switch (tree.data(index)) {
        .identifier_name => |identifier| std.mem.eql(u8, tree.string(identifier.name), expected),
        else => false,
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
