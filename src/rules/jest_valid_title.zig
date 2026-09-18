const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const jest_fn_call = @import("jest_fn_call.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "jest/valid-title";

const title_must_be_string = "Title must be a string";
const duplicate_prefix = "should not have duplicate prefix";
const accidental_space = "should not have leading or trailing spaces";

pub const Options = struct {
    ignore_spaces: bool = false,
    ignore_type_of_describe_name: bool = false,
    ignore_type_of_test_name: bool = false,
    disallowed_words: core.JestValidTitleDisallowedWords = .{},
    must_not_match: core.JestValidTitleMatchers = .{},
    must_match: core.JestValidTitleMatchers = .{},
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    global_aliases: core.JestGlobalAliases,
    options: Options,
) Allocator.Error!void {
    var resolver = try jest_fn_call.Resolver.init(allocator, tree, symbol_table, global_aliases);
    defer resolver.deinit();

    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .resolver = &resolver,
        .options = options,
    };
    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    resolver: *const jest_fn_call.Resolver,
    options: Options,

    pub fn enter_call_expression(
        self: *Visitor,
        expression: ast.CallExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const call = self.resolver.parseCall(expression, index, ctx.path.parent()) orelse return .proceed;
        const kind = call.function.kind();
        if (kind == .expect) return .proceed;

        const arguments = ctx.tree.extra(expression.arguments);
        if (arguments.len == 0) return .proceed;
        const argument = arguments[0];
        const static_title = staticTitle(ctx.tree, argument);
        if (static_title == null) {
            if (containsStringInBinaryExpression(ctx.tree, argument)) return .proceed;
            if (treeIsTemplateLiteral(ctx.tree, argument)) return .proceed;
            if ((kind == .describe and self.options.ignore_type_of_describe_name) or
                (kind == .test_case and self.options.ignore_type_of_test_name)) return .proceed;

            try core.addDiagnostic(
                self.allocator,
                self.diagnostics,
                .warning,
                id,
                title_must_be_string,
                ctx.tree.span(argument),
            );
            return .proceed;
        }

        const title = static_title.?;
        if (title.value.len == 0) {
            try core.addDiagnosticFmt(
                self.allocator,
                self.diagnostics,
                .warning,
                id,
                ctx.tree.span(index),
                "{s} should not have an empty title",
                .{if (kind == .describe) "describe" else "test"},
            );
            return .proceed;
        }

        if (call.memberNamed("each") != null and call.nested_calls != 0) {
            if (invalidEachSpecifier(title.value)) |specifier| {
                try core.addDiagnosticFmt(
                    self.allocator,
                    self.diagnostics,
                    .warning,
                    id,
                    title.span,
                    "\"%{c}\" is not a valid format specifier",
                    .{specifier},
                );
            }
        }

        if (self.disallowedWord(title.value)) |word| {
            try core.addDiagnosticFmt(
                self.allocator,
                self.diagnostics,
                .warning,
                id,
                title.span,
                "\"{s}\" is not allowed in test titles",
                .{word},
            );
            return .proceed;
        }

        if (!self.options.ignore_spaces and hasAccidentalSpace(title.value)) {
            const fixes = accidentalSpaceFixes(ctx.tree, title.span);
            if (fixes.len == 0) {
                try core.addDiagnostic(
                    self.allocator,
                    self.diagnostics,
                    .warning,
                    id,
                    accidental_space,
                    title.span,
                );
            } else {
                try core.addDiagnosticWithFixes(
                    self.allocator,
                    self.diagnostics,
                    .warning,
                    id,
                    accidental_space,
                    title.span,
                    fixes.slice(),
                );
            }
        }

        const function_group = functionGroup(call.function);
        if (hasDuplicatePrefix(title.value, function_group.name)) {
            if (duplicatePrefixFix(ctx.tree, title.span)) |fix| {
                try core.addDiagnosticWithFix(
                    self.allocator,
                    self.diagnostics,
                    .warning,
                    id,
                    duplicate_prefix,
                    title.span,
                    fix,
                );
            } else {
                try core.addDiagnostic(
                    self.allocator,
                    self.diagnostics,
                    .warning,
                    id,
                    duplicate_prefix,
                    title.span,
                );
            }
        }

        const must_not_match = matcherFor(&self.options.must_not_match, function_group.matcher_kind);
        if (must_not_match.pattern()) |pattern| {
            if (regexMatches(pattern, title.value)) {
                try self.addMatcherDiagnostic(title.span, function_group.name, pattern, must_not_match.message(), false);
                return .proceed;
            }
        }

        const must_match = matcherFor(&self.options.must_match, function_group.matcher_kind);
        if (must_match.pattern()) |pattern| {
            if (!regexMatches(pattern, title.value)) {
                try self.addMatcherDiagnostic(title.span, function_group.name, pattern, must_match.message(), true);
                return .proceed;
            }
        }

        return .proceed;
    }

    fn disallowedWord(self: *const Visitor, title: []const u8) ?[]const u8 {
        for (0..title.len + 1) |offset| {
            for (0..self.options.disallowed_words.count) |word_index| {
                const word = self.options.disallowed_words.at(word_index);
                if (word.len == 0) {
                    const left_word = offset != 0 and isAsciiWord(title[offset - 1]);
                    const right_word = offset < title.len and isAsciiWord(title[offset]);
                    if (left_word != right_word) return title[offset..offset];
                    continue;
                }
                if (offset + word.len > title.len) continue;
                const candidate = title[offset .. offset + word.len];
                if (!std.ascii.eqlIgnoreCase(candidate, word)) continue;
                if (offset != 0 and isAsciiWord(title[offset - 1])) continue;
                if (offset + word.len != title.len and isAsciiWord(title[offset + word.len])) continue;
                return candidate;
            }
        }
        return null;
    }

    fn addMatcherDiagnostic(
        self: *Visitor,
        span: ast.Span,
        function_name: []const u8,
        pattern: []const u8,
        custom_message: ?[]const u8,
        should_match: bool,
    ) Allocator.Error!void {
        if (custom_message) |message| {
            return core.addDiagnostic(self.allocator, self.diagnostics, .warning, id, message, span);
        }
        if (should_match) {
            return core.addDiagnosticFmt(
                self.allocator,
                self.diagnostics,
                .warning,
                id,
                span,
                "{s} should match /{s}/u",
                .{ function_name, pattern },
            );
        }
        return core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .warning,
            id,
            span,
            "{s} should not match /{s}/u",
            .{ function_name, pattern },
        );
    }
};

