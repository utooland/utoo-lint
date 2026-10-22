const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-loop-func";

const SymbolId = traverser.semantic.SymbolId;
const ReferenceLookup = std.AutoHashMap(ast.NodeIndex, SymbolId);
const DeclSymbolMap = std.AutoHashMap(ast.NodeIndex, SymbolId);

const WriteMap = std.AutoHashMap(SymbolId, ast.Span);

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    try runWithId(allocator, diagnostics, tree, symbol_table, id);
}

pub fn runWithId(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    rule_id: []const u8,
) Allocator.Error!void {
    var candidate_visitor = CandidateVisitor{};
    try traverser.basic.traverse(CandidateVisitor, tree, &candidate_visitor);
    if (!candidate_visitor.found) return;

    var reference_lookup = ReferenceLookup.init(allocator);
    defer reference_lookup.deinit();

    var decl_symbols = DeclSymbolMap.init(allocator);
    defer decl_symbols.deinit();

    var symbol_iter = symbol_table.iterSymbols();
    while (symbol_iter.next()) |entry| {
        for (symbol_table.symbolDecls(entry.id)) |decl| {
            try decl_symbols.put(decl, entry.id);
        }
    }

    var reference_iter = symbol_table.iterReferences();
    while (reference_iter.next()) |entry| {
        if (entry.reference.kind != .value) continue;
        try reference_lookup.put(entry.reference.node, symbol_table.referenceSymbol(entry.id));
    }

    var writes = WriteMap.init(allocator);
    defer writes.deinit();

    var write_visitor = WriteVisitor{
        .reference_lookup = &reference_lookup,
        .decl_symbols = &decl_symbols,
        .writes = &writes,
    };
    try traverser.basic.traverse(WriteVisitor, tree, &write_visitor);

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .symbol_table = symbol_table,
        .reference_lookup = &reference_lookup,
        .writes = &writes,
        .rule_id = rule_id,
    };
    defer visitor.loop_stack.deinit(allocator);
    defer visitor.function_loop_depth_stack.deinit(allocator);

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const CandidateVisitor = struct {
    loop_depth: usize = 0,
    found: bool = false,

    pub fn enter_while_statement(self: *CandidateVisitor, _: ast.WhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_while_statement(self: *CandidateVisitor, _: ast.WhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_do_while_statement(self: *CandidateVisitor, _: ast.DoWhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_do_while_statement(self: *CandidateVisitor, _: ast.DoWhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_for_statement(self: *CandidateVisitor, _: ast.ForStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_for_statement(self: *CandidateVisitor, _: ast.ForStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_for_in_statement(self: *CandidateVisitor, _: ast.ForInStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_for_in_statement(self: *CandidateVisitor, _: ast.ForInStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_for_of_statement(self: *CandidateVisitor, _: ast.ForOfStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        self.loop_depth += 1;
        return .proceed;
    }

    pub fn exit_for_of_statement(self: *CandidateVisitor, _: ast.ForOfStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.loop_depth -= 1;
    }

    pub fn enter_function(self: *CandidateVisitor, _: ast.Function, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        if (self.loop_depth == 0) return .proceed;
        self.found = true;
        return .stop;
    }

    pub fn enter_arrow_function_expression(self: *CandidateVisitor, _: ast.ArrowFunctionExpression, _: ast.NodeIndex, _: *traverser.basic.Ctx) traverser.Action {
        if (self.loop_depth == 0) return .proceed;
        self.found = true;
        return .stop;
    }
};

const WriteVisitor = struct {
    reference_lookup: *const ReferenceLookup,
    decl_symbols: *const DeclSymbolMap,
    writes: *WriteMap,

    pub fn enter_variable_declarator(
        self: *WriteVisitor,
        declarator: ast.VariableDeclarator,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (declarator.init == .null) return .proceed;
        try self.collectBindingWrite(ctx.tree, declarator.id, ctx.tree.span(index));
        return .proceed;
    }

    pub fn enter_assignment_expression(
        self: *WriteVisitor,
        expression: ast.AssignmentExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectTargetWrite(ctx.tree, expression.left, ctx.tree.span(index));
        return .proceed;
    }

    pub fn enter_update_expression(
        self: *WriteVisitor,
        expression: ast.UpdateExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectTargetWrite(ctx.tree, expression.argument, ctx.tree.span(index));
        return .proceed;
    }

    pub fn enter_for_in_statement(
        self: *WriteVisitor,
        statement: ast.ForInStatement,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectLoopLeftWrite(ctx.tree, statement.left, ctx.tree.span(index));
        return .proceed;
    }

    pub fn enter_for_of_statement(
        self: *WriteVisitor,
        statement: ast.ForOfStatement,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectLoopLeftWrite(ctx.tree, statement.left, ctx.tree.span(index));
        return .proceed;
    }

    fn collectBindingWrite(self: *WriteVisitor, tree: *const ast.Tree, index: ast.NodeIndex, span: ast.Span) Allocator.Error!void {
        if (index == .null) return;

        switch (tree.data(index)) {
            .binding_identifier => {
                const symbol_id = self.decl_symbols.get(index) orelse return;
                try self.recordWrite(symbol_id, span);
            },
            .assignment_pattern => |pattern| try self.collectBindingWrite(tree, pattern.left, span),
            .binding_rest_element => |element| try self.collectBindingWrite(tree, element.argument, span),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    try self.collectBindingWrite(tree, element, span);
                }
                try self.collectBindingWrite(tree, pattern.rest, span);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    try self.collectBindingWrite(tree, property.value, span);
                }
                try self.collectBindingWrite(tree, pattern.rest, span);
            },
            else => {},
        }
    }

    fn collectLoopLeftWrite(self: *WriteVisitor, tree: *const ast.Tree, index: ast.NodeIndex, span: ast.Span) Allocator.Error!void {
        if (index == .null) return;

        switch (tree.data(index)) {
            .variable_declaration => |declaration| {
                for (tree.extra(declaration.declarators)) |declarator_index| {
                    const declarator = switch (tree.data(declarator_index)) {
                        .variable_declarator => |declarator| declarator,
                        else => continue,
                    };
                    try self.collectBindingWrite(tree, declarator.id, span);
                }
            },
            else => try self.collectTargetWrite(tree, index, span),
        }
    }

    fn collectTargetWrite(self: *WriteVisitor, tree: *const ast.Tree, index: ast.NodeIndex, span: ast.Span) Allocator.Error!void {
        if (index == .null) return;

        const unwrapped = unwrapTransparent(tree, index);
        switch (tree.data(unwrapped)) {
            .identifier_reference => {
                const symbol_id = self.reference_lookup.get(unwrapped) orelse return;
                if (symbol_id != .none) try self.recordWrite(symbol_id, span);
            },
            .assignment_pattern => |pattern| try self.collectTargetWrite(tree, pattern.left, span),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    try self.collectTargetWrite(tree, element, span);
                }
                try self.collectTargetWrite(tree, pattern.rest, span);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    try self.collectTargetWrite(tree, property.value, span);
                }
                try self.collectTargetWrite(tree, pattern.rest, span);
            },
            else => {},
        }
    }

    fn recordWrite(self: *WriteVisitor, symbol_id: SymbolId, span: ast.Span) Allocator.Error!void {
        const entry = try self.writes.getOrPut(symbol_id);
        if (!entry.found_existing or span.start > entry.value_ptr.start) {
            entry.value_ptr.* = span;
        }
    }
};

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    symbol_table: traverser.semantic.SymbolTable,
    reference_lookup: *const ReferenceLookup,
    writes: *const WriteMap,
    rule_id: []const u8,
    loop_stack: std.ArrayList(ast.Span) = .empty,
    function_loop_depth_stack: std.ArrayList(usize) = .empty,

    pub fn enter_while_statement(self: *Visitor, _: ast.WhileStatement, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        try self.pushLoop(ctx.tree.span(index));
        return .proceed;
    }

    pub fn exit_while_statement(self: *Visitor, _: ast.WhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.popLoop();
    }

    pub fn enter_do_while_statement(self: *Visitor, _: ast.DoWhileStatement, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        try self.pushLoop(ctx.tree.span(index));
        return .proceed;
    }

    pub fn exit_do_while_statement(self: *Visitor, _: ast.DoWhileStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.popLoop();
    }

    pub fn enter_for_statement(self: *Visitor, _: ast.ForStatement, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        try self.pushLoop(ctx.tree.span(index));
        return .proceed;
    }

    pub fn exit_for_statement(self: *Visitor, _: ast.ForStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.popLoop();
    }

    pub fn enter_for_in_statement(self: *Visitor, _: ast.ForInStatement, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        try self.pushLoop(ctx.tree.span(index));
        return .proceed;
    }

    pub fn exit_for_in_statement(self: *Visitor, _: ast.ForInStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.popLoop();
    }

    pub fn enter_for_of_statement(self: *Visitor, _: ast.ForOfStatement, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        try self.pushLoop(ctx.tree.span(index));
        return .proceed;
    }

    pub fn exit_for_of_statement(self: *Visitor, _: ast.ForOfStatement, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.popLoop();
    }

    pub fn enter_function(
        self: *Visitor,
        _: ast.Function,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.checkFunction(ctx.tree, index);
        try self.function_loop_depth_stack.append(self.allocator, self.loop_stack.items.len);
        return .proceed;
    }

    pub fn exit_function(self: *Visitor, _: ast.Function, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        _ = self.function_loop_depth_stack.pop();
    }

    pub fn enter_arrow_function_expression(
        self: *Visitor,
        _: ast.ArrowFunctionExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.checkFunction(ctx.tree, index);
        try self.function_loop_depth_stack.append(self.allocator, self.loop_stack.items.len);
        return .proceed;
    }

    pub fn exit_arrow_function_expression(self: *Visitor, _: ast.ArrowFunctionExpression, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        _ = self.function_loop_depth_stack.pop();
    }

    fn pushLoop(self: *Visitor, span: ast.Span) Allocator.Error!void {
        try self.loop_stack.append(self.allocator, span);
    }

    fn popLoop(self: *Visitor) void {
        _ = self.loop_stack.pop();
    }

    fn checkFunction(self: *Visitor, tree: *const ast.Tree, index: ast.NodeIndex) Allocator.Error!void {
        const base_depth = if (self.function_loop_depth_stack.items.len == 0) 0 else self.function_loop_depth_stack.items[self.function_loop_depth_stack.items.len - 1];
        if (self.loop_stack.items.len <= base_depth) return;

        const loop_span = self.loop_stack.items[self.loop_stack.items.len - 1];
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(self.allocator);

        try self.collectUnsafeReferences(tree, index, loop_span, &names);

        if (names.items.len == 0) return;

        const joined = try joinNames(self.allocator, names.items);
        defer self.allocator.free(joined);

        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .warning,
            self.rule_id,
            tree.span(index),
            "Function declared in a loop contains unsafe references to variable(s) {s}.",
            .{joined},
        );
    }

    fn collectUnsafeReferences(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        loop_span: ast.Span,
        names: *std.ArrayList([]const u8),
    ) Allocator.Error!void {
        if (index == .null) return;

        switch (tree.data(index)) {
            .identifier_reference => |identifier| {
                try self.checkReference(tree, identifier, index, loop_span, names);
            },
            inline else => |node| {
                try self.collectUnsafeReferencesFromPayload(tree, node, loop_span, names);
            },
        }
    }

    fn collectUnsafeReferencesFromPayload(
        self: *Visitor,
        tree: *const ast.Tree,
        payload: anytype,
        loop_span: ast.Span,
        names: *std.ArrayList([]const u8),
    ) Allocator.Error!void {
        const Payload = @TypeOf(payload);
        if (@typeInfo(Payload) != .@"struct") return;

        inline for (@typeInfo(Payload).@"struct".field_names) |field_name| {
            const value = @field(payload, field_name);
            if (@FieldType(Payload, field_name) == ast.NodeIndex) {
                try self.collectUnsafeReferences(tree, value, loop_span, names);
            } else if (@FieldType(Payload, field_name) == ast.IndexRange) {
                for (tree.extra(value)) |child| {
                    try self.collectUnsafeReferences(tree, child, loop_span, names);
                }
            }
        }
    }

    fn checkReference(
        self: *Visitor,
        tree: *const ast.Tree,
        identifier: ast.IdentifierReference,
        index: ast.NodeIndex,
        loop_span: ast.Span,
        names: *std.ArrayList([]const u8),
    ) Allocator.Error!void {
        const symbol_id = self.reference_lookup.get(index) orelse return;
        if (symbol_id == .none) return;
        if (self.isSafe(tree, symbol_id, loop_span)) return;

        const name = tree.string(identifier.name);
        if (!containsName(names.items, name)) {
            try names.append(self.allocator, name);
        }
    }

    fn isSafe(self: *const Visitor, tree: *const ast.Tree, symbol_id: SymbolId, loop_span: ast.Span) bool {
        const symbol = self.symbol_table.getSymbol(symbol_id);
        if (symbol.flags.const_var) return true;

        const decls = self.symbol_table.symbolDecls(symbol_id);
        if (symbol.flags.block_scoped_var and decls.len > 0 and spanInside(tree.span(decls[0]), loop_span)) {
            return true;
        }

        const last_write = self.writes.get(symbol_id) orelse return true;
        return last_write.start < loop_span.start;
    }
};

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

fn joinNames(allocator: Allocator, names: []const []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    for (names, 0..) |name, index| {
        if (index != 0) try out.appendSlice(allocator, ", ");
        try out.append(allocator, '\'');
        try out.appendSlice(allocator, name);
        try out.append(allocator, '\'');
    }

    return try out.toOwnedSlice(allocator);
}

fn spanInside(span: ast.Span, container: ast.Span) bool {
    return span.start >= container.start and span.end <= container.end;
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
