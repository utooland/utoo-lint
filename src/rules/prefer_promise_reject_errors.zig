const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "prefer-promise-reject-errors";

pub const Options = struct {
    allow_empty_reject: bool = false,
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    return runWithOptions(allocator, diagnostics, tree, symbol_table, .{});
}

pub fn runWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .symbol_table = symbol_table,
        .options = options,
    };

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (isGlobalPromiseRejectCall(ctx.tree, self.symbol_table, call)) {
            try checkRejectArgument(self.allocator, self.diagnostics, ctx.tree, call.arguments, index, self.options);
        }

        return .proceed;
    }

    pub fn enter_new_expression(
        self: *Visitor,
        expression: ast.NewExpression,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (!isGlobalPromiseReference(ctx.tree, self.symbol_table, expression.callee)) return .proceed;
        const executor = promiseExecutor(ctx.tree, expression.arguments) orelse return .proceed;
        const reject_name = executorRejectName(ctx.tree, executor) orelse return .proceed;

        try scanExecutor(self.allocator, self.diagnostics, ctx.tree, reject_name, executor, self.options);
        return .proceed;
    }
};

fn isGlobalPromiseRejectCall(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    call: ast.CallExpression,
) bool {
    if (call.optional) return false;

    const member = switch (tree.data(unwrapTransparent(tree, call.callee))) {
        .member_expression => |member| member,
        else => return false,
    };
    if (member.optional) return false;

    const property = staticMemberPropertyName(tree, member) orelse return false;
    if (!std.mem.eql(u8, property, "reject")) return false;
    return isGlobalPromiseReference(tree, symbol_table, member.object);
}

fn promiseExecutor(tree: *const ast.Tree, arguments: ast.IndexRange) ?ast.NodeIndex {
    if (arguments.len == 0) return null;

    const executor = unwrapTransparent(tree, tree.extra(arguments)[0]);
    return switch (tree.data(executor)) {
        .arrow_function_expression,
        .function,
        => executor,
        else => null,
    };
}

fn executorRejectName(tree: *const ast.Tree, executor: ast.NodeIndex) ?[]const u8 {
    const params_index = switch (tree.data(executor)) {
        .function => |function| function.params,
        .arrow_function_expression => |arrow| arrow.params,
        else => return null,
    };

    const params = switch (tree.data(params_index)) {
        .formal_parameters => |params| params,
        else => return null,
    };

    const items = tree.extra(params.items);
    if (items.len < 2) return null;

    const second = switch (tree.data(items[1])) {
        .formal_parameter => |parameter| parameter.pattern,
        else => return null,
    };

    return bindingIdentifierName(tree, second);
}

fn scanExecutor(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    reject_name: []const u8,
    executor: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    switch (tree.data(executor)) {
        .function => |function| try scanNode(allocator, diagnostics, tree, reject_name, function.body, options),
        .arrow_function_expression => |arrow| try scanNode(allocator, diagnostics, tree, reject_name, arrow.body, options),
        else => {},
    }
}

fn scanNode(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    reject_name: []const u8,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .call_expression => |call| {
            if (isRejectCall(tree, reject_name, call)) {
                try checkRejectArgument(allocator, diagnostics, tree, call.arguments, index, options);
            }
            try scanChildren(allocator, diagnostics, tree, reject_name, call, options);
        },
        .function,
        .arrow_function_expression,
        .class,
        => return,
        inline else => |node| try scanChildren(allocator, diagnostics, tree, reject_name, node, options),
    }
}

fn scanChildren(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    reject_name: []const u8,
    node: anytype,
    options: Options,
) Allocator.Error!void {
    const T = @TypeOf(node);
    if (@typeInfo(T) != .@"struct") return;

    inline for (@typeInfo(T).@"struct".field_names) |field_name| {
        if (@FieldType(T, field_name) == ast.NodeIndex) {
            try scanNode(allocator, diagnostics, tree, reject_name, @field(node, field_name), options);
        } else if (@FieldType(T, field_name) == ast.IndexRange) {
            for (tree.extra(@field(node, field_name))) |child| {
                try scanNode(allocator, diagnostics, tree, reject_name, child, options);
            }
        }
    }
}

fn isRejectCall(tree: *const ast.Tree, reject_name: []const u8, call: ast.CallExpression) bool {
    if (call.optional) return false;
    return isIdentifierReferenceNamed(tree, call.callee, reject_name);
}

fn checkRejectArgument(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    arguments: ast.IndexRange,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    if (arguments.len == 0) {
        if (!options.allow_empty_reject) {
            try addDiagnostic(allocator, diagnostics, tree, index);
        }
        return;
    }
    const argument = tree.extra(arguments)[0];
    if (!isInvalidRejectReason(tree, unwrapTransparent(tree, argument))) return;

    try addDiagnostic(allocator, diagnostics, tree, index);
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
        "Expected the Promise rejection reason to be an Error.",
        tree.span(index),
    );
}

fn isInvalidRejectReason(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;

    return switch (tree.data(index)) {
        .string_literal,
        .numeric_literal,
        .bigint_literal,
        .boolean_literal,
        .null_literal,
        .template_literal,
        .regexp_literal,
        .object_expression,
        .array_expression,
        => true,
        .identifier_reference => |identifier| std.mem.eql(u8, tree.string(identifier.name), "undefined"),
        .unary_expression => true,
        .binary_expression => |expression| expression.operator == .add,
        else => false,
    };
}

fn isGlobalPromiseReference(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    index: ast.NodeIndex,
) bool {
    const unwrapped = unwrapTransparent(tree, index);
    if (!isIdentifierReferenceNamed(tree, unwrapped, "Promise")) return false;
    return isUnresolvedReference(symbol_table, unwrapped);
}

fn isUnresolvedReference(
    symbol_table: traverser.semantic.SymbolTable,
    node: ast.NodeIndex,
) bool {
    return symbol_table.isUnresolvedReference(node);
}

fn bindingIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    return switch (tree.data(unwrapTransparent(tree, index))) {
        .binding_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn isIdentifierReferenceNamed(tree: *const ast.Tree, index: ast.NodeIndex, name: []const u8) bool {
    if (index == .null) return false;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| std.mem.eql(u8, tree.string(identifier.name), name),
        else => false,
    };
}

fn staticMemberPropertyName(tree: *const ast.Tree, member: ast.MemberExpression) ?[]const u8 {
    if (member.property == .null) return null;

    return switch (tree.data(member.property)) {
        .identifier_name => |identifier| if (member.computed) null else tree.string(identifier.name),
        .string_literal => |literal| tree.string(literal.value),
        .template_literal => |literal| templateStringValue(tree, literal),
        else => null,
    };
}

fn templateStringValue(tree: *const ast.Tree, literal: ast.TemplateLiteral) ?[]const u8 {
    if (literal.expressions.len != 0) return null;

    const quasis = tree.extra(literal.quasis);
    if (quasis.len == 0) return "";

    return switch (tree.data(quasis[0])) {
        .template_element => |element| tree.string(element.cooked),
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
