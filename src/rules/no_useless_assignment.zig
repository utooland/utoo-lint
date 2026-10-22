const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const semantic_compat = @import("../semantic_compat.zig");

const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;
const SymbolId = semantic_compat.traverser.semantic.SymbolId;
const ReferenceId = semantic_compat.traverser.semantic.ReferenceId;
const SymbolTable = semantic_compat.SymbolTable;

pub const id = "no-useless-assignment";

const NodeId = enum(u32) { none = std.math.maxInt(u32), _ };

const Event = struct {
    kind: enum { read, write },
    node: ast.NodeIndex,
    optional: bool = false,
    reportable: bool = true,
};

const GraphNode = struct {
    kind: enum { noop, read, write },
    next: NodeId = .none,
    alternate: NodeId = .none,
    report_node: ast.NodeIndex = .null,
    reportable: bool = false,
};

const Graph = struct {
    allocator: Allocator,
    nodes: std.ArrayList(GraphNode) = .empty,
    candidates: std.ArrayList(NodeId) = .empty,

    fn deinit(self: *Graph) void {
        self.nodes.deinit(self.allocator);
        self.candidates.deinit(self.allocator);
    }

    fn add(self: *Graph, node: GraphNode) Allocator.Error!NodeId {
        const index: NodeId = @fromBackingInt(@intCast(self.nodes.items.len));
        try self.nodes.append(self.allocator, node);
        if (node.kind == .write) try self.candidates.append(self.allocator, index);
        return index;
    }

    fn join(self: *Graph, first: NodeId, second: NodeId) Allocator.Error!NodeId {
        if (first == second) return first;
        return self.add(.{ .kind = .noop, .next = first, .alternate = second });
    }

    fn prependEvents(self: *Graph, events: []const Event, continuation: NodeId) Allocator.Error!NodeId {
        var entry = continuation;
        var index = events.len;
        while (index > 0) {
            index -= 1;
            const event = events[index];
            const event_node = try self.add(.{
                .kind = switch (event.kind) {
                    .read => .read,
                    .write => .write,
                },
                .next = entry,
                .report_node = event.node,
                .reportable = event.kind == .write and event.reportable,
            });
            entry = if (event.optional) try self.join(event_node, entry) else event_node;
        }
        return entry;
    }
};

const Controls = struct {
    break_target: NodeId = .none,
    continue_target: NodeId = .none,
};

