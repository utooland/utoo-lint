const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const SymbolTable = @import("../semantic_compat.zig").SymbolTable;
const Allocator = std.mem.Allocator;

pub const id = "@typescript-eslint/restrict-plus-operands";

pub const Options = struct {
    allow_number_and_string: bool = false,
    allow_any: bool = true,
    skip_compound_assignments: bool = false,
};

const ValueType = enum {
    string,
    number,
    bigint,
    boolean,
    unknown,
    any,
    invalid,
    unknown_expression,

    fn text(self: ValueType) []const u8 {
        return switch (self) {
            .string => "string",
            .number => "number",
            .bigint => "bigint",
            .boolean => "boolean",
            .unknown => "unknown",
            .any => "any",
            .invalid => "invalid",
            .unknown_expression => "unknown",
        };
    }
};

pub fn run(allocator: Allocator, diagnostics: *core.DiagnosticList, tree: *const ast.Tree, symbols: SymbolTable, options: Options) Allocator.Error!void {
    for (tree.nodes.items(.data), 0..) |data, raw_index| {
        switch (data) {
            .binary_expression => |expression| try checkBinaryExpression(allocator, diagnostics, tree, expression, @enumFromInt(raw_index), symbols, options),
            .assignment_expression => |expression| if (expression.operator == .add_assign and !options.skip_compound_assignments) {
                try checkOperands(allocator, diagnostics, tree, expression.left, expression.right, @enumFromInt(raw_index), symbols, options);
            },
            else => {},
        }
    }
}

pub fn checkBinaryExpression(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    expression: ast.BinaryExpression,
    index: ast.NodeIndex,
    symbols: SymbolTable,
    options: Options,
) Allocator.Error!void {
    if (expression.operator != .add) return;

    try checkOperands(allocator, diagnostics, tree, expression.left, expression.right, index, symbols, options);
}

fn checkOperands(allocator: Allocator, diagnostics: *core.DiagnosticList, tree: *const ast.Tree, left_node: ast.NodeIndex, right_node: ast.NodeIndex, index: ast.NodeIndex, symbols: SymbolTable, options: Options) Allocator.Error!void {
    const left = inferExpressionType(tree, symbols, left_node);
    const right = inferExpressionType(tree, symbols, right_node);
    if (left == .any or right == .any) {
        if (!options.allow_any) {
            try core.addDiagnostic(allocator, diagnostics, .warning, id, "Invalid operand for a '+' operation. Operands must each be a number, string, or bigint. Got `any`.", tree.span(index));
            return;
        }
        const other = if (left == .any) right else left;
        if (other == .any or other == .unknown_expression or isAllowedOperand(other)) return;
    }
    if (left == .unknown_expression or right == .unknown_expression) return;
    if (isAllowedPair(left, right, options)) return;

    if ((left == .bigint and right == .number) or (left == .number and right == .bigint)) {
        try core.addDiagnosticFmt(allocator, diagnostics, .warning, id, tree.span(index), "Numeric '+' operations must either be both bigints or both numbers. Got `{s}` + `{s}`.", .{ left.text(), right.text() });
        return;
    }
    if (isAllowedOperand(left) and isAllowedOperand(right)) {
        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            .warning,
            id,
            tree.span(index),
            "Operands of '+' operations must be a number, string, or bigint. Got `{s}` + `{s}`.",
            .{ left.text(), right.text() },
        );
        return;
    }

    const invalid = if (left != .any and !isAllowedOperand(left)) left else right;
    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        .warning,
        id,
        tree.span(index),
        "Invalid operand for a '+' operation. Operands must each be a number, string, or bigint. Got `{s}`.",
        .{invalid.text()},
    );
}

fn isAllowedPair(left: ValueType, right: ValueType, options: Options) bool {
    if ((left == .number and right == .number) or
        (left == .string and right == .string) or
        (left == .bigint and right == .bigint))
    {
        return true;
    }
    if (options.allow_number_and_string) {
        return (left == .number and right == .string) or
            (left == .string and right == .number);
    }
    return false;
}

fn isAllowedOperand(value_type: ValueType) bool {
    return value_type == .number or value_type == .string or value_type == .bigint;
}

