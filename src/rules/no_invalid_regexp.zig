const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-invalid-regexp";

pub const Options = struct {
    allow_constructor_flags: core.NoInvalidRegexpAllowConstructorFlags = .{},
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    _: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    return runWithOptions(allocator, diagnostics, tree, .{});
}

pub fn runWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    options: Options,
) Allocator.Error!void {
    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .options = options,
    };

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    options: Options,

    pub fn enter_call_expression(
        self: *Visitor,
        call: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.check(ctx.tree, call.callee, call.arguments, index);
        return .proceed;
    }

    pub fn enter_new_expression(
        self: *Visitor,
        expression: ast.NewExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.check(ctx.tree, expression.callee, expression.arguments, index);
        return .proceed;
    }

    fn check(
        self: *Visitor,
        tree: *const ast.Tree,
        callee: ast.NodeIndex,
        argument_range: ast.IndexRange,
        index: ast.NodeIndex,
    ) Allocator.Error!void {
        const arguments = tree.extra(argument_range);
        if (arguments.len == 0) return;
        if (!isRegExpReferenceName(tree, callee)) return;

        const flags = if (arguments.len >= 2) stringLiteralValue(tree, arguments[1]) else null;
        if (flags) |value| {
            if (validateFlags(value, self.options.allow_constructor_flags)) |message| {
                try self.addDiagnostic(tree, index, message);
                return;
            }
        }

        const pattern = stringLiteralValue(tree, arguments[0]) orelse return;
        const unicode_sets = if (flags) |value| std.mem.indexOfScalar(u8, value, 'v') != null else false;
        const message = (try validatePattern(self.allocator, pattern, unicode_sets)) orelse return;
        try self.addDiagnostic(tree, index, message);
    }

    fn addDiagnostic(
        self: *Visitor,
        tree: *const ast.Tree,
        index: ast.NodeIndex,
        message: []const u8,
    ) Allocator.Error!void {
        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .warning,
            id,
            tree.span(index),
            "Invalid regular expression: {s}.",
            .{message},
        );
    }
};

fn validateFlags(flags: []const u8, allow_constructor_flags: core.NoInvalidRegexpAllowConstructorFlags) ?[]const u8 {
    var seen: u32 = 0;

    for (flags) |flag| {
        if (allow_constructor_flags.contains(flag)) continue;

        const valid = switch (flag) {
            'd', 'g', 'i', 'm', 's', 'u', 'v', 'y' => true,
            else => false,
        };
        if (!valid) return "invalid flags";

        const bit: u5 = @intCast(flag - 'a');
        if ((seen & (@as(u32, 1) << bit)) != 0) return "duplicate flags";
        seen |= @as(u32, 1) << bit;
    }

    const u_bit = @as(u32, 1) << ('u' - 'a');
    const v_bit = @as(u32, 1) << ('v' - 'a');
    if ((seen & u_bit) != 0 and (seen & v_bit) != 0) return "incompatible flags";

    return null;
}

fn validatePattern(allocator: Allocator, pattern: []const u8, unicode_sets: bool) Allocator.Error!?[]const u8 {
    var group_depth: usize = 0;
    var class_depth: usize = 0;
    var escaped = false;

    for (pattern) |char| {
        if (escaped) {
            escaped = false;
            continue;
        }

        if (char == '\\') {
            escaped = true;
            continue;
        }

        if (class_depth != 0) {
            if (char == ']') class_depth -= 1;
            if (unicode_sets and char == '[') class_depth += 1;
            continue;
        }

        switch (char) {
            '[' => class_depth = 1,
            '(' => group_depth += 1,
            ')' => {
                if (group_depth == 0) return "unmatched ')'";
                group_depth -= 1;
            },
            else => {},
        }
    }

    if (escaped) return "trailing escape";
    if (class_depth != 0) return "unterminated character class";
    if (group_depth != 0) return "unterminated group";

    return validateCaptureNames(allocator, pattern, unicode_sets);
}

// Paths are immutable: starting another alternative creates a new path entry,
// so captures retain the alternative in which they were declared.
const DisjunctionPath = struct {
    parent: ?usize,
    depth: usize,
    disjunction: usize,
    alternative: usize,
};

const NamedCapture = struct {
    path: usize,
    previous: ?usize,
};

