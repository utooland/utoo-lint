const std = @import("std");
const parser = @import("parser");
const ast = parser.ast;
const SymbolTable = @import("../semantic_compat.zig").SymbolTable;
const SymbolId = parser.traverser.semantic.SymbolId;

// Track one operand's binding through the enclosing function. Nested functions
// have separate flow, and paths that return or throw do not join later paths.
pub fn Narrowing(comptime ValueType: type) type {
    return struct {
        const Self = @This();
        tree: *const ast.Tree,
        symbols: SymbolTable,
        symbol: SymbolId,
        reference: ast.NodeIndex,
        baseline: ValueType,

        pub fn run(self: Self) ValueType {
            var scope = self.reference;
            while (self.symbols.parentOf(scope)) |parent| {
                switch (self.tree.data(parent)) {
                    .function => |function| return if (self.contains(function.body)) self.at(function.body, self.baseline, 0) else self.baseline,
                    .arrow_function_expression => |arrow| return if (self.contains(arrow.body)) self.at(arrow.body, self.baseline, 0) else self.baseline,
                    .program => return self.at(parent, self.baseline, 0),
                    else => scope = parent,
                }
            }
            return self.baseline;
        }

        fn contains(self: Self, node: ast.NodeIndex) bool {
            if (node == .null) return false;
            const span = self.tree.span(node);
            const reference = self.tree.span(self.reference);
            return span.start <= reference.start and reference.end <= span.end;
        }

        fn atList(self: Self, nodes: []const ast.NodeIndex, initial: ValueType, depth: usize) ValueType {
            var state = initial;
            for (nodes) |node| {
                if (self.contains(node)) return self.at(node, state, depth + 1);
                state = self.after(node, state, depth + 1) orelse return self.baseline;
            }
            return state;
        }

        fn at(self: Self, node: ast.NodeIndex, state: ValueType, depth: usize) ValueType {
            if (node == .null or depth >= 64 or node == self.reference) return state;
            return switch (self.tree.data(node)) {
                .program => |value| self.atList(self.tree.extra(value.body), state, depth),
                .function_body => |value| self.atList(self.tree.extra(value.body), state, depth),
                .block_statement => |value| self.atList(self.tree.extra(value.body), state, depth),
                .if_statement => |value| blk: {
                    if (self.contains(value.@"test")) break :blk self.at(value.@"test", state, depth + 1);
                    const tested = self.after(value.@"test", state, depth + 1) orelse state;
                    const yes = self.contains(value.consequent);
                    break :blk self.at(if (yes) value.consequent else value.alternate, self.condition(value.@"test", yes, tested, depth + 1), depth + 1);
                },
                .conditional_expression => |value| blk: {
                    if (self.contains(value.@"test")) break :blk self.at(value.@"test", state, depth + 1);
                    const tested = self.after(value.@"test", state, depth + 1) orelse state;
                    const yes = self.contains(value.consequent);
                    break :blk self.at(if (yes) value.consequent else value.alternate, self.condition(value.@"test", yes, tested, depth + 1), depth + 1);
                },
                .logical_expression => |value| blk: {
                    if (self.contains(value.left)) break :blk self.at(value.left, state, depth + 1);
                    const left = self.after(value.left, state, depth + 1) orelse state;
                    const narrowed = if (value.operator == .nullish_coalescing) left else self.condition(value.left, value.operator == .@"and", left, depth + 1);
                    break :blk self.at(value.right, narrowed, depth + 1);
                },
                .while_statement => |value| self.atLoop(node, value.@"test", value.body, state, depth),
                .for_statement => |value| if (self.contains(value.init)) self.at(value.init, state, depth + 1) else self.atLoop(node, value.@"test", value.body, state, depth),
                .for_of_statement => |value| self.at(value.body, if (self.hasWrite(node, self.tree.span(node).end)) self.baseline else state, depth + 1),
                .for_in_statement => |value| self.at(value.body, if (self.hasWrite(node, self.tree.span(node).end)) self.baseline else state, depth + 1),
                .do_while_statement => |value| blk: {
                    const entry = if (self.hasWrite(node, self.tree.span(node).end)) self.baseline else state;
                    break :blk if (self.contains(value.body)) self.at(value.body, entry, depth + 1) else self.at(value.@"test", self.after(value.body, entry, depth + 1) orelse entry, depth + 1);
                },
                .binary_expression => |value| if (self.contains(value.left)) self.at(value.left, state, depth + 1) else self.at(value.right, self.after(value.left, state, depth + 1) orelse state, depth + 1),
                .sequence_expression => |value| self.atList(self.tree.extra(value.expressions), state, depth),
                .expression_statement => |value| self.at(value.expression, state, depth + 1),
                .return_statement => |value| self.at(value.argument, state, depth + 1),
                .throw_statement => |value| self.at(value.argument, state, depth + 1),
                .parenthesized_expression => |value| self.at(value.expression, state, depth + 1),
                .variable_declaration => |value| self.atList(self.tree.extra(value.declarators), state, depth),
                .variable_declarator => |value| self.at(value.init, state, depth + 1),
                .assignment_expression => |value| self.at(value.right, state, depth + 1),
                .call_expression => |value| self.atList(self.tree.extra(value.arguments), self.after(value.callee, state, depth + 1) orelse state, depth),
                else => if (self.hasWrite(node, self.tree.span(self.reference).start)) self.baseline else state,
            };
        }

        fn atLoop(self: Self, node: ast.NodeIndex, condition_node: ast.NodeIndex, body: ast.NodeIndex, state: ValueType, depth: usize) ValueType {
            // A write later in the loop can precede this reference on the next
            // iteration. Reapply only the loop's own guard after invalidation.
            const entry = if (self.hasWrite(node, self.tree.span(node).end)) self.baseline else state;
            if (self.contains(condition_node)) return self.at(condition_node, entry, depth + 1);
            const tested = self.after(condition_node, entry, depth + 1) orelse entry;
            return self.at(body, self.condition(condition_node, true, tested, depth + 1), depth + 1);
        }

        fn join(self: Self, left: ?ValueType, right: ?ValueType) ?ValueType {
            if (left == null) return right;
            if (right == null) return left;
            return if (left.? == right.?) left else self.baseline;
        }

        fn afterList(self: Self, nodes: []const ast.NodeIndex, initial: ValueType, depth: usize) ?ValueType {
            var state = initial;
            for (nodes) |node| state = self.after(node, state, depth + 1) orelse return null;
            return state;
        }

        fn after(self: Self, node: ast.NodeIndex, state: ValueType, depth: usize) ?ValueType {
            if (node == .null) return state;
            if (depth >= 64) return self.baseline;
            return switch (self.tree.data(node)) {
                .function_body => |value| self.afterList(self.tree.extra(value.body), state, depth),
                .block_statement => |value| self.afterList(self.tree.extra(value.body), state, depth),
                .if_statement => |value| blk: {
                    const tested = self.after(value.@"test", state, depth + 1) orelse state;
                    break :blk self.join(self.after(value.consequent, self.condition(value.@"test", true, tested, depth + 1), depth + 1), self.after(value.alternate, self.condition(value.@"test", false, tested, depth + 1), depth + 1));
                },
                .return_statement, .throw_statement => null,
                .function, .arrow_function_expression => state,
                .expression_statement => |value| self.after(value.expression, state, depth + 1),
                .parenthesized_expression => |value| self.after(value.expression, state, depth + 1),
                .sequence_expression => |value| self.afterList(self.tree.extra(value.expressions), state, depth),
                .variable_declaration => |value| self.afterList(self.tree.extra(value.declarators), state, depth),
                .variable_declarator => |value| self.after(value.init, state, depth + 1),
                else => if (self.hasWrite(node, self.tree.span(node).end)) self.baseline else state,
            };
        }

        fn isBinding(self: Self, node: ast.NodeIndex) bool {
            if (node == .null) return false;
            return self.symbols.symbolOf(node) == self.symbol;
        }

        fn condition(self: Self, node: ast.NodeIndex, truth: bool, state: ValueType, depth: usize) ValueType {
            if (node == .null or depth >= 64) return state;
            switch (self.tree.data(node)) {
                .parenthesized_expression => |value| return self.condition(value.expression, truth, state, depth + 1),
                .unary_expression => |value| if (value.operator == .logical_not) return self.condition(value.argument, !truth, state, depth + 1),
                .logical_expression => |value| {
                    if ((value.operator == .@"and" and truth) or (value.operator == .@"or" and !truth)) {
                        const left = self.condition(value.left, truth, state, depth + 1);
                        const right = self.after(value.right, left, depth + 1) orelse left;
                        return self.condition(value.right, truth, right, depth + 1);
                    }
                },
                .binary_expression => |value| {
                    const equality = switch (value.operator) {
                        .strict_equal, .equal => true,
                        .strict_not_equal, .not_equal => false,
                        else => return state,
                    };
                    if (equality != truth) return state;
                    const narrowed = self.typeofComparison(value.left, value.right) orelse self.typeofComparison(value.right, value.left);
                    return narrowed orelse state;
                },
                else => {},
            }
            return state;
        }

        fn typeofComparison(self: Self, left: ast.NodeIndex, right: ast.NodeIndex) ?ValueType {
            const unary = switch (self.tree.data(left)) {
                .unary_expression => |value| value,
                else => return null,
            };
            if (unary.operator != .typeof or !self.isBinding(unary.argument)) return null;
            const literal = switch (self.tree.data(right)) {
                .string_literal => |value| self.tree.string(value.value),
                else => return null,
            };
            if (std.mem.eql(u8, literal, "number")) return .number;
            if (std.mem.eql(u8, literal, "string")) return .string;
            if (std.mem.eql(u8, literal, "bigint")) return .bigint;
            if (std.mem.eql(u8, literal, "boolean")) return .boolean;
            return null;
        }

        // Unsupported flow constructs conservatively invalidate narrowing on a
        // write to this symbol, including destructuring targets. Ignore bodies
        // of nested functions: declaring one does not execute its writes.
        fn hasWrite(self: Self, container: ast.NodeIndex, before: u32) bool {
            const span = self.tree.span(container);
            for (self.symbols.model.uses(self.symbol)) |reference_id| {
                if (!self.symbols.isWriteReference(reference_id)) continue;
                const reference = self.symbols.getReference(reference_id);
                const ref_span = self.tree.span(reference.node);
                if (ref_span.start < span.start or ref_span.end > @min(span.end, before)) continue;
                var parent = reference.node;
                var write: ast.NodeIndex = .null;
                var nested = false;
                while (parent != container) {
                    parent = self.symbols.parentOf(parent) orelse break;
                    switch (self.tree.data(parent)) {
                        .function, .arrow_function_expression => {
                            nested = true;
                            break;
                        },
                        .assignment_expression, .update_expression, .for_of_statement, .for_in_statement => if (write == .null) {
                            write = parent;
                        },
                        else => {},
                    }
                }
                if (!nested and write != .null and self.tree.span(write).end <= before) return true;
            }
            return false;
        }
    };
}
