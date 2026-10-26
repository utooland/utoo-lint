const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "@typescript-eslint/ban-types";

const BannedType = struct {
    name: []const u8,
    message: []const u8,
    fix: ?[]const u8 = null,
};

pub fn checkTypeReference(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    reference: ast.TSTypeReference,
    config: core.TypescriptEslintBanTypesConfig,
) Allocator.Error!void {
    const name = typeName(tree, reference.type_name) orelse return;
    const banned = bannedType(name, &config) orelse return;

    try report(allocator, diagnostics, tree, tree.span(reference.type_name), banned, reference.type_arguments == .null, &config);
}

pub fn checkTypeLiteral(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    type_literal: ast.TSTypeLiteral,
    index: ast.NodeIndex,
    config: core.TypescriptEslintBanTypesConfig,
) Allocator.Error!void {
    if (type_literal.members.len != 0) return;
    const banned = bannedType("{}", &config) orelse return;

    try report(allocator, diagnostics, tree, tree.span(index), banned, true, &config);
}

pub fn checkObjectKeyword(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    config: core.TypescriptEslintBanTypesConfig,
) Allocator.Error!void {
    const banned = bannedType("object", &config) orelse return;

    try report(allocator, diagnostics, tree, tree.span(index), banned, true, &config);
}

fn bannedType(name: []const u8, config: *const core.TypescriptEslintBanTypesConfig) ?BannedType {
    if (config.custom.messageFor(name)) |message| return .{
        .name = name,
        .message = message,
        .fix = config.custom.fixFor(name),
    };
    if (config.disabled.contains(name)) return null;
    if (!config.extend_defaults) return null;
    return defaultBannedType(name);
}

fn defaultBannedType(name: []const u8) ?BannedType {
    if (std.mem.eql(u8, name, "String")) return .{
        .name = "String",
        .message = "Use string instead",
        .fix = "string",
    };
    if (std.mem.eql(u8, name, "Boolean")) return .{
        .name = "Boolean",
        .message = "Use boolean instead",
        .fix = "boolean",
    };
    if (std.mem.eql(u8, name, "Number")) return .{
        .name = "Number",
        .message = "Use number instead",
        .fix = "number",
    };
    if (std.mem.eql(u8, name, "Symbol")) return .{
        .name = "Symbol",
        .message = "Use symbol instead",
        .fix = "symbol",
    };
    if (std.mem.eql(u8, name, "BigInt")) return .{
        .name = "BigInt",
        .message = "Use bigint instead",
        .fix = "bigint",
    };
    if (std.mem.eql(u8, name, "Function")) return .{
        .name = "Function",
        .message = "The `Function` type accepts any function-like value.\n" ++
            "It provides no type safety when calling the function, which can be a common source of bugs.\n" ++
            "It also accepts things like class declarations, which will throw at runtime as they will not be called with `new`.\n" ++
            "If you are expecting the function to accept certain arguments, you should explicitly define the function shape.",
    };
    if (std.mem.eql(u8, name, "Object")) return .{
        .name = "Object",
        .message = "The `Object` type actually means \"any non-nullish value\", so it is marginally better than `unknown`.\n" ++
            "- If you want a type meaning \"any object\", you probably want `object` instead.\n" ++
            "- If you want a type meaning \"any value\", you probably want `unknown` instead.\n" ++
            "- If you really want a type meaning \"any non-nullish value\", you probably want `NonNullable<unknown>` instead.",
    };

    return null;
}

fn typeName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;

    return switch (tree.data(index)) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        .identifier_name => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn report(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    span: ast.Span,
    banned: BannedType,
    can_fix: bool,
    config: *const core.TypescriptEslintBanTypesConfig,
) Allocator.Error!void {
    const message = try std.fmt.allocPrint(allocator, "Don't use `{s}` as a type. {s}", .{ banned.name, banned.message });
    defer allocator.free(message);
    var replacement: ?[]u8 = null;
    defer if (replacement) |text| allocator.free(text);
    if (can_fix and !hasComments(tree, span)) {
        var checked = CheckedFixTypes{};
        if (banned.fix) |text| replacement = try safeReplacement(allocator, text, config, &.{banned.name}, &checked);
    }
    const fixes: []const core.Fix = if (replacement) |text| &.{.{ .span = span, .replacement = text }} else &.{};
    try core.addDiagnosticWithFixes(allocator, diagnostics, .@"error", id, message, span, fixes);
}

