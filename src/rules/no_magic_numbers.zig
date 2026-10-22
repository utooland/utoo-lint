const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-magic-numbers";

pub const Options = struct {
    detect_objects: bool = false,
    enforce_const: bool = false,
    ignore: ?*const core.NoMagicNumbersIgnoreValues = null,
    ignore_array_indexes: bool = false,
    ignore_default_values: bool = false,
    ignore_class_field_initial_values: bool = false,
    ignore_enums: bool = false,
    ignore_numeric_literal_types: bool = false,
    ignore_readonly_class_properties: bool = false,
    ignore_type_indexes: bool = false,
};

const Sign = enum {
    none,
    positive,
    negative,

    fn text(self: Sign) []const u8 {
        return switch (self) {
            .none => "",
            .positive => "+",
            .negative => "-",
        };
    }
};

const FullNumber = struct {
    index: ast.NodeIndex,
    depth: usize,
    sign: Sign,
};

const Parent = struct {
    index: ast.NodeIndex,
    depth: usize,
};

pub fn checkNumericLiteral(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    literal: ast.NumericLiteral,
    index: ast.NodeIndex,
    ctx: *traverser.basic.Ctx,
    options: Options,
) Allocator.Error!void {
    const full = fullNumber(tree, index, ctx);
    const unsigned_value = literal.value(tree);
    const value = if (full.sign == .negative) -unsigned_value else unsigned_value;
    const raw = tree.string(literal.raw);

    if (options.ignore) |ignore| {
        if (ignore.containsNumber(value)) return;
    }
    if (shouldIgnore(tree, ctx, full, .{ .number = value }, options)) return;
    try checkParentAndReport(allocator, diagnostics, tree, ctx, full, raw, "", options);
}

pub fn checkBigIntLiteral(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    literal: ast.BigIntLiteral,
    index: ast.NodeIndex,
    ctx: *traverser.basic.Ctx,
    options: Options,
) Allocator.Error!void {
    const full = fullNumber(tree, index, ctx);
    const raw = tree.string(literal.raw);

    if (options.ignore) |ignore| {
        var canonical_buffer: [core.max_no_magic_numbers_bigint_len]u8 = undefined;
        if (canonicalBigInt(raw, full.sign == .negative, &canonical_buffer)) |canonical| {
            if (ignore.containsBigInt(canonical)) return;
        }
    }
    if (shouldIgnore(tree, ctx, full, .{ .bigint = raw }, options)) return;
    try checkParentAndReport(allocator, diagnostics, tree, ctx, full, raw, "n", options);
}

const NumberValue = union(enum) {
    number: f64,
    bigint: []const u8,
};

fn shouldIgnore(
    tree: *const ast.Tree,
    ctx: *traverser.basic.Ctx,
    full: FullNumber,
    value: NumberValue,
    options: Options,
) bool {
    const parent = structuralParent(tree, ctx, full.depth) orelse return false;

    if (options.ignore_default_values and isDefaultValue(tree, parent, full.index)) return true;
    if (options.ignore_class_field_initial_values and isClassFieldInitialValue(tree, parent, full.index)) return true;
    if (options.ignore_enums and tree.data(parent.index) == .ts_enum_member) return true;
    if (options.ignore_numeric_literal_types and isNumericLiteralType(tree, ctx, full.depth)) return true;
    if (options.ignore_type_indexes and isTypeIndex(tree, ctx, full.depth)) return true;
    if (options.ignore_readonly_class_properties and isReadonlyClassProperty(tree, parent)) return true;
    if (isParseIntRadix(tree, parent, full.index)) return true;
    if (isJsxNode(tree.data(parent.index))) return true;
    if (options.ignore_array_indexes and isArrayIndex(tree, parent, full, value)) return true;
    return false;
}

fn checkParentAndReport(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    ctx: *traverser.basic.Ctx,
    full: FullNumber,
    raw: []const u8,
    suffix: []const u8,
    options: Options,
) Allocator.Error!void {
    const parent = structuralParent(tree, ctx, full.depth) orelse return;

    if (tree.data(parent.index) == .variable_declarator) {
        if (!options.enforce_const) return;
        const declaration = ancestorAfter(tree, ctx, parent.depth, false) orelse return;
        const is_const = switch (tree.data(declaration.index)) {
            .variable_declaration => |value| value.kind == .@"const",
            else => false,
        };
        if (is_const) return;

        try core.addDiagnostic(
            allocator,
            diagnostics,
            .warning,
            id,
            "Number constants declarations must use 'const'.",
            tree.span(full.index),
        );
        return;
    }

    if (!options.detect_objects) {
        switch (tree.data(parent.index)) {
            .object_expression, .object_property => return,
            .assignment_expression => |assignment| {
                if (!isIdentifierReference(tree, unwrapTransparent(tree, assignment.left))) return;
            },
            else => {},
        }
    }

    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        .warning,
        id,
        tree.span(full.index),
        "No magic number: {s}{s}{s}.",
        .{ full.sign.text(), raw, suffix },
    );
}

