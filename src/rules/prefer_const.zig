const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "prefer-const";

const SymbolId = traverser.semantic.SymbolId;
const DeclSymbolMap = std.AutoHashMap(ast.NodeIndex, SymbolId);
const ReferenceLookup = std.AutoHashMap(ast.NodeIndex, SymbolId);
const DestructuringGroupMap = std.AutoHashMap(usize, bool);

pub const Destructuring = enum {
    any,
    all,
};

pub const Options = struct {
    destructuring: Destructuring = .any,
    ignore_read_before_assign: bool = true,
};

const Candidate = struct {
    node: ast.NodeIndex,
    declaration: ast.NodeIndex,
    name: []const u8,
    initialized: bool = true,
    reassigned: bool = false,
    assignment_count: usize = 0,
    first_assignment_node: ast.NodeIndex = .null,
    first_assignment_end: u32 = 0,
    read_before_assignment: bool = false,
    destructuring_group: ?usize = null,
    /// Statement list that directly contains the declaration. A delayed
    /// assignment can only be merged into the declaration when it is an
    /// expression statement in the same list.
    declaration_host: ast.NodeIndex = .null,
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
    var decl_symbols = DeclSymbolMap.init(allocator);
    defer decl_symbols.deinit();

    var reference_lookup = ReferenceLookup.init(allocator);
    defer reference_lookup.deinit();

    var destructuring_groups = DestructuringGroupMap.init(allocator);
    defer destructuring_groups.deinit();

    const candidate_symbols = try allocator.alloc(bool, symbol_table.symbols.len);
    defer allocator.free(candidate_symbols);
    @memset(candidate_symbols, false);

    var candidates = std.AutoHashMap(SymbolId, Candidate).init(allocator);
    defer candidates.deinit();

    var symbol_iter = symbol_table.iterSymbols();
    while (symbol_iter.next()) |entry| {
        const symbol = entry.symbol;
        if (!symbol.flags.block_scoped_var or symbol.flags.const_var) continue;
        candidate_symbols[@intFromEnum(entry.id)] = true;
        for (symbol_table.symbolDecls(entry.id)) |decl| {
            try decl_symbols.put(decl, entry.id);
        }
    }

    var ref_iter = symbol_table.iterReferences();
    while (ref_iter.next()) |entry| {
        const symbol_id = symbol_table.referenceSymbol(entry.id);
        if (symbol_id == .none) continue;

        const symbol_index = @intFromEnum(symbol_id);
        if (symbol_index >= candidate_symbols.len or !candidate_symbols[symbol_index]) continue;

        try reference_lookup.put(entry.reference.node, symbol_id);
    }

    var visitor = Visitor{
        .allocator = allocator,
        .decl_symbols = &decl_symbols,
        .reference_lookup = &reference_lookup,
        .candidates = &candidates,
        .destructuring_groups = &destructuring_groups,
        .options = options,
    };
    try traverser.basic.traverse(Visitor, tree, &visitor);

    var fixed_declarations = std.AutoHashMap(ast.NodeIndex, bool).init(allocator);
    defer fixed_declarations.deinit();

    var candidate_iter = candidates.iterator();
    while (candidate_iter.next()) |entry| {
        const candidate = entry.value_ptr.*;
        const report_node = candidateReportNode(candidate, &destructuring_groups, options) orelse continue;

        const can_fix = candidate.initialized and
            !fixed_declarations.contains(candidate.declaration) and
            declarationCanFix(tree, candidate.declaration, &decl_symbols, &candidates, &destructuring_groups, options);
        if (can_fix) {
            if (try declarationReplacement(allocator, tree, candidate.declaration)) |replacement| {
                defer allocator.free(replacement);
                const message = try std.fmt.allocPrint(allocator, "'{s}' is never reassigned. Use 'const' instead.", .{candidate.name});
                defer allocator.free(message);
                const declaration_span = tree.span(candidate.declaration);
                try core.addDiagnosticWithFix(
                    allocator,
                    diagnostics,
                    .warning,
                    id,
                    message,
                    tree.span(report_node),
                    .{ .span = declaration_span, .replacement = replacement },
                );
                try fixed_declarations.put(candidate.declaration, true);
                continue;
            }
        }

        try addCandidateDiagnostic(allocator, diagnostics, tree, candidate, report_node);
    }
}

