const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "no-param-reassign";

const ParamSet = std.StringHashMapUnmanaged(void);

pub const Options = struct {
    props: bool = false,
    ignore_property_modifications_for: core.NoParamReassignIgnoredNames = .{},
    ignore_property_modifications_for_regex: core.NoParamReassignIgnoredNamePatterns = .{},
};

pub fn checkFunction(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    function: ast.Function,
) Allocator.Error!void {
    try checkFunctionWithOptions(allocator, diagnostics, tree, function, .{});
}

pub fn checkFunctionWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    function: ast.Function,
    options: Options,
) Allocator.Error!void {
    var params: ParamSet = .empty;
    defer params.deinit(allocator);

    try collectFormalParameters(allocator, tree, function.params, &params);
    if (params.size == 0 or function.body == .null) return;

    try scanNode(allocator, diagnostics, tree, &params, function.body, options);
}

pub fn checkArrowFunction(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    expression: ast.ArrowFunctionExpression,
) Allocator.Error!void {
    try checkArrowFunctionWithOptions(allocator, diagnostics, tree, expression, .{});
}

pub fn checkArrowFunctionWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    expression: ast.ArrowFunctionExpression,
    options: Options,
) Allocator.Error!void {
    var params: ParamSet = .empty;
    defer params.deinit(allocator);

    try collectFormalParameters(allocator, tree, expression.params, &params);
    if (params.size == 0) return;

    try scanNode(allocator, diagnostics, tree, &params, expression.body, options);
}

fn collectFormalParameters(
    allocator: Allocator,
    tree: *const ast.Tree,
    params_index: ast.NodeIndex,
    out: *ParamSet,
) Allocator.Error!void {
    if (params_index == .null) return;

    const params = switch (tree.data(params_index)) {
        .formal_parameters => |params| params,
        else => return,
    };

    for (tree.extra(params.items)) |item_index| {
        switch (tree.data(item_index)) {
            .formal_parameter => |parameter| try collectBinding(allocator, tree, parameter.pattern, out),
            .ts_parameter_property => |property| try collectBinding(allocator, tree, property.parameter, out),
            else => {},
        }
    }

    try collectBinding(allocator, tree, params.rest, out);
}

fn collectBinding(
    allocator: Allocator,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    out: *ParamSet,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .binding_identifier => |identifier| try out.put(allocator, tree.string(identifier.name), {}),
        .assignment_pattern => |pattern| try collectBinding(allocator, tree, pattern.left, out),
        .binding_rest_element => |element| try collectBinding(allocator, tree, element.argument, out),
        .array_pattern => |pattern| {
            for (tree.extra(pattern.elements)) |element| {
                try collectBinding(allocator, tree, element, out);
            }
            try collectBinding(allocator, tree, pattern.rest, out);
        },
        .object_pattern => |pattern| {
            for (tree.extra(pattern.properties)) |property_index| {
                const property = switch (tree.data(property_index)) {
                    .binding_property => |property| property,
                    else => continue,
                };
                try collectBinding(allocator, tree, property.value, out);
            }
            try collectBinding(allocator, tree, pattern.rest, out);
        },
        else => {},
    }
}

fn scanNode(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    params: *const ParamSet,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .assignment_expression => |expression| {
            try checkTarget(allocator, diagnostics, tree, params, expression.left, options);
            try scanNode(allocator, diagnostics, tree, params, expression.right, options);
        },
        .update_expression => |expression| try checkTarget(allocator, diagnostics, tree, params, expression.argument, options),
        .unary_expression => |expression| {
            if (expression.operator == .delete) {
                try checkTarget(allocator, diagnostics, tree, params, expression.argument, options);
            } else {
                try scanNode(allocator, diagnostics, tree, params, expression.argument, options);
            }
        },
        .for_in_statement => |statement| {
            try checkTarget(allocator, diagnostics, tree, params, statement.left, options);
            try scanNode(allocator, diagnostics, tree, params, statement.right, options);
            try scanNode(allocator, diagnostics, tree, params, statement.body, options);
        },
        .for_of_statement => |statement| {
            try checkTarget(allocator, diagnostics, tree, params, statement.left, options);
            try scanNode(allocator, diagnostics, tree, params, statement.right, options);
            try scanNode(allocator, diagnostics, tree, params, statement.body, options);
        },
        .function => |function| try scanNestedFunction(allocator, diagnostics, tree, params, function, options),
        .arrow_function_expression => |expression| try scanNestedArrowFunction(allocator, diagnostics, tree, params, expression, options),
        .class,
        => return,
        inline else => |node| try scanChildren(allocator, diagnostics, tree, params, @TypeOf(node), node, options),
    }
}

