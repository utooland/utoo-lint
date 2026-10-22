const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "arrow-body-style";

pub const Style = enum {
    always,
    as_needed,
    never,
};

pub const Options = struct {
    style: Style = .as_needed,
    require_return_for_object_literal: bool = false,
};

pub fn checkArrowFunction(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    expression: ast.ArrowFunctionExpression,
    index: ast.NodeIndex,
    ctx: *const traverser.basic.Ctx,
    options: Options,
) Allocator.Error!void {
    if (expression.expression) {
        const needs_block = options.style == .always or
            (options.style == .as_needed and
                options.require_return_for_object_literal and
                isObjectExpression(tree, expression.body));
        if (needs_block) {
            const body_span = tree.span(expression.body);
            const replacement = try std.fmt.allocPrint(
                allocator,
                "{{ return {s}; }}",
                .{tree.source[body_span.start..body_span.end]},
            );
            defer allocator.free(replacement);

            try core.addDiagnosticWithFix(
                allocator,
                diagnostics,
                .warning,
                id,
                "Expected block statement surrounding arrow body.",
                tree.span(index),
                .{ .span = body_span, .replacement = replacement },
            );
        }
        return;
    }

    if (options.style == .always) return;
    const returned = singleReturnedExpression(tree, expression.body) orelse return;
    if (options.style == .as_needed and options.require_return_for_object_literal and isObjectExpression(tree, returned)) {
        return;
    }

    const message = "Unexpected block statement surrounding arrow body; move the returned value immediately after the `=>`.";
    const body_span = tree.span(expression.body);
    const returned_span = tree.span(returned);
    if (hasAsiHazard(tree, tree.span(index).end)) {
        try core.addDiagnostic(allocator, diagnostics, .warning, id, message, body_span);
        return;
    }

    if (hasCommentsOutsideReturnedExpression(tree, body_span, returned_span)) {
        try addCommentPreservingDiagnostic(
            allocator,
            diagnostics,
            tree,
            message,
            body_span,
            returned_span,
            conciseBodyNeedsParens(tree, returned, index, ctx),
        );
        return;
    }

    if (!conciseBodyNeedsParens(tree, returned, index, ctx)) {
        try core.addDiagnosticWithFix(
            allocator,
            diagnostics,
            .warning,
            id,
            message,
            body_span,
            .{
                .span = body_span,
                .replacement = tree.source[returned_span.start..returned_span.end],
            },
        );
        return;
    }

    const replacement = try std.fmt.allocPrint(
        allocator,
        "({s})",
        .{tree.source[returned_span.start..returned_span.end]},
    );
    defer allocator.free(replacement);
    try core.addDiagnosticWithFix(
        allocator,
        diagnostics,
        .warning,
        id,
        message,
        body_span,
        .{ .span = body_span, .replacement = replacement },
    );
}

fn addCommentPreservingDiagnostic(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    message: []const u8,
    body_span: ast.Span,
    returned_span: ast.Span,
    needs_parens: bool,
) Allocator.Error!void {
    const opening_brace = findByteOutsideComments(tree, body_span.start, returned_span.start, '{') orelse {
        try core.addDiagnostic(allocator, diagnostics, .warning, id, message, body_span);
        return;
    };
    const return_start = findSliceOutsideComments(tree, opening_brace + 1, returned_span.start, "return") orelse {
        try core.addDiagnostic(allocator, diagnostics, .warning, id, message, body_span);
        return;
    };
    const closing_brace = findLastByteOutsideComments(tree, returned_span.end, body_span.end, '}') orelse {
        try core.addDiagnostic(allocator, diagnostics, .warning, id, message, body_span);
        return;
    };

    var fixes: [4]core.Fix = undefined;
    var fix_count: usize = 0;
    fixes[fix_count] = .{
        .span = .{ .start = opening_brace, .end = opening_brace + 1 },
        .replacement = if (needs_parens) "(" else "",
    };
    fix_count += 1;
    fixes[fix_count] = .{
        .span = .{ .start = return_start, .end = return_start + @as(u32, "return".len) },
        .replacement = "",
    };
    fix_count += 1;
    if (findByteOutsideComments(tree, returned_span.end, closing_brace, ';')) |semicolon| {
        fixes[fix_count] = .{
            .span = .{ .start = semicolon, .end = semicolon + 1 },
            .replacement = "",
        };
        fix_count += 1;
    }
    fixes[fix_count] = .{
        .span = .{ .start = closing_brace, .end = closing_brace + 1 },
        .replacement = if (needs_parens) ")" else "",
    };
    fix_count += 1;

    try core.addDiagnosticWithFixes(
        allocator,
        diagnostics,
        .warning,
        id,
        message,
        body_span,
        fixes[0..fix_count],
    );
}