const Visitor = struct {
    allocator: Allocator,
    decl_symbols: *const DeclSymbolMap,
    reference_lookup: *const ReferenceLookup,
    candidates: *std.AutoHashMap(SymbolId, Candidate),
    destructuring_groups: *DestructuringGroupMap,
    options: Options,
    next_destructuring_group: usize = 0,

    pub fn enter_variable_declaration(
        self: *Visitor,
        declaration: ast.VariableDeclaration,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (declaration.kind != .let) return .proceed;

        const host = declarationHost(ctx);
        for (ctx.tree.extra(declaration.declarators)) |declarator_index| {
            const declarator = switch (ctx.tree.data(declarator_index)) {
                .variable_declarator => |declarator| declarator,
                else => continue,
            };

            const group = if (self.options.destructuring == .all and isDestructuringPattern(ctx.tree, declarator.id)) group: {
                const group_id = self.next_destructuring_group;
                self.next_destructuring_group += 1;
                try self.destructuring_groups.put(group_id, false);
                break :group group_id;
            } else null;

            try self.collectCandidate(ctx.tree, declarator.id, index, host, group, declarator.init != .null);
        }

        return .proceed;
    }

    pub fn enter_assignment_expression(
        self: *Visitor,
        expression: ast.AssignmentExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.markAssignment(
            ctx.tree,
            expression.left,
            expression.operator == .assign,
            assignmentHost(ctx),
            ctx.tree.span(index).end,
        );
        return .proceed;
    }

    pub fn enter_for_in_statement(
        self: *Visitor,
        statement: ast.ForInStatement,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectForLoopLeft(ctx.tree, statement.left);
        return .proceed;
    }

    pub fn enter_for_of_statement(
        self: *Visitor,
        statement: ast.ForOfStatement,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.collectForLoopLeft(ctx.tree, statement.left);
        return .proceed;
    }

    pub fn enter_update_expression(
        self: *Visitor,
        expression: ast.UpdateExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.markAssignment(ctx.tree, expression.argument, false, .null, ctx.tree.span(index).end);
        return .proceed;
    }

    fn collectForLoopLeft(self: *Visitor, tree: *const ast.Tree, index: ast.NodeIndex) Allocator.Error!void {
        const declaration = switch (tree.data(index)) {
            .variable_declaration => |declaration| declaration,
            else => return,
        };
        if (declaration.kind != .let) return;

        for (tree.extra(declaration.declarators)) |declarator_index| {
            const declarator = switch (tree.data(declarator_index)) {
                .variable_declarator => |declarator| declarator,
                else => continue,
            };

            const group = if (self.options.destructuring == .all and isDestructuringPattern(tree, declarator.id)) group: {
                const group_id = self.next_destructuring_group;
                self.next_destructuring_group += 1;
                try self.destructuring_groups.put(group_id, false);
                break :group group_id;
            } else null;

            try self.collectCandidate(tree, declarator.id, index, .null, group, true);
        }
    }

    pub fn enter_identifier_reference(
        self: *Visitor,
        _: ast.IdentifierReference,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) traverser.Action {
        if (isAssignmentWrite(ctx.tree, index, ctx)) return .proceed;

        const symbol_id = self.reference_lookup.get(index) orelse return .proceed;
        if (self.candidates.getPtr(symbol_id)) |candidate| {
            if (!candidate.initialized and isReadBeforeFirstAssignment(ctx.tree, index, candidate.*)) {
                candidate.read_before_assignment = true;
            }
        }

        return .proceed;
    }

    fn collectCandidate(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        declaration: ast.NodeIndex,
        declaration_host: ast.NodeIndex,
        group: ?usize,
        initialized: bool,
    ) Allocator.Error!void {
        if (index == .null) return;

        switch (tree.data(index)) {
            .binding_identifier => |identifier| {
                const symbol_id = self.decl_symbols.get(index) orelse return;
                if (!initialized) {
                    if (self.candidates.get(symbol_id)) |existing| {
                        if (existing.initialized) return;
                    }
                }
                try self.candidates.put(symbol_id, .{
                    .node = index,
                    .declaration = declaration,
                    .name = tree.string(identifier.name),
                    .initialized = initialized,
                    .destructuring_group = group,
                    .declaration_host = declaration_host,
                });
            },
            .assignment_pattern => |pattern| try self.collectCandidate(tree, pattern.left, declaration, declaration_host, group, initialized),
            .binding_rest_element => |element| try self.collectCandidate(tree, element.argument, declaration, declaration_host, group, initialized),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    try self.collectCandidate(tree, element, declaration, declaration_host, group, initialized);
                }
                try self.collectCandidate(tree, pattern.rest, declaration, declaration_host, group, initialized);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    try self.collectCandidate(tree, property.value, declaration, declaration_host, group, initialized);
                }
                try self.collectCandidate(tree, pattern.rest, declaration, declaration_host, group, initialized);
            },
            else => {},
        }
    }

    /// `assignment_host` is the statement list that directly contains the
    /// assignment expression statement, or `.null` when the assignment cannot
    /// be rewritten into a declaration (nested expression, `if` body without
    /// braces, labeled statement, and so on).
    fn markAssignment(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        simple_assign: bool,
        assignment_host: ast.NodeIndex,
        assignment_end: u32,
    ) Allocator.Error!void {
        if (index == .null) return;

        const unwrapped = unwrapTransparent(tree, index);
        switch (tree.data(unwrapped)) {
            .identifier_reference => {
                const symbol_id = self.reference_lookup.get(unwrapped) orelse return;
                if (self.candidates.getPtr(symbol_id)) |candidate| {
                    if (candidate.initialized) {
                        candidate.reassigned = true;
                    } else if (simple_assign) {
                        candidate.assignment_count += 1;
                        if (candidate.assignment_count == 1) {
                            candidate.first_assignment_node = unwrapped;
                            candidate.first_assignment_end = assignment_end;
                            // ESLint only merges the assignment into the
                            // declaration when both live in the same
                            // statement list. Anything else keeps `let`.
                            if (assignment_host == .null or assignment_host != candidate.declaration_host) {
                                candidate.reassigned = true;
                            }
                        } else {
                            candidate.reassigned = true;
                        }
                    } else {
                        candidate.reassigned = true;
                    }
                    if (candidate.destructuring_group) |group_id| {
                        try self.destructuring_groups.put(group_id, true);
                    }
                }
            },
            .assignment_pattern => |pattern| try self.markAssignment(tree, pattern.left, simple_assign, assignment_host, assignment_end),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    try self.markAssignment(tree, element, simple_assign, assignment_host, assignment_end);
                }
                try self.markAssignment(tree, pattern.rest, simple_assign, assignment_host, assignment_end);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    try self.markAssignment(tree, property.value, simple_assign, assignment_host, assignment_end);
                }
                try self.markAssignment(tree, pattern.rest, simple_assign, assignment_host, assignment_end);
            },
            else => {},
        }
    }
};

