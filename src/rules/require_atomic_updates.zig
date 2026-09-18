const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "require-atomic-updates";

pub const Options = struct {
    allow_properties: bool = false,
};

const SymbolId = traverser.semantic.SymbolId;
const ReferenceLookup = std.AutoHashMap(ast.NodeIndex, SymbolId);
const SymbolSet = std.AutoHashMap(SymbolId, void);

const State = struct {
    read_symbols: SymbolSet,
    stale_symbols: SymbolSet,
    read_objects: SymbolSet,
    stale_objects: SymbolSet,

    fn deinit(self: *State) void {
        self.read_symbols.deinit();
        self.stale_symbols.deinit();
        self.read_objects.deinit();
        self.stale_objects.deinit();
    }
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    var reference_lookup = ReferenceLookup.init(allocator);
    defer reference_lookup.deinit();

    var reference_iter = symbol_table.iterReferences();
    while (reference_iter.next()) |entry| {
        if (entry.reference.kind != .value) continue;
        try reference_lookup.put(entry.reference.node, symbol_table.referenceSymbol(entry.id));
    }

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .symbol_table = symbol_table,
        .reference_lookup = &reference_lookup,
        .options = options,
    };
    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    symbol_table: traverser.semantic.SymbolTable,
    reference_lookup: *const ReferenceLookup,
    options: Options,

    pub fn enter_function(
        self: *Visitor,
        function: ast.Function,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (!function.async and !function.generator) return .proceed;
        try self.checkFunction(ctx.tree, function.body, ctx.tree.span(index));
        return .proceed;
    }

    pub fn enter_arrow_function_expression(
        self: *Visitor,
        expression: ast.ArrowFunctionExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (!expression.async) return .proceed;
        try self.checkFunction(ctx.tree, expression.body, ctx.tree.span(index));
        return .proceed;
    }

    fn checkFunction(
        self: *Visitor,
        tree: *const ast.Tree,
        body: ast.NodeIndex,
        function_span: ast.Span,
    ) Allocator.Error!void {
        var analyzer = Analyzer{
            .allocator = self.allocator,
            .diagnostics = self.diagnostics,
            .tree = tree,
            .symbol_table = self.symbol_table,
            .reference_lookup = self.reference_lookup,
            .function_span = function_span,
            .options = self.options,
            .read_symbols = SymbolSet.init(self.allocator),
            .stale_symbols = SymbolSet.init(self.allocator),
            .read_objects = SymbolSet.init(self.allocator),
            .stale_objects = SymbolSet.init(self.allocator),
        };
        defer analyzer.deinit();

        try analyzer.scanFunctionBody(body);
    }
};