fn inferExpressionType(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex) ValueType {
    return inferExpressionTypeAtDepth(tree, symbols, index, 0);
}

fn inferExpressionTypeAtDepth(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) ValueType {
    if (index == .null or depth >= 32) return .unknown_expression;

    return switch (tree.data(index)) {
        .numeric_literal => .number,
        .string_literal, .template_literal => .string,
        .bigint_literal => .bigint,
        .boolean_literal => .boolean,
        .null_literal, .array_expression, .object_expression => .invalid,
        .identifier_reference => narrowedReferenceType(tree, symbols, index, depth + 1),
        .parenthesized_expression => |parenthesized| inferExpressionTypeAtDepth(tree, symbols, parenthesized.expression, depth + 1),
        .ts_as_expression => |expression| typeFromAnnotation(tree, symbols, expression.type_annotation, depth + 1) orelse .unknown_expression,
        .ts_type_assertion => |expression| typeFromAnnotation(tree, symbols, expression.type_annotation, depth + 1) orelse .unknown_expression,
        .ts_satisfies_expression => |expression| inferExpressionTypeAtDepth(tree, symbols, expression.expression, depth + 1),
        .ts_non_null_expression => |expression| inferExpressionTypeAtDepth(tree, symbols, expression.expression, depth + 1),
        .chain_expression => |expression| inferExpressionTypeAtDepth(tree, symbols, expression.expression, depth + 1),
        .member_expression => |member| memberType(tree, symbols, member, depth + 1),
        .call_expression => |call| callType(tree, symbols, call, depth + 1),
        .binary_expression => |binary| if (binary.operator == .add) inferBinaryResultType(tree, symbols, binary, depth + 1) else .unknown_expression,
        else => .unknown_expression,
    };
}

fn inferBinaryResultType(tree: *const ast.Tree, symbols: SymbolTable, expression: ast.BinaryExpression, depth: usize) ValueType {
    const left = inferExpressionTypeAtDepth(tree, symbols, expression.left, depth + 1);
    const right = inferExpressionTypeAtDepth(tree, symbols, expression.right, depth + 1);
    if (left == .string and right == .string) return .string;
    if (left == .number and right == .number) return .number;
    if (left == .bigint and right == .bigint) return .bigint;
    return .unknown_expression;
}

fn typeFromAnnotation(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) ?ValueType {
    if (index == .null or depth >= 32) return null;
    const type_index = switch (tree.data(index)) {
        .ts_type_annotation => |annotation| annotation.type_annotation,
        else => index,
    };

    return switch (tree.data(type_index)) {
        .ts_string_keyword => .string,
        .ts_number_keyword => .number,
        .ts_bigint_keyword => .bigint,
        .ts_boolean_keyword => .boolean,
        .ts_unknown_keyword => .unknown,
        .ts_any_keyword => .any,
        .ts_literal_type => |literal| literalType(tree, literal.literal),
        .ts_parenthesized_type => |value| typeFromAnnotation(tree, symbols, value.type_annotation, depth + 1),
        .ts_type_alias_declaration => |alias| typeFromAnnotation(tree, symbols, alias.type_annotation, depth + 1),
        .ts_type_parameter => |parameter| typeFromAnnotation(tree, symbols, parameter.constraint, depth + 1),
        .ts_type_reference => |reference| blk: {
            const symbol = symbols.symbolOf(reference.type_name) orelse break :blk null;
            for (symbols.symbolDecls(symbol)) |declaration| {
                const parent = symbols.parentOf(declaration) orelse continue;
                if (typeFromAnnotation(tree, symbols, parent, depth + 1)) |value| break :blk value;
            }
            break :blk null;
        },
        else => null,
    };
}

fn literalType(tree: *const ast.Tree, index: ast.NodeIndex) ?ValueType {
    return switch (tree.data(index)) {
        .numeric_literal => .number,
        .string_literal, .template_literal => .string,
        .bigint_literal => .bigint,
        .boolean_literal => .boolean,
        .null_literal => .invalid,
        else => null,
    };
}