const Builder = struct {
    allocator: Allocator,
    tree: *const ast.Tree,
    symbol_table: SymbolTable,
    symbol: SymbolId,
    code_path_root: ast.NodeIndex,
    delayed_pattern_nodes: []const bool,
    graph: Graph,

    fn init(
        allocator: Allocator,
        tree: *const ast.Tree,
        symbol_table: SymbolTable,
        symbol: SymbolId,
        code_path_root: ast.NodeIndex,
        delayed_pattern_nodes: []const bool,
    ) Builder {
        return .{
            .allocator = allocator,
            .tree = tree,
            .symbol_table = symbol_table,
            .symbol = symbol,
            .code_path_root = code_path_root,
            .delayed_pattern_nodes = delayed_pattern_nodes,
            .graph = .{ .allocator = allocator },
        };
    }

    fn deinit(self: *Builder) void {
        self.graph.deinit();
    }

    fn build(self: *Builder) Allocator.Error!NodeId {
        return switch (self.tree.data(self.code_path_root)) {
            .program => |program| self.buildStatements(self.tree.extra(program.body), .none, .{}, false),
            .function => |function| self.buildFunctionBody(function.body),
            .arrow_function_expression => |arrow| if (arrow.expression)
                self.buildExpression(arrow.body, .none, false)
            else
                self.buildFunctionBody(arrow.body),
            .static_block => |block| self.buildStatements(self.tree.extra(block.body), .none, .{}, false),
            else => .none,
        };
    }

    fn buildFunctionBody(self: *Builder, index: ast.NodeIndex) Allocator.Error!NodeId {
        if (index == .null) return .none;
        return switch (self.tree.data(index)) {
            .function_body => |body| self.buildStatements(self.tree.extra(body.body), .none, .{}, false),
            else => self.buildStatement(index, .none, .{}, false),
        };
    }

    fn buildStatements(
        self: *Builder,
        statements: []const ast.NodeIndex,
        continuation: NodeId,
        controls: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        var entry = continuation;
        var index = statements.len;
        while (index > 0) {
            index -= 1;
            entry = try self.buildStatement(statements[index], entry, controls, suppress_writes);
        }
        return entry;
    }

    fn buildStatement(
        self: *Builder,
        index: ast.NodeIndex,
        continuation: NodeId,
        controls: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        if (index == .null) return continuation;
        return switch (self.tree.data(index)) {
            .block_statement => |block| self.buildStatements(self.tree.extra(block.body), continuation, controls, suppress_writes),
            .function_body => |body| self.buildStatements(self.tree.extra(body.body), continuation, controls, suppress_writes),
            .expression_statement => |statement| self.buildExpression(statement.expression, continuation, suppress_writes),
            .variable_declaration => self.buildLinear(index, continuation, suppress_writes),
            .if_statement => |statement| self.buildIf(statement, continuation, controls, suppress_writes),
            .while_statement => |statement| self.buildWhile(statement, continuation, controls, suppress_writes),
            .do_while_statement => |statement| self.buildDoWhile(statement, continuation, controls, suppress_writes),
            .for_statement => |statement| self.buildFor(statement, continuation, controls, suppress_writes),
            .for_in_statement => |statement| self.buildForIn(statement.left, statement.right, statement.body, continuation, controls, suppress_writes),
            .for_of_statement => |statement| self.buildForIn(statement.left, statement.right, statement.body, continuation, controls, suppress_writes),
            .return_statement => |statement| self.buildExpression(statement.argument, .none, suppress_writes),
            .throw_statement => |statement| self.buildExpression(statement.argument, .none, suppress_writes),
            .break_statement => if (controls.break_target != .none) controls.break_target else .none,
            .continue_statement => if (controls.continue_target != .none) controls.continue_target else .none,
            .labeled_statement => |statement| self.buildStatement(statement.body, continuation, .{
                .break_target = continuation,
                .continue_target = controls.continue_target,
            }, suppress_writes),
            .try_statement => |statement| self.buildTry(statement, continuation, controls, suppress_writes),
            .catch_clause => |clause| self.buildStatement(clause.body, continuation, controls, suppress_writes),
            .switch_statement => |statement| self.buildSwitch(statement, continuation, controls, suppress_writes),
            .with_statement => |statement| self.buildExpression(
                statement.object,
                try self.buildStatement(statement.body, continuation, controls, suppress_writes),
                suppress_writes,
            ),
            .function, .arrow_function_expression, .class => continuation,
            else => self.buildLinear(index, continuation, suppress_writes),
        };
    }

    fn buildIf(
        self: *Builder,
        statement: ast.IfStatement,
        continuation: NodeId,
        controls: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        const consequent = try self.buildStatement(statement.consequent, continuation, controls, suppress_writes);
        const alternate = if (statement.alternate == .null)
            continuation
        else
            try self.buildStatement(statement.alternate, continuation, controls, suppress_writes);
        const branch = try self.graph.join(consequent, alternate);
        return self.buildExpression(statement.@"test", branch, suppress_writes);
    }

    fn buildWhile(
        self: *Builder,
        statement: ast.WhileStatement,
        continuation: NodeId,
        _: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        const branch = try self.graph.add(.{ .kind = .noop, .alternate = continuation });
        const test_entry = try self.buildExpression(statement.@"test", branch, suppress_writes);
        const body = try self.buildStatement(statement.body, test_entry, .{
            .break_target = continuation,
            .continue_target = test_entry,
        }, suppress_writes);
        self.graph.nodes.items[@backingInt(branch)].next = body;
        return test_entry;
    }

    fn buildDoWhile(
        self: *Builder,
        statement: ast.DoWhileStatement,
        continuation: NodeId,
        _: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        const branch = try self.graph.add(.{ .kind = .noop, .alternate = continuation });
        const test_entry = try self.buildExpression(statement.@"test", branch, suppress_writes);
        const body = try self.buildStatement(statement.body, test_entry, .{
            .break_target = continuation,
            .continue_target = test_entry,
        }, suppress_writes);
        self.graph.nodes.items[@backingInt(branch)].next = body;
        return body;
    }

    fn buildFor(
        self: *Builder,
        statement: ast.ForStatement,
        continuation: NodeId,
        _: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        const branch = try self.graph.add(.{ .kind = .noop, .alternate = if (statement.@"test" == .null) .none else continuation });
        const test_entry = if (statement.@"test" == .null)
            branch
        else
            try self.buildExpression(statement.@"test", branch, suppress_writes);
        const update_entry = try self.buildExpression(statement.update, test_entry, suppress_writes);
        const body = try self.buildStatement(statement.body, update_entry, .{
            .break_target = continuation,
            .continue_target = update_entry,
        }, suppress_writes);
        self.graph.nodes.items[@backingInt(branch)].next = body;
        return self.buildStatement(statement.init, test_entry, .{}, suppress_writes);
    }

    fn buildForIn(
        self: *Builder,
        left: ast.NodeIndex,
        right: ast.NodeIndex,
        body_index: ast.NodeIndex,
        continuation: NodeId,
        _: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        const branch = try self.graph.add(.{ .kind = .noop, .alternate = continuation });
        const body = try self.buildStatement(body_index, branch, .{
            .break_target = continuation,
            .continue_target = branch,
        }, suppress_writes);
        const iteration = try self.buildLinear(left, body, suppress_writes);
        self.graph.nodes.items[@backingInt(branch)].next = iteration;
        return self.buildExpression(right, branch, suppress_writes);
    }

    fn buildTry(
        self: *Builder,
        statement: ast.TryStatement,
        continuation: NodeId,
        controls: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        const after_try = if (statement.finalizer == .null)
            continuation
        else
            try self.buildStatement(statement.finalizer, continuation, controls, suppress_writes);
        const handler = if (statement.handler == .null)
            after_try
        else
            try self.buildStatement(statement.handler, after_try, controls, suppress_writes);
        const block = try self.buildStatement(statement.block, after_try, controls, true);
        return self.graph.join(block, handler);
    }

    fn buildSwitch(
        self: *Builder,
        statement: ast.SwitchStatement,
        continuation: NodeId,
        controls: Controls,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        const cases = self.tree.extra(statement.cases);
        var fallthrough = continuation;
        var choices = continuation;
        var index = cases.len;
        while (index > 0) {
            index -= 1;
            const case = switch (self.tree.data(cases[index])) {
                .switch_case => |value| value,
                else => continue,
            };
            const case_entry = try self.buildStatements(self.tree.extra(case.consequent), fallthrough, .{
                .break_target = continuation,
                .continue_target = controls.continue_target,
            }, suppress_writes);
            fallthrough = case_entry;
            choices = try self.graph.join(case_entry, choices);
        }
        return self.buildExpression(statement.discriminant, choices, suppress_writes);
    }

    fn buildExpression(
        self: *Builder,
        index: ast.NodeIndex,
        continuation: NodeId,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        if (index == .null) return continuation;
        return switch (self.tree.data(index)) {
            .logical_expression => |expression| blk: {
                const right = try self.buildExpression(expression.right, continuation, suppress_writes);
                const branch = try self.graph.join(right, continuation);
                break :blk self.buildExpression(expression.left, branch, suppress_writes);
            },
            .conditional_expression => |expression| blk: {
                const consequent = try self.buildExpression(expression.consequent, continuation, suppress_writes);
                const alternate = try self.buildExpression(expression.alternate, continuation, suppress_writes);
                const branch = try self.graph.join(consequent, alternate);
                break :blk self.buildExpression(expression.@"test", branch, suppress_writes);
            },
            .sequence_expression => |expression| blk: {
                var entry = continuation;
                const expressions = self.tree.extra(expression.expressions);
                var expression_index = expressions.len;
                while (expression_index > 0) {
                    expression_index -= 1;
                    entry = try self.buildExpression(expressions[expression_index], entry, suppress_writes);
                }
                break :blk entry;
            },
            else => self.buildLinear(index, continuation, suppress_writes),
        };
    }

    fn buildLinear(
        self: *Builder,
        index: ast.NodeIndex,
        continuation: NodeId,
        suppress_writes: bool,
    ) Allocator.Error!NodeId {
        if (index == .null) return continuation;
        var events: std.ArrayList(Event) = .empty;
        defer events.deinit(self.allocator);
        try events.ensureTotalCapacity(
            self.allocator,
            self.symbol_table.model.uses(self.symbol).len * 3 +
                self.symbol_table.symbolDecls(self.symbol).len * 2 + 8,
        );

        var collector = EventCollector{
            .tree = self.tree,
            .symbol_table = self.symbol_table,
            .symbol = self.symbol,
            .code_path_root = self.code_path_root,
            .delayed_pattern_nodes = self.delayed_pattern_nodes,
            .suppress_writes = suppress_writes,
            .events = &events,
        };
        var subtree = self.tree.*;
        subtree.root = index;
        try traverser.basic.traverse(EventCollector, &subtree, &collector);
        return self.graph.prependEvents(events.items, continuation);
    }
};

