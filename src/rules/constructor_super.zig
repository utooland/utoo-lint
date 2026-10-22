const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "constructor-super";

pub fn checkClass(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    class: ast.Class,
) Allocator.Error!void {
    const constructor = constructorMethod(tree, class) orelse return;
    const function = switch (tree.data(constructor.method.value)) {
        .function => |function| function,
        else => return,
    };
    if (function.body == .null) return;

    const body = switch (tree.data(function.body)) {
        .function_body => |body| body,
        else => return,
    };

    if (class.super_class == .null) return;

    var super_calls: std.ArrayList(ast.NodeIndex) = .empty;
    defer super_calls.deinit(allocator);

    try collectSuperCalls(allocator, tree, function.body, &super_calls);
    if (super_calls.items.len == 0) {
        if (!rangeGuaranteesSuper(tree, body.body)) {
            try core.addDiagnostic(
                allocator,
                diagnostics,
                .warning,
                id,
                "Expected to call 'super()'.",
                tree.span(constructor.index),
            );
        }
        return;
    }

    if (!rangeGuaranteesSuper(tree, body.body)) {
        try core.addDiagnostic(
            allocator,
            diagnostics,
            .warning,
            id,
            "Lacked a call of 'super()' in some code paths.",
            tree.span(constructor.index),
        );
    }

    _ = try reportDuplicateSuperCallsInRange(allocator, diagnostics, tree, body.body, 0);
}

const Constructor = struct {
    method: ast.MethodDefinition,
    index: ast.NodeIndex,
};

fn constructorMethod(tree: *const ast.Tree, class: ast.Class) ?Constructor {
    const body = switch (tree.data(class.body)) {
        .class_body => |body| body,
        else => return null,
    };

    for (tree.extra(body.body)) |member_index| {
        const method = switch (tree.data(member_index)) {
            .method_definition => |method| method,
            else => continue,
        };
        if (method.kind == .constructor and !method.static) {
            return .{ .method = method, .index = member_index };
        }
    }

    return null;
}

fn collectSuperCalls(
    allocator: Allocator,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    out: *std.ArrayList(ast.NodeIndex),
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .call_expression => |call| {
            if (tree.data(unwrapTransparent(tree, call.callee)) == .super) {
                try out.append(allocator, index);
            }
            try scanChildrenForSuper(allocator, tree, @TypeOf(call), call, out);
        },
        .function,
        .arrow_function_expression,
        .class,
        => return,
        inline else => |node| try scanChildrenForSuper(allocator, tree, @TypeOf(node), node, out),
    }
}

fn scanChildrenForSuper(
    allocator: Allocator,
    tree: *const ast.Tree,
    comptime T: type,
    node: T,
    out: *std.ArrayList(ast.NodeIndex),
) Allocator.Error!void {
    if (@typeInfo(T) != .@"struct") return;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            try collectSuperCalls(allocator, tree, @field(node, field_name), out);
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                try collectSuperCalls(allocator, tree, child, out);
            }
        }
    }
}

fn containsSuperCall(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;

    switch (tree.data(index)) {
        .call_expression => |call| {
            if (tree.data(unwrapTransparent(tree, call.callee)) == .super) return true;
            return childrenContainSuper(tree, @TypeOf(call), call);
        },
        .function,
        .arrow_function_expression,
        .class,
        => return false,
        inline else => |node| return childrenContainSuper(tree, @TypeOf(node), node),
    }
}

fn reportDuplicateSuperCallsInRange(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    range: ast.IndexRange,
    incoming: usize,
) Allocator.Error!usize {
    var count = incoming;

    for (tree.extra(range)) |statement| {
        count = try reportDuplicateSuperCallsInNode(allocator, diagnostics, tree, statement, count);
        if (nodeAbruptlyCompletes(tree, statement)) break;
    }

    return count;
}