fn scanNestedFunction(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    params: *const ParamSet,
    function: ast.Function,
    options: Options,
) Allocator.Error!void {
    if (function.body == .null) return;

    var filtered = try filterShadowedParams(allocator, tree, params, function.params, function.body);
    defer filtered.deinit(allocator);

    if (filtered.size == 0) return;
    try scanNode(allocator, diagnostics, tree, &filtered, function.body, options);
}

fn scanNestedArrowFunction(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    params: *const ParamSet,
    expression: ast.ArrowFunctionExpression,
    options: Options,
) Allocator.Error!void {
    var filtered = try filterShadowedParams(allocator, tree, params, expression.params, expression.body);
    defer filtered.deinit(allocator);

    if (filtered.size == 0) return;
    try scanNode(allocator, diagnostics, tree, &filtered, expression.body, options);
}

fn filterShadowedParams(
    allocator: Allocator,
    tree: *const ast.Tree,
    params: *const ParamSet,
    params_index: ast.NodeIndex,
    body_index: ast.NodeIndex,
) Allocator.Error!ParamSet {
    var shadows: ParamSet = .empty;
    defer shadows.deinit(allocator);

    try collectFormalParameters(allocator, tree, params_index, &shadows);
    try collectLocalDeclarations(allocator, tree, body_index, &shadows);

    var filtered: ParamSet = .empty;
    errdefer filtered.deinit(allocator);

    var iterator = params.iterator();
    while (iterator.next()) |entry| {
        const name = entry.key_ptr.*;
        if (!shadows.contains(name)) try filtered.put(allocator, name, {});
    }

    return filtered;
}

fn collectLocalDeclarations(
    allocator: Allocator,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    out: *ParamSet,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .variable_declaration => |declaration| {
            for (tree.extra(declaration.declarators)) |declarator_index| {
                const declarator = switch (tree.data(declarator_index)) {
                    .variable_declarator => |declarator| declarator,
                    else => continue,
                };
                try collectBinding(allocator, tree, declarator.id, out);
            }
        },
        .function => |function| {
            try collectBinding(allocator, tree, function.id, out);
            return;
        },
        .class => |class| {
            try collectBinding(allocator, tree, class.id, out);
            return;
        },
        .arrow_function_expression => return,
        inline else => |node| try collectLocalDeclarationChildren(allocator, tree, @TypeOf(node), node, out),
    }
}

fn collectLocalDeclarationChildren(
    allocator: Allocator,
    tree: *const ast.Tree,
    comptime T: type,
    node: T,
    out: *ParamSet,
) Allocator.Error!void {
    if (@typeInfo(T) != .@"struct") return;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            try collectLocalDeclarations(allocator, tree, @field(node, field_name), out);
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                try collectLocalDeclarations(allocator, tree, child, out);
            }
        }
    }
}

fn scanChildren(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    params: *const ParamSet,
    comptime T: type,
    node: T,
    options: Options,
) Allocator.Error!void {
    if (@typeInfo(T) != .@"struct") return;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            try scanNode(allocator, diagnostics, tree, params, @field(node, field_name), options);
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                try scanNode(allocator, diagnostics, tree, params, child, options);
            }
        }
    }
}