const MatcherKind = enum { describe, test_case, it };

const FunctionGroup = struct {
    name: []const u8,
    matcher_kind: MatcherKind,
};

fn functionGroup(function: jest_fn_call.Function) FunctionGroup {
    return switch (function) {
        .describe, .fdescribe, .xdescribe => .{ .name = "describe", .matcher_kind = .describe },
        .test_case, .xtest => .{ .name = "test", .matcher_kind = .test_case },
        .it, .fit, .xit => .{ .name = "it", .matcher_kind = .it },
        .expect => unreachable,
    };
}

fn matcherFor(matchers: *const core.JestValidTitleMatchers, kind: MatcherKind) *const core.JestValidTitleMatcher {
    return switch (kind) {
        .describe => &matchers.describe,
        .test_case => &matchers.test_case,
        .it => &matchers.it,
    };
}

const StaticTitle = struct {
    value: []const u8,
    span: ast.Span,
};

fn staticTitle(tree: *const ast.Tree, index: ast.NodeIndex) ?StaticTitle {
    return switch (tree.data(index)) {
        .string_literal => |literal| .{ .value = tree.string(literal.value), .span = tree.span(index) },
        .template_literal => |literal| blk: {
            if (literal.expressions.len != 0) break :blk null;
            const quasis = tree.extra(literal.quasis);
            if (quasis.len != 1) break :blk null;
            const value = switch (tree.data(quasis[0])) {
                .template_element => |element| tree.string(element.cooked),
                else => break :blk null,
            };
            break :blk .{ .value = value, .span = tree.span(index) };
        },
        else => null,
    };
}