const EventCollector = struct {
    tree: *const ast.Tree,
    symbol_table: SymbolTable,
    symbol: SymbolId,
    code_path_root: ast.NodeIndex,
    delayed_pattern_nodes: []const bool,
    suppress_writes: bool,
    events: *std.ArrayList(Event),

    pub fn enter_node(
        self: *EventCollector,
        _: ast.NodeData,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        if (self.isDelayedPatternNode(index)) return .proceed;
        const reference_id = self.symbol_table.model.referenceOf(index) orelse return .proceed;
        const reference = self.symbol_table.model.reference(reference_id);
        if (reference.symbol != self.symbol or reference.flags.write) return .proceed;
        self.events.appendAssumeCapacity(.{ .kind = .read, .node = index });
        return .proceed;
    }

    pub fn enter_function(
        self: *EventCollector,
        _: ast.Function,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        return if (index == self.code_path_root) .proceed else .skip;
    }

    pub fn enter_arrow_function_expression(
        self: *EventCollector,
        _: ast.ArrowFunctionExpression,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        return if (index == self.code_path_root) .proceed else .skip;
    }

    pub fn enter_static_block(
        self: *EventCollector,
        _: ast.StaticBlock,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        return if (index == self.code_path_root) .proceed else .skip;
    }

    pub fn enter_assignment_expression(
        self: *EventCollector,
        expression: ast.AssignmentExpression,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        if (self.isDelayedPatternNode(index)) return .proceed;
        if (expression.operator != .assign and self.patternHasWrite(expression.left)) {
            self.events.appendAssumeCapacity(.{ .kind = .read, .node = firstWriteNode(self.tree, self.symbol_table, self.symbol, expression.left) orelse expression.left });
        }
        return .proceed;
    }

    pub fn exit_assignment_expression(
        self: *EventCollector,
        expression: ast.AssignmentExpression,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) void {
        if (self.isDelayedPatternNode(index)) return;
        if (isPatternTarget(self.tree.data(expression.left)) and self.patternHasReference(expression.left)) {
            self.appendPatternEvents(expression.left);
        }
    }

    pub fn enter_update_expression(
        self: *EventCollector,
        expression: ast.UpdateExpression,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        if (self.isDelayedPatternNode(index)) return .proceed;
        if (self.patternHasWrite(expression.argument)) {
            self.events.appendAssumeCapacity(.{ .kind = .read, .node = firstWriteNode(self.tree, self.symbol_table, self.symbol, expression.argument) orelse expression.argument });
        }
        return .proceed;
    }

    pub fn exit_update_expression(
        self: *EventCollector,
        expression: ast.UpdateExpression,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) void {
        if (self.isDelayedPatternNode(index)) return;
        if (firstWriteNode(self.tree, self.symbol_table, self.symbol, expression.argument)) |node| {
            self.appendWrite(node, false);
        }
    }

    pub fn exit_variable_declarator(
        self: *EventCollector,
        declarator: ast.VariableDeclarator,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) void {
        if (declarator.init == .null or self.isDelayedPatternNode(index)) return;
        if (self.patternHasDeclaration(declarator.id) or self.patternHasReference(declarator.id)) {
            self.appendPatternEvents(declarator.id);
        }
    }

    fn appendPatternEvents(self: *EventCollector, pattern: ast.NodeIndex) void {
        const declarations = self.symbol_table.symbolDecls(self.symbol);
        const uses = self.symbol_table.model.uses(self.symbol);
        var declaration_index: usize = 0;
        var use_index: usize = 0;

        while (true) {
            while (declaration_index < declarations.len and !containsNode(self.tree, pattern, declarations[declaration_index])) declaration_index += 1;
            while (use_index < uses.len and !containsNode(self.tree, pattern, self.symbol_table.model.reference(uses[use_index]).node)) use_index += 1;
            if (declaration_index >= declarations.len and use_index >= uses.len) break;

            const take_declaration = if (declaration_index >= declarations.len)
                false
            else if (use_index >= uses.len)
                true
            else
                self.tree.span(declarations[declaration_index]).start <= self.tree.span(self.symbol_table.model.reference(uses[use_index]).node).start;

            if (take_declaration) {
                const node = declarations[declaration_index];
                declaration_index += 1;
                self.appendWrite(node, isInDefaultExpression(self.tree, self.symbol_table, pattern, node));
                continue;
            }

            const reference_id = uses[use_index];
            use_index += 1;
            const reference = self.symbol_table.model.reference(reference_id);
            const optional = isInDefaultExpression(self.tree, self.symbol_table, pattern, reference.node);
            if (reference.flags.write) {
                if (writeReadsOldValue(self.tree, self.symbol_table, reference.node)) {
                    self.events.appendAssumeCapacity(.{ .kind = .read, .node = reference.node, .optional = optional });
                }
                self.appendWrite(reference.node, optional);
            } else {
                self.events.appendAssumeCapacity(.{ .kind = .read, .node = reference.node, .optional = optional });
            }
        }
    }

    fn appendWrite(self: *EventCollector, node: ast.NodeIndex, optional: bool) void {
        self.events.appendAssumeCapacity(.{
            .kind = .write,
            .node = node,
            .optional = optional,
            .reportable = !self.suppress_writes,
        });
    }

    fn patternHasWrite(self: *EventCollector, pattern: ast.NodeIndex) bool {
        return firstWriteNode(self.tree, self.symbol_table, self.symbol, pattern) != null;
    }

    fn patternHasReference(self: *EventCollector, pattern: ast.NodeIndex) bool {
        for (self.symbol_table.model.uses(self.symbol)) |reference_id| {
            if (containsNode(self.tree, pattern, self.symbol_table.model.reference(reference_id).node)) return true;
        }
        return false;
    }

    fn patternHasDeclaration(self: *EventCollector, pattern: ast.NodeIndex) bool {
        for (self.symbol_table.symbolDecls(self.symbol)) |declaration| {
            if (containsNode(self.tree, pattern, declaration)) return true;
        }
        return false;
    }

    fn isDelayedPatternNode(self: *EventCollector, node: ast.NodeIndex) bool {
        return node != .null and self.delayed_pattern_nodes[@backingInt(node)];
    }
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: SymbolTable,
) Allocator.Error!void {
    var report_nodes: std.ArrayList(ast.NodeIndex) = .empty;
    defer report_nodes.deinit(allocator);

    var exported_directive_names: std.ArrayList([]const u8) = .empty;
    defer exported_directive_names.deinit(allocator);
    try collectExportedDirectiveNames(allocator, tree.source, &exported_directive_names);

    const delayed_pattern_nodes = try collectDelayedPatternNodes(allocator, tree);
    defer allocator.free(delayed_pattern_nodes);

    var symbols = symbol_table.iterSymbols();
    while (symbols.next()) |entry| {
        const symbol = entry.symbol;
        if (!symbol.flags.intersects(parser.semantic.Symbol.value_space) or symbol.flags.exported) continue;
        const declarations = symbol_table.symbolDecls(entry.id);
        if (declarations.len == 0) continue;
        if (isExportedByDirective(exported_directive_names.items, tree.string(symbol.name)) or
            isExportedBySpecifier(tree, symbol_table, entry.id)) continue;

        const root = codePathRoot(tree, symbol_table, declarations[0]);
        var has_local_read = false;
        var has_external_read = false;
        for (symbol_table.model.uses(entry.id)) |reference_id| {
            const reference = symbol_table.model.reference(reference_id);
            if (!isReadReference(tree, symbol_table, reference_id)) continue;
            if (codePathRoot(tree, symbol_table, reference.node) == root) {
                has_local_read = true;
            } else {
                has_external_read = true;
            }
        }
        if (!has_local_read or has_external_read) continue;

        var builder = Builder.init(allocator, tree, symbol_table, entry.id, root, delayed_pattern_nodes);
        defer builder.deinit();
        const graph_entry = try builder.build();
        if (graph_entry == .none or builder.graph.candidates.items.len == 0) continue;

        const reachable = try reachableNodes(allocator, builder.graph.nodes.items, graph_entry);
        defer allocator.free(reachable);

        for (builder.graph.candidates.items) |candidate| {
            const node = builder.graph.nodes.items[@backingInt(candidate)];
            if (!node.reportable or !reachable[@backingInt(candidate)]) continue;
            if (try assignmentIsUsed(allocator, builder.graph.nodes.items, candidate)) continue;
            try report_nodes.append(allocator, node.report_node);
        }
    }

    std.mem.sort(ast.NodeIndex, report_nodes.items, tree, nodeLessThan);
    for (report_nodes.items) |report_node| {
        try core.addDiagnostic(
            allocator,
            diagnostics,
            .warning,
            id,
            "This assigned value is not used in subsequent statements.",
            tree.span(report_node),
        );
    }
}

