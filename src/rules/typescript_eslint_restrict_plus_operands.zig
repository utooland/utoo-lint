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

    const left = inferExpressionType(tree, symbols, expression.left);
    const right = inferExpressionType(tree, symbols, expression.right);
    if (left == .any or right == .any) {
        if (!options.allow_any) {
            try core.addDiagnostic(allocator, diagnostics, .warning, id, "Invalid operand for a '+' operation. Operands must each be a number or string. Got `any`.", tree.span(index));
            return;
        }
        const other = if (left == .any) right else left;
        if (other == .any or other == .unknown_expression or isAllowedOperand(other)) return;
    }
    if (left == .unknown_expression or right == .unknown_expression) return;
    if (isAllowedPair(left, right, options)) return;

    if (isAllowedOperand(left) and isAllowedOperand(right)) {
        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            .warning,
            id,
            tree.span(index),
            "Operands of '+' operations must be a number or string. Got `{s}` + `{s}`.",
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
        "Invalid operand for a '+' operation. Operands must each be a number or string. Got `{s}`.",
        .{invalid.text()},
    );
}

fn isAllowedPair(left: ValueType, right: ValueType, options: Options) bool {
    if ((left == .number and right == .number) or
        (left == .string and right == .string))
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
    return value_type == .number or value_type == .string;
}

fn inferExpressionType(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex) ValueType {
    if (index == .null) return .unknown_expression;

    return switch (tree.data(index)) {
        .numeric_literal => .number,
        .string_literal, .template_literal => .string,
        .bigint_literal => .bigint,
        .boolean_literal => .boolean,
        .null_literal, .array_expression, .object_expression => .invalid,
        .identifier_reference => referenceType(tree, symbols, index),
        .parenthesized_expression => |parenthesized| inferExpressionType(tree, symbols, parenthesized.expression),
        .ts_as_expression => |expression| typeFromAnnotation(tree, expression.type_annotation) orelse inferExpressionType(tree, symbols, expression.expression),
        .ts_type_assertion => |expression| typeFromAnnotation(tree, expression.type_annotation) orelse inferExpressionType(tree, symbols, expression.expression),
        .ts_satisfies_expression => |expression| inferExpressionType(tree, symbols, expression.expression),
        .ts_non_null_expression => |expression| inferExpressionType(tree, symbols, expression.expression),
        .binary_expression => |binary| if (binary.operator == .add) inferBinaryResultType(tree, symbols, binary) else .unknown_expression,
        else => .unknown_expression,
    };
}

fn inferBinaryResultType(tree: *const ast.Tree, symbols: SymbolTable, expression: ast.BinaryExpression) ValueType {
    const left = inferExpressionType(tree, symbols, expression.left);
    const right = inferExpressionType(tree, symbols, expression.right);
    if (left == .string and right == .string) return .string;
    if (left == .number and right == .number) return .number;
    return .unknown_expression;
}

fn typeFromAnnotation(tree: *const ast.Tree, index: ast.NodeIndex) ?ValueType {
    if (index == .null) return null;
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

fn referenceType(tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex) ValueType {
    const symbol = symbols.symbolOf(index) orelse return .unknown_expression;
    for (symbols.symbolDecls(symbol)) |declaration| {
        const annotation = switch (tree.data(declaration)) {
            .binding_identifier => |identifier| identifier.type_annotation,
            else => .null,
        };
        if (typeFromAnnotation(tree, annotation)) |value| return value;
        if (symbols.parentOf(declaration)) |parent| {
            if (tree.data(parent) == .assignment_pattern) {
                if (typeFromAnnotation(tree, tree.data(parent).assignment_pattern.type_annotation)) |value| return value;
            }
        }
    }
    return .unknown_expression;
}
