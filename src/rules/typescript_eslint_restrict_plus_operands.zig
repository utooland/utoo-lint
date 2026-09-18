const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = parser.traverser;
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

const TypeEnv = std.StringHashMapUnmanaged(ValueType);

pub const State = struct {
    env: TypeEnv = .empty,
    initialized: bool = false,

    pub fn deinit(self: *State, allocator: Allocator) void {
        self.env.deinit(allocator);
    }

    fn ensureInitialized(self: *State, allocator: Allocator, tree: *const ast.Tree) Allocator.Error!void {
        if (self.initialized) return;
        self.initialized = true;
        var visitor = TypeEnvVisitor{ .allocator = allocator, .env = &self.env };
        try traverser.basic.traverse(TypeEnvVisitor, tree, &visitor);
    }
};

pub fn checkBinaryExpression(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    expression: ast.BinaryExpression,
    index: ast.NodeIndex,
    state: *State,
    options: Options,
) Allocator.Error!void {
    if (expression.operator != .add) return;

    try state.ensureInitialized(allocator, tree);

    const left = inferExpressionType(tree, state.env, expression.left);
    const right = inferExpressionType(tree, state.env, expression.right);
    if (left == .any or right == .any) {
        if (!options.allow_any) {
            try core.addDiagnostic(allocator, diagnostics, .warning, id, "Invalid operand for a '+' operation. Operands must each be a number or string. Got `any`.", tree.span(index));
        }
        return;
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

    const invalid = if (!isAllowedOperand(left)) left else right;
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

fn inferExpressionType(tree: *const ast.Tree, env: TypeEnv, index: ast.NodeIndex) ValueType {
    if (index == .null) return .unknown_expression;

    return switch (tree.data(index)) {
        .numeric_literal => .number,
        .string_literal, .template_literal => .string,
        .bigint_literal => .bigint,
        .boolean_literal => .boolean,
        .null_literal, .array_expression, .object_expression => .invalid,
        .identifier_reference => |identifier| env.get(tree.string(identifier.name)) orelse .unknown_expression,
        .parenthesized_expression => |parenthesized| inferExpressionType(tree, env, parenthesized.expression),
        .ts_as_expression => |expression| typeFromAnnotation(tree, expression.type_annotation) orelse inferExpressionType(tree, env, expression.expression),
        .ts_type_assertion => |expression| typeFromAnnotation(tree, expression.type_annotation) orelse inferExpressionType(tree, env, expression.expression),
        .ts_satisfies_expression => |expression| inferExpressionType(tree, env, expression.expression),
        .ts_non_null_expression => |expression| inferExpressionType(tree, env, expression.expression),
        .binary_expression => |binary| if (binary.operator == .add) inferBinaryResultType(tree, env, binary) else .unknown_expression,
        else => .unknown_expression,
    };
}

fn inferBinaryResultType(tree: *const ast.Tree, env: TypeEnv, expression: ast.BinaryExpression) ValueType {
    const left = inferExpressionType(tree, env, expression.left);
    const right = inferExpressionType(tree, env, expression.right);
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

const TypeEnvVisitor = struct {
    allocator: Allocator,
    env: *TypeEnv,

    pub fn enter_variable_declarator(
        self: *TypeEnvVisitor,
        declarator: ast.VariableDeclarator,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectBinding(ctx.tree, declarator.id);
        return .proceed;
    }

    pub fn enter_formal_parameter(
        self: *TypeEnvVisitor,
        parameter: ast.FormalParameter,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectBinding(ctx.tree, parameter.pattern);
        return .proceed;
    }

    fn collectBinding(self: *TypeEnvVisitor, tree: *const ast.Tree, index: ast.NodeIndex) Allocator.Error!void {
        if (index == .null) return;

        switch (tree.data(index)) {
            .binding_identifier => |identifier| {
                const value_type = typeFromAnnotation(tree, identifier.type_annotation) orelse return;
                try self.env.put(self.allocator, tree.string(identifier.name), value_type);
            },
            .assignment_pattern => |assignment| {
                if (typeFromAnnotation(tree, assignment.type_annotation)) |value_type| {
                    if (tree.data(assignment.left) == .binding_identifier) {
                        const identifier = tree.data(assignment.left).binding_identifier;
                        try self.env.put(self.allocator, tree.string(identifier.name), value_type);
                        return;
                    }
                }
                try self.collectBinding(tree, assignment.left);
            },
            else => {},
        }
    }
};