fn nodeLessThan(tree: *const ast.Tree, left: ast.NodeIndex, right: ast.NodeIndex) bool {
    return tree.span(left).start < tree.span(right).start;
}

fn reachableNodes(allocator: Allocator, nodes: []const GraphNode, entry: NodeId) Allocator.Error![]bool {
    const reachable = try allocator.alloc(bool, nodes.len);
    @memset(reachable, false);
    var queue: std.ArrayList(NodeId) = .empty;
    defer queue.deinit(allocator);
    try queue.append(allocator, entry);
    while (queue.pop()) |node_id| {
        if (node_id == .none) continue;
        const index = @backingInt(node_id);
        if (reachable[index]) continue;
        reachable[index] = true;
        const node = nodes[index];
        if (node.next != .none) try queue.append(allocator, node.next);
        if (node.alternate != .none) try queue.append(allocator, node.alternate);
    }
    return reachable;
}

fn assignmentIsUsed(allocator: Allocator, nodes: []const GraphNode, assignment: NodeId) Allocator.Error!bool {
    const visited = try allocator.alloc(bool, nodes.len);
    defer allocator.free(visited);
    @memset(visited, false);
    visited[@backingInt(assignment)] = true;

    var queue: std.ArrayList(NodeId) = .empty;
    defer queue.deinit(allocator);
    const start = nodes[@backingInt(assignment)];
    if (start.next != .none) try queue.append(allocator, start.next);
    if (start.alternate != .none) try queue.append(allocator, start.alternate);

    while (queue.pop()) |node_id| {
        if (node_id == .none) continue;
        const index = @backingInt(node_id);
        if (visited[index]) continue;
        visited[index] = true;
        const node = nodes[index];
        if (node.kind == .read) return true;
        if (node.kind == .write) continue;
        if (node.next != .none) try queue.append(allocator, node.next);
        if (node.alternate != .none) try queue.append(allocator, node.alternate);
    }
    return false;
}

