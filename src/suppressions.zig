const std = @import("std");
const parser = @import("parser");
const core = @import("core.zig");
const native_rules = @import("rules/root.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

const DirectiveKind = enum {
    ignore,
    ignore_all,
    ignore_start,
    ignore_end,
    eslint_disable,
    eslint_enable,
    eslint_disable_line,
    eslint_disable_next_line,
};

const DirectiveTarget = struct {
    rule_id: ?[]const u8,
    justification: []const u8,

    fn matches(self: DirectiveTarget, rule_id: []const u8) bool {
        return self.rule_id == null or std.mem.eql(u8, self.rule_id.?, rule_id);
    }
};

const ParsedDirective = struct {
    kind: DirectiveKind,
    target: DirectiveTarget,
};

const Directive = struct {
    kind: DirectiveKind,
    target: DirectiveTarget,
    span_start: u32,
    span_end: u32,
    next_code_offset: ?u32 = null,
    top_level: bool = false,
};

pub fn apply(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    suppressed_diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
) Allocator.Error!void {
    if (tree.comments.len == 0) return;

    var directives = try collectDirectives(allocator, tree);
    defer directives.deinit(allocator);
    if (directives.items.len == 0) return;

    try suppressDiagnostics(allocator, diagnostics, suppressed_diagnostics, tree, directives.items);
    try reportUnknownEslintRules(allocator, diagnostics, directives.items);
}

fn reportUnknownEslintRules(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    directives: []const Directive,
) Allocator.Error!void {
    // Disabled rules are still defined. Keep this lookup independent of the
    // file's enabled rules and of whether any rule produced diagnostics.
    for (directives) |directive| {
        switch (directive.kind) {
            .eslint_disable, .eslint_enable, .eslint_disable_line, .eslint_disable_next_line => {},
            else => continue,
        }
        const rule_id = directive.target.rule_id orelse continue;
        if (isKnownRule(rule_id)) continue;

        const owned_rule_id = try allocator.dupe(u8, rule_id);
        errdefer allocator.free(owned_rule_id);
        try core.addDiagnosticFmt(
            allocator,
            diagnostics,
            .@"error",
            owned_rule_id,
            .{ .start = directive.span_start, .end = directive.span_end },
            "Definition for rule '{s}' was not found.",
            .{rule_id},
        );
        diagnostics.items[diagnostics.items.len - 1].owned_rule_id = true;
    }
}

const known_rule_ids = blk: {
    @setEvalBranchQuota(100000);
    const declarations = @typeInfo(native_rules).@"struct".decl_names;
    var entries: [declarations.len]struct { []const u8, void } = undefined;
    var count: usize = 0;
    for (declarations) |name| {
        // Only rule modules have an enable flag. Do not resolve dispatch
        // functions here: their native I/O bodies are unavailable on WASM.
        if (@hasField(core.Options, name)) {
            if (@FieldType(core.Options, name) == bool) {
                const rule = @field(native_rules, name);
                entries[count] = .{ rule.id, {} };
                count += 1;
            }
        }
    }
    break :blk std.StaticStringMap(void).initComptime(entries[0..count]);
};

fn isKnownRule(rule_id: []const u8) bool {
    // These existing native pseudo-rules are accepted outside the rule modules.
    return known_rule_ids.has(rule_id) or std.mem.eql(u8, rule_id, "parse") or
        std.mem.eql(u8, rule_id, "semantic-errors") or std.mem.eql(u8, rule_id, "prettier/prettier");
}

fn suppressDiagnostics(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    suppressed_diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    directives: []const Directive,
) Allocator.Error!void {
    if (diagnostics.items.len == 0) return;

    var line_starts = try collectLineStarts(allocator, tree.source);
    defer line_starts.deinit(allocator);

    const decisions = try allocator.alloc(std.ArrayList(usize), diagnostics.items.len);
    var initialized_decisions: usize = 0;
    defer {
        for (decisions[0..initialized_decisions]) |*decision| decision.deinit(allocator);
        allocator.free(decisions);
    }
    const primary_decision_indices = try allocator.alloc(usize, diagnostics.items.len);
    defer allocator.free(primary_decision_indices);
    var suppressed_count: usize = 0;
    for (diagnostics.items, 0..) |diagnostic, index| {
        decisions[index] = .empty;
        initialized_decisions += 1;
        if (suppressionDirectiveIndexFor(directives, line_starts.items, diagnostic)) |primary_directive_index| {
            try appendEslintSuppressionIndicesFor(
                allocator,
                &decisions[index],
                directives,
                line_starts.items,
                diagnostic,
            );
            try appendUtlintSuppressionIndicesFor(
                allocator,
                &decisions[index],
                directives,
                line_starts.items,
                diagnostic,
            );
            if (std.mem.indexOfScalar(usize, decisions[index].items, primary_directive_index) == null) {
                try decisions[index].append(allocator, primary_directive_index);
            }
            primary_decision_indices[index] = std.mem.indexOfScalar(
                usize,
                decisions[index].items,
                primary_directive_index,
            ).?;
            suppressed_count += 1;
        }
    }
    if (suppressed_count == 0) return;

    var kept: core.DiagnosticList = .empty;
    errdefer kept.deinit(allocator);
    try kept.ensureTotalCapacity(allocator, diagnostics.items.len);
    try suppressed_diagnostics.ensureUnusedCapacity(allocator, suppressed_count);

    const owned_suppressions = try allocator.alloc(?[]core.Suppression, diagnostics.items.len);
    @memset(owned_suppressions, null);
    var ownership_transferred = false;
    defer {
        if (!ownership_transferred) {
            for (owned_suppressions) |maybe_suppressions| {
                if (maybe_suppressions) |owned| {
                    for (owned) |suppression| allocator.free(suppression.justification);
                    allocator.free(owned);
                }
            }
        }
        allocator.free(owned_suppressions);
    }
    for (decisions, 0..) |decision, index| {
        if (decision.items.len == 0) continue;

        const owned = try allocator.alloc(core.Suppression, decision.items.len);
        var initialized_suppressions: usize = 0;
        errdefer {
            for (owned[0..initialized_suppressions]) |suppression| allocator.free(suppression.justification);
            allocator.free(owned);
        }
        for (decision.items, 0..) |directive_index, suppression_index| {
            owned[suppression_index] = .{
                .justification = try allocator.dupe(u8, directives[directive_index].target.justification),
            };
            initialized_suppressions += 1;
        }
        owned_suppressions[index] = owned;
    }

    for (diagnostics.items, 0..) |item, index| {
        var diagnostic = item;
        if (owned_suppressions[index]) |items| {
            diagnostic.suppression = items[primary_decision_indices[index]];
            diagnostic.suppressions = items;
            suppressed_diagnostics.appendAssumeCapacity(diagnostic);
        } else {
            kept.appendAssumeCapacity(diagnostic);
        }
    }
    ownership_transferred = true;

    diagnostics.deinit(allocator);
    diagnostics.* = kept;
}

fn appendEslintSuppressionIndicesFor(
    allocator: Allocator,
    suppression_indices: *std.ArrayList(usize),
    directives: []const Directive,
    line_starts: []const u32,
    diagnostic: core.Diagnostic,
) Allocator.Error!void {
    if (std.mem.eql(u8, diagnostic.rule_id, "parse")) return;

    const diagnostic_line = lineAtOffset(line_starts, diagnostic.span.start);
    var range_matches: std.ArrayList(usize) = .empty;
    defer range_matches.deinit(allocator);
    var line_matches: std.ArrayList(usize) = .empty;
    defer line_matches.deinit(allocator);

    for (directives, 0..) |directive, index| {
        if (directive.kind == .eslint_disable_line or directive.kind == .eslint_disable_next_line) {
            const directive_offset = if (directive.kind == .eslint_disable_next_line and directive.span_end > directive.span_start)
                directive.span_end - 1
            else
                directive.span_start;
            const directive_line = lineAtOffset(line_starts, directive_offset);
            const target_line = directive_line + @intFromBool(directive.kind == .eslint_disable_next_line);
            if (target_line == diagnostic_line and directive.target.matches(diagnostic.rule_id)) {
                try line_matches.append(allocator, index);
            }
            continue;
        }
        if (directive.span_start > diagnostic.span.start) continue;

        switch (directive.kind) {
            .eslint_disable => {
                if (directive.target.matches(diagnostic.rule_id)) try range_matches.append(allocator, index);
            },
            .eslint_enable => {
                if (directive.target.matches(diagnostic.rule_id)) range_matches.clearRetainingCapacity();
            },
            else => {},
        }
    }

    try suppression_indices.appendSlice(allocator, range_matches.items);
    try suppression_indices.appendSlice(allocator, line_matches.items);
}

fn appendUtlintSuppressionIndicesFor(
    allocator: Allocator,
    suppression_indices: *std.ArrayList(usize),
    directives: []const Directive,
    line_starts: []const u32,
    diagnostic: core.Diagnostic,
) Allocator.Error!void {
    if (std.mem.eql(u8, diagnostic.rule_id, "parse")) return;

    const diagnostic_line = lineAtOffset(line_starts, diagnostic.span.start);
    var all_rule_ranges: std.ArrayList(usize) = .empty;
    defer all_rule_ranges.deinit(allocator);
    var named_rule_ranges: std.ArrayList(usize) = .empty;
    defer named_rule_ranges.deinit(allocator);
    var matches: std.ArrayList(usize) = .empty;
    defer matches.deinit(allocator);

    for (directives, 0..) |directive, index| {
        if (directive.span_start > diagnostic.span.start) continue;

        switch (directive.kind) {
            .ignore_start => {
                if (!directive.target.matches(diagnostic.rule_id)) continue;
                if (directive.target.rule_id == null) {
                    try all_rule_ranges.append(allocator, index);
                } else {
                    try named_rule_ranges.append(allocator, index);
                }
            },
            .ignore_end => {
                if (directive.target.rule_id) |rule_id| {
                    if (std.mem.eql(u8, rule_id, diagnostic.rule_id) and named_rule_ranges.items.len > 0) {
                        _ = named_rule_ranges.pop();
                    }
                } else if (all_rule_ranges.items.len > 0) {
                    _ = all_rule_ranges.pop();
                }
            },
            .ignore_all => {
                if (directive.top_level and directive.target.matches(diagnostic.rule_id)) {
                    try matches.append(allocator, index);
                }
            },
            .ignore => {
                const next_offset = directive.next_code_offset orelse continue;
                if (lineAtOffset(line_starts, next_offset) == diagnostic_line and directive.target.matches(diagnostic.rule_id)) {
                    try matches.append(allocator, index);
                }
            },
            else => {},
        }
    }

    try matches.appendSlice(allocator, all_rule_ranges.items);
    try matches.appendSlice(allocator, named_rule_ranges.items);
    std.mem.sort(usize, matches.items, {}, std.sort.asc(usize));
    try suppression_indices.appendSlice(allocator, matches.items);
}

fn collectDirectives(allocator: Allocator, tree: *const ast.Tree) Allocator.Error!std.ArrayList(Directive) {
    var directives: std.ArrayList(Directive) = .empty;
    errdefer directives.deinit(allocator);

    for (tree.comments) |comment| {
        const value = tree.string(comment.value);
        if (parseCommentDirective(value)) |parsed| {
            try directives.append(allocator, .{
                .kind = parsed.kind,
                .target = parsed.target,
                .span_start = comment.span.start,
                .span_end = comment.span.end,
                .next_code_offset = if (parsed.kind == .ignore) nextCodeOffset(tree, comment.span.end) else null,
                .top_level = parsed.kind == .ignore_all and isTopLevelComment(tree, comment),
            });
            continue;
        }
        if (parseEslintDirective(value, comment.type)) |parsed| {
            if (parsed.kind == .eslint_disable_line and comment.type == .block and
                containsLineTerminator(tree.source[@intCast(comment.span.start)..@intCast(comment.span.end)]))
            {
                continue;
            }
            try appendEslintDirectiveTargets(allocator, &directives, parsed, comment.span.start, comment.span.end);
        }
    }

    return directives;
}

fn parseCommentDirective(value: []const u8) ?ParsedDirective {
    const kinds = [_]struct { prefix: []const u8, kind: DirectiveKind }{
        .{ .prefix = "utlint-ignore-start", .kind = .ignore_start },
        .{ .prefix = "utlint-ignore-end", .kind = .ignore_end },
        .{ .prefix = "utlint-ignore-all", .kind = .ignore_all },
        .{ .prefix = "utlint-ignore", .kind = .ignore },
    };
    for (kinds) |entry| {
        if (parseDirectiveTarget(value, entry.prefix)) |target| {
            return .{ .kind = entry.kind, .target = target };
        }
    }
    return null;
}

const ParsedEslintDirective = struct {
    kind: DirectiveKind,
    rules: []const u8,
    justification: []const u8,
};

fn parseEslintDirective(value: []const u8, comment_type: ast.Comment.Type) ?ParsedEslintDirective {
    const trimmed = trimEslintWhitespaceStart(value);
    const kinds = [_]struct { prefix: []const u8, kind: DirectiveKind }{
        .{ .prefix = "eslint-disable-next-line", .kind = .eslint_disable_next_line },
        .{ .prefix = "eslint-disable-line", .kind = .eslint_disable_line },
        .{ .prefix = "eslint-disable", .kind = .eslint_disable },
        .{ .prefix = "eslint-enable", .kind = .eslint_enable },
    };
    for (kinds) |entry| {
        if (!std.mem.startsWith(u8, trimmed, entry.prefix)) continue;
        if (trimmed.len > entry.prefix.len and eslintWhitespaceLengthAt(trimmed, entry.prefix.len) == 0) continue;
        if (comment_type == .line and (entry.kind == .eslint_disable or entry.kind == .eslint_enable)) continue;

        const tail = trimmed[entry.prefix.len..];
        const separator = eslintDescriptionSeparator(tail);
        return .{
            .kind = entry.kind,
            .rules = trimEslintWhitespace(if (separator) |item| tail[0..item.start] else tail),
            .justification = if (separator) |item| trimEslintWhitespace(tail[item.end..]) else "",
        };
    }
    return null;
}

const DescriptionSeparator = struct {
    start: usize,
    end: usize,
};

fn eslintDescriptionSeparator(value: []const u8) ?DescriptionSeparator {
    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        const leading_whitespace_len = eslintWhitespaceLengthAt(value, index);
        if (leading_whitespace_len == 0) continue;

        var end = index + leading_whitespace_len;
        while (end < value.len and value[end] == '-') : (end += 1) {}
        if (end < index + leading_whitespace_len + 2 or end == value.len) continue;
        const trailing_whitespace_len = eslintWhitespaceLengthAt(value, end);
        if (trailing_whitespace_len == 0) continue;
        return .{ .start = index, .end = end + trailing_whitespace_len };
    }
    return null;
}

