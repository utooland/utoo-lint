const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "array-callback-return";

pub const Options = struct {
    allow_implicit: bool = false,
    check_for_each: bool = false,
    allow_void: bool = false,
};

const CallbackKind = enum {
    value_required,
    for_each,
};

const CallbackTarget = struct {
    callback: ast.NodeIndex,
    kind: CallbackKind,
};

const Completion = enum {
    continues,
    valid_terminal,
    invalid_return,
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    call: ast.CallExpression,
    _: ast.NodeIndex,
) Allocator.Error!void {
    return checkWithOptions(allocator, diagnostics, tree, call, .{});
}

pub fn checkWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    call: ast.CallExpression,
    options: Options,
) Allocator.Error!void {
    const target = callbackTarget(tree, call, options) orelse return;

    if (target.kind == .for_each) {
        try checkForEachCallback(allocator, diagnostics, tree, target.callback, options);
        return;
    }

    if (callbackReturnsValue(tree, target.callback, options)) return;

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .warning,
        id,
        "Expected to return a value in array callback.",
        tree.span(target.callback),
    );
}

fn callbackTarget(tree: *const ast.Tree, call: ast.CallExpression, options: Options) ?CallbackTarget {
    const arguments = tree.extra(call.arguments);
    if (arguments.len == 0) return null;

    const callee = unwrapTransparent(tree, call.callee);
    const member = switch (tree.data(callee)) {
        .member_expression => |member| member,
        else => return null,
    };

    const method = propertyName(tree, member) orelse return null;
    if (std.mem.eql(u8, method, "forEach")) {
        if (!options.check_for_each) return null;
        return .{
            .callback = callbackIfFunction(tree, arguments[0]) orelse return null,
            .kind = .for_each,
        };
    }

    if (isArrayFromCall(tree, member, method)) {
        if (arguments.len < 2) return null;
        return .{
            .callback = callbackIfFunction(tree, arguments[1]) orelse return null,
            .kind = .value_required,
        };
    }

    if (!isArrayCallbackMethod(method)) return null;
    return .{
        .callback = callbackIfFunction(tree, arguments[0]) orelse return null,
        .kind = .value_required,
    };
}

fn callbackIfFunction(tree: *const ast.Tree, index: ast.NodeIndex) ?ast.NodeIndex {
    const callback = unwrapTransparent(tree, index);
    return switch (tree.data(callback)) {
        .function => |function| if (function.async or function.generator) null else callback,
        .arrow_function_expression => |arrow| if (arrow.async) null else callback,
        else => null,
    };
}

fn isArrayFromCall(tree: *const ast.Tree, member: ast.MemberExpression, method: []const u8) bool {
    return std.mem.eql(u8, method, "from") and isIdentifierReferenceNamed(tree, member.object, "Array");
}

fn isArrayCallbackMethod(method: []const u8) bool {
    const methods = [_][]const u8{
        "every",
        "filter",
        "find",
        "findIndex",
        "findLast",
        "findLastIndex",
        "flatMap",
        "map",
        "reduce",
        "reduceRight",
        "some",
        "sort",
        "toSorted",
    };

    for (methods) |candidate| {
        if (std.mem.eql(u8, method, candidate)) return true;
    }

    return false;
}

fn callbackReturnsValue(tree: *const ast.Tree, callback: ast.NodeIndex, options: Options) bool {
    return switch (tree.data(callback)) {
        .function => |function| functionReturnsValue(tree, function.body, options),
        .arrow_function_expression => |arrow| if (arrow.expression)
            expressionIsValidReturnValue(tree, arrow.body, options)
        else
            functionReturnsValue(tree, arrow.body, options),
        else => true,
    };
}

fn functionReturnsValue(tree: *const ast.Tree, body_index: ast.NodeIndex, options: Options) bool {
    if (body_index == .null) return true;

    const body = switch (tree.data(body_index)) {
        .function_body => |body| body,
        else => return true,
    };

    return rangeCompletion(tree, body.body, options) == .valid_terminal;
}

fn rangeCompletion(tree: *const ast.Tree, range: ast.IndexRange, options: Options) Completion {
    for (tree.extra(range)) |statement| {
        switch (statementCompletion(tree, statement, options)) {
            .continues => {},
            .valid_terminal => return .valid_terminal,
            .invalid_return => return .invalid_return,
        }
    }

    return .continues;
}

fn statementCompletion(tree: *const ast.Tree, index: ast.NodeIndex, options: Options) Completion {
    if (index == .null) return .continues;

    return switch (tree.data(index)) {
        .return_statement => |statement| returnCompletion(tree, statement, options),
        .throw_statement => .valid_terminal,
        .block_statement => |block| rangeCompletion(tree, block.body, options),
        .if_statement => |statement| ifCompletion(tree, statement, options),
        .try_statement => |statement| tryCompletion(tree, statement, options),
        .switch_statement => |statement| switchCompletion(tree, statement, options),
        else => .continues,
    };
}