fn firstWriteNode(
    tree: *const ast.Tree,
    symbol_table: SymbolTable,
    symbol: SymbolId,
    container: ast.NodeIndex,
) ?ast.NodeIndex {
    for (symbol_table.model.uses(symbol)) |reference_id| {
        const reference = symbol_table.model.reference(reference_id);
        if (reference.flags.write and containsNode(tree, container, reference.node)) return reference.node;
    }
    return null;
}

fn isReadReference(tree: *const ast.Tree, symbol_table: SymbolTable, reference_id: ReferenceId) bool {
    const reference = symbol_table.model.reference(reference_id);
    return !reference.flags.write or writeReadsOldValue(tree, symbol_table, reference.node);
}

fn writeReadsOldValue(tree: *const ast.Tree, symbol_table: SymbolTable, node: ast.NodeIndex) bool {
    var current = node;
    while (symbol_table.parentOf(current)) |parent| {
        switch (tree.data(parent)) {
            .update_expression => return true,
            .assignment_expression => |expression| return expression.operator != .assign,
            .parenthesized_expression, .ts_as_expression, .ts_satisfies_expression, .ts_non_null_expression, .ts_type_assertion => {},
            else => return false,
        }
        current = parent;
    }
    return false;
}

fn isInDefaultExpression(
    tree: *const ast.Tree,
    symbol_table: SymbolTable,
    pattern: ast.NodeIndex,
    node: ast.NodeIndex,
) bool {
    var current = node;
    while (current != pattern) {
        const parent = symbol_table.parentOf(current) orelse return false;
        switch (tree.data(parent)) {
            .assignment_pattern => |assignment| if (containsNode(tree, assignment.right, node)) return true,
            else => {},
        }
        current = parent;
    }
    return false;
}