/// Returns the statement list that directly owns the node being visited.
/// `switch` cases share one scope, so their consequents map to the `switch`
/// statement itself.
fn statementListHost(ctx: *traverser.basic.Ctx, depth: usize) ast.NodeIndex {
    const host = ctx.path.ancestor(depth) orelse return .null;
    return switch (ctx.tree.data(host)) {
        .program, .function_body, .block_statement, .static_block => host,
        .switch_case => ctx.path.ancestor(depth + 1) orelse .null,
        else => .null,
    };
}

/// `export let value;` wraps the declaration in an export declaration that
/// sits in the module's statement list.
fn declarationHost(ctx: *traverser.basic.Ctx) ast.NodeIndex {
    const parent = ctx.path.parent() orelse return .null;
    return switch (ctx.tree.data(parent)) {
        .export_named_declaration => statementListHost(ctx, 2),
        else => statementListHost(ctx, 1),
    };
}

/// Mirrors ESLint's `canBecomeVariableDeclaration`: the assignment must be a
/// whole expression statement placed directly in a statement list.
/// Parentheses around the assignment are transparent, which also covers the
/// mandatory `({ value } = source);` form.
fn assignmentHost(ctx: *traverser.basic.Ctx) ast.NodeIndex {
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        switch (ctx.tree.data(ancestor)) {
            .parenthesized_expression => continue,
            .expression_statement => return statementListHost(ctx, depth + 1),
            else => return .null,
        }
    }
    return .null;
}

fn candidateReportNode(
    candidate: Candidate,
    destructuring_groups: *const DestructuringGroupMap,
    options: Options,
) ?ast.NodeIndex {
    if (candidate.reassigned) return null;
    const report_node = if (candidate.initialized) candidate.node else report_node: {
        if (candidate.assignment_count != 1) return null;
        if (options.ignore_read_before_assign and candidate.read_before_assignment) return null;
        break :report_node candidate.first_assignment_node;
    };
    if (candidate.destructuring_group) |group_id| {
        if (options.destructuring == .all and (destructuring_groups.get(group_id) orelse false)) return null;
    }
    return report_node;
}

