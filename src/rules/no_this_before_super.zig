const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "no-this-before-super";

const Constructor = struct {
    method: ast.MethodDefinition,
    index: ast.NodeIndex,
};

const Flow = struct {
    has_super: bool,
    continues: bool = true,
};

pub fn checkClass(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    class: ast.Class,
) Allocator.Error!void {
    if (class.super_class == .null) return;

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

    _ = try scanStatementRange(allocator, diagnostics, tree, body.body, .{ .has_super = false });
}

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

fn scanStatementRange(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    range: ast.IndexRange,
    incoming: Flow,
) Allocator.Error!Flow {
    var flow = incoming;

    for (tree.extra(range)) |statement| {
        if (!flow.continues) break;
        flow = try scanNode(allocator, diagnostics, tree, statement, flow);
    }

    return flow;
}

fn scanNode(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    incoming: Flow,
) Allocator.Error!Flow {
    if (index == .null or !incoming.continues) return incoming;

    switch (tree.data(index)) {
        .this_expression => {
            if (!incoming.has_super) {
                try addDiagnostic(allocator, diagnostics, tree, index);
            }
            return incoming;
        },
        .super => {
            if (!incoming.has_super) {
                try addDiagnostic(allocator, diagnostics, tree, index);
            }
            return incoming;
        },
        .call_expression => |call| {
            if (tree.data(unwrapTransparent(tree, call.callee)) == .super) {
                var flow = try scanExpressionRange(allocator, diagnostics, tree, call.arguments, incoming);
                flow.has_super = true;
                return flow;
            }
            return scanChildren(allocator, diagnostics, tree, @TypeOf(call), call, incoming);
        },
        .block_statement => |block| return scanStatementRange(allocator, diagnostics, tree, block.body, incoming),
        .if_statement => |statement| return scanIfStatement(allocator, diagnostics, tree, statement, incoming),
        .return_statement => |statement| {
            var flow = try scanChildren(allocator, diagnostics, tree, @TypeOf(statement), statement, incoming);
            flow.continues = false;
            return flow;
        },
        .throw_statement => |statement| {
            var flow = try scanChildren(allocator, diagnostics, tree, @TypeOf(statement), statement, incoming);
            flow.continues = false;
            return flow;
        },
        .function,
        .arrow_function_expression,
        .class,
        => return incoming,
        inline else => |node| return scanChildren(allocator, diagnostics, tree, @TypeOf(node), node, incoming),
    }
}

fn scanIfStatement(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    statement: ast.IfStatement,
    incoming: Flow,
) Allocator.Error!Flow {
    const consequent = try scanNode(allocator, diagnostics, tree, statement.consequent, incoming);
    const alternate = if (statement.alternate != .null)
        try scanNode(allocator, diagnostics, tree, statement.alternate, incoming)
    else
        incoming;

    return mergeBranches(consequent, alternate);
}

fn mergeBranches(left: Flow, right: Flow) Flow {
    if (left.continues and right.continues) {
        return .{ .has_super = left.has_super and right.has_super };
    }
    if (left.continues) return left;
    if (right.continues) return right;
    return .{ .has_super = left.has_super and right.has_super, .continues = false };
}

fn scanExpressionRange(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    range: ast.IndexRange,
    incoming: Flow,
) Allocator.Error!Flow {
    var flow = incoming;

    for (tree.extra(range)) |expression| {
        flow = try scanNode(allocator, diagnostics, tree, expression, flow);
    }

    return flow;
}

fn scanChildren(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    comptime T: type,
    node: T,
    incoming: Flow,
) Allocator.Error!Flow {
    if (@typeInfo(T) != .@"struct") return incoming;

    var flow = incoming;
    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            flow = try scanNode(allocator, diagnostics, tree, @field(node, field_name), flow);
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            flow = try scanExpressionRange(allocator, diagnostics, tree, @field(node, field_name), flow);
        }
    }

    return flow;
}

fn addDiagnostic(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
) Allocator.Error!void {
    try core.addDiagnostic(
        allocator,
        diagnostics,
        .warning,
        id,
        "Unexpected use of 'this' or 'super' before 'super()'.",
        tree.span(index),
    );
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