fn codePathRoot(tree: *const ast.Tree, symbol_table: SymbolTable, node: ast.NodeIndex) ast.NodeIndex {
    var current = node;
    while (true) {
        switch (tree.data(current)) {
            .function, .arrow_function_expression, .static_block, .program => return current,
            else => {},
        }
        current = symbol_table.parentOf(current) orelse return tree.root;
    }
}

fn containsNode(tree: *const ast.Tree, container: ast.NodeIndex, node: ast.NodeIndex) bool {
    if (container == .null or node == .null) return false;
    const outer = tree.span(container);
    const inner = tree.span(node);
    return outer.start <= inner.start and inner.end <= outer.end;
}

fn isPatternTarget(data: ast.NodeData) bool {
    return switch (data) {
        .identifier_reference, .object_pattern, .array_pattern, .assignment_pattern, .binding_rest_element, .parenthesized_expression => true,
        else => false,
    };
}

fn collectDelayedPatternNodes(allocator: Allocator, tree: *const ast.Tree) Allocator.Error![]bool {
    const delayed = try allocator.alloc(bool, tree.nodes.len);
    errdefer allocator.free(delayed);
    @memset(delayed, false);

    for (tree.nodes.items(.data)) |data| {
        const pattern = switch (data) {
            .variable_declarator => |declarator| declarator.id,
            .assignment_expression => |expression| if (isPatternTarget(tree.data(expression.left))) expression.left else .null,
            else => .null,
        };
        if (pattern == .null) continue;

        var subtree = tree.*;
        subtree.root = pattern;
        var marker = DelayedPatternMarker{ .nodes = delayed };
        try traverser.basic.traverse(DelayedPatternMarker, &subtree, &marker);
    }

    return delayed;
}