fn conciseBodyNeedsParens(
    tree: *const ast.Tree,
    returned: ast.NodeIndex,
    arrow: ast.NodeIndex,
    ctx: *const traverser.basic.Ctx,
) bool {
    if (tree.data(returned) == .parenthesized_expression) return false;
    return switch (tree.data(unwrapTransparent(tree, returned))) {
        .object_expression, .sequence_expression => true,
        else => containsInOperator(tree, returned) and isInsideForInitializer(tree, arrow, &ctx.path),
    };
}

fn containsInOperator(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;
    switch (tree.data(index)) {
        .binary_expression => |expression| {
            if (expression.operator == .in) return true;
            return containsInOperator(tree, expression.left) or containsInOperator(tree, expression.right);
        },
        inline else => |node| return childrenContainInOperator(tree, @TypeOf(node), node),
    }
}

fn childrenContainInOperator(tree: *const ast.Tree, comptime T: type, node: T) bool {
    if (@typeInfo(T) != .@"struct") return false;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            if (containsInOperator(tree, @field(node, field_name))) return true;
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                if (containsInOperator(tree, child)) return true;
            }
        }
    }
    return false;
}

fn isInsideForInitializer(
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    path: anytype,
) bool {
    var child = index;
    var depth: usize = 1;
    while (path.ancestor(depth)) |ancestor| : (depth += 1) {
        switch (tree.data(ancestor)) {
            .for_statement => |statement| if (statement.init == child) return true,
            else => {},
        }
        child = ancestor;
    }
    return false;
}

fn hasCommentsOutsideReturnedExpression(tree: *const ast.Tree, body_span: ast.Span, returned_span: ast.Span) bool {
    for (tree.comments) |comment| {
        if (comment.span.end <= body_span.start) continue;
        if (comment.span.start >= body_span.end) break;
        if (comment.span.start < returned_span.start or comment.span.end > returned_span.end) return true;
    }
    return false;
}

fn hasAsiHazard(tree: *const ast.Tree, arrow_end: u32) bool {
    var offset: usize = arrow_end;
    while (offset < tree.source.len) {
        if (std.ascii.isWhitespace(tree.source[offset])) {
            offset += 1;
            continue;
        }
        if (commentAt(tree, @intCast(offset))) |comment| {
            offset = comment.span.end;
            continue;
        }
        break;
    }
    if (offset == tree.source.len) return false;
    return switch (tree.source[offset]) {
        '(', '[', '/', '`', '+', '-' => true,
        else => false,
    };
}

fn commentAt(tree: *const ast.Tree, offset: u32) ?ast.Comment {
    for (tree.comments) |comment| {
        if (comment.span.end <= offset) continue;
        if (comment.span.start > offset) break;
        return comment;
    }
    return null;
}

fn singleReturnedExpression(tree: *const ast.Tree, body_index: ast.NodeIndex) ?ast.NodeIndex {
    const body = switch (tree.data(body_index)) {
        .function_body => |body| body,
        else => return null,
    };

    const statements = tree.extra(body.body);
    if (statements.len != 1) return null;

    const statement = switch (tree.data(statements[0])) {
        .return_statement => |statement| statement,
        else => return null,
    };
    if (statement.argument == .null) return null;
    return statement.argument;
}

fn findByteOutsideComments(tree: *const ast.Tree, start: u32, end: u32, byte: u8) ?u32 {
    var offset = start;
    while (offset < end) : (offset += 1) {
        if (tree.source[offset] == byte and !hasCommentAt(tree, offset)) return offset;
    }
    return null;
}

fn findLastByteOutsideComments(tree: *const ast.Tree, start: u32, end: u32, byte: u8) ?u32 {
    var offset = end;
    while (offset > start) {
        offset -= 1;
        if (tree.source[offset] == byte and !hasCommentAt(tree, offset)) return offset;
    }
    return null;
}

fn findSliceOutsideComments(tree: *const ast.Tree, start: u32, end: u32, needle: []const u8) ?u32 {
    if (needle.len == 0 or start >= end) return null;
    var search_start: usize = start;
    while (std.mem.indexOfPos(u8, tree.source[0..end], search_start, needle)) |offset| {
        if (!hasCommentAt(tree, @intCast(offset))) return @intCast(offset);
        search_start = offset + needle.len;
    }
    return null;
}

fn hasCommentAt(tree: *const ast.Tree, offset: u32) bool {
    return commentAt(tree, offset) != null;
}

fn isObjectExpression(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .object_expression => true,
        else => false,
    };
}

fn unwrapTransparent(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    var current = index;
    while (current != .null) {
        switch (tree.data(current)) {
            .parenthesized_expression => |parenthesized| current = parenthesized.expression,
            else => return current,
        }
    }
    return current;
}