fn referenceType(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) ValueType {
    const symbol = symbols.symbolOf(index) orelse return .unknown_expression;
    for (symbols.symbolDecls(symbol)) |declaration| {
        const annotation = switch (tree.data(declaration)) {
            .binding_identifier => |identifier| identifier.type_annotation,
            else => .null,
        };
        if (annotation != .null) return typeFromAnnotation(tree, symbols, annotation, depth + 1) orelse .unknown_expression;
        if (symbols.parentOf(declaration)) |parent| {
            if (tree.data(parent) == .variable_declarator) {
                if (bindingHasWrites(symbols, index)) return .unknown_expression;
                return inferExpressionTypeAtDepth(tree, symbols, tree.data(parent).variable_declarator.init, depth + 1);
            }
            if (tree.data(parent) == .assignment_pattern) {
                const pattern = tree.data(parent).assignment_pattern;
                if (pattern.type_annotation != .null) return typeFromAnnotation(tree, symbols, pattern.type_annotation, depth + 1) orelse .unknown_expression;
                const parameter = symbols.parentOf(parent) orelse return .unknown_expression;
                if (tree.data(parameter) != .formal_parameter) return parameterPatternType(tree, symbols, declaration, depth + 1);
                const params = symbols.parentOf(parameter) orelse return .unknown_expression;
                const function = symbols.parentOf(params) orelse return .unknown_expression;
                if (!hasUncontextualizedParameters(tree, symbols, function, depth + 1)) return .unknown_expression;
                return inferExpressionTypeAtDepth(tree, symbols, pattern.right, depth + 1);
            }
            if (tree.data(parent) == .binding_property or tree.data(parent) == .array_pattern or tree.data(parent) == .object_pattern) {
                return parameterPatternType(tree, symbols, declaration, depth + 1);
            }
            if (tree.data(parent) == .formal_parameter) {
                const params = symbols.parentOf(parent) orelse continue;
                const function = symbols.parentOf(params) orelse continue;
                if (hasUncontextualizedParameters(tree, symbols, function, depth + 1)) return .any;
            }
        }
    }
    return .unknown_expression;
}

// Callback parameters and annotated function expressions may be contextually
// typed. Only infer implicit any where no surrounding signature supplies it.
fn hasUncontextualizedParameters(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) bool {
    if (depth >= 32) return false;
    switch (tree.data(index)) {
        .function => |function| if (function.type == .function_declaration) return true,
        .arrow_function_expression => {},
        else => return false,
    }
    var current = index;
    while (symbols.parentOf(current)) |parent| {
        switch (tree.data(parent)) {
            .parenthesized_expression => current = parent,
            .variable_declarator => |declarator| return switch (tree.data(declarator.id)) {
                .binding_identifier => |binding| binding.type_annotation == .null or typeFromAnnotation(tree, symbols, binding.type_annotation, depth + 1) == .any,
                else => false,
            },
            .call_expression => |call| return inferExpressionTypeAtDepth(tree, symbols, call.callee, depth + 1) == .any,
            .export_default_declaration => return true,
            else => return false,
        }
    }
    return false;
}

fn memberType(tree: *const ast.Tree, symbols: SymbolTable, member: ast.MemberExpression, depth: usize) ValueType {
    if (depth >= 32) return .unknown_expression;
    if (inferExpressionTypeAtDepth(tree, symbols, member.object, depth + 1) == .any) return .any;
    const annotation = expressionAnnotation(tree, symbols, member.object, depth + 1);
    if (member.computed and isNumericIndex(tree, symbols, member.property, depth + 1)) {
        const element = arrayElementAnnotation(tree, symbols, annotation, depth + 1);
        if (element != .null) return typeFromAnnotation(tree, symbols, element, depth + 1) orelse .unknown_expression;
    }
    const name = memberName(tree, member.property, member.computed) orelse return .unknown_expression;
    const property = propertyAnnotation(tree, symbols, annotation, name, depth + 1);
    return typeFromAnnotation(tree, symbols, property, depth + 1) orelse .unknown_expression;
}