fn validateCaptureNames(allocator: Allocator, pattern: []const u8, unicode_sets: bool) Allocator.Error!?[]const u8 {
    if (std.mem.indexOf(u8, pattern, "(?<") == null) return null;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var paths: std.ArrayList(DisjunctionPath) = .empty;
    try paths.append(scratch, .{ .parent = null, .depth = 0, .disjunction = 0, .alternative = 0 });
    var captures: std.ArrayList(NamedCapture) = .empty;
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    var current: usize = 0;
    var class_depth: usize = 0;
    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        const char = pattern[index];
        if (char == '\\') {
            index += 1;
            continue;
        }
        if (class_depth != 0) {
            if (char == ']') class_depth -= 1;
            if (unicode_sets and char == '[') class_depth += 1;
            continue;
        }
        switch (char) {
            '[' => class_depth = 1,
            '(' => {
                if (std.mem.startsWith(u8, pattern[index..], "(?<") and index + 3 < pattern.len and
                    pattern[index + 3] != '=' and pattern[index + 3] != '!')
                {
                    const name_start = index + 3;
                    const name_end = std.mem.indexOfScalarPos(u8, pattern, name_start, '>') orelse return "invalid capture group name";
                    const name = (try decodeCaptureName(scratch, pattern[name_start..name_end])) orelse return "invalid capture group name";
                    if (!parser.lexical.isIdentifierName(name)) return "invalid capture group name";
                    const entry = try names.getOrPut(scratch, name);
                    const previous = if (entry.found_existing) entry.value_ptr.* else null;
                    var earlier = previous;
                    while (earlier) |capture| {
                        if (mightBothParticipate(paths.items, captures.items[capture].path, current)) return "duplicate capture group name";
                        earlier = captures.items[capture].previous;
                    }
                    entry.value_ptr.* = captures.items.len;
                    try captures.append(scratch, .{ .path = current, .previous = previous });
                    index = name_end;
                }
                const child = paths.items.len;
                try paths.append(scratch, .{ .parent = current, .depth = paths.items[current].depth + 1, .disjunction = child, .alternative = 0 });
                current = child;
            },
            ')' => current = paths.items[current].parent orelse return "unmatched ')'",
            '|' => {
                var next = paths.items[current];
                next.alternative += 1;
                current = paths.items.len;
                try paths.append(scratch, next);
            },
            else => {},
        }
    }
    return null;
}

fn mightBothParticipate(paths: []const DisjunctionPath, lhs: usize, rhs: usize) bool {
    var left = lhs;
    var right = rhs;
    while (paths[left].depth > paths[right].depth) left = paths[left].parent.?;
    while (paths[right].depth > paths[left].depth) right = paths[right].parent.?;
    while (true) {
        if (paths[left].disjunction == paths[right].disjunction and paths[left].alternative != paths[right].alternative) return false;
        left = paths[left].parent orelse return true;
        right = paths[right].parent.?;
    }
}

fn decodeCaptureName(allocator: Allocator, raw: []const u8) Allocator.Error!?[]const u8 {
    if (raw.len == 0) return null;
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return raw;
    var name: std.ArrayList(u8) = .empty;
    var index: usize = 0;
    while (index < raw.len) {
        if (raw[index] != '\\') {
            try name.append(allocator, raw[index]);
            index += 1;
            continue;
        }
        var code_point = parseNameEscape(raw, &index) orelse return null;
        if (code_point >= 0xd800 and code_point <= 0xdbff) {
            const trail = parseNameEscape(raw, &index) orelse return null;
            if (trail < 0xdc00 or trail > 0xdfff) return null;
            code_point = 0x10000 + ((code_point - 0xd800) << 10) + trail - 0xdc00;
        }
        var bytes: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(code_point, &bytes) catch return null;
        try name.appendSlice(allocator, bytes[0..length]);
    }
    return name.items;
}

fn parseNameEscape(raw: []const u8, index: *usize) ?u21 {
    if (!std.mem.startsWith(u8, raw[index.*..], "\\u")) return null;
    index.* += 2;
    if (index.* >= raw.len) return null;
    const braced = raw[index.*] == '{';
    if (braced) index.* += 1;
    const start = index.*;
    const end = if (braced) std.mem.indexOfScalarPos(u8, raw, start, '}') orelse return null else start + 4;
    if (end > raw.len or end == start) return null;
    const value = std.fmt.parseInt(u21, raw[start..end], 16) catch return null;
    if (value > 0x10ffff) return null;
    index.* = end + @intFromBool(braced);
    return value;
}

fn isRegExpReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const unwrapped = unwrapTransparent(tree, index);
    const name = identifierReferenceName(tree, unwrapped) orelse return false;
    return std.mem.eql(u8, name, "RegExp");
}

fn stringLiteralValue(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .string_literal => |literal| tree.string(literal.value),
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

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}