fn checkTarget(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    params: *const ParamSet,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| {
            const name = tree.string(identifier.name);
            if (!params.contains(name)) return;

            try core.addDiagnosticFmt(
                allocator,
                diagnostics,
                .warning,
                id,
                tree.span(index),
                "Assignment to function parameter '{s}'.",
                .{name},
            );
        },
        .member_expression => |member| {
            if (!options.props) return;
            const name = rootIdentifierReferenceName(tree, member.object) orelse return;
            if (!params.contains(name)) return;
            if (isIgnoredPropertyModificationName(name, options)) return;

            try core.addDiagnosticFmt(
                allocator,
                diagnostics,
                .warning,
                id,
                tree.span(index),
                "Assignment to property of function parameter '{s}'.",
                .{name},
            );
        },
        .assignment_pattern => |pattern| try checkTarget(allocator, diagnostics, tree, params, pattern.left, options),
        .array_pattern => |pattern| {
            for (tree.extra(pattern.elements)) |element| {
                try checkTarget(allocator, diagnostics, tree, params, element, options);
            }
            try checkTarget(allocator, diagnostics, tree, params, pattern.rest, options);
        },
        .object_pattern => |pattern| {
            for (tree.extra(pattern.properties)) |property_index| {
                const property = switch (tree.data(property_index)) {
                    .binding_property => |property| property,
                    else => continue,
                };
                try checkTarget(allocator, diagnostics, tree, params, property.value, options);
            }
            try checkTarget(allocator, diagnostics, tree, params, pattern.rest, options);
        },
        .binding_rest_element => |element| try checkTarget(allocator, diagnostics, tree, params, element.argument, options),
        else => {},
    }
}

fn isIgnoredPropertyModificationName(name: []const u8, options: Options) bool {
    if (options.ignore_property_modifications_for.contains(name)) return true;

    for (0..options.ignore_property_modifications_for_regex.count) |index| {
        if (matchesPattern(name, options.ignore_property_modifications_for_regex.at(index))) return true;
    }

    return false;
}

fn matchesPattern(value: []const u8, pattern: []const u8) bool {
    var start: usize = 0;
    while (start <= pattern.len) {
        const remainder = pattern[start..];
        const separator = std.mem.indexOfScalar(u8, remainder, '|');
        const end = if (separator) |offset| start + offset else pattern.len;
        if (matchesAlternative(value, pattern[start..end])) return true;
        if (separator == null) break;
        start = end + 1;
    }
    return false;
}

fn matchesAlternative(value: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return false;

    const anchored_start = std.mem.startsWith(u8, pattern, "^");
    const anchored_end = std.mem.endsWith(u8, pattern, "$");
    const body_start: usize = if (anchored_start) 1 else 0;
    const body_end = if (anchored_end and pattern.len > body_start) pattern.len - 1 else pattern.len;
    const body = pattern[body_start..body_end];

    if (std.mem.indexOf(u8, body, ".*") != null) {
        return matchesWildcardSequence(value, body, anchored_start, anchored_end);
    }
    if (anchored_start and anchored_end) return std.mem.eql(u8, value, body);
    if (anchored_start) return std.mem.startsWith(u8, value, body);
    if (anchored_end) return std.mem.endsWith(u8, value, body);
    return std.mem.indexOf(u8, value, body) != null;
}

fn matchesWildcardSequence(value: []const u8, pattern: []const u8, anchored_start: bool, anchored_end: bool) bool {
    var value_offset: usize = 0;
    var pattern_offset: usize = 0;
    var part_index: usize = 0;

    while (pattern_offset <= pattern.len) : (part_index += 1) {
        const remainder = pattern[pattern_offset..];
        const wildcard = std.mem.indexOf(u8, remainder, ".*");
        const part_end = if (wildcard) |offset| pattern_offset + offset else pattern.len;
        const part = pattern[pattern_offset..part_end];

        if (part.len > 0) {
            if (part_index == 0 and anchored_start) {
                if (!std.mem.startsWith(u8, value[value_offset..], part)) return false;
                value_offset += part.len;
            } else {
                const found = std.mem.indexOf(u8, value[value_offset..], part) orelse return false;
                value_offset += found + part.len;
            }
        }

        if (wildcard == null) break;
        pattern_offset = part_end + 2;
    }

    if (!anchored_end) return true;
    const suffix_start = lastWildcardPartStart(pattern);
    return std.mem.endsWith(u8, value, pattern[suffix_start..]);
}

fn lastWildcardPartStart(pattern: []const u8) usize {
    var offset: usize = 0;
    var start: usize = 0;
    while (offset < pattern.len) {
        const wildcard = std.mem.indexOf(u8, pattern[offset..], ".*") orelse break;
        start = offset + wildcard + 2;
        offset = start;
    }
    return start;
}

fn rootIdentifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        .member_expression => |member| rootIdentifierReferenceName(tree, member.object),
        else => null,
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