fn expressionAnnotation(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) ast.NodeIndex {
    if (index == .null or depth >= 32) return .null;
    return switch (tree.data(index)) {
        .identifier_reference => blk: {
            const symbol = symbols.symbolOf(index) orelse break :blk .null;
            for (symbols.symbolDecls(symbol)) |declaration| {
                if (tree.data(declaration) == .binding_identifier) {
                    const annotation = tree.data(declaration).binding_identifier.type_annotation;
                    if (annotation != .null) break :blk annotation;
                }
                const parent = symbols.parentOf(declaration) orelse continue;
                switch (tree.data(parent)) {
                    .assignment_pattern => |pattern| if (pattern.type_annotation != .null) {
                        break :blk pattern.type_annotation;
                    },
                    .variable_declarator => |variable| {
                        if (bindingHasWrites(symbols, index)) break :blk .null;
                        break :blk expressionAnnotation(tree, symbols, variable.init, depth + 1);
                    },
                    else => {},
                }
            }
            break :blk .null;
        },
        .ts_as_expression => |value| value.type_annotation,
        .ts_type_assertion => |value| value.type_annotation,
        .parenthesized_expression => |value| expressionAnnotation(tree, symbols, value.expression, depth + 1),
        .ts_non_null_expression => |value| expressionAnnotation(tree, symbols, value.expression, depth + 1),
        .chain_expression => |value| expressionAnnotation(tree, symbols, value.expression, depth + 1),
        .ts_satisfies_expression => |value| expressionAnnotation(tree, symbols, value.expression, depth + 1),
        .member_expression => |member| blk: {
            const name = memberName(tree, member.property, member.computed) orelse break :blk .null;
            break :blk propertyAnnotation(tree, symbols, expressionAnnotation(tree, symbols, member.object, depth + 1), name, depth + 1);
        },
        else => .null,
    };
}