fn treeIsTemplateLiteral(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(index)) {
        .template_literal => true,
        else => false,
    };
}

fn containsStringInBinaryExpression(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const expression = switch (tree.data(index)) {
        .binary_expression => |value| value,
        else => return false,
    };
    if (staticTitle(tree, expression.right) != null) return true;
    if (tree.data(expression.left) == .binary_expression) {
        return containsStringInBinaryExpression(tree, expression.left);
    }
    return staticTitle(tree, expression.left) != null;
}

fn invalidEachSpecifier(title: []const u8) ?u8 {
    var index: usize = 0;
    while (index + 1 < title.len) {
        if (title[index] != '%') {
            index += 1;
            continue;
        }
        if (title[index + 1] == '%') {
            index += 2;
            continue;
        }
        const specifier = title[index + 1];
        if (std.mem.indexOfScalar(u8, "psdifjo#$%", specifier) == null) return specifier;
        index += 1;
    }
    return null;
}

fn hasAccidentalSpace(title: []const u8) bool {
    if (title.len == 0) return false;
    return startsWithJsWhitespace(title) or endsWithJsWhitespace(title);
}

const js_unicode_whitespace = [_][]const u8{
    "\xC2\xA0", // no-break space
    "\xE1\x9A\x80", // ogham space mark
    "\xE2\x80\x80",
    "\xE2\x80\x81",
    "\xE2\x80\x82",
    "\xE2\x80\x83",
    "\xE2\x80\x84",
    "\xE2\x80\x85",
    "\xE2\x80\x86",
    "\xE2\x80\x87",
    "\xE2\x80\x88",
    "\xE2\x80\x89",
    "\xE2\x80\x8A", // U+2000..U+200A
    "\xE2\x80\xA8",
    "\xE2\x80\xA9",
    "\xE2\x80\xAF",
    "\xE2\x81\x9F",
    "\xE3\x80\x80",
    "\xEF\xBB\xBF",
};

fn startsWithJsWhitespace(value: []const u8) bool {
    return jsWhitespacePrefixLen(value) != 0;
}

fn endsWithJsWhitespace(value: []const u8) bool {
    return jsWhitespaceSuffixLen(value) != 0;
}

fn jsWhitespacePrefixLen(value: []const u8) usize {
    if (value.len == 0) return 0;
    if (std.ascii.isWhitespace(value[0])) return 1;
    for (js_unicode_whitespace) |sequence| {
        if (std.mem.startsWith(u8, value, sequence)) return sequence.len;
    }
    return 0;
}

fn jsWhitespaceSuffixLen(value: []const u8) usize {
    if (value.len == 0) return 0;
    if (std.ascii.isWhitespace(value[value.len - 1])) return 1;
    for (js_unicode_whitespace) |sequence| {
        if (std.mem.endsWith(u8, value, sequence)) return sequence.len;
    }
    return 0;
}

fn isJsWhitespaceCodepoint(value: []const u8, start: usize, end: usize) bool {
    if (start >= end or end > value.len) return false;
    return jsWhitespacePrefixLen(value[start..end]) == end - start;
}

const FixBuffer = struct {
    items: [2]core.Fix = undefined,
    len: usize = 0,

    fn append(self: *FixBuffer, fix: core.Fix) void {
        self.items[self.len] = fix;
        self.len += 1;
    }

    fn slice(self: *const FixBuffer) []const core.Fix {
        return self.items[0..self.len];
    }
};

fn accidentalSpaceFixes(tree: *const ast.Tree, span: ast.Span) FixBuffer {
    var result = FixBuffer{};
    if (span.end <= span.start + 1) return result;
    const content_start: usize = span.start + 1;
    const content_end: usize = span.end - 1;
    var trimmed_start = content_start;
    while (trimmed_start < content_end) {
        const whitespace_len = jsWhitespacePrefixLen(tree.source[trimmed_start..content_end]);
        if (whitespace_len == 0) break;
        trimmed_start += whitespace_len;
    }
    var trimmed_end = content_end;
    while (trimmed_end > trimmed_start) {
        const whitespace_len = jsWhitespaceSuffixLen(tree.source[trimmed_start..trimmed_end]);
        if (whitespace_len == 0) break;
        trimmed_end -= whitespace_len;
    }
    if (trimmed_start > content_start) result.append(.{
        .span = .{ .start = @intCast(content_start), .end = @intCast(trimmed_start) },
        .replacement = "",
    });
    if (trimmed_end < content_end) result.append(.{
        .span = .{ .start = @intCast(trimmed_end), .end = @intCast(content_end) },
        .replacement = "",
    });
    return result;
}