fn appendEslintDirectiveTargets(
    allocator: Allocator,
    directives: *std.ArrayList(Directive),
    parsed: ParsedEslintDirective,
    span_start: u32,
    span_end: u32,
) Allocator.Error!void {
    if (parsed.rules.len == 0) {
        try directives.append(allocator, .{
            .kind = parsed.kind,
            .target = .{ .rule_id = null, .justification = parsed.justification },
            .span_start = span_start,
            .span_end = span_end,
        });
        return;
    }

    const first_target_index = directives.items.len;
    var appended_rule = false;
    var rules = std.mem.splitScalar(u8, parsed.rules, ',');
    while (rules.next()) |raw_rule_id| {
        const rule_id = trimEslintWhitespace(raw_rule_id);
        if (rule_id.len == 0) continue;
        var duplicate = false;
        for (directives.items[first_target_index..]) |existing| {
            if (std.mem.eql(u8, existing.target.rule_id.?, rule_id)) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;
        appended_rule = true;
        try directives.append(allocator, .{
            .kind = parsed.kind,
            .target = .{ .rule_id = rule_id, .justification = parsed.justification },
            .span_start = span_start,
            .span_end = span_end,
        });
    }
    if (!appended_rule) {
        try directives.append(allocator, .{
            .kind = parsed.kind,
            .target = .{ .rule_id = null, .justification = parsed.justification },
            .span_start = span_start,
            .span_end = span_end,
        });
    }
}

fn parseDirectiveTarget(value: []const u8, prefix: []const u8) ?DirectiveTarget {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;
    if (trimmed.len == prefix.len) return .{ .rule_id = null, .justification = "" };
    if (trimmed[prefix.len] != ':' and !std.ascii.isWhitespace(trimmed[prefix.len])) return null;

    const tail = std.mem.trim(u8, trimmed[prefix.len..], " \t\r\n");
    const rule_end = std.mem.indexOfScalar(u8, tail, ':') orelse tail.len;
    const rule_id = std.mem.trim(u8, tail[0..rule_end], " \t\r\n");
    const justification = if (rule_end < tail.len)
        std.mem.trim(u8, tail[rule_end + 1 ..], " \t\r\n")
    else
        "";
    return .{
        .rule_id = if (rule_id.len == 0) null else rule_id,
        .justification = justification,
    };
}

fn suppressionDirectiveIndexFor(
    directives: []const Directive,
    line_starts: []const u32,
    diagnostic: core.Diagnostic,
) ?usize {
    if (std.mem.eql(u8, diagnostic.rule_id, "parse")) return null;

    const diagnostic_line = lineAtOffset(line_starts, diagnostic.span.start);
    var all_rules_range_depth: usize = 0;
    var named_rule_range_depth: usize = 0;
    var all_rules_range_directive_index: ?usize = null;
    var named_rule_range_directive_index: ?usize = null;
    var eslint_all_rules_directive_index: ?usize = null;
    var eslint_named_rule_directive_index: ?usize = null;
    var eslint_rule_enabled_under_all = false;

    for (directives, 0..) |directive, index| {
        if (directive.kind == .eslint_disable_line or directive.kind == .eslint_disable_next_line) {
            const directive_offset = if (directive.kind == .eslint_disable_next_line and directive.span_end > directive.span_start)
                directive.span_end - 1
            else
                directive.span_start;
            const directive_line = lineAtOffset(line_starts, directive_offset);
            const target_line = directive_line + @intFromBool(directive.kind == .eslint_disable_next_line);
            if (target_line == diagnostic_line and directive.target.matches(diagnostic.rule_id)) {
                return index;
            }
            continue;
        }
        if (directive.span_start > diagnostic.span.start) continue;

        switch (directive.kind) {
            .ignore_start => {
                if (directive.target.rule_id) |rule_id| {
                    if (std.mem.eql(u8, rule_id, diagnostic.rule_id)) {
                        if (named_rule_range_depth == 0) named_rule_range_directive_index = index;
                        named_rule_range_depth += 1;
                    }
                } else {
                    if (all_rules_range_depth == 0) all_rules_range_directive_index = index;
                    all_rules_range_depth += 1;
                }
            },
            .ignore_end => {
                if (directive.target.rule_id) |rule_id| {
                    if (std.mem.eql(u8, rule_id, diagnostic.rule_id) and named_rule_range_depth > 0) named_rule_range_depth -= 1;
                } else if (all_rules_range_depth > 0) {
                    all_rules_range_depth -= 1;
                }
            },
            .ignore_all => {
                if (directive.top_level and directive.target.matches(diagnostic.rule_id)) {
                    return index;
                }
            },
            .ignore => {
                const next_offset = directive.next_code_offset orelse continue;
                if (lineAtOffset(line_starts, next_offset) == diagnostic_line and directive.target.matches(diagnostic.rule_id)) {
                    return index;
                }
            },
            .eslint_disable => {
                if (directive.target.rule_id) |rule_id| {
                    if (std.mem.eql(u8, rule_id, diagnostic.rule_id)) {
                        eslint_named_rule_directive_index = index;
                        eslint_rule_enabled_under_all = false;
                    }
                } else {
                    eslint_all_rules_directive_index = index;
                    eslint_rule_enabled_under_all = false;
                }
            },
            .eslint_enable => {
                if (directive.target.rule_id) |rule_id| {
                    if (std.mem.eql(u8, rule_id, diagnostic.rule_id)) {
                        eslint_named_rule_directive_index = null;
                        if (eslint_all_rules_directive_index != null) eslint_rule_enabled_under_all = true;
                    }
                } else {
                    eslint_all_rules_directive_index = null;
                    eslint_named_rule_directive_index = null;
                    eslint_rule_enabled_under_all = false;
                }
            },
            .eslint_disable_line, .eslint_disable_next_line => unreachable,
        }
    }

    if (named_rule_range_depth > 0) return named_rule_range_directive_index.?;
    if (all_rules_range_depth > 0) return all_rules_range_directive_index.?;
    if (eslint_named_rule_directive_index) |index| return index;
    if (eslint_all_rules_directive_index) |index| {
        if (!eslint_rule_enabled_under_all) return index;
    }
    return null;
}

fn isTopLevelComment(tree: *const ast.Tree, target: ast.Comment) bool {
    var cursor: usize = if (std.mem.startsWith(u8, tree.source, "\xef\xbb\xbf")) 3 else 0;
    if (std.mem.startsWith(u8, tree.source[cursor..], "#!")) {
        cursor = if (std.mem.indexOfScalarPos(u8, tree.source, cursor, '\n')) |newline|
            newline + 1
        else
            tree.source.len;
    }
    for (tree.comments) |comment| {
        if (comment.span.start >= target.span.start) break;
        const comment_start: usize = @intCast(comment.span.start);
        if (comment_start < cursor) continue;
        if (!isWhitespaceOnly(tree.source[cursor..comment_start])) return false;
        cursor = @intCast(comment.span.end);
    }
    return isWhitespaceOnly(tree.source[cursor..@as(usize, @intCast(target.span.start))]);
}

fn isWhitespaceOnly(value: []const u8) bool {
    for (value) |byte| {
        if (!std.ascii.isWhitespace(byte)) return false;
    }
    return true;
}

fn nextCodeOffset(tree: *const ast.Tree, start: u32) ?u32 {
    var offset: usize = @intCast(start);
    while (offset < tree.source.len) {
        while (offset < tree.source.len and std.ascii.isWhitespace(tree.source[offset])) : (offset += 1) {}
        if (offset == tree.source.len) return null;

        var skipped_comment = false;
        for (tree.comments) |comment| {
            if (comment.span.start < offset) continue;
            if (comment.span.start > offset) break;
            offset = @intCast(comment.span.end);
            skipped_comment = true;
            break;
        }
        if (skipped_comment) continue;

        return @intCast(offset);
    }
    return null;
}

fn collectLineStarts(allocator: Allocator, source: []const u8) Allocator.Error!std.ArrayList(u32) {
    var starts: std.ArrayList(u32) = .empty;
    errdefer starts.deinit(allocator);
    try starts.append(allocator, 0);

    var index: usize = 0;
    while (index < source.len) {
        const terminator_len = lineTerminatorLengthAt(source, index);
        if (terminator_len == 0) {
            index += 1;
            continue;
        }

        index += terminator_len;
        if (index < source.len) try starts.append(allocator, @intCast(index));
    }
    return starts;
}

fn containsLineTerminator(source: []const u8) bool {
    var index: usize = 0;
    while (index < source.len) {
        const terminator_len = lineTerminatorLengthAt(source, index);
        if (terminator_len > 0) return true;
        index += 1;
    }
    return false;
}

fn lineTerminatorLengthAt(source: []const u8, index: usize) usize {
    if (source[index] == '\r') {
        return if (index + 1 < source.len and source[index + 1] == '\n') 2 else 1;
    }
    if (source[index] == '\n') return 1;
    if (index + 2 < source.len and source[index] == 0xe2 and source[index + 1] == 0x80 and
        (source[index + 2] == 0xa8 or source[index + 2] == 0xa9))
    {
        return 3;
    }
    return 0;
}

fn trimEslintWhitespace(value: []const u8) []const u8 {
    const without_leading = trimEslintWhitespaceStart(value);
    const start = value.len - without_leading.len;

    var cursor = start;
    var end = start;
    while (cursor < value.len) {
        const whitespace_len = eslintWhitespaceLengthAt(value, cursor);
        if (whitespace_len > 0) {
            cursor += whitespace_len;
        } else {
            cursor += 1;
            end = cursor;
        }
    }
    return value[start..end];
}

fn trimEslintWhitespaceStart(value: []const u8) []const u8 {
    var start: usize = 0;
    while (start < value.len) {
        const whitespace_len = eslintWhitespaceLengthAt(value, start);
        if (whitespace_len == 0) break;
        start += whitespace_len;
    }
    return value[start..];
}

fn eslintWhitespaceLengthAt(value: []const u8, index: usize) usize {
    return switch (value[index]) {
        '\t', '\n', '\x0b', '\x0c', '\r', ' ' => 1,
        0xc2 => if (index + 1 < value.len and value[index + 1] == 0xa0) 2 else 0,
        0xe1 => if (index + 2 < value.len and value[index + 1] == 0x9a and value[index + 2] == 0x80) 3 else 0,
        0xe2 => if (index + 2 < value.len and ((value[index + 1] == 0x80 and
            (value[index + 2] >= 0x80 and value[index + 2] <= 0x8a or value[index + 2] == 0xa8 or
                value[index + 2] == 0xa9 or value[index + 2] == 0xaf)) or
            (value[index + 1] == 0x81 and value[index + 2] == 0x9f))) 3 else 0,
        0xe3 => if (index + 2 < value.len and value[index + 1] == 0x80 and value[index + 2] == 0x80) 3 else 0,
        0xef => if (index + 2 < value.len and value[index + 1] == 0xbb and value[index + 2] == 0xbf) 3 else 0,
        else => 0,
    };
}

fn lineAtOffset(line_starts: []const u32, offset: u32) usize {
    var low: usize = 0;
    var high = line_starts.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (line_starts[middle] <= offset) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}