const Analyzer = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    reference_lookup: *const ReferenceLookup,
    function_span: ast.Span,
    options: Options,
    read_symbols: SymbolSet,
    stale_symbols: SymbolSet,
    read_objects: SymbolSet,
    stale_objects: SymbolSet,

    fn deinit(self: *Analyzer) void {
        self.read_symbols.deinit();
        self.stale_symbols.deinit();
        self.read_objects.deinit();
        self.stale_objects.deinit();
    }

    fn scanFunctionBody(self: *Analyzer, body_index: ast.NodeIndex) Allocator.Error!void {
        if (body_index == .null) return;

        switch (self.tree.data(body_index)) {
            .function_body => |body| try self.scanRange(body.body),
            else => try self.scanNode(body_index),
        }
    }

    fn scanRange(self: *Analyzer, range: ast.IndexRange) Allocator.Error!void {
        for (self.tree.extra(range)) |child| {
            try self.scanNode(child);
        }
    }

    fn scanIfBranches(
        self: *Analyzer,
        consequent: ast.NodeIndex,
        alternate: ast.NodeIndex,
    ) Allocator.Error!void {
        var base = try self.captureState();
        defer base.deinit();

        try self.scanNode(consequent);
        var consequent_state = try self.captureState();
        defer consequent_state.deinit();

        try self.setCurrentFromState(&base);
        try self.scanNode(alternate);
        var alternate_state = try self.captureState();
        defer alternate_state.deinit();

        try self.setCurrentFromMergedStates(&consequent_state, &alternate_state);
    }

    fn scanNode(self: *Analyzer, index: ast.NodeIndex) Allocator.Error!void {
        if (index == .null) return;

        switch (self.tree.data(index)) {
            .identifier_reference => try self.markReadReference(index),
            .member_expression => |member| try self.scanMemberExpression(member),
            .assignment_expression => |expression| try self.scanAssignmentExpression(expression, index),
            .update_expression => |expression| try self.scanUpdateExpression(expression, index),
            .await_expression => |expression| {
                try self.scanNode(expression.argument);
                try self.markSuspend();
            },
            .yield_expression => |expression| {
                try self.scanNode(expression.argument);
                try self.markSuspend();
            },
            .variable_declaration => |declaration| {
                for (self.tree.extra(declaration.declarators)) |declarator_index| {
                    const declarator = switch (self.tree.data(declarator_index)) {
                        .variable_declarator => |declarator| declarator,
                        else => continue,
                    };
                    try self.scanNode(declarator.init);
                }
            },
            .if_statement => |statement| {
                try self.scanNode(statement.@"test");
                try self.scanIfBranches(statement.consequent, statement.alternate);
            },
            .switch_statement => |statement| {
                try self.scanNode(statement.discriminant);
                for (self.tree.extra(statement.cases)) |case_index| {
                    const case = switch (self.tree.data(case_index)) {
                        .switch_case => |case| case,
                        else => continue,
                    };
                    try self.scanNode(case.@"test");
                    try self.scanRange(case.consequent);
                }
            },
            .for_statement => |statement| {
                try self.scanNode(statement.init);
                try self.scanNode(statement.@"test");
                try self.scanNode(statement.body);
                try self.scanNode(statement.update);
            },
            .for_in_statement => |statement| {
                try self.scanNode(statement.right);
                try self.scanLoopLeft(statement.left);
                try self.scanNode(statement.body);
            },
            .for_of_statement => |statement| {
                try self.scanNode(statement.right);
                try self.scanLoopLeft(statement.left);
                if (statement.await) try self.markSuspend();
                try self.scanNode(statement.body);
            },
            .while_statement => |statement| {
                try self.scanNode(statement.@"test");
                try self.scanNode(statement.body);
            },
            .do_while_statement => |statement| {
                try self.scanNode(statement.body);
                try self.scanNode(statement.@"test");
            },
            .with_statement => |statement| {
                try self.scanNode(statement.object);
                try self.scanNode(statement.body);
            },
            .try_statement => |statement| {
                try self.scanNode(statement.block);
                if (statement.handler != .null) {
                    const handler = switch (self.tree.data(statement.handler)) {
                        .catch_clause => |handler| handler,
                        else => return,
                    };
                    try self.scanNode(handler.body);
                }
                try self.scanNode(statement.finalizer);
            },
            .return_statement => |statement| try self.scanNode(statement.argument),
            .throw_statement => |statement| try self.scanNode(statement.argument),
            .expression_statement => |statement| try self.scanNode(statement.expression),
            .labeled_statement => |statement| try self.scanNode(statement.body),
            .block_statement => |block| try self.scanRange(block.body),
            .static_block => |block| try self.scanRange(block.body),
            .function,
            .arrow_function_expression,
            .class,
            => return,
            inline else => |node| try self.scanPayload(node),
        }
    }

    fn scanPayload(self: *Analyzer, payload: anytype) Allocator.Error!void {
        const Payload = @TypeOf(payload);
        if (@typeInfo(Payload) != .@"struct") return;

        inline for (@typeInfo(Payload).@"struct".fields) |field| {
            const value = @field(payload, field.name);
            if (field.type == ast.NodeIndex) {
                try self.scanNode(value);
            } else if (field.type == ast.IndexRange) {
                for (self.tree.extra(value)) |child| {
                    try self.scanNode(child);
                }
            }
        }
    }

    fn scanMemberExpression(self: *Analyzer, member: ast.MemberExpression) Allocator.Error!void {
        try self.scanNode(member.object);
        if (member.computed) try self.scanNode(member.property);
        try self.markObjectRead(member.object);
    }

    fn scanAssignmentExpression(
        self: *Analyzer,
        expression: ast.AssignmentExpression,
        index: ast.NodeIndex,
    ) Allocator.Error!void {
        if (expression.operator == .assign) {
            try self.scanAssignmentTargetReference(expression.left);
        } else {
            try self.scanAssignmentTargetRead(expression.left);
        }

        try self.scanNode(expression.right);
        try self.checkAssignmentTarget(expression.left, index);
    }

    fn scanUpdateExpression(
        self: *Analyzer,
        expression: ast.UpdateExpression,
        index: ast.NodeIndex,
    ) Allocator.Error!void {
        try self.scanAssignmentTargetRead(expression.argument);
        try self.checkAssignmentTarget(expression.argument, index);
    }

    fn scanLoopLeft(self: *Analyzer, index: ast.NodeIndex) Allocator.Error!void {
        if (index == .null) return;

        switch (self.tree.data(index)) {
            .variable_declaration => |declaration| {
                for (self.tree.extra(declaration.declarators)) |declarator_index| {
                    const declarator = switch (self.tree.data(declarator_index)) {
                        .variable_declarator => |declarator| declarator,
                        else => continue,
                    };
                    try self.scanNode(declarator.init);
                }
            },
            else => try self.scanAssignmentTargetReference(index),
        }
    }

    fn scanAssignmentTargetReference(self: *Analyzer, index: ast.NodeIndex) Allocator.Error!void {
        if (index == .null) return;

        const unwrapped = unwrapTransparent(self.tree, index);
        switch (self.tree.data(unwrapped)) {
            .member_expression => |member| {
                if (self.tree.data(unwrapTransparent(self.tree, member.object)) == .member_expression) {
                    try self.scanAssignmentTargetReference(member.object);
                } else {
                    try self.scanNode(member.object);
                }
                if (member.computed) try self.scanNode(member.property);
                // Evaluating a write target does not reread its property's value.
                // Keep pre-suspension reads stale until an actual member read.
            },
            .array_pattern => |pattern| {
                for (self.tree.extra(pattern.elements)) |element| {
                    try self.scanAssignmentTargetReference(element);
                }
                try self.scanAssignmentTargetReference(pattern.rest);
            },
            .object_pattern => |pattern| {
                for (self.tree.extra(pattern.properties)) |property_index| {
                    const property = switch (self.tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    if (property.computed) try self.scanNode(property.key);
                    try self.scanAssignmentTargetReference(property.value);
                }
                try self.scanAssignmentTargetReference(pattern.rest);
            },
            .assignment_pattern => |pattern| try self.scanAssignmentTargetReference(pattern.left),
            .binding_rest_element => |element| try self.scanAssignmentTargetReference(element.argument),
            else => {},
        }
    }

    fn scanAssignmentTargetRead(self: *Analyzer, index: ast.NodeIndex) Allocator.Error!void {
        if (index == .null) return;

        const unwrapped = unwrapTransparent(self.tree, index);
        switch (self.tree.data(unwrapped)) {
            .identifier_reference => try self.markReadReference(unwrapped),
            .member_expression => |member| try self.scanMemberExpression(member),
            else => try self.scanAssignmentTargetReference(unwrapped),
        }
    }

    fn checkAssignmentTarget(
        self: *Analyzer,
        target: ast.NodeIndex,
        diagnostic_node: ast.NodeIndex,
    ) Allocator.Error!void {
        if (target == .null) return;

        const unwrapped = unwrapTransparent(self.tree, target);
        switch (self.tree.data(unwrapped)) {
            .identifier_reference => {
                const symbol_id = self.reference_lookup.get(unwrapped) orelse return;
                if (symbol_id == .none or !self.stale_symbols.contains(symbol_id)) return;
                if (self.isLocalSymbol(symbol_id)) return;

                const name = identifierReferenceName(self.tree, unwrapped) orelse return;
                try self.addVariableDiagnostic(diagnostic_node, name);
            },
            .member_expression => |member| {
                if (self.options.allow_properties) return;

                const symbol_id = rootObjectSymbol(self.tree, self.reference_lookup, member.object);
                if (symbol_id == .none or !self.stale_objects.contains(symbol_id)) return;

                const target_text = sourceText(self.tree, unwrapped);
                const object_text = rootObjectText(self.tree, member.object) orelse target_text;
                try self.addPropertyDiagnostic(diagnostic_node, target_text, object_text);
            },
            .array_pattern => |pattern| {
                for (self.tree.extra(pattern.elements)) |element| {
                    try self.checkAssignmentTarget(element, diagnostic_node);
                }
                try self.checkAssignmentTarget(pattern.rest, diagnostic_node);
            },
            .object_pattern => |pattern| {
                for (self.tree.extra(pattern.properties)) |property_index| {
                    const property = switch (self.tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    try self.checkAssignmentTarget(property.value, diagnostic_node);
                }
                try self.checkAssignmentTarget(pattern.rest, diagnostic_node);
            },
            .assignment_pattern => |pattern| try self.checkAssignmentTarget(pattern.left, diagnostic_node),
            .binding_rest_element => |element| try self.checkAssignmentTarget(element.argument, diagnostic_node),
            else => {},
        }
    }

    fn markReadReference(self: *Analyzer, index: ast.NodeIndex) Allocator.Error!void {
        const symbol_id = self.reference_lookup.get(index) orelse return;
        if (symbol_id == .none) return;

        _ = self.stale_symbols.remove(symbol_id);
        try self.read_symbols.put(symbol_id, {});
    }

    fn markObjectRead(self: *Analyzer, index: ast.NodeIndex) Allocator.Error!void {
        const symbol_id = rootObjectSymbol(self.tree, self.reference_lookup, index);
        if (symbol_id == .none) return;

        _ = self.stale_objects.remove(symbol_id);
        try self.read_objects.put(symbol_id, {});
    }

    fn markSuspend(self: *Analyzer) Allocator.Error!void {
        var symbol_iter = self.read_symbols.keyIterator();
        while (symbol_iter.next()) |symbol_id| {
            try self.stale_symbols.put(symbol_id.*, {});
        }
        self.read_symbols.clearRetainingCapacity();

        var object_iter = self.read_objects.keyIterator();
        while (object_iter.next()) |symbol_id| {
            try self.stale_objects.put(symbol_id.*, {});
        }
        self.read_objects.clearRetainingCapacity();
    }

    fn isLocalSymbol(self: *const Analyzer, symbol_id: SymbolId) bool {
        const decls = self.symbol_table.symbolDecls(symbol_id);
        if (decls.len == 0) return false;
        return spanInside(self.tree.span(decls[0]), self.function_span);
    }

    fn addVariableDiagnostic(
        self: *Analyzer,
        node: ast.NodeIndex,
        name: []const u8,
    ) Allocator.Error!void {
        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .warning,
            id,
            self.tree.span(node),
            "Possible race condition: '{s}' might be reassigned based on an outdated value of '{s}'.",
            .{ name, name },
        );
    }

    fn addPropertyDiagnostic(
        self: *Analyzer,
        node: ast.NodeIndex,
        target: []const u8,
        object: []const u8,
    ) Allocator.Error!void {
        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .warning,
            id,
            self.tree.span(node),
            "Possible race condition: '{s}' might be assigned based on an outdated state of '{s}'.",
            .{ target, object },
        );
    }

    fn captureState(self: *Analyzer) Allocator.Error!State {
        return .{
            .read_symbols = try self.cloneSet(&self.read_symbols),
            .stale_symbols = try self.cloneSet(&self.stale_symbols),
            .read_objects = try self.cloneSet(&self.read_objects),
            .stale_objects = try self.cloneSet(&self.stale_objects),
        };
    }

    fn cloneSet(self: *Analyzer, source: *const SymbolSet) Allocator.Error!SymbolSet {
        var out = SymbolSet.init(self.allocator);
        errdefer out.deinit();

        var iter = source.keyIterator();
        while (iter.next()) |symbol_id| {
            try out.put(symbol_id.*, {});
        }

        return out;
    }

    fn setCurrentFromState(self: *Analyzer, state: *const State) Allocator.Error!void {
        self.clearState();
        try self.copySetInto(&self.read_symbols, &state.read_symbols);
        try self.copySetInto(&self.stale_symbols, &state.stale_symbols);
        try self.copySetInto(&self.read_objects, &state.read_objects);
        try self.copySetInto(&self.stale_objects, &state.stale_objects);
    }

    fn setCurrentFromMergedStates(self: *Analyzer, a: *const State, b: *const State) Allocator.Error!void {
        self.clearState();
        try self.copySetInto(&self.read_symbols, &a.read_symbols);
        try self.copySetInto(&self.read_symbols, &b.read_symbols);
        try self.copySetInto(&self.stale_symbols, &a.stale_symbols);
        try self.copySetInto(&self.stale_symbols, &b.stale_symbols);
        try self.copySetInto(&self.read_objects, &a.read_objects);
        try self.copySetInto(&self.read_objects, &b.read_objects);
        try self.copySetInto(&self.stale_objects, &a.stale_objects);
        try self.copySetInto(&self.stale_objects, &b.stale_objects);
    }

    fn clearState(self: *Analyzer) void {
        self.read_symbols.clearRetainingCapacity();
        self.stale_symbols.clearRetainingCapacity();
        self.read_objects.clearRetainingCapacity();
        self.stale_objects.clearRetainingCapacity();
    }

    fn copySetInto(_: *Analyzer, target: *SymbolSet, source: *const SymbolSet) Allocator.Error!void {
        var iter = source.keyIterator();
        while (iter.next()) |symbol_id| {
            try target.put(symbol_id.*, {});
        }
    }
};

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

fn rootObjectSymbol(
    tree: *const ast.Tree,
    reference_lookup: *const ReferenceLookup,
    index: ast.NodeIndex,
) SymbolId {
    if (index == .null) return .none;

    const unwrapped = unwrapTransparent(tree, index);
    return switch (tree.data(unwrapped)) {
        .identifier_reference => reference_lookup.get(unwrapped) orelse .none,
        .member_expression => |member| rootObjectSymbol(tree, reference_lookup, member.object),
        else => .none,
    };
}

fn rootObjectText(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    const unwrapped = unwrapTransparent(tree, index);
    return switch (tree.data(unwrapped)) {
        .identifier_reference => sourceText(tree, unwrapped),
        .member_expression => |member| rootObjectText(tree, member.object),
        else => null,
    };
}

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn sourceText(tree: *const ast.Tree, index: ast.NodeIndex) []const u8 {
    const span = tree.span(index);
    const start: usize = @intCast(span.start);
    const end: usize = @intCast(span.end);
    return tree.source[start..end];
}

fn spanInside(span: ast.Span, container: ast.Span) bool {
    return span.start >= container.start and span.end <= container.end;
}
