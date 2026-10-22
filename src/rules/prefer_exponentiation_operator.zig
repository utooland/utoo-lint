const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "prefer-exponentiation-operator";

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .symbol_table = symbol_table,
    };

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    symbol_table: traverser.semantic.SymbolTable,

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (isGlobalMathPowCall(ctx.tree, self.symbol_table, call.callee)) {
            if (try buildFix(self.allocator, ctx.tree, call, index, ctx)) |fix| {
                defer self.allocator.free(fix.replacement);
                try core.addDiagnosticWithFix(
                    self.allocator,
                    self.diagnostics,
                    .warning,
                    id,
                    "Use the exponentiation operator (**) instead of Math.pow.",
                    ctx.tree.span(index),
                    fix,
                );
                return .proceed;
            }

            try core.addDiagnostic(
                self.allocator,
                self.diagnostics,
                .warning,
                id,
                "Use the exponentiation operator (**) instead of Math.pow.",
                ctx.tree.span(index),
            );
        }

        return .proceed;
    }
};

fn buildFix(
    allocator: Allocator,
    tree: *const ast.Tree,
    call: ast.CallExpression,
    index: ast.NodeIndex,
    ctx: *const traverser.basic.Ctx,
) Allocator.Error!?core.Fix {
    const arguments = tree.extra(call.arguments);
    if (arguments.len != 2) return null;
    if (tree.data(arguments[0]) == .spread_element or tree.data(arguments[1]) == .spread_element) return null;
    if (hasCommentsInside(tree, tree.span(index))) return null;

    const base = unwrapParentheses(tree, arguments[0]);
    const exponent = unwrapParentheses(tree, arguments[1]);
    const base_span = tree.span(base);
    const exponent_span = tree.span(exponent);
    const parenthesize_base = doesBaseNeedParens(tree, base);
    const parenthesize_exponent = expressionPrecedence(tree, exponent) == .lower;
    const starts_expression_statement = isStartOfExpressionStatement(tree, index, ctx);
    const parenthesize_all = doesReplacementNeedParens(tree, index, ctx) or
        (starts_expression_statement and
            !parenthesize_base and
            startsStatementSensitiveExpression(tree.source[base_span.start..base_span.end]));
    const call_span = tree.span(index);
    const first_replacement_byte = if (parenthesize_all or parenthesize_base)
        '('
    else
        tree.source[base_span.start];
    const last_replacement_byte = if (parenthesize_all or parenthesize_exponent)
        ')'
    else
        tree.source[exponent_span.end - 1];
    var prefix: []const u8 = if (needsBoundarySpaceBefore(tree, call_span, first_replacement_byte)) " " else "";
    if (prefix.len == 0 and
        starts_expression_statement and
        !isDirectControlFlowBody(tree, index, ctx) and
        isContinuationByte(first_replacement_byte) and
        needsPrecedingSemicolon(tree, call_span.start))
    {
        prefix = ";";
    }
    const suffix = if (needsBoundarySpaceAfter(tree, call_span, last_replacement_byte)) " " else "";
    return .{
        .span = call_span,
        .replacement = try std.fmt.allocPrint(
            allocator,
            "{s}{s}{s}{s}{s}**{s}{s}{s}{s}{s}",
            .{
                prefix,
                if (parenthesize_all) "(" else "",
                if (parenthesize_base) "(" else "",
                tree.source[base_span.start..base_span.end],
                if (parenthesize_base) ")" else "",
                if (parenthesize_exponent) "(" else "",
                tree.source[exponent_span.start..exponent_span.end],
                if (parenthesize_exponent) ")" else "",
                if (parenthesize_all) ")" else "",
                suffix,
            },
        ),
    };
}

fn isDirectControlFlowBody(
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    ctx: *const traverser.basic.Ctx,
) bool {
    const start = tree.span(index).start;
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        if (tree.span(ancestor).start != start) return false;
        if (tree.data(ancestor) != .expression_statement) continue;

        const parent = ctx.path.ancestor(depth + 1) orelse return false;
        return switch (tree.data(parent)) {
            .if_statement => |statement| statement.consequent == ancestor or statement.alternate == ancestor,
            .for_statement => |statement| statement.body == ancestor,
            .for_in_statement => |statement| statement.body == ancestor,
            .for_of_statement => |statement| statement.body == ancestor,
            .while_statement => |statement| statement.body == ancestor,
            .do_while_statement => |statement| statement.body == ancestor,
            .with_statement => |statement| statement.body == ancestor,
            .labeled_statement => |statement| statement.body == ancestor,
            else => false,
        };
    }
    return false;
}

fn isStartOfExpressionStatement(
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    ctx: *const traverser.basic.Ctx,
) bool {
    const start = tree.span(index).start;
    var depth: usize = 1;
    while (ctx.path.ancestor(depth)) |ancestor| : (depth += 1) {
        if (tree.span(ancestor).start != start) return false;
        if (tree.data(ancestor) == .expression_statement) return true;
    }
    return false;
}