fn declarationCanFix(
    tree: *const ast.Tree,
    declaration_index: ast.NodeIndex,
    decl_symbols: *const DeclSymbolMap,
    candidates: *const std.AutoHashMap(SymbolId, Candidate),
    destructuring_groups: *const DestructuringGroupMap,
    options: Options,
) bool {
    const declaration = switch (tree.data(declaration_index)) {
        .variable_declaration => |declaration| declaration,
        else => return false,
    };
    if (declaration.kind != .let or declaration.declarators.len == 0) return false;

    for (tree.extra(declaration.declarators)) |declarator_index| {
        const declarator = switch (tree.data(declarator_index)) {
            .variable_declarator => |declarator| declarator,
            else => return false,
        };
        if (!patternCanFix(
            tree,
            declarator.id,
            declaration_index,
            decl_symbols,
            candidates,
            destructuring_groups,
            options,
        )) return false;
    }
    return true;
}

fn patternCanFix(
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    declaration_index: ast.NodeIndex,
    decl_symbols: *const DeclSymbolMap,
    candidates: *const std.AutoHashMap(SymbolId, Candidate),
    destructuring_groups: *const DestructuringGroupMap,
    options: Options,
) bool {
    if (index == .null) return true;

    return switch (tree.data(index)) {
        .binding_identifier => binding: {
            const symbol_id = decl_symbols.get(index) orelse break :binding false;
            const candidate = candidates.get(symbol_id) orelse break :binding false;
            break :binding candidate.declaration == declaration_index and
                candidate.initialized and
                candidateReportNode(candidate, destructuring_groups, options) != null;
        },
        .assignment_pattern => |pattern| patternCanFix(
            tree,
            pattern.left,
            declaration_index,
            decl_symbols,
            candidates,
            destructuring_groups,
            options,
        ),
        .binding_rest_element => |element| patternCanFix(
            tree,
            element.argument,
            declaration_index,
            decl_symbols,
            candidates,
            destructuring_groups,
            options,
        ),
        .array_pattern => |pattern| pattern: {
            for (tree.extra(pattern.elements)) |element| {
                if (!patternCanFix(
                    tree,
                    element,
                    declaration_index,
                    decl_symbols,
                    candidates,
                    destructuring_groups,
                    options,
                )) break :pattern false;
            }
            break :pattern patternCanFix(
                tree,
                pattern.rest,
                declaration_index,
                decl_symbols,
                candidates,
                destructuring_groups,
                options,
            );
        },
        .object_pattern => |pattern| pattern: {
            for (tree.extra(pattern.properties)) |property_index| {
                const property = switch (tree.data(property_index)) {
                    .binding_property => |property| property,
                    else => break :pattern false,
                };
                if (!patternCanFix(
                    tree,
                    property.value,
                    declaration_index,
                    decl_symbols,
                    candidates,
                    destructuring_groups,
                    options,
                )) break :pattern false;
            }
            break :pattern patternCanFix(
                tree,
                pattern.rest,
                declaration_index,
                decl_symbols,
                candidates,
                destructuring_groups,
                options,
            );
        },
        else => false,
    };
}

fn declarationReplacement(
    allocator: Allocator,
    tree: *const ast.Tree,
    declaration_index: ast.NodeIndex,
) Allocator.Error!?[]u8 {
    const span = tree.span(declaration_index);
    if (span.end < span.start + "let".len or
        !std.mem.eql(u8, tree.source[span.start .. span.start + "let".len], "let")) return null;

    return try std.fmt.allocPrint(
        allocator,
        "const{s}",
        .{tree.source[span.start + "let".len .. span.end]},
    );
}

fn addCandidateDiagnostic(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    candidate: Candidate,
    report_node: ast.NodeIndex,
) Allocator.Error!void {
    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        .warning,
        id,
        tree.span(report_node),
        "'{s}' is never reassigned. Use 'const' instead.",
        .{candidate.name},
    );
}

fn isReadBeforeFirstAssignment(tree: *const ast.Tree, index: ast.NodeIndex, candidate: Candidate) bool {
    if (candidate.assignment_count == 0) return true;
    if (candidate.assignment_count > 1 or candidate.first_assignment_end == 0) return false;
    return tree.span(index).start <= candidate.first_assignment_end;
}

fn isAssignmentWrite(tree: *const ast.Tree, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) bool {
    const parent = ctx.path.parent() orelse return false;

    return switch (tree.data(parent)) {
        .assignment_expression => |expression| unwrapTransparent(tree, expression.left) == index,
        .update_expression => |expression| unwrapTransparent(tree, expression.argument) == index,
        else => false,
    };
}

fn isDestructuringPattern(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;
    return switch (tree.data(index)) {
        .array_pattern,
        .object_pattern,
        => true,
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