fn hasDuplicatePrefix(title: []const u8, function_name: []const u8) bool {
    const separator = std.mem.indexOfScalar(u8, title, ' ') orelse return false;
    return std.ascii.eqlIgnoreCase(title[0..separator], function_name);
}

fn duplicatePrefixFix(tree: *const ast.Tree, span: ast.Span) ?core.Fix {
    if (span.end <= span.start + 1) return null;
    const content_start: usize = span.start + 1;
    const content_end: usize = span.end - 1;
    const separator = std.mem.indexOfScalar(u8, tree.source[content_start..content_end], ' ') orelse return null;
    return .{
        .span = .{ .start = @intCast(content_start), .end = @intCast(content_start + separator + 1) },
        .replacement = "",
    };
}

fn isAsciiWord(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

// A small allocation-free ECMAScript-pattern matcher for rule configuration.
// It supports anchors, groups, lookaheads, alternation, character classes,
// common escape classes, and the ?, *, +, and {n,m} quantifiers used by the
// upstream option examples.
pub fn regexMatches(pattern: []const u8, text: []const u8) bool {
    for (0..text.len + 1) |start| {
        if (matchAlternatives(pattern, 0, pattern.len, text, start, null)) return true;
    }
    return false;
}

fn matchAlternatives(
    pattern: []const u8,
    start: usize,
    end: usize,
    text: []const u8,
    text_start: usize,
    required_end: ?usize,
) bool {
    var branch_start = start;
    var cursor = start;
    var depth: usize = 0;
    var in_class = false;
    while (cursor < end) : (cursor += 1) {
        const byte = pattern[cursor];
        if (byte == '\\') {
            cursor += @intFromBool(cursor + 1 < end);
            continue;
        }
        if (in_class) {
            if (byte == ']') in_class = false;
            continue;
        }
        if (byte == '[') {
            in_class = true;
        } else if (byte == '(') {
            depth += 1;
        } else if (byte == ')' and depth != 0) {
            depth -= 1;
        } else if (byte == '|' and depth == 0) {
            if (matchSequence(pattern, branch_start, cursor, text, text_start, required_end)) return true;
            branch_start = cursor + 1;
        }
    }
    return matchSequence(pattern, branch_start, end, text, text_start, required_end);
}

const Atom = struct {
    start: usize,
    end: usize,
    next: usize,
    min: usize = 1,
    max: usize = 1,
};

fn matchSequence(
    pattern: []const u8,
    start: usize,
    end: usize,
    text: []const u8,
    text_start: usize,
    required_end: ?usize,
) bool {
    if (start >= end) return required_end == null or text_start == required_end.?;
    const atom = parseAtom(pattern, start, end) orelse return false;
    return matchQuantified(pattern, atom, end, text, text_start, 0, required_end);
}

fn matchQuantified(
    pattern: []const u8,
    atom: Atom,
    sequence_end: usize,
    text: []const u8,
    text_start: usize,
    count: usize,
    required_end: ?usize,
) bool {
    if (count >= atom.min and matchSequence(pattern, atom.next, sequence_end, text, text_start, required_end)) return true;
    if (count >= atom.max) return false;

    var candidate_end = text_start;
    while (candidate_end <= text.len) : (candidate_end += 1) {
        if (!atomMatches(pattern, atom.start, atom.end, text, text_start, candidate_end)) continue;
        if (candidate_end == text_start and atom.max != 1) return false;
        if (matchQuantified(pattern, atom, sequence_end, text, candidate_end, count + 1, required_end)) return true;
    }
    return false;
}

fn parseAtom(pattern: []const u8, start: usize, end: usize) ?Atom {
    var atom_end = start + 1;
    if (pattern[start] == '\\') {
        atom_end = @min(start + 2, end);
    } else if (pattern[start] == '[') {
        atom_end = findClassEnd(pattern, start, end) orelse return null;
    } else if (pattern[start] == '(') {
        atom_end = findGroupEnd(pattern, start, end) orelse return null;
    } else if (pattern[start] >= 0x80) {
        const sequence_length: usize = std.unicode.utf8ByteSequenceLength(pattern[start]) catch 1;
        atom_end = @min(start + sequence_length, end);
    }

    var atom = Atom{ .start = start, .end = atom_end, .next = atom_end };
    if (atom.next >= end) return atom;
    switch (pattern[atom.next]) {
        '?' => {
            atom.min = 0;
            atom.max = 1;
            atom.next += 1;
        },
        '*' => {
            atom.min = 0;
            atom.max = std.math.maxInt(usize);
            atom.next += 1;
        },
        '+' => {
            atom.min = 1;
            atom.max = std.math.maxInt(usize);
            atom.next += 1;
        },
        '{' => parseBraceQuantifier(pattern, &atom, end),
        else => {},
    }
    return atom;
}

fn parseBraceQuantifier(pattern: []const u8, atom: *Atom, end: usize) void {
    const close = std.mem.indexOfScalarPos(u8, pattern[0..end], atom.next + 1, '}') orelse return;
    const body = pattern[atom.next + 1 .. close];
    const comma = std.mem.indexOfScalar(u8, body, ',');
    const minimum_text = if (comma) |index| body[0..index] else body;
    const minimum = std.fmt.parseUnsigned(usize, minimum_text, 10) catch return;
    var maximum = minimum;
    if (comma) |index| {
        maximum = if (index + 1 == body.len)
            std.math.maxInt(usize)
        else
            std.fmt.parseUnsigned(usize, body[index + 1 ..], 10) catch return;
    }
    if (maximum < minimum) return;
    atom.min = minimum;
    atom.max = maximum;
    atom.next = close + 1;
}

fn findClassEnd(pattern: []const u8, start: usize, end: usize) ?usize {
    var cursor = start + 1;
    while (cursor < end) : (cursor += 1) {
        if (pattern[cursor] == '\\') {
            cursor += @intFromBool(cursor + 1 < end);
        } else if (pattern[cursor] == ']') {
            return cursor + 1;
        }
    }
    return null;
}

fn findGroupEnd(pattern: []const u8, start: usize, end: usize) ?usize {
    var cursor = start + 1;
    var depth: usize = 1;
    var in_class = false;
    while (cursor < end) : (cursor += 1) {
        const byte = pattern[cursor];
        if (byte == '\\') {
            cursor += @intFromBool(cursor + 1 < end);
            continue;
        }
        if (in_class) {
            if (byte == ']') in_class = false;
            continue;
        }
        if (byte == '[') in_class = true else if (byte == '(') depth += 1 else if (byte == ')') {
            depth -= 1;
            if (depth == 0) return cursor + 1;
        }
    }
    return null;
}

fn atomMatches(
    pattern: []const u8,
    start: usize,
    end: usize,
    text: []const u8,
    text_start: usize,
    text_end: usize,
) bool {
    const atom = pattern[start..end];
    if (atom.len == 1) {
        if (atom[0] == '^') return text_start == 0 and text_end == text_start;
        if (atom[0] == '$') return text_start == text.len and text_end == text_start;
        if (text_start >= text.len) return false;
        if (atom[0] == '.') return text_end == nextCodepoint(text, text_start);
        return text_end == text_start + 1 and text[text_start] == atom[0];
    }
    if (atom[0] == '\\') return escapedAtomMatches(atom, text, text_start, text_end);
    if (atom[0] == '[') return classMatches(atom, text, text_start, text_end);
    if (atom[0] == '(') return groupMatches(atom, text, text_start, text_end);
    return text_end == text_start + atom.len and std.mem.eql(u8, text[text_start..text_end], atom);
}

fn escapedAtomMatches(atom: []const u8, text: []const u8, start: usize, end: usize) bool {
    if (atom.len != 2) return false;
    const escape = atom[1];
    if (escape == 'b' or escape == 'B') {
        if (end != start) return false;
        const left_word = start != 0 and isAsciiWord(text[start - 1]);
        const right_word = start < text.len and isAsciiWord(text[start]);
        return (left_word != right_word) == (escape == 'b');
    }
    if (start >= text.len or end != nextCodepoint(text, start)) return false;
    const byte = text[start];
    return switch (escape) {
        'd' => std.ascii.isDigit(byte),
        'D' => !std.ascii.isDigit(byte),
        'w' => isAsciiWord(byte),
        'W' => !isAsciiWord(byte),
        's' => isJsWhitespaceCodepoint(text, start, end),
        'S' => !isJsWhitespaceCodepoint(text, start, end),
        'n' => byte == '\n',
        'r' => byte == '\r',
        't' => byte == '\t',
        else => end == start + 1 and byte == escape,
    };
}

fn classMatches(atom: []const u8, text: []const u8, start: usize, end: usize) bool {
    if (start >= text.len or end != nextCodepoint(text, start)) return false;
    const byte = text[start];
    var cursor: usize = 1;
    const negated = cursor < atom.len - 1 and atom[cursor] == '^';
    if (negated) cursor += 1;
    var found = false;
    while (cursor < atom.len - 1) {
        if (atom[cursor] == '\\' and cursor + 1 < atom.len - 1) {
            const escaped = atom[cursor + 1];
            found = found or switch (escaped) {
                'd' => std.ascii.isDigit(byte),
                'D' => !std.ascii.isDigit(byte),
                'w' => isAsciiWord(byte),
                'W' => !isAsciiWord(byte),
                's' => isJsWhitespaceCodepoint(text, start, end),
                'S' => !isJsWhitespaceCodepoint(text, start, end),
                'n' => byte == '\n',
                'r' => byte == '\r',
                't' => byte == '\t',
                else => byte == escaped,
            };
            cursor += 2;
            continue;
        }
        if (cursor + 2 < atom.len - 1 and atom[cursor + 1] == '-') {
            found = found or (byte >= atom[cursor] and byte <= atom[cursor + 2]);
            cursor += 3;
        } else {
            found = found or byte == atom[cursor];
            cursor += 1;
        }
    }
    return if (negated) !found else found;
}

fn groupMatches(atom: []const u8, text: []const u8, start: usize, end: usize) bool {
    var content_start: usize = 1;
    if (std.mem.startsWith(u8, atom, "(?:")) content_start = 3;
    if (std.mem.startsWith(u8, atom, "(?=")) {
        return end == start and matchAlternatives(atom, 3, atom.len - 1, text, start, null);
    }
    if (std.mem.startsWith(u8, atom, "(?!")) {
        return end == start and !matchAlternatives(atom, 3, atom.len - 1, text, start, null);
    }
    return matchAlternatives(atom, content_start, atom.len - 1, text, start, end);
}

fn nextCodepoint(text: []const u8, start: usize) usize {
    if (start >= text.len) return start;
    const length: usize = std.unicode.utf8ByteSequenceLength(text[start]) catch 1;
    return @min(start + length, text.len);
}

test "configured regular-expression matching" {
    try std.testing.expect(regexMatches("^that", "that works"));
    try std.testing.expect(!regexMatches("^that", "not that"));
    try std.testing.expect(regexMatches("^[^#]+$|(?:#(?:unit|e2e))", "works #unit"));
    try std.testing.expect(regexMatches("(?:#(?!unit|e2e))\\w+", "works #jest4life"));
    try std.testing.expect(!regexMatches("(?:#(?!unit|e2e))\\w+", "works #unit"));
    try std.testing.expect(regexMatches("\\.$", "ends."));
    try std.testing.expect(regexMatches("^foo\\sbar$", "foo\xC2\xA0bar"));
    try std.testing.expect(!regexMatches("^foo\\Sbar$", "foo\xC2\xA0bar"));
    try std.testing.expect(regexMatches("^foo[\\s]bar$", "foo\xC2\xA0bar"));
}