// A configured replacement must be a complete type, not injected declarations.
// Parenthesize compound types so an array/indexed-access parent keeps its meaning.
fn safeReplacement(
    allocator: Allocator,
    replacement: []const u8,
    config: *const core.TypescriptEslintBanTypesConfig,
    path: []const []const u8,
    checked_types: *CheckedFixTypes,
) Allocator.Error!?[]u8 {
    // Longer configured chains exceed lintSourceAndFix's pass budget and
    // would leave another fix for the next invocation instead of stabilizing.
    if (path.len > core.max_autofix_passes) return null;
    const text = std.mem.trim(u8, replacement, " \t\r\n");
    if (text.len == 0) return null;
    const prefix = "type __UtooBanTypeFix = ";
    const source = try std.fmt.allocPrint(allocator, "{s}{s};", .{ prefix, text });
    defer allocator.free(source);
    var parsed = try parser.parse(allocator, source, .{ .lang = ast.Lang.fromPath("fix.ts") });
    defer parsed.deinit();
    if (parsed.hasErrors()) return null;
    const program = parsed.data(parsed.root).program;
    const body = parsed.extra(program.body);
    if (body.len != 1 or parsed.data(body[0]) != .ts_type_alias_declaration) return null;
    const annotation = parsed.span(parsed.data(body[0]).ts_type_alias_declaration.type_annotation);
    if (annotation.start != prefix.len or annotation.end != prefix.len + text.len) return null;
    // Reject self-expanding replacements and cycles between configured types.
    // Otherwise successive fix passes can keep growing or toggling the source.
    for (parsed.nodes.items(.data)) |data| {
        const name = switch (data) {
            .ts_type_reference => |reference| typeName(&parsed, reference.type_name) orelse continue,
            .ts_type_literal => |literal| if (literal.members.len == 0) "{}" else continue,
            .ts_object_keyword => "object",
            else => continue,
        };
        const dependency = bannedType(name, config) orelse continue;
        const next = dependency.fix orelse continue;
        for (path) |ancestor| {
            if (std.mem.eql(u8, ancestor, name)) return null;
        }
        if (checked_types.contains(name)) continue;
        var next_path: [core.max_typescript_eslint_ban_type_entries + 8][]const u8 = undefined;
        if (path.len >= next_path.len) return null;
        @memcpy(next_path[0..path.len], path);
        next_path[path.len] = name;
        const checked = (try safeReplacement(allocator, next, config, next_path[0 .. path.len + 1], checked_types)) orelse return null;
        allocator.free(checked);
        checked_types.append(name);
    }
    var simple = true;
    for (text) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '$' and byte != '.') simple = false;
    }
    return if (simple) try allocator.dupe(u8, text) else try std.fmt.allocPrint(allocator, "({s})", .{text});
}

fn hasComments(tree: *const ast.Tree, span: ast.Span) bool {
    for (tree.comments) |comment| {
        if (comment.span.start < span.end and comment.span.end > span.start) return true;
    }
    return false;
}

// Memoize completed dependency checks so a branching replacement graph is
// visited once per type rather than expanded exponentially.
const CheckedFixTypes = struct {
    count: usize = 0,
    names: [core.max_typescript_eslint_ban_type_entries + 8][core.max_typescript_eslint_ban_type_name_len]u8 = undefined,
    lengths: [core.max_typescript_eslint_ban_type_entries + 8]usize = undefined,

    fn contains(self: *const CheckedFixTypes, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.names[index][0..self.lengths[index]], name)) return true;
        }
        return false;
    }

    fn append(self: *CheckedFixTypes, name: []const u8) void {
        if (self.count >= self.names.len or name.len > core.max_typescript_eslint_ban_type_name_len) return;
        @memcpy(self.names[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};
