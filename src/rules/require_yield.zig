const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = @import("std").mem.Allocator;

pub const id = "require-yield";

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    function: ast.Function,
    index: ast.NodeIndex,
) Allocator.Error!void {
    if (!function.generator or function.body == .null) return;
    if (functionBodyEmpty(tree, function.body)) return;
    if (containsYield(tree, function.body)) return;

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .warning,
        id,
        "This generator function does not have 'yield'.",
        tree.span(index),
    );
}

fn functionBodyEmpty(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(index)) {
        .function_body => |body| body.body.len == 0,
        else => false,
    };
}

fn containsYield(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;

    return switch (tree.data(index)) {
        .yield_expression => true,
        .function,
        .arrow_function_expression,
        => false,
        inline else => |node| nodeContainsYield(tree, node),
    };
}

fn nodeContainsYield(tree: *const ast.Tree, node: anytype) bool {
    const T = @TypeOf(node);
    if (@typeInfo(T) != .@"struct") return false;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            if (containsYield(tree, @field(node, field_name))) return true;
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                if (containsYield(tree, child)) return true;
            }
        }
    }

    return false;
}
