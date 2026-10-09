const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "react/jsx-no-comment-textnodes";

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    text: ast.JSXText,
    index: ast.NodeIndex,
) Allocator.Error!void {
    if (!startsWithCommentToken(tree.string(text.raw))) return;

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .@"error",
        id,
        "Comments inside children section of tag should be placed inside braces",
        tree.span(index),
    );
}

fn startsWithCommentToken(value: []const u8) bool {
    var line_start: usize = 0;
    while (line_start <= value.len) {
        const line_end = std.mem.indexOfScalarPos(u8, value, line_start, '\n') orelse value.len;
        var index = line_start;
        while (index < line_end and isWhitespace(value[index])) : (index += 1) {}
        if (index + 1 < line_end and value[index] == '/' and (value[index + 1] == '/' or value[index + 1] == '*')) {
            return true;
        }
        if (line_end == value.len) break;
        line_start = line_end + 1;
    }
    return false;
}

fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}