fn startsStatementSensitiveExpression(text: []const u8) bool {
    if (text.len == 0 or text[0] == '{') return true;
    return startsWithKeyword(text, "function") or
        startsWithKeyword(text, "class") or
        (startsWithKeyword(text, "async") and std.mem.indexOf(u8, text, "function") != null);
}

fn startsWithKeyword(text: []const u8, keyword: []const u8) bool {
    if (!std.mem.startsWith(u8, text, keyword)) return false;
    return text.len == keyword.len or !isIdentifierByte(text[keyword.len]);
}

fn isContinuationByte(byte: u8) bool {
    return byte == '(' or byte == '[' or byte == '/' or byte == '`';
}

fn needsPrecedingSemicolon(tree: *const ast.Tree, offset: u32) bool {
    const previous = previousSignificantByte(tree, offset) orelse return false;
    if (std.mem.indexOfAny(u8, tree.source[previous + 1 .. offset], "\r\n") == null) return false;

    const byte = tree.source[previous];
    if (byte == '}') return closingBraceRequiresSemicolon(tree, previous + 1);
    if (byte == ';' or byte == '{' or byte == ':') return false;
    if (isIdentifierByte(byte) and
        (uninitializedDeclarationEndsAt(tree, previous + 1) or
            typescriptTypeBoundaryEndsAt(tree, previous + 1))) return false;
    if ((byte == '\'' or byte == '"') and moduleDeclarationEndsAt(tree, previous + 1)) return false;
    if (previous > 0) {
        const pair = tree.source[previous - 1 .. previous + 1];
        if (std.mem.eql(u8, pair, "=>") or
            std.mem.eql(u8, pair, "++") or
            std.mem.eql(u8, pair, "--")) return false;
    }

    const word = previousWord(tree.source, previous);
    if (std.mem.eql(u8, word, "break") or
        std.mem.eql(u8, word, "continue") or
        std.mem.eql(u8, word, "debugger") or
        std.mem.eql(u8, word, "do") or
        std.mem.eql(u8, word, "else") or
        std.mem.eql(u8, word, "return") or
        std.mem.eql(u8, word, "yield")) return false;

    return true;
}

fn typescriptTypeBoundaryEndsAt(tree: *const ast.Tree, end: usize) bool {
    for (0..tree.nodes.len) |raw_index| {
        const index: ast.NodeIndex = @fromBackingInt(@intCast(raw_index));
        if (tree.span(index).end != end) continue;
        const data = tree.data(index);
        if (data.isTypeContext()) return true;
        switch (data) {
            .ts_type_alias_declaration => return true,
            .function => |function| if (function.type == .ts_declare_function) return true,
            else => {},
        }
    }
    return false;
}

fn moduleDeclarationEndsAt(tree: *const ast.Tree, end: usize) bool {
    for (0..tree.nodes.len) |raw_index| {
        const index: ast.NodeIndex = @fromBackingInt(@intCast(raw_index));
        if (tree.span(index).end != end) continue;
        switch (tree.data(index)) {
            .import_declaration, .export_named_declaration, .export_all_declaration => return true,
            else => {},
        }
    }
    return false;
}

fn uninitializedDeclarationEndsAt(tree: *const ast.Tree, end: usize) bool {
    for (0..tree.nodes.len) |raw_index| {
        const index: ast.NodeIndex = @fromBackingInt(@intCast(raw_index));
        if (tree.span(index).end != end) continue;
        switch (tree.data(index)) {
            .variable_declarator => |declarator| if (declarator.init == .null) return true,
            else => {},
        }
    }
    return false;
}

fn closingBraceRequiresSemicolon(tree: *const ast.Tree, end: usize) bool {
    for (0..tree.nodes.len) |raw_index| {
        const index: ast.NodeIndex = @fromBackingInt(@intCast(raw_index));
        if (tree.span(index).end != end) continue;
        switch (tree.data(index)) {
            .object_expression => return true,
            .function => |function| if (function.type == .function_expression) return true,
            .class => |class| if (class.type == .class_expression) return true,
            else => {},
        }
    }
    return false;
}

fn previousSignificantByte(tree: *const ast.Tree, offset: u32) ?usize {
    var cursor: usize = offset;
    while (cursor > 0) {
        while (cursor > 0 and std.ascii.isWhitespace(tree.source[cursor - 1])) cursor -= 1;
        if (cursor == 0) return null;

        var skipped_comment = false;
        for (tree.comments) |comment| {
            if (comment.span.end == cursor) {
                cursor = comment.span.start;
                skipped_comment = true;
                break;
            }
            if (comment.span.end > cursor) break;
        }
        if (!skipped_comment) return cursor - 1;
    }
    return null;
}

fn previousWord(source: []const u8, end: usize) []const u8 {
    if (!isIdentifierByte(source[end])) return "";
    var start = end;
    while (start > 0 and isIdentifierByte(source[start - 1])) start -= 1;
    return source[start .. end + 1];
}