// A case may both exit and fall through (for example, a conditional break).
// Keep those paths separate until the enclosing switch consumes its breaks.
const CaseFlow = struct {
    const next: u8 = 1;
    const terminal: u8 = 2;
    const invalid: u8 = 4;
    const breaks: u8 = 8;
    const escapes: u8 = 16;
};

fn caseRangeFlow(tree: *const ast.Tree, range: ast.IndexRange, options: Options) u8 {
    var flow: u8 = CaseFlow.next;
    for (tree.extra(range)) |statement| {
        if (flow & CaseFlow.next == 0) {
            // ESLint reports bare returns even in unreachable statements.
            flow |= caseNodeFlow(tree, statement, options) & CaseFlow.invalid;
            continue;
        }
        flow = (flow & ~CaseFlow.next) | caseNodeFlow(tree, statement, options);
    }
    return flow;
}

fn caseNodeFlow(tree: *const ast.Tree, index: ast.NodeIndex, options: Options) u8 {
    if (index == .null) return CaseFlow.next;
    return switch (tree.data(index)) {
        .break_statement => |statement| if (statement.label == .null) CaseFlow.breaks else CaseFlow.escapes,
        .continue_statement => CaseFlow.escapes,
        .block_statement => |block| caseRangeFlow(tree, block.body, options),
        .if_statement => |statement| caseNodeFlow(tree, statement.consequent, options) | caseNodeFlow(tree, statement.alternate, options),
        .try_statement => |statement| blk: {
            var flow = caseNodeFlow(tree, statement.block, options);
            if (statement.handler != .null) {
                const handler = tree.data(statement.handler).catch_clause;
                flow |= caseNodeFlow(tree, handler.body, options);
            }
            if (statement.finalizer != .null) {
                const finalizer = caseNodeFlow(tree, statement.finalizer, options);
                flow = (finalizer & ~CaseFlow.next) | (if (finalizer & CaseFlow.next != 0) flow else @as(u8, 0));
            }
            break :blk flow;
        },
        else => switch (statementCompletion(tree, index, options)) {
            .continues => CaseFlow.next,
            .valid_terminal => CaseFlow.terminal,
            .invalid_return => CaseFlow.invalid,
        },
    };
}

fn switchCompletion(tree: *const ast.Tree, statement: ast.SwitchStatement, options: Options) Completion {
    const cases = tree.extra(statement.cases);
    var has_default = false;
    for (cases) |index| if (tree.data(index).switch_case.@"test" == .null) {
        has_default = true;
    };
    var flow: u8 = if (has_default) 0 else CaseFlow.next;
    var suffix: u8 = CaseFlow.next;
    var cursor = cases.len;
    while (cursor > 0) {
        cursor -= 1;
        const current = caseRangeFlow(tree, tree.data(cases[cursor]).switch_case.consequent, options);
        suffix = (current & ~CaseFlow.next) | (if (current & CaseFlow.next != 0) suffix else @as(u8, 0));
        flow |= suffix;
    }
    if (flow & CaseFlow.invalid != 0) return .invalid_return;
    if (flow & (CaseFlow.next | CaseFlow.breaks | CaseFlow.escapes) != 0) return .continues;
    return if (flow & CaseFlow.terminal != 0) .valid_terminal else .continues;
}

fn returnCompletion(tree: *const ast.Tree, statement: ast.ReturnStatement, options: Options) Completion {
    if (statement.argument == .null) return if (options.allow_implicit)
        .valid_terminal
    else
        .invalid_return;
    if (!expressionIsValidReturnValue(tree, statement.argument, options)) return .invalid_return;
    return .valid_terminal;
}

fn checkForEachCallback(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    callback: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    switch (tree.data(callback)) {
        .function => |function| try scanForEachFunctionBody(allocator, diagnostics, tree, function.body, options),
        .arrow_function_expression => |arrow| if (arrow.expression) {
            if (expressionIsForbiddenForEachReturn(tree, arrow.body, options)) {
                try addForEachDiagnostic(allocator, diagnostics, tree, callback);
            }
        } else {
            try scanForEachFunctionBody(allocator, diagnostics, tree, arrow.body, options);
        },
        else => {},
    }
}

fn scanForEachFunctionBody(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    body_index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    if (body_index == .null) return;

    const body = switch (tree.data(body_index)) {
        .function_body => |body| body,
        else => return,
    };

    try scanForEachRange(allocator, diagnostics, tree, body.body, options);
}

fn scanForEachRange(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    range: ast.IndexRange,
    options: Options,
) Allocator.Error!void {
    for (tree.extra(range)) |statement| {
        try scanForEachNode(allocator, diagnostics, tree, statement, options);
    }
}