fn reportDuplicateSuperCallsInNode(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    incoming: usize,
) Allocator.Error!usize {
    if (index == .null) return incoming;

    return switch (tree.data(index)) {
        .block_statement => |block| try reportDuplicateSuperCallsInRange(allocator, diagnostics, tree, block.body, incoming),
        .if_statement => |statement| blk: {
            const consequent_count = try reportDuplicateSuperCallsInNode(
                allocator,
                diagnostics,
                tree,
                statement.consequent,
                incoming,
            );
            const alternate_count = if (statement.alternate != .null)
                try reportDuplicateSuperCallsInNode(allocator, diagnostics, tree, statement.alternate, incoming)
            else
                incoming;
            break :blk @max(consequent_count, alternate_count);
        },
        else => try reportDuplicateSuperCallsInSubtree(allocator, diagnostics, tree, index, incoming),
    };
}

fn reportDuplicateSuperCallsInSubtree(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    incoming: usize,
) Allocator.Error!usize {
    if (index == .null) return incoming;

    var count = incoming;
    switch (tree.data(index)) {
        .call_expression => |call| {
            if (tree.data(unwrapTransparent(tree, call.callee)) == .super) {
                if (count > 0) {
                    try core.addDiagnostic(
                        allocator,
                        diagnostics,
                        .warning,
                        id,
                        "Unexpected duplicate 'super()'.",
                        tree.span(index),
                    );
                }
                count += 1;
            }
            count = try reportDuplicateSuperCallsInChildren(allocator, diagnostics, tree, @TypeOf(call), call, count);
        },
        .function,
        .arrow_function_expression,
        .class,
        => {},
        inline else => |node| {
            count = try reportDuplicateSuperCallsInChildren(allocator, diagnostics, tree, @TypeOf(node), node, count);
        },
    }

    return count;
}

fn reportDuplicateSuperCallsInChildren(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    comptime T: type,
    node: T,
    incoming: usize,
) Allocator.Error!usize {
    if (@typeInfo(T) != .@"struct") return incoming;

    var count = incoming;
    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            count = try reportDuplicateSuperCallsInNode(allocator, diagnostics, tree, @field(node, field_name), count);
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            count = try reportDuplicateSuperCallsInRange(allocator, diagnostics, tree, @field(node, field_name), count);
        }
    }

    return count;
}

fn childrenContainSuper(tree: *const ast.Tree, comptime T: type, node: T) bool {
    if (@typeInfo(T) != .@"struct") return false;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            if (containsSuperCall(tree, @field(node, field_name))) return true;
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                if (containsSuperCall(tree, child)) return true;
            }
        }
    }

    return false;
}

fn rangeGuaranteesSuper(tree: *const ast.Tree, range: ast.IndexRange) bool {
    for (tree.extra(range)) |statement| {
        if (nodeGuaranteesSuper(tree, statement)) return true;
        if (nodeAbruptlyCompletes(tree, statement)) return true;
    }

    return false;
}

fn nodeGuaranteesSuper(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;

    return switch (tree.data(index)) {
        .expression_statement => |statement| isSuperCall(tree, statement.expression),
        .block_statement => |block| rangeGuaranteesSuper(tree, block.body),
        .if_statement => |statement| statement.alternate != .null and
            nodeGuaranteesSuperOrAbrupt(tree, statement.consequent) and
            nodeGuaranteesSuperOrAbrupt(tree, statement.alternate),
        else => false,
    };
}

fn nodeGuaranteesSuperOrAbrupt(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return nodeGuaranteesSuper(tree, index) or nodeAbruptlyCompletes(tree, index);
}

fn nodeAbruptlyCompletes(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;

    return switch (tree.data(index)) {
        .return_statement => |statement| statement.argument != .null,
        .throw_statement => true,
        .block_statement => |block| rangeAbruptlyCompletes(tree, block.body),
        .if_statement => |statement| statement.alternate != .null and
            nodeAbruptlyCompletes(tree, statement.consequent) and
            nodeAbruptlyCompletes(tree, statement.alternate),
        else => false,
    };
}

fn rangeAbruptlyCompletes(tree: *const ast.Tree, range: ast.IndexRange) bool {
    const statements = tree.extra(range);
    if (statements.len == 0) return false;

    return nodeAbruptlyCompletes(tree, statements[statements.len - 1]);
}

fn isSuperCall(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .call_expression => |call| tree.data(unwrapTransparent(tree, call.callee)) == .super,
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