fn memberName(tree: *const ast.Tree, index: ast.NodeIndex, computed: bool) ?[]const u8 {
    return switch (tree.data(index)) {
        .identifier_name => |name| if (!computed) tree.string(name.name) else null,
        .identifier_reference => |name| if (!computed) tree.string(name.name) else null,
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn referencedPropertyAnnotation(tree: *const ast.Tree, symbols: SymbolTable, reference: ast.NodeIndex, name: []const u8, depth: usize) ast.NodeIndex {
    const symbol = symbols.symbolOf(reference) orelse return .null;
    for (symbols.symbolDecls(symbol)) |declaration| {
        const parent = symbols.parentOf(declaration) orelse continue;
        const annotation = propertyAnnotation(tree, symbols, parent, name, depth + 1);
        if (annotation != .null) return annotation;
    }
    return .null;
}

fn propertyAnnotation(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, name: []const u8, depth: usize) ast.NodeIndex {
    if (index == .null or depth >= 32) return .null;
    const members = switch (tree.data(index)) {
        .ts_type_annotation => |value| return propertyAnnotation(tree, symbols, value.type_annotation, name, depth + 1),
        .ts_parenthesized_type => |value| return propertyAnnotation(tree, symbols, value.type_annotation, name, depth + 1),
        .ts_type_alias_declaration => |value| return propertyAnnotation(tree, symbols, value.type_annotation, name, depth + 1),
        .ts_type_reference => |reference| return referencedPropertyAnnotation(tree, symbols, reference.type_name, name, depth + 1),
        .ts_type_parameter => |value| return propertyAnnotation(tree, symbols, value.constraint, name, depth + 1),
        .ts_interface_declaration => |value| {
            const own = propertyAnnotation(tree, symbols, value.body, name, depth + 1);
            if (own != .null) return own;
            for (tree.extra(value.extends)) |base| {
                const inherited = propertyAnnotation(tree, symbols, base, name, depth + 1);
                if (inherited != .null) return inherited;
            }
            return .null;
        },
        .ts_interface_heritage => |base| return referencedPropertyAnnotation(tree, symbols, base.expression, name, depth + 1),
        .ts_type_literal => |value| value.members,
        .ts_interface_body => |value| value.body,
        else => return .null,
    };
    for (tree.extra(members)) |member| {
        const property = switch (tree.data(member)) {
            .ts_property_signature => |value| value,
            else => continue,
        };
        const key = memberName(tree, property.key, property.computed) orelse continue;
        if (std.mem.eql(u8, key, name)) return property.type_annotation;
    }
    return .null;
}

fn bindingHasWrites(symbols: SymbolTable, index: ast.NodeIndex) bool {
    const symbol = symbols.symbolOf(index) orelse return true;
    for (symbols.model.uses(symbol)) |reference| if (symbols.isWriteReference(reference)) return true;
    return false;
}

fn parameterPatternType(tree: *const ast.Tree, symbols: SymbolTable, declaration: ast.NodeIndex, depth: usize) ValueType {
    if (depth >= 32) return .unknown_expression;
    var current = declaration;
    var path: [16][]const u8 = undefined;
    var path_len: usize = 0;
    var default_value: ast.NodeIndex = .null;
    var aggregate_default = false;
    var steps: usize = 0;
    while (symbols.parentOf(current)) |parent| {
        steps += 1;
        if (steps >= 32) return .unknown_expression;
        const annotation: ast.NodeIndex = switch (tree.data(parent)) {
            .object_pattern => |pattern| pattern.type_annotation,
            .array_pattern => |pattern| pattern.type_annotation,
            .assignment_pattern => |pattern| pattern.type_annotation,
            else => .null,
        };
        if (annotation != .null) {
            if (typeFromAnnotation(tree, symbols, annotation, depth + 1) == .any) return .any;
            var selected = annotation;
            for (0..path_len) |i| selected = propertyAnnotation(tree, symbols, selected, path[path_len - i - 1], depth + 1);
            return typeFromAnnotation(tree, symbols, selected, depth + 1) orelse .unknown_expression;
        }
        switch (tree.data(parent)) {
            .binding_property => |property| {
                if (path_len == path.len) return .unknown_expression;
                path[path_len] = memberName(tree, property.key, property.computed) orelse return .unknown_expression;
                path_len += 1;
            },
            .object_pattern, .array_pattern => {},
            .assignment_pattern => |pattern| {
                if (pattern.left == declaration) default_value = pattern.right else aggregate_default = true;
            },
            .formal_parameter => {
                const params = symbols.parentOf(parent) orelse return .unknown_expression;
                const function = symbols.parentOf(params) orelse return .unknown_expression;
                if (!hasUncontextualizedParameters(tree, symbols, function, depth + 1) or aggregate_default) return .unknown_expression;
                return if (default_value != .null) inferExpressionTypeAtDepth(tree, symbols, default_value, depth + 1) else .any;
            },
            else => return .unknown_expression,
        }
        current = parent;
    }
    return .unknown_expression;
}

fn narrowedReferenceType(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) ValueType {
    const baseline = referenceType(tree, symbols, index, depth);
    if (depth >= 32 or (baseline != .unknown and baseline != .any)) return baseline;
    const symbol = symbols.symbolOf(index) orelse return baseline;
    const Flow = @import("typescript_eslint_restrict_plus_operands_flow.zig").Narrowing(ValueType);
    return (Flow{ .tree = tree, .symbols = symbols, .symbol = symbol, .reference = index, .baseline = baseline }).run();
}

// Keep type-parameter identity alongside alias instantiations. Names alone can
// collide across nested aliases and function-level generic parameters.
const TypeBindings = struct {
    parameters: [16]ast.NodeIndex = undefined,
    arguments: [16]ast.NodeIndex = undefined,
    len: usize = 0,

    fn append(self: *TypeBindings, tree: *const ast.Tree, parameters: ast.NodeIndex, arguments: ast.NodeIndex) bool {
        if (parameters == .null) return true;
        const params = tree.extra(tree.data(parameters).ts_type_parameter_declaration.params);
        const args = if (arguments == .null) &.{} else tree.extra(tree.data(arguments).ts_type_parameter_instantiation.params);
        for (params, 0..) |index, i| {
            if (self.len == self.parameters.len) return false;
            const parameter = tree.data(index).ts_type_parameter;
            self.parameters[self.len] = parameter.name;
            self.arguments[self.len] = if (i < args.len) args[i] else parameter.default;
            self.len += 1;
        }
        return true;
    }

    fn resolve(self: TypeBindings, tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex) ast.NodeIndex {
        var current = unwrapAnnotation(tree, index);
        for (0..32) |_| {
            if (current == .null or tree.data(current) != .ts_type_reference) return current;
            const symbol = symbols.symbolOf(tree.data(current).ts_type_reference.type_name) orelse return current;
            var found = false;
            for (self.parameters[0..self.len], self.arguments[0..self.len]) |parameter, argument| {
                if (symbols.symbolOf(parameter) == symbol) {
                    current = unwrapAnnotation(tree, argument);
                    found = true;
                    break;
                }
            }
            if (!found) return current;
        }
        return .null;
    }
};

const Signature = struct {
    return_type: ast.NodeIndex,
    params: ast.NodeIndex,
    type_parameters: ast.NodeIndex,
    bindings: TypeBindings = .{},
};

fn callSignature(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) ?Signature {
    if (index == .null or depth >= 32) return null;
    return switch (tree.data(index)) {
        .function => |function| if (function.async or function.generator) null else .{ .return_type = function.return_type, .params = function.params, .type_parameters = function.type_parameters },
        .arrow_function_expression => |function| if (function.async) null else .{ .return_type = function.return_type, .params = function.params, .type_parameters = function.type_parameters },
        .ts_function_type => |function| .{ .return_type = function.return_type, .params = function.params, .type_parameters = function.type_parameters },
        .ts_type_annotation => |annotation| callSignature(tree, symbols, annotation.type_annotation, depth + 1),
        .ts_type_alias_declaration => |alias| callSignature(tree, symbols, alias.type_annotation, depth + 1),
        .parenthesized_expression => |expression| callSignature(tree, symbols, expression.expression, depth + 1),
        .ts_as_expression => |expression| callSignature(tree, symbols, expression.type_annotation, depth + 1),
        .ts_type_reference => |reference| blk: {
            const symbol = symbols.symbolOf(reference.type_name) orelse break :blk null;
            for (symbols.symbolDecls(symbol)) |declaration| {
                const parent = symbols.parentOf(declaration) orelse continue;
                if (callSignature(tree, symbols, parent, depth + 1)) |resolved| {
                    var signature = resolved;
                    if (tree.data(parent) == .ts_type_alias_declaration and
                        !signature.bindings.append(tree, tree.data(parent).ts_type_alias_declaration.type_parameters, reference.type_arguments)) break :blk null;
                    break :blk signature;
                }
            }
            break :blk null;
        },
        .identifier_reference => blk: {
            const symbol = symbols.symbolOf(index) orelse break :blk null;
            // Overload selection requires a full checker; do not choose an arbitrary signature.
            const declarations = symbols.symbolDecls(symbol);
            if (declarations.len != 1 or bindingHasWrites(symbols, index)) break :blk null;
            const declaration = declarations[0];
            if (tree.data(declaration) == .binding_identifier) {
                const annotation = tree.data(declaration).binding_identifier.type_annotation;
                if (annotation != .null) break :blk callSignature(tree, symbols, annotation, depth + 1);
            }
            const parent = symbols.parentOf(declaration) orelse break :blk null;
            if (tree.data(parent) == .variable_declarator) break :blk callSignature(tree, symbols, tree.data(parent).variable_declarator.init, depth + 1);
            break :blk callSignature(tree, symbols, parent, depth + 1);
        },
        else => null,
    };
}

fn unwrapAnnotation(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    if (index == .null) return .null;
    return switch (tree.data(index)) {
        .ts_type_annotation => |annotation| annotation.type_annotation,
        else => index,
    };
}

fn callType(tree: *const ast.Tree, symbols: SymbolTable, call: ast.CallExpression, depth: usize) ValueType {
    if (depth >= 32) return .unknown_expression;
    if (inferExpressionTypeAtDepth(tree, symbols, call.callee, depth + 1) == .any) return .any;
    const signature = callSignature(tree, symbols, call.callee, depth + 1) orelse return .unknown_expression;
    const result = signature.bindings.resolve(tree, symbols, signature.return_type);
    if (result == .null) return .unknown_expression;
    if (signature.type_parameters != .null and tree.data(result) == .ts_type_reference) {
        const result_symbol = symbols.symbolOf(tree.data(result).ts_type_reference.type_name) orelse return .unknown_expression;
        const parameters = tree.extra(tree.data(signature.type_parameters).ts_type_parameter_declaration.params);
        for (parameters, 0..) |parameter_index, position| {
            const parameter = tree.data(parameter_index).ts_type_parameter;
            if (symbols.symbolOf(parameter.name) != result_symbol) continue;
            if (call.type_arguments != .null) {
                const arguments = tree.extra(tree.data(call.type_arguments).ts_type_parameter_instantiation.params);
                if (position < arguments.len) return typeFromAnnotation(tree, symbols, signature.bindings.resolve(tree, symbols, arguments[position]), depth + 1) orelse .unknown_expression;
                return typeFromAnnotation(tree, symbols, signature.bindings.resolve(tree, symbols, parameter.default), depth + 1) orelse .unknown_expression;
            }
            const arguments = tree.extra(call.arguments);
            const formals = tree.extra(tree.data(signature.params).formal_parameters.items);
            var inferred: ?ValueType = null;
            for (formals, 0..) |formal, i| {
                if (i >= arguments.len or tree.data(formal) != .formal_parameter) continue;
                const pattern = tree.data(formal).formal_parameter.pattern;
                if (tree.data(pattern) != .binding_identifier) continue;
                const annotation = unwrapAnnotation(tree, tree.data(pattern).binding_identifier.type_annotation);
                if (annotation == .null or tree.data(annotation) != .ts_type_reference) continue;
                if (symbols.symbolOf(tree.data(annotation).ts_type_reference.type_name) != result_symbol) continue;
                const actual = inferExpressionTypeAtDepth(tree, symbols, arguments[i], depth + 1);
                if (inferred) |previous| {
                    if (previous == .any or actual == .any) inferred = .any else if (previous != actual) return .unknown_expression;
                } else inferred = actual;
            }
            if (inferred) |actual| return actual;
            return typeFromAnnotation(tree, symbols, signature.bindings.resolve(tree, symbols, parameter.default), depth + 1) orelse .unknown_expression;
        }
    }
    return typeFromAnnotation(tree, symbols, result, depth + 1) orelse .unknown_expression;
}

fn isNumericIndex(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) bool {
    if (tree.data(index) == .string_literal) {
        _ = std.fmt.parseInt(usize, tree.string(tree.data(index).string_literal.value), 10) catch return false;
        return true;
    }
    return inferExpressionTypeAtDepth(tree, symbols, index, depth + 1) == .number;
}

fn arrayElementAnnotation(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, depth: usize) ast.NodeIndex {
    return arrayElementWithBindings(tree, symbols, index, .{}, depth);
}

fn arrayElementWithBindings(tree: *const ast.Tree, symbols: SymbolTable, original: ast.NodeIndex, bindings: TypeBindings, depth: usize) ast.NodeIndex {
    const index = bindings.resolve(tree, symbols, original);
    if (index == .null or depth >= 32) return .null;
    return switch (tree.data(index)) {
        .ts_type_annotation => |annotation| arrayElementWithBindings(tree, symbols, annotation.type_annotation, bindings, depth + 1),
        .ts_parenthesized_type => |annotation| arrayElementWithBindings(tree, symbols, annotation.type_annotation, bindings, depth + 1),
        .ts_type_alias_declaration => |alias| arrayElementWithBindings(tree, symbols, alias.type_annotation, bindings, depth + 1),
        .ts_array_type => |array| bindings.resolve(tree, symbols, array.element_type),
        .ts_type_reference => |reference| blk: {
            if (symbols.symbolOf(reference.type_name)) |symbol| {
                for (symbols.symbolDecls(symbol)) |declaration| {
                    const parent = symbols.parentOf(declaration) orelse continue;
                    var instantiated = bindings;
                    if (tree.data(parent) == .ts_type_alias_declaration and
                        !instantiated.append(tree, tree.data(parent).ts_type_alias_declaration.type_parameters, reference.type_arguments)) break :blk .null;
                    const element = arrayElementWithBindings(tree, symbols, parent, instantiated, depth + 1);
                    if (element != .null) break :blk element;
                }
                break :blk .null;
            }
            const name = memberName(tree, reference.type_name, false) orelse break :blk .null;
            if ((!std.mem.eql(u8, name, "Array") and !std.mem.eql(u8, name, "ReadonlyArray")) or reference.type_arguments == .null) break :blk .null;
            const arguments = tree.extra(tree.data(reference.type_arguments).ts_type_parameter_instantiation.params);
            break :blk if (arguments.len == 1) bindings.resolve(tree, symbols, arguments[0]) else .null;
        },
        else => .null,
    };
}
