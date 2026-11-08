const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "react/self-closing-comp";

pub const Options = struct {
    component: bool = true,
    html: bool = true,
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    opening: ast.JSXOpeningElement,
    index: ast.NodeIndex,
    parent: ?ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    if (opening.self_closing) return;
    if (!isConfiguredElementName(tree, opening.name, options)) return;

    const element = switch (tree.data(parent orelse return)) {
        .jsx_element => |element| element,
        else => return,
    };
    if (!childrenAreEmpty(tree, element.children)) return;

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .@"error",
        id,
        "Empty components are self-closing",
        tree.span(index),
    );
}

fn isConfiguredElementName(tree: *const ast.Tree, index: ast.NodeIndex, options: Options) bool {
    return switch (tree.data(index)) {
        .jsx_identifier => |identifier| {
            const name = tree.string(identifier.name);
            return if (name.len > 0 and std.ascii.isLower(name[0])) options.html else options.component;
        },
        .jsx_member_expression => options.component,
        else => false,
    };
}

fn childrenAreEmpty(tree: *const ast.Tree, children_range: ast.IndexRange) bool {
    const children = tree.extra(children_range);
    if (children.len == 0) return true;
    if (children.len != 1) return false;

    const value = switch (tree.data(children[0])) {
        .jsx_text => |text| tree.string(text.value),
        else => return false,
    };
    if (!containsLineBreak(value)) return false;
    return isMultilineWhitespace(value);
}

fn containsLineBreak(value: []const u8) bool {
    return std.mem.indexOfScalar(u8, value, '\n') != null or
        std.mem.indexOfScalar(u8, value, '\r') != null;
}

fn isMultilineWhitespace(value: []const u8) bool {
    for (value) |byte| {
        if (byte == 0xc2 or byte == 0xa0) return false;
        if (!isWhitespace(byte)) return false;
    }
    return true;
}

fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}