fn fullNumber(tree: *const ast.Tree, index: ast.NodeIndex, ctx: *traverser.basic.Ctx) FullNumber {
    var depth: usize = 0;

    while (ctx.path.ancestor(depth + 1)) |parent| {
        switch (tree.data(parent)) {
            .parenthesized_expression => {
                depth += 1;
                continue;
            },
            .unary_expression => |unary| {
                if ((unary.operator == .positive or unary.operator == .negate) and
                    unwrapTransparent(tree, unary.argument) == index)
                {
                    return .{
                        .index = parent,
                        .depth = depth + 1,
                        .sign = if (unary.operator == .negate) .negative else .positive,
                    };
                }
            },
            else => {},
        }
        break;
    }

    return .{ .index = index, .depth = 0, .sign = .none };
}

fn structuralParent(tree: *const ast.Tree, ctx: *traverser.basic.Ctx, depth: usize) ?Parent {
    return ancestorAfter(tree, ctx, depth, false);
}

fn ancestorAfter(
    tree: *const ast.Tree,
    ctx: *traverser.basic.Ctx,
    start_depth: usize,
    skip_type_parentheses: bool,
) ?Parent {
    var depth = start_depth + 1;
    while (ctx.path.ancestor(depth)) |index| : (depth += 1) {
        switch (tree.data(index)) {
            .parenthesized_expression, .chain_expression => continue,
            .ts_parenthesized_type => if (skip_type_parentheses) continue,
            else => {},
        }
        return .{ .index = index, .depth = depth };
    }
    return null;
}

fn isDefaultValue(tree: *const ast.Tree, parent: Parent, full: ast.NodeIndex) bool {
    return switch (tree.data(parent.index)) {
        .assignment_pattern => |pattern| unwrapTransparent(tree, pattern.right) == full,
        else => false,
    };
}

fn isClassFieldInitialValue(tree: *const ast.Tree, parent: Parent, full: ast.NodeIndex) bool {
    return switch (tree.data(parent.index)) {
        .property_definition => |property| unwrapTransparent(tree, property.value) == full,
        else => false,
    };
}

fn isReadonlyClassProperty(tree: *const ast.Tree, parent: Parent) bool {
    return switch (tree.data(parent.index)) {
        .property_definition => |property| property.readonly,
        else => false,
    };
}

fn isNumericLiteralType(tree: *const ast.Tree, ctx: *traverser.basic.Ctx, full_depth: usize) bool {
    var ancestor = ancestorAfter(tree, ctx, full_depth, true) orelse return false;
    while (true) {
        const parent = ancestorAfter(tree, ctx, ancestor.depth, true) orelse return false;
        if (tree.data(parent.index) == .ts_union_type) {
            ancestor = parent;
            continue;
        }
        return tree.data(parent.index) == .ts_type_alias_declaration;
    }
}

fn isTypeIndex(tree: *const ast.Tree, ctx: *traverser.basic.Ctx, full_depth: usize) bool {
    var ancestor = ancestorAfter(tree, ctx, full_depth, true) orelse return false;
    while (true) {
        const parent = ancestorAfter(tree, ctx, ancestor.depth, true) orelse return false;
        switch (tree.data(parent.index)) {
            .ts_union_type, .ts_intersection_type => ancestor = parent,
            .ts_indexed_access_type => return true,
            else => return false,
        }
    }
}

fn isParseIntRadix(tree: *const ast.Tree, parent: Parent, full: ast.NodeIndex) bool {
    const call = switch (tree.data(parent.index)) {
        .call_expression => |call| call,
        else => return false,
    };
    const arguments = tree.extra(call.arguments);
    if (arguments.len < 2 or unwrapTransparent(tree, arguments[1]) != full) return false;

    const callee = unwrapTransparent(tree, call.callee);
    if (identifierName(tree, callee)) |name| return std.mem.eql(u8, name, "parseInt");

    const member = switch (tree.data(callee)) {
        .member_expression => |member| member,
        else => return false,
    };
    if (member.computed) return false;
    const property = identifierName(tree, unwrapTransparent(tree, member.property)) orelse return false;
    if (!std.mem.eql(u8, property, "parseInt")) return false;
    const object = identifierName(tree, unwrapTransparent(tree, member.object)) orelse return false;
    return std.mem.eql(u8, object, "Number");
}

