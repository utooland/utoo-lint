const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "no-unused-private-class-members";

const PrivateMember = struct {
    name: []const u8,
    node: ast.NodeIndex,
    used: bool = false,
    write_uses: bool = false,
};

const UsageKind = enum {
    read,
    write,
};

pub fn checkClass(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    class: ast.Class,
) Allocator.Error!void {
    const body = switch (tree.data(class.body)) {
        .class_body => |body| body,
        else => return,
    };

    var members: std.ArrayList(PrivateMember) = .empty;
    defer members.deinit(allocator);

    for (tree.extra(body.body)) |member_index| {
        switch (tree.data(member_index)) {
            .property_definition => |property| {
                if (privateName(tree, property.key, property.computed)) |name| {
                    try members.append(allocator, .{
                        .name = name,
                        .node = member_index,
                        .write_uses = property.accessor,
                    });
                }
            },
            .method_definition => |method| {
                if (privateName(tree, method.key, method.computed)) |name| {
                    try members.append(allocator, .{
                        .name = name,
                        .node = member_index,
                        .write_uses = method.kind == .set,
                    });
                }
            },
            else => {},
        }
    }
    if (members.items.len == 0) return;

    for (tree.extra(body.body)) |member_index| {
        try scanClassMember(allocator, tree, member_index, members.items);
    }

    for (members.items) |member| {
        if (member.used) continue;
        try core.addDiagnostic(
            allocator,
            diagnostics,
            .warning,
            id,
            "Private class member is defined but never used.",
            tree.span(member.node),
        );
    }
}

fn scanClassMember(
    allocator: Allocator,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    members: []PrivateMember,
) Allocator.Error!void {
    switch (tree.data(index)) {
        .property_definition => |property| {
            if (property.computed) try scanNode(allocator, tree, property.key, members);
            try scanNode(allocator, tree, property.value, members);
        },
        .method_definition => |method| {
            if (method.computed) try scanNode(allocator, tree, method.key, members);
            try scanNode(allocator, tree, method.value, members);
        },
        .static_block => |block| try scanRange(allocator, tree, block.body, members),
        else => {},
    }
}

fn scanNode(
    allocator: Allocator,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    members: []PrivateMember,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .class => return,
        .member_expression => |member| {
            try scanNode(allocator, tree, member.object, members);
            try markPrivateUse(tree, member, members, .read);
            if (member.computed) try scanNode(allocator, tree, member.property, members);
        },
        .assignment_expression => |expression| {
            try scanNode(allocator, tree, expression.right, members);
            if (expression.operator == .assign) {
                try scanAssignmentTarget(allocator, tree, expression.left, members);
            } else {
                try scanNode(allocator, tree, expression.left, members);
            }
        },
        .update_expression => |expression| try scanNode(allocator, tree, expression.argument, members),
        inline else => |node| try scanPayload(allocator, tree, node, members),
    }
}

fn scanAssignmentTarget(
    allocator: Allocator,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    members: []PrivateMember,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .member_expression => |member| {
            try scanNode(allocator, tree, member.object, members);
            try markPrivateUse(tree, member, members, .write);
            if (member.computed) try scanNode(allocator, tree, member.property, members);
        },
        inline else => |node| try scanPayload(allocator, tree, node, members),
    }
}

fn scanPayload(
    allocator: Allocator,
    tree: *const ast.Tree,
    node: anytype,
    members: []PrivateMember,
) Allocator.Error!void {
    const T = @TypeOf(node);
    if (@typeInfo(T) != .@"struct") return;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            try scanNode(allocator, tree, @field(node, field_name), members);
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            try scanRange(allocator, tree, @field(node, field_name), members);
        }
    }
}

fn scanRange(
    allocator: Allocator,
    tree: *const ast.Tree,
    range: ast.IndexRange,
    members: []PrivateMember,
) Allocator.Error!void {
    for (tree.extra(range)) |child| {
        try scanNode(allocator, tree, child, members);
    }
}

fn markPrivateUse(
    tree: *const ast.Tree,
    member: ast.MemberExpression,
    members: []PrivateMember,
    kind: UsageKind,
) Allocator.Error!void {
    const name = privateName(tree, member.property, member.computed) orelse return;
    for (members) |*candidate| {
        if (!std.mem.eql(u8, candidate.name, name)) continue;
        switch (kind) {
            .read => candidate.used = true,
            .write => {
                if (candidate.write_uses) candidate.used = true;
            },
        }
    }
}

fn privateName(tree: *const ast.Tree, index: ast.NodeIndex, computed: bool) ?[]const u8 {
    if (computed or index == .null) return null;
    return switch (tree.data(index)) {
        .private_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}