fn needsBoundarySpaceBefore(tree: *const ast.Tree, span: ast.Span, first: u8) bool {
    if (span.start == 0 or std.ascii.isWhitespace(tree.source[span.start - 1])) return false;
    if (hasCommentEndingAt(tree, span.start)) return false;
    return bytesNeedSeparation(tree.source[span.start - 1], first);
}

fn needsBoundarySpaceAfter(tree: *const ast.Tree, span: ast.Span, last: u8) bool {
    if (span.end >= tree.source.len or std.ascii.isWhitespace(tree.source[span.end])) return false;
    if (hasCommentStartingAt(tree, span.end)) return false;
    return bytesNeedSeparation(last, tree.source[span.end]);
}

fn hasCommentEndingAt(tree: *const ast.Tree, offset: u32) bool {
    for (tree.comments) |comment| {
        if (comment.span.end == offset) return true;
        if (comment.span.end > offset) return false;
    }
    return false;
}

fn hasCommentStartingAt(tree: *const ast.Tree, offset: u32) bool {
    for (tree.comments) |comment| {
        if (comment.span.start == offset) return true;
        if (comment.span.start > offset) return false;
    }
    return false;
}

fn bytesNeedSeparation(left: u8, right: u8) bool {
    if (isIdentifierByte(left) and isIdentifierByte(right)) return true;
    return switch (left) {
        '+', '-' => right == left or right == '=',
        '/' => right == '/' or right == '*' or right == '=',
        '*' => right == '/' or right == '*' or right == '=',
        '<', '>' => right == left or right == '=',
        '&', '|', '^', '%', '!', '=' => right == left or right == '=',
        '?' => right == '?' or right == '=' or right == '.',
        '.' => std.ascii.isDigit(right),
        else => false,
    };
}

fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '$' or byte >= 0x80;
}

fn doesReplacementNeedParens(
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    ctx: *const traverser.basic.Ctx,
) bool {
    var child = index;
    var depth: usize = 1;
    var parent = ctx.path.ancestor(depth) orelse return false;

    if (tree.data(parent) == .chain_expression) {
        child = parent;
        depth += 1;
        parent = ctx.path.ancestor(depth) orelse return false;
    }

    return switch (tree.data(parent)) {
        .parenthesized_expression => false,
        .class => |class| class.super_class == child,
        .binary_expression => |binary| binary.operator == .exponent and binary.left == child,
        .unary_expression => |unary| unary.argument == child,
        .await_expression => |await_expression| await_expression.argument == child,
        .update_expression => |update| update.argument == child,
        .member_expression => |member| member.object == child,
        .call_expression => |call| call.callee == child,
        .new_expression => |new_expression| new_expression.callee == child,
        .tagged_template_expression => |tagged| tagged.tag == child,
        .ts_as_expression => |expression| expression.expression == child,
        .ts_satisfies_expression => |expression| expression.expression == child,
        .ts_type_assertion => |expression| expression.expression == child,
        .ts_non_null_expression => |expression| expression.expression == child,
        else => false,
    };
}

const RelativePrecedence = enum {
    lower,
    equal,
    higher,
};

fn doesBaseNeedParens(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(index)) {
        .await_expression, .unary_expression => true,
        else => expressionPrecedence(tree, index) != .higher,
    };
}

fn expressionPrecedence(tree: *const ast.Tree, index: ast.NodeIndex) RelativePrecedence {
    return switch (tree.data(index)) {
        .binary_expression => |binary| if (binary.operator == .exponent) .equal else .lower,
        .sequence_expression,
        .arrow_function_expression,
        .logical_expression,
        .conditional_expression,
        .assignment_expression,
        .yield_expression,
        .ts_as_expression,
        .ts_satisfies_expression,
        .ts_type_assertion,
        => .lower,
        else => .higher,
    };
}

fn unwrapParentheses(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    var current = index;
    while (tree.data(current) == .parenthesized_expression) {
        current = tree.data(current).parenthesized_expression.expression;
    }
    return current;
}

fn hasCommentsInside(tree: *const ast.Tree, span: ast.Span) bool {
    for (tree.comments) |comment| {
        if (comment.span.start >= span.end) return false;
        if (comment.span.start >= span.start and comment.span.end <= span.end) return true;
    }
    return false;
}

fn isGlobalMathPowCall(
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    callee: ast.NodeIndex,
) bool {
    const unwrapped = unwrapTransparent(tree, callee);
    const member = switch (tree.data(unwrapped)) {
        .member_expression => |member| member,
        else => return false,
    };

    const property_name = propertyName(tree, member) orelse return false;
    if (!std.mem.eql(u8, property_name, "pow")) return false;

    const object = unwrapTransparent(tree, member.object);
    const object_name = identifierReferenceName(tree, object) orelse return false;
    return std.mem.eql(u8, object_name, "Math") and isUnresolvedReference(symbol_table, object);
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

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
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

fn isUnresolvedReference(
    symbol_table: traverser.semantic.SymbolTable,
    node: ast.NodeIndex,
) bool {
    return symbol_table.isUnresolvedReference(node);
}
