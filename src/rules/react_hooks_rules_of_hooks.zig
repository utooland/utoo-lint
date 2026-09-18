const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "react-hooks/rules-of-hooks";

const FunctionContext = struct {
    name: ?[]const u8,
    directly_allowed: bool,
    somewhere_inside_component_or_hook: bool,
    class_method: bool,
    branch_base: usize,
    loop_base: usize,
    has_conditional_return: bool = false,
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
) Allocator.Error!void {
    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
    };
    defer visitor.function_stack.deinit(allocator);

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    function_stack: std.ArrayList(FunctionContext) = .empty,
    branch_depth: usize = 0,
    loop_depth: usize = 0,

    pub fn enter_function(
        self: *Visitor,
        function: ast.Function,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const parent = ctx.path.ancestor(1) orelse .null;
        try self.pushFunction(ctx.tree, index, parent, functionName(ctx.tree, index, parent, function.id));
        return .proceed;
    }

    pub fn exit_function(self: *Visitor, _: ast.Function, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        _ = self.function_stack.pop();
    }

    pub fn enter_arrow_function_expression(
        self: *Visitor,
        _: ast.ArrowFunctionExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const parent = ctx.path.ancestor(1) orelse .null;
        try self.pushFunction(ctx.tree, index, parent, functionName(ctx.tree, index, parent, .null));
        return .proceed;
    }

    pub fn exit_arrow_function_expression(
        self: *Visitor,
        _: ast.ArrowFunctionExpression,
        _: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) void {
        _ = self.function_stack.pop();
    }

    pub fn exit_return_statement(self: *Visitor, _: ast.ReturnStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        if (self.function_stack.items.len == 0) return;
        self.function_stack.items[self.function_stack.items.len - 1].has_conditional_return = true;
    }

    pub fn enter_if_statement(self: *Visitor, _: ast.IfStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.branch_depth += 1;
        return .proceed;
    }

    pub fn exit_if_statement(self: *Visitor, _: ast.IfStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.branch_depth -= 1;
    }

    pub fn enter_conditional_expression(self: *Visitor, _: ast.ConditionalExpression, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.branch_depth += 1;
        return .proceed;
    }

    pub fn exit_conditional_expression(self: *Visitor, _: ast.ConditionalExpression, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.branch_depth -= 1;
    }

    pub fn enter_switch_statement(self: *Visitor, _: ast.SwitchStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.branch_depth += 1;
        return .proceed;
    }

    pub fn exit_switch_statement(self: *Visitor, _: ast.SwitchStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.branch_depth -= 1;
    }

    pub fn enter_while_statement(self: *Visitor, _: ast.WhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_while_statement(self: *Visitor, _: ast.WhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_do_while_statement(self: *Visitor, _: ast.DoWhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_do_while_statement(self: *Visitor, _: ast.DoWhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_for_statement(self: *Visitor, _: ast.ForStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_for_statement(self: *Visitor, _: ast.ForStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_for_in_statement(self: *Visitor, _: ast.ForInStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_for_in_statement(self: *Visitor, _: ast.ForInStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_for_of_statement(self: *Visitor, _: ast.ForOfStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_for_of_statement(self: *Visitor, _: ast.ForOfStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (isHook(ctx.tree, call.callee) and !isUnreachableHook(ctx.tree, call.callee, ctx)) {
            try self.checkHook(ctx.tree, call.callee);
        }
        return .proceed;
    }

    fn pushFunction(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        parent: ast.NodeIndex,
        name: ?[]const u8,
    ) Allocator.Error!void {
        const parent_inside = if (self.currentFunction()) |current|
            current.somewhere_inside_component_or_hook or current.directly_allowed
        else
            false;
        const directly_allowed = if (name) |function_name|
            isComponentName(function_name) or isHookName(function_name)
        else
            isForwardRefOrMemoCallback(tree, index, parent);

        try self.function_stack.append(self.allocator, .{
            .name = name,
            .directly_allowed = directly_allowed,
            .somewhere_inside_component_or_hook = parent_inside or directly_allowed,
            .class_method = isClassMethodValue(tree, index, parent),
            .branch_base = self.branch_depth,
            .loop_base = self.loop_depth,
        });
    }

    fn currentFunction(self: *Visitor) ?FunctionContext {
        if (self.function_stack.items.len == 0) return null;
        return self.function_stack.items[self.function_stack.items.len - 1];
    }

    fn checkHook(
        self: *Visitor,
        tree: *const ast.Tree,
        callee: ast.NodeIndex,
    ) Allocator.Error!void {
        const hook_source = nodeSource(tree, callee);
        const context = self.currentFunction() orelse {
            try self.report(
                tree,
                callee,
                "React Hook \"{s}\" cannot be called at the top level. React Hooks must be called in a React function component or a custom React Hook function.",
                .{hook_source},
            );
            return;
        };

        const loop_delta = self.loop_depth - context.loop_base;
        if (context.directly_allowed and loop_delta > 0) {
            try self.report(
                tree,
                callee,
                "React Hook \"{s}\" may be executed more than once. Possibly because it is called in a loop. React Hooks must be called in the exact same order in every component render.",
                .{hook_source},
            );
            return;
        }

        const branch_delta = self.branch_depth - context.branch_base;
        if (context.directly_allowed and (branch_delta > 0 or context.has_conditional_return)) {
            try self.report(
                tree,
                callee,
                "React Hook \"{s}\" is called conditionally. React Hooks must be called in the exact same order in every component render.",
                .{hook_source},
            );
            return;
        }

        if (context.directly_allowed) return;

        if (context.class_method) {
            try self.report(
                tree,
                callee,
                "React Hook \"{s}\" cannot be called in a class component. React Hooks must be called in a React function component or a custom React Hook function.",
                .{hook_source},
            );
            return;
        }

        if (context.name) |function_name| {
            try self.report(
                tree,
                callee,
                "React Hook \"{s}\" is called in function \"{s}\" that is neither a React function component nor a custom React Hook function. React component names must start with an uppercase letter. React Hook names must start with the word \"use\".",
                .{ hook_source, function_name },
            );
            return;
        }

        if (context.somewhere_inside_component_or_hook) {
            try self.report(
                tree,
                callee,
                "React Hook \"{s}\" cannot be called inside a callback. React Hooks must be called in a React function component or a custom React Hook function.",
                .{hook_source},
            );
        }
    }

    fn report(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        comptime fmt: []const u8,
        args: anytype,
    ) Allocator.Error!void {
        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .@"error",
            id,
            tree.span(index),
            fmt,
            args,
        );
    }
};

fn isUnreachableHook(tree: *const ast.Tree, callee: ast.NodeIndex, ctx: *traverser.basic.Ctx) bool {
    const offset = tree.span(callee).start;
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        const statements = switch (tree.data(ancestor)) {
            .function, .arrow_function_expression => break,
            .block_statement => |block| block.body,
            .function_body => |body| body.body,
            .switch_case => |case| case.consequent,
            else => continue,
        };
        for (tree.extra(statements)) |statement| {
            if (tree.span(statement).end > offset) break;
            if (definitelyTerminates(tree, statement)) return true;
        }
    }
    return false;
}

fn definitelyTerminates(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;
    return switch (tree.data(index)) {
        .return_statement, .throw_statement => true,
        .block_statement => |block| terminatingStatements(tree, block.body),
        .function_body => |body| terminatingStatements(tree, body.body),
        .if_statement => |statement| definitelyTerminates(tree, statement.consequent) and definitelyTerminates(tree, statement.alternate),
        .catch_clause => |clause| definitelyTerminates(tree, clause.body),
        .try_statement => |statement| definitelyTerminates(tree, statement.finalizer) or
            (definitelyTerminates(tree, statement.block) and (statement.handler == .null or definitelyTerminates(tree, statement.handler))),
        else => false,
    };
}

fn terminatingStatements(tree: *const ast.Tree, statements: ast.IndexRange) bool {
    for (tree.extra(statements)) |statement| {
        if (definitelyTerminates(tree, statement)) return true;
    }
    return false;
}

fn isHook(tree: *const ast.Tree, callee: ast.NodeIndex) bool {
    if (identifierReferenceName(tree, callee)) |name| return isHookName(name);

    const member = switch (tree.data(unwrapTransparent(tree, callee))) {
        .member_expression => |member| member,
        else => return false,
    };
    if (member.computed) return false;
    if (!isIdentifierReferenceNamed(tree, unwrapTransparent(tree, member.object), "React")) return false;
    const member_name = propertyName(tree, member) orelse return false;
    return isHookName(member_name);
}

fn functionName(tree: *const ast.Tree, index: ast.NodeIndex, parent: ast.NodeIndex, id_node: ast.NodeIndex) ?[]const u8 {
    if (bindingName(tree, id_node)) |name| return name;

    return switch (tree.data(parent)) {
        .variable_declarator => |declarator| if (declarator.init == index) bindingName(tree, declarator.id) else null,
        .assignment_expression => |assignment| if (assignment.right == index) expressionName(tree, assignment.left) else null,
        .object_property => |property| if (property.value == index and !property.computed) propertyKeyName(tree, property.key) else null,
        else => null,
    };
}

fn isForwardRefOrMemoCallback(tree: *const ast.Tree, index: ast.NodeIndex, parent: ast.NodeIndex) bool {
    const call = switch (tree.data(parent)) {
        .call_expression => |call| call,
        else => return false,
    };
    if (call.arguments.len == 0 or tree.extra(call.arguments)[0] != index) return false;
    return isNamedCallee(tree, call.callee, "forwardRef") or
        isNamedCallee(tree, call.callee, "memo") or
        isReactMemberCallee(tree, call.callee, "forwardRef") or
        isReactMemberCallee(tree, call.callee, "memo");
}

fn isNamedCallee(tree: *const ast.Tree, callee: ast.NodeIndex, name: []const u8) bool {
    return isIdentifierReferenceNamed(tree, unwrapTransparent(tree, callee), name);
}

fn isReactMemberCallee(tree: *const ast.Tree, callee: ast.NodeIndex, name: []const u8) bool {
    const member = switch (tree.data(unwrapTransparent(tree, callee))) {
        .member_expression => |member| member,
        else => return false,
    };
    if (member.computed) return false;
    if (!isIdentifierReferenceNamed(tree, unwrapTransparent(tree, member.object), "React")) return false;
    const member_name = propertyName(tree, member) orelse return false;
    return std.mem.eql(u8, member_name, name);
}

fn isClassMethodValue(tree: *const ast.Tree, index: ast.NodeIndex, parent: ast.NodeIndex) bool {
    return switch (tree.data(parent)) {
        .method_definition => |method| method.value == index,
        else => false,
    };
}

fn isComponentName(name: []const u8) bool {
    return name.len > 0 and std.ascii.isUpper(name[0]);
}

fn isHookName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "use")) return false;
    return name.len == 3 or (name.len > 3 and !std.ascii.isLower(name[3]));
}

fn bindingName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(index)) {
        .binding_identifier => |identifier| tree.string(identifier.name),
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn expressionName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        .binding_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn propertyKeyName(tree: *const ast.Tree, key: ast.NodeIndex) ?[]const u8 {
    if (key == .null) return null;
    return switch (tree.data(key)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn isIdentifierReferenceNamed(tree: *const ast.Tree, index: ast.NodeIndex, name: []const u8) bool {
    const actual = identifierReferenceName(tree, index) orelse return false;
    return std.mem.eql(u8, actual, name);
}

fn propertyName(tree: *const ast.Tree, member: ast.MemberExpression) ?[]const u8 {
    if (member.property == .null) return null;
    return if (member.computed)
        switch (tree.data(member.property)) {
            .string_literal => |literal| tree.string(literal.value),
            else => null,
        }
    else switch (tree.data(member.property)) {
        .identifier_name => |identifier| tree.string(identifier.name),
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

fn nodeSource(tree: *const ast.Tree, index: ast.NodeIndex) []const u8 {
    const span = tree.span(index);
    if (span.start >= span.end or span.end > tree.source.len) return "useHook";
    return std.mem.trim(u8, tree.source[span.start..span.end], " \t\r\n");
}