fn scanForEachNode(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    if (index == .null) return;

    switch (tree.data(index)) {
        .return_statement => |statement| {
            if (statement.argument != .null and expressionIsForbiddenForEachReturn(tree, statement.argument, options)) {
                try addForEachDiagnostic(allocator, diagnostics, tree, index);
            }
        },
        .block_statement => |block| try scanForEachRange(allocator, diagnostics, tree, block.body, options),
        .static_block => |block| try scanForEachRange(allocator, diagnostics, tree, block.body, options),
        .if_statement => |statement| {
            try scanForEachNode(allocator, diagnostics, tree, statement.consequent, options);
            try scanForEachNode(allocator, diagnostics, tree, statement.alternate, options);
        },
        .switch_statement => |statement| {
            for (tree.extra(statement.cases)) |case_index| {
                const switch_case = switch (tree.data(case_index)) {
                    .switch_case => |switch_case| switch_case,
                    else => continue,
                };
                try scanForEachRange(allocator, diagnostics, tree, switch_case.consequent, options);
            }
        },
        .for_statement => |statement| try scanForEachNode(allocator, diagnostics, tree, statement.body, options),
        .for_in_statement => |statement| try scanForEachNode(allocator, diagnostics, tree, statement.body, options),
        .for_of_statement => |statement| try scanForEachNode(allocator, diagnostics, tree, statement.body, options),
        .while_statement => |statement| try scanForEachNode(allocator, diagnostics, tree, statement.body, options),
        .do_while_statement => |statement| try scanForEachNode(allocator, diagnostics, tree, statement.body, options),
        .with_statement => |statement| try scanForEachNode(allocator, diagnostics, tree, statement.body, options),
        .labeled_statement => |statement| try scanForEachNode(allocator, diagnostics, tree, statement.body, options),
        .try_statement => |statement| {
            try scanForEachNode(allocator, diagnostics, tree, statement.block, options);
            if (statement.handler != .null) {
                const handler = switch (tree.data(statement.handler)) {
                    .catch_clause => |handler| handler,
                    else => return,
                };
                try scanForEachNode(allocator, diagnostics, tree, handler.body, options);
            }
            try scanForEachNode(allocator, diagnostics, tree, statement.finalizer, options);
        },
        .function,
        .arrow_function_expression,
        .class,
        => return,
        else => return,
    }
}

fn addForEachDiagnostic(
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
        "Array.prototype.forEach() expects no useless return value from callback.",
        tree.span(index),
    );
}

fn ifCompletion(tree: *const ast.Tree, statement: ast.IfStatement, options: Options) Completion {
    const consequent = statementCompletion(tree, statement.consequent, options);
    if (consequent == .invalid_return) return .invalid_return;

    if (statement.alternate == .null) return .continues;
    const alternate = statementCompletion(tree, statement.alternate, options);
    if (alternate == .invalid_return) return .invalid_return;

    if (consequent == .valid_terminal and alternate == .valid_terminal) return .valid_terminal;
    return .continues;
}

fn tryCompletion(tree: *const ast.Tree, statement: ast.TryStatement, options: Options) Completion {
    if (statement.finalizer != .null) {
        const finalizer = statementCompletion(tree, statement.finalizer, options);
        if (finalizer != .continues) return finalizer;
    }

    const block = statementCompletion(tree, statement.block, options);
    if (block == .invalid_return) return .invalid_return;
    if (statement.handler == .null) return block;

    const handler_node = switch (tree.data(statement.handler)) {
        .catch_clause => |handler| handler.body,
        else => return .continues,
    };
    const handler = statementCompletion(tree, handler_node, options);
    if (handler == .invalid_return) return .invalid_return;

    if (block == .valid_terminal and handler == .valid_terminal) return .valid_terminal;
    return .continues;
}

fn isVoidExpression(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .unary_expression => |expression| expression.operator == .void,
        else => false,
    };
}

fn expressionIsValidReturnValue(tree: *const ast.Tree, index: ast.NodeIndex, options: Options) bool {
    return !isVoidExpression(tree, index) or options.allow_void;
}

fn expressionIsForbiddenForEachReturn(tree: *const ast.Tree, index: ast.NodeIndex, options: Options) bool {
    return !isVoidExpression(tree, index) or !options.allow_void;
}

fn propertyName(tree: *const ast.Tree, member: ast.MemberExpression) ?[]const u8 {
    if (member.property == .null) return null;

    return if (member.computed)
        switch (tree.data(member.property)) {
            .string_literal => |literal| tree.string(literal.value),
            .template_literal => |literal| templateStringValue(tree, literal),
            else => null,
        }
    else switch (tree.data(member.property)) {
        .identifier_name => |identifier| tree.string(identifier.name),
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

fn isIdentifierReferenceNamed(tree: *const ast.Tree, index: ast.NodeIndex, name: []const u8) bool {
    if (index == .null) return false;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| std.mem.eql(u8, tree.string(identifier.name), name),
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
