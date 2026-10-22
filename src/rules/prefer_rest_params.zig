const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "prefer-rest-params";

const ArgumentsScanResult = enum {
    none,
    declared,
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    function: ast.Function,
    index: ast.NodeIndex,
) Allocator.Error!void {
    _ = index;
    if (function.body == .null) return;
    if (bindingNamed(tree, function.id, "arguments")) return;
    if (paramsContainBinding(tree, function.params, "arguments")) return;

    var references: std.ArrayList(ast.NodeIndex) = .empty;
    defer references.deinit(allocator);

    if (try collectBodyArguments(allocator, tree, function.body, &references) == .declared) return;

    for (references.items) |reference| {
        try core.addDiagnostic(
            allocator,
            diagnostics,
            .warning,
            id,
            "Use the rest parameters instead of 'arguments'.",
            tree.span(reference),
        );
    }
}

fn paramsContainBinding(tree: *const ast.Tree, params_index: ast.NodeIndex, name: []const u8) bool {
    const params = formalParameters(tree, params_index) orelse return false;

    for (tree.extra(params.items)) |item_index| {
        switch (tree.data(item_index)) {
            .formal_parameter => |parameter| if (bindingNamed(tree, parameter.pattern, name)) return true,
            .ts_parameter_property => |property| if (bindingNamed(tree, property.parameter, name)) return true,
            else => {},
        }
    }

    return bindingNamed(tree, params.rest, name);
}

fn formalParameters(tree: *const ast.Tree, params_index: ast.NodeIndex) ?ast.FormalParameters {
    if (params_index == .null) return null;
    return switch (tree.data(params_index)) {
        .formal_parameters => |params| params,
        else => null,
    };
}

fn collectBodyArguments(
    allocator: Allocator,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    references: *std.ArrayList(ast.NodeIndex),
) Allocator.Error!ArgumentsScanResult {
    if (index == .null) return .none;

    return switch (tree.data(index)) {
        .variable_declaration => |declaration| try collectVariableDeclarationArguments(allocator, tree, declaration, references),
        .function => |function| if (function.type == .function_declaration and bindingNamed(tree, function.id, "arguments")) .declared else .none,
        .member_expression => |member| try collectMemberExpressionArguments(allocator, tree, member, references),
        .identifier_reference => |identifier| {
            if (std.mem.eql(u8, tree.string(identifier.name), "arguments")) {
                try references.append(allocator, index);
            }
            return .none;
        },
        .arrow_function_expression => |arrow| try collectArrowArguments(allocator, tree, arrow, references),
        inline else => |node| try collectNodeArguments(allocator, tree, node, references),
    };
}

fn collectVariableDeclarationArguments(
    allocator: Allocator,
    tree: *const ast.Tree,
    declaration: ast.VariableDeclaration,
    references: *std.ArrayList(ast.NodeIndex),
) Allocator.Error!ArgumentsScanResult {
    for (tree.extra(declaration.declarators)) |declarator_index| {
        const declarator = switch (tree.data(declarator_index)) {
            .variable_declarator => |declarator| declarator,
            else => continue,
        };
        if (bindingNamed(tree, declarator.id, "arguments")) return .declared;
        if (try collectBodyArguments(allocator, tree, declarator.init, references) == .declared) return .declared;
    }

    return .none;
}

fn collectArrowArguments(
    allocator: Allocator,
    tree: *const ast.Tree,
    arrow: ast.ArrowFunctionExpression,
    references: *std.ArrayList(ast.NodeIndex),
) Allocator.Error!ArgumentsScanResult {
    if (paramsContainBinding(tree, arrow.params, "arguments")) return .none;

    const before = references.items.len;
    if (try collectBodyArguments(allocator, tree, arrow.body, references) == .declared) {
        references.shrinkRetainingCapacity(before);
    }

    return .none;
}

fn collectMemberExpressionArguments(
    allocator: Allocator,
    tree: *const ast.Tree,
    member: ast.MemberExpression,
    references: *std.ArrayList(ast.NodeIndex),
) Allocator.Error!ArgumentsScanResult {
    if (!member.computed and isIdentifierReferenceNamed(tree, member.object, "arguments")) return .none;

    switch (try collectBodyArguments(allocator, tree, member.object, references)) {
        .declared => return .declared,
        .none => {},
    }

    if (member.computed) {
        switch (try collectBodyArguments(allocator, tree, member.property, references)) {
            .declared => return .declared,
            .none => {},
        }
    }

    return .none;
}

fn collectNodeArguments(
    allocator: Allocator,
    tree: *const ast.Tree,
    node: anytype,
    references: *std.ArrayList(ast.NodeIndex),
) Allocator.Error!ArgumentsScanResult {
    const T = @TypeOf(node);
    if (@typeInfo(T) != .@"struct") return .none;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            switch (try collectBodyArguments(allocator, tree, @field(node, field_name), references)) {
                .declared => return .declared,
                .none => {},
            }
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                switch (try collectBodyArguments(allocator, tree, child, references)) {
                    .declared => return .declared,
                    .none => {},
                }
            }
        }
    }

    return .none;
}

fn isIdentifierReferenceNamed(tree: *const ast.Tree, index: ast.NodeIndex, name: []const u8) bool {
    if (index == .null) return false;

    return switch (tree.data(index)) {
        .identifier_reference => |identifier| std.mem.eql(u8, tree.string(identifier.name), name),
        else => false,
    };
}

fn bindingNamed(tree: *const ast.Tree, index: ast.NodeIndex, name: []const u8) bool {
    if (index == .null) return false;

    return switch (tree.data(index)) {
        .binding_identifier => |identifier| std.mem.eql(u8, tree.string(identifier.name), name),
        .formal_parameter => |parameter| bindingNamed(tree, parameter.pattern, name),
        .assignment_pattern => |pattern| bindingNamed(tree, pattern.left, name),
        .binding_rest_element => |element| bindingNamed(tree, element.argument, name),
        .array_pattern => |pattern| {
            for (tree.extra(pattern.elements)) |element| {
                if (bindingNamed(tree, element, name)) return true;
            }
            return bindingNamed(tree, pattern.rest, name);
        },
        .object_pattern => |pattern| {
            for (tree.extra(pattern.properties)) |property_index| {
                const property = switch (tree.data(property_index)) {
                    .binding_property => |property| property,
                    else => continue,
                };
                if (bindingNamed(tree, property.value, name)) return true;
            }
            return bindingNamed(tree, pattern.rest, name);
        },
        else => false,
    };
}