fn isArrayIndex(
    tree: *const ast.Tree,
    parent: Parent,
    full: FullNumber,
    value: NumberValue,
) bool {
    const member = switch (tree.data(parent.index)) {
        .member_expression => |member| member,
        else => return false,
    };
    if (!member.computed or unwrapTransparent(tree, member.property) != full.index) return false;

    return switch (value) {
        .number => |number| std.math.isFinite(number) and
            number == @floor(number) and
            number >= 0 and
            number < 4294967295.0,
        .bigint => |raw| bigintArrayIndex(raw, full.sign),
    };
}

fn bigintArrayIndex(raw: []const u8, sign: Sign) bool {
    const parsed = parseSmallBigInt(raw, 4294967295) orelse return false;
    if (sign == .negative and parsed != 0) return false;
    return parsed < 4294967295;
}

fn parseSmallBigInt(raw_with_suffix: []const u8, limit: u64) ?u64 {
    var raw = raw_with_suffix;
    if (raw.len > 0 and (raw[raw.len - 1] == 'n' or raw[raw.len - 1] == 'N')) raw = raw[0 .. raw.len - 1];
    const radix: u8 = if (raw.len >= 2 and raw[0] == '0') switch (raw[1]) {
        'x', 'X' => 16,
        'o', 'O' => 8,
        'b', 'B' => 2,
        else => 10,
    } else 10;
    if (radix != 10) raw = raw[2..];

    var value: u64 = 0;
    var saw_digit = false;
    for (raw) |char| {
        if (char == '_') continue;
        const digit = std.fmt.charToDigit(char, radix) catch return null;
        saw_digit = true;
        if (value > (limit -| digit) / radix) return null;
        value = value * radix + digit;
    }
    return if (saw_digit) value else null;
}

fn canonicalBigInt(raw_with_suffix: []const u8, negative: bool, output: []u8) ?[]const u8 {
    var raw = raw_with_suffix;
    if (raw.len > 0 and (raw[raw.len - 1] == 'n' or raw[raw.len - 1] == 'N')) raw = raw[0 .. raw.len - 1];
    const radix: u8 = if (raw.len >= 2 and raw[0] == '0') switch (raw[1]) {
        'x', 'X' => 16,
        'o', 'O' => 8,
        'b', 'B' => 2,
        else => 10,
    } else 10;
    if (radix != 10) raw = raw[2..];

    var digits: [core.max_no_magic_numbers_bigint_len]u8 = @splat(0);
    var digits_len: usize = 1;
    var saw_digit = false;

    for (raw) |char| {
        if (char == '_') continue;
        const source_digit = std.fmt.charToDigit(char, radix) catch return null;
        saw_digit = true;
        var carry: u16 = source_digit;
        for (digits[0..digits_len]) |*digit| {
            const value: u16 = @as(u16, digit.*) * radix + carry;
            digit.* = @intCast(value % 10);
            carry = value / 10;
        }
        while (carry > 0) {
            if (digits_len >= digits.len) return null;
            digits[digits_len] = @intCast(carry % 10);
            digits_len += 1;
            carry /= 10;
        }
    }
    if (!saw_digit) return null;
    while (digits_len > 1 and digits[digits_len - 1] == 0) digits_len -= 1;

    const is_zero = digits_len == 1 and digits[0] == 0;
    const offset: usize = @intFromBool(negative and !is_zero);
    if (digits_len + offset > output.len) return null;
    if (offset == 1) output[0] = '-';
    for (0..digits_len) |index| output[offset + index] = '0' + digits[digits_len - 1 - index];
    return output[0 .. digits_len + offset];
}

fn isJsxNode(data: ast.NodeData) bool {
    return std.mem.startsWith(u8, @tagName(std.meta.activeTag(data)), "jsx_");
}

fn isIdentifierReference(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return tree.data(index) == .identifier_reference;
}

fn identifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        .identifier_name => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn unwrapTransparent(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    var current = index;
    while (current != .null) {
        switch (tree.data(current)) {
            .parenthesized_expression => |parenthesized| current = parenthesized.expression,
            .chain_expression => |chain| current = chain.expression,
            else => return current,
        }
    }
    return current;
}

test "normalizes bigint values across radices" {
    var buffer: [core.max_no_magic_numbers_bigint_len]u8 = undefined;
    try std.testing.expectEqualStrings("171", canonicalBigInt("0xAB", false, &buffer).?);
    try std.testing.expectEqualStrings("-8", canonicalBigInt("0b1000", true, &buffer).?);
    try std.testing.expectEqualStrings("0", canonicalBigInt("0", true, &buffer).?);
}