const DelayedPatternMarker = struct {
    nodes: []bool,

    pub fn enter_node(
        self: *DelayedPatternMarker,
        _: ast.NodeData,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) traverser.Action {
        self.nodes[@backingInt(index)] = true;
        return .proceed;
    }
};

fn collectExportedDirectiveNames(
    allocator: Allocator,
    source: []const u8,
    names: *std.ArrayList([]const u8),
) Allocator.Error!void {
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, source, offset, "/*")) |start| {
        const end = std.mem.indexOfPos(u8, source, start + 2, "*/") orelse return;
        const comment = source[start + 2 .. end];
        if (std.mem.indexOf(u8, comment, "exported")) |keyword| {
            var tokens = std.mem.tokenizeAny(u8, comment[keyword + "exported".len ..], " \t\r\n,;:");
            while (tokens.next()) |token| try names.append(allocator, token);
        }
        offset = end + 2;
    }
}

fn isExportedByDirective(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

fn isExportedBySpecifier(tree: *const ast.Tree, symbol_table: SymbolTable, symbol: SymbolId) bool {
    for (symbol_table.model.uses(symbol)) |reference_id| {
        var current = symbol_table.model.reference(reference_id).node;
        while (symbol_table.parentOf(current)) |parent| {
            switch (tree.data(parent)) {
                .export_specifier => return true,
                .parenthesized_expression => {},
                else => break,
            }
            current = parent;
        }
    }
    return false;
}
