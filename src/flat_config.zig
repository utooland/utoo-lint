const std = @import("std");
const lint = @import("utoo_lint");

pub const RuleSeverityMap = std.StringHashMap(lint.Severity);

pub const ResolvedConfig = struct {
    options: lint.Options,
    rule_severities: RuleSeverityMap,

    pub fn deinit(self: *ResolvedConfig, allocator: std.mem.Allocator) void {
        clearRuleSeverities(allocator, &self.rule_severities);
        self.rule_severities.deinit();
    }
};

pub const FlatConfig = struct {
    parsed: std.json.Parsed(std.json.Value),
    io: std.Io,
    directory: []u8,
    cwd: []u8,

    pub fn deinit(self: *FlatConfig, allocator: std.mem.Allocator) void {
        self.parsed.deinit();
        allocator.free(self.directory);
        allocator.free(self.cwd);
    }

    pub fn validateAndApplyAggregate(
        self: *FlatConfig,
        allocator: std.mem.Allocator,
        options: *lint.Options,
        rule_severities: *RuleSeverityMap,
    ) !void {
        const entries = self.parsed.value.array.items;
        options.* = lint.Options.allDisabled();
        for (entries) |entry_value| {
            const entry = switch (entry_value) {
                .object => |object| object,
                else => return error.InvalidFlatConfigEntry,
            };
            if (isGlobalIgnoreEntry(entry)) continue;
            try applyConfigObject(allocator, entry, options, rule_severities);
        }
    }

    pub fn resolveForFile(
        self: *const FlatConfig,
        allocator: std.mem.Allocator,
        file_path: []const u8,
    ) !ResolvedConfig {
        var resolved = ResolvedConfig{
            .options = lint.Options.allDisabled(),
            .rule_severities = RuleSeverityMap.init(allocator),
        };
        errdefer resolved.deinit(allocator);

        const paths = try ConfigPaths.init(allocator, self.io, self.cwd, self.directory, file_path);
        defer paths.deinit(allocator);

        for (self.parsed.value.array.items) |entry_value| {
            const entry = entry_value.object;
            if (isGlobalIgnoreEntry(entry) or !entryApplies(entry, paths)) continue;
            try applyConfigObject(allocator, entry, &resolved.options, &resolved.rule_severities);
        }
        return resolved;
    }

    pub fn isGloballyIgnored(self: *const FlatConfig, allocator: std.mem.Allocator, path: []const u8) !bool {
        const paths = try ConfigPaths.init(allocator, self.io, self.cwd, self.directory, path);
        defer paths.deinit(allocator);

        var ignored = false;
        for (self.parsed.value.array.items) |entry_value| {
            const entry = entry_value.object;
            if (!isGlobalIgnoreEntry(entry)) continue;
            ignored = ignoredByValue(paths, entry.get("ignores").?, ignored);
        }
        return ignored;
    }

    pub fn shouldTraverseDirectory(self: *const FlatConfig, allocator: std.mem.Allocator, path: []const u8) !bool {
        if (!try self.isGloballyIgnored(allocator, path)) return true;

        // Negated global patterns may re-include a descendant. Traversing in
        // that uncommon case is conservative and preserves ignore ordering.
        for (self.parsed.value.array.items) |entry_value| {
            const entry = entry_value.object;
            if (!isGlobalIgnoreEntry(entry)) continue;
            if (hasNegatedPattern(entry.get("ignores").?)) return true;
        }
        return false;
    }

    pub fn selectsFile(self: *const FlatConfig, allocator: std.mem.Allocator, path: []const u8) !bool {
        if (!self.hasFileSelectors()) return true;

        const paths = try ConfigPaths.init(allocator, self.io, self.cwd, self.directory, path);
        defer paths.deinit(allocator);
        for (self.parsed.value.array.items) |entry_value| {
            const entry = entry_value.object;
            if (isGlobalIgnoreEntry(entry)) continue;
            if (entry.get("files") != null) {
                if (entryApplies(entry, paths)) return true;
                continue;
            }
            if (hasRules(entry) and entryApplies(entry, paths)) return true;
        }
        return false;
    }

    fn hasFileSelectors(self: *const FlatConfig) bool {
        for (self.parsed.value.array.items) |entry_value| {
            if (entry_value.object.get("files") != null) return true;
        }
        return false;
    }
};

pub fn applyConfigObject(
    allocator: std.mem.Allocator,
    root: std.json.ObjectMap,
    options: *lint.Options,
    rule_severities: *RuleSeverityMap,
) !void {
    if (root.get("settings")) |settings_value| {
        const settings = switch (settings_value) {
            .object => |object| object,
            else => return error.InvalidSettings,
        };
        if (settings.get("jest")) |jest_value| {
            const jest = switch (jest_value) {
                .object => |object| object,
                else => return error.InvalidJestSettings,
            };
            const defaults = lint.Options{};
            options.jest_version = defaults.jest_version;
            options.jest_global_aliases = defaults.jest_global_aliases;
            if (jest.get("version")) |version| try options.setJestVersionFromConfig(version);
            if (jest.get("globalAliases")) |aliases| try options.setJestGlobalAliasesFromConfig(aliases);
        }
    }

    if (root.get("languageOptions")) |language_options_value| {
        const language_options = switch (language_options_value) {
            .object => |object| object,
            else => return error.InvalidLanguageOptions,
        };
        if (language_options.get("globals")) |globals| {
            try options.setConfiguredGlobalsFromConfig(globals);
        }
    }

    const rules_value = root.get("rules") orelse return;
    const rules = switch (rules_value) {
        .object => |object| object,
        else => return error.InvalidRules,
    };

    var iter = rules.iterator();
    while (iter.next()) |entry| {
        const severity = try lint.Options.severityFromRuleConfigValue(entry.value_ptr.*);
        if (isSeverityOnlyRuleConfig(entry.value_ptr.*)) {
            if (!options.setByCliName(entry.key_ptr.*, severity != null)) return error.UnknownRule;
        } else {
            try options.setByRuleConfigValue(entry.key_ptr.*, entry.value_ptr.*);
        }
        try setRuleSeverity(allocator, rule_severities, entry.key_ptr.*, severity);
    }
}

fn setRuleSeverity(
    allocator: std.mem.Allocator,
    rule_severities: *RuleSeverityMap,
    rule: []const u8,
    severity: ?lint.Severity,
) !void {
    if (severity) |configured| {
        const existing = try rule_severities.getOrPut(rule);
        if (!existing.found_existing) {
            existing.key_ptr.* = try allocator.dupe(u8, rule);
        }
        existing.value_ptr.* = configured;
        return;
    }
    if (rule_severities.fetchRemove(rule)) |removed| allocator.free(removed.key);
}

fn clearRuleSeverities(allocator: std.mem.Allocator, rule_severities: *RuleSeverityMap) void {
    var iter = rule_severities.keyIterator();
    while (iter.next()) |rule| allocator.free(rule.*);
    rule_severities.clearRetainingCapacity();
}

fn isSeverityOnlyRuleConfig(value: std.json.Value) bool {
    return switch (value) {
        .array => |items| items.items.len == 1,
        else => true,
    };
}

const ConfigPaths = struct {
    absolute: []u8,
    relative: []u8,

    fn init(allocator: std.mem.Allocator, io: std.Io, cwd: []const u8, directory: []const u8, path: []const u8) !ConfigPaths {
        const absolute = try canonicalPathAlloc(allocator, io, cwd, path);
        errdefer allocator.free(absolute);
        const relative = try std.fs.path.relative(allocator, ".", null, directory, absolute);
        return .{ .absolute = absolute, .relative = relative };
    }

    fn deinit(self: ConfigPaths, allocator: std.mem.Allocator) void {
        allocator.free(self.absolute);
        allocator.free(self.relative);
    }
};

pub fn canonicalPathAlloc(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: []const u8,
    path: []const u8,
) ![]u8 {
    const absolute = try std.fs.path.resolve(allocator, &.{ cwd, path });
    const canonical = std.Io.Dir.realPathFileAbsoluteAlloc(io, absolute, allocator) catch return absolute;
    defer allocator.free(canonical);
    allocator.free(absolute);
    return allocator.dupe(u8, canonical);
}

fn entryApplies(entry: std.json.ObjectMap, paths: ConfigPaths) bool {
    if (entry.get("files")) |files| {
        if (!fileSelectorsMatch(paths, files)) return false;
    }
    if (entry.get("ignores")) |ignores| {
        if (ignoredByValue(paths, ignores, false)) return false;
    }
    return true;
}

fn hasRules(entry: std.json.ObjectMap) bool {
    const rules = entry.get("rules") orelse return false;
    return switch (rules) {
        .object => |object| object.count() > 0,
        else => false,
    };
}

fn isGlobalIgnoreEntry(entry: std.json.ObjectMap) bool {
    if (entry.get("ignores") == null) return false;
    var iter = entry.iterator();
    while (iter.next()) |field| {
        if (!std.mem.eql(u8, field.key_ptr.*, "name") and !std.mem.eql(u8, field.key_ptr.*, "ignores")) return false;
    }
    return true;
}

fn fileSelectorsMatch(paths: ConfigPaths, value: std.json.Value) bool {
    return switch (value) {
        .string => |pattern| matchesConfigPattern(paths, pattern),
        .array => |items| blk: {
            for (items.items) |selector| {
                switch (selector) {
                    .string => |pattern| if (matchesConfigPattern(paths, pattern)) break :blk true,
                    .array => |patterns| {
                        if (patterns.items.len == 0) continue;
                        for (patterns.items) |pattern_value| {
                            const pattern = switch (pattern_value) {
                                .string => |text| text,
                                else => break,
                            };
                            if (!matchesConfigPattern(paths, pattern)) break;
                        } else break :blk true;
                    },
                    else => {},
                }
            }
            break :blk false;
        },
        else => false,
    };
}

fn ignoredByValue(paths: ConfigPaths, value: std.json.Value, initial: bool) bool {
    var ignored = initial;
    switch (value) {
        .string => |pattern| applyIgnorePattern(paths, pattern, &ignored),
        .array => |items| for (items.items) |item| {
            if (item == .string) applyIgnorePattern(paths, item.string, &ignored);
        },
        else => {},
    }
    return ignored;
}

fn hasNegatedPattern(value: std.json.Value) bool {
    return switch (value) {
        .string => |pattern| pattern.len > 1 and pattern[0] == '!',
        .array => |items| blk: {
            for (items.items) |item| {
                if (item == .string and item.string.len > 1 and item.string[0] == '!') break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

fn applyIgnorePattern(paths: ConfigPaths, raw_pattern: []const u8, ignored: *bool) void {
    const negated = raw_pattern.len > 1 and raw_pattern[0] == '!';
    const pattern = if (negated) raw_pattern[1..] else raw_pattern;
    if (matchesIgnorePattern(paths, pattern)) ignored.* = !negated;
}

fn matchesConfigPattern(paths: ConfigPaths, raw_pattern: []const u8) bool {
    const pattern = normalizePattern(raw_pattern);
    const target = if (std.fs.path.isAbsolute(pattern)) paths.absolute else paths.relative;
    if (!hasGlobSyntax(pattern)) {
        return pathEql(target, pattern) or pathStartsWith(target, pattern) or pathEndsWith(target, pattern);
    }
    return globMatches(pattern, target);
}

fn matchesIgnorePattern(paths: ConfigPaths, raw_pattern: []const u8) bool {
    var pattern = normalizePattern(raw_pattern);
    const absolute = std.fs.path.isAbsolute(pattern);
    var target = if (absolute) paths.absolute else paths.relative;
    const anchored = !absolute and pattern.len > 0 and isSeparator(pattern[0]);
    if (anchored) pattern = pattern[1..];
    if (anchored and target.len > 0 and isSeparator(target[0])) target = target[1..];

    if (endsWithNormalized(pattern, "/**")) {
        const directory_pattern = pattern[0 .. pattern.len - 3];
        if (!hasGlobSyntax(directory_pattern)) {
            return pathEql(target, directory_pattern) or pathStartsWith(target, directory_pattern);
        }
        if (globMatches(directory_pattern, target)) return true;
        var index: usize = 0;
        while (index < target.len) : (index += 1) {
            if (isSeparator(target[index]) and globMatches(directory_pattern, target[0..index])) return true;
        }
        return false;
    }
    if (startsWithNormalized(pattern, "**/")) {
        const suffix = pattern[3..];
        if (!hasGlobSyntax(suffix) and (pathEndsWith(target, suffix) or pathContainsSegmentSuffix(target, suffix))) return true;
    }
    if (!hasGlobSyntax(pattern)) {
        if (absolute or anchored or containsSeparator(pattern)) {
            return pathEql(target, pattern) or pathStartsWith(target, pattern);
        }
        return pathEql(target, pattern) or pathEndsWith(target, pattern) or pathStartsWith(target, pattern);
    }
    if (absolute or anchored or containsSeparator(pattern)) return globMatches(pattern, target);
    if (globMatches(pattern, target)) return true;
    var index: usize = 0;
    while (index < target.len) : (index += 1) {
        if (isSeparator(target[index]) and globMatches(pattern, target[index + 1 ..])) return true;
    }
    return false;
}

fn normalizePattern(pattern: []const u8) []const u8 {
    var result = pattern;
    while (startsWithNormalized(result, "./")) result = result[2..];
    while (result.len > 1 and isSeparator(result[result.len - 1])) result = result[0 .. result.len - 1];
    return result;
}

fn hasGlobSyntax(pattern: []const u8) bool {
    return std.mem.indexOfAny(u8, pattern, "*?[{") != null;
}

fn globMatches(pattern: []const u8, path: []const u8) bool {
    return globMatchesAt(pattern, 0, path, 0);
}

fn globMatchesAt(pattern: []const u8, pattern_index: usize, path: []const u8, path_index: usize) bool {
    var pi = pattern_index;
    var si = path_index;
    while (pi < pattern.len) {
        const char = normalizedChar(pattern[pi]);
        if (char == '*') {
            if (pi + 1 < pattern.len and pattern[pi + 1] == '*') {
                var next = pi + 2;
                while (next < pattern.len and pattern[next] == '*') next += 1;
                if (next < pattern.len and isSeparator(pattern[next])) {
                    next += 1;
                    if (globMatchesAt(pattern, next, path, si)) return true;
                    var cursor = si;
                    while (cursor < path.len) : (cursor += 1) {
                        if (isSeparator(path[cursor]) and globMatchesAt(pattern, next, path, cursor + 1)) return true;
                    }
                    return false;
                }
                var cursor = si;
                while (true) : (cursor += 1) {
                    if (globMatchesAt(pattern, next, path, cursor)) return true;
                    if (cursor == path.len) return false;
                }
            }
            var cursor = si;
            while (true) : (cursor += 1) {
                if (globMatchesAt(pattern, pi + 1, path, cursor)) return true;
                if (cursor == path.len or isSeparator(path[cursor])) return false;
            }
        }
        if (char == '?') {
            if (si == path.len or isSeparator(path[si])) return false;
            pi += 1;
            si += 1;
            continue;
        }
        if (char == '{') {
            const end = std.mem.indexOfScalarPos(u8, pattern, pi + 1, '}') orelse return false;
            var choices = std.mem.splitScalar(u8, pattern[pi + 1 .. end], ',');
            while (choices.next()) |choice| {
                if (pathHasLiteral(path, si, choice) and globMatchesAt(pattern, end + 1, path, si + choice.len)) return true;
            }
            return false;
        }
        if (char == '[') {
            const end = std.mem.indexOfScalarPos(u8, pattern, pi + 1, ']') orelse return false;
            if (si == path.len or isSeparator(path[si]) or !classMatches(pattern[pi + 1 .. end], path[si])) return false;
            pi = end + 1;
            si += 1;
            continue;
        }
        if (si == path.len or normalizedChar(path[si]) != char) return false;
        pi += 1;
        si += 1;
    }
    return si == path.len;
}

fn classMatches(class: []const u8, value: u8) bool {
    if (class.len == 0) return false;
    const negated = class[0] == '!' or class[0] == '^';
    var matched = false;
    var index: usize = if (negated) 1 else 0;
    while (index < class.len) : (index += 1) {
        if (index + 2 < class.len and class[index + 1] == '-') {
            matched = matched or (value >= class[index] and value <= class[index + 2]);
            index += 2;
        } else {
            matched = matched or value == class[index];
        }
    }
    return if (negated) !matched else matched;
}

fn pathHasLiteral(path: []const u8, start: usize, literal: []const u8) bool {
    if (start + literal.len > path.len) return false;
    for (literal, 0..) |char, index| {
        if (normalizedChar(path[start + index]) != normalizedChar(char)) return false;
    }
    return true;
}

fn pathEql(path: []const u8, pattern: []const u8) bool {
    return path.len == pattern.len and pathHasLiteral(path, 0, pattern);
}

fn pathStartsWith(path: []const u8, pattern: []const u8) bool {
    return pathHasLiteral(path, 0, pattern) and path.len > pattern.len and isSeparator(path[pattern.len]);
}

fn pathEndsWith(path: []const u8, pattern: []const u8) bool {
    if (pattern.len > path.len) return false;
    const start = path.len - pattern.len;
    return pathHasLiteral(path, start, pattern) and start > 0 and isSeparator(path[start - 1]);
}

fn pathContainsSegmentSuffix(path: []const u8, suffix: []const u8) bool {
    if (suffix.len > path.len) return false;
    var index: usize = 0;
    while (index + suffix.len <= path.len) : (index += 1) {
        if ((index == 0 or isSeparator(path[index - 1])) and pathHasLiteral(path, index, suffix)) return true;
    }
    return false;
}

fn containsSeparator(value: []const u8) bool {
    for (value) |char| if (isSeparator(char)) return true;
    return false;
}

fn startsWithNormalized(value: []const u8, prefix: []const u8) bool {
    return value.len >= prefix.len and pathHasLiteral(value, 0, prefix);
}

fn endsWithNormalized(value: []const u8, suffix: []const u8) bool {
    return value.len >= suffix.len and pathHasLiteral(value, value.len - suffix.len, suffix);
}

fn normalizedChar(char: u8) u8 {
    return if (char == '\\') '/' else char;
}

fn isSeparator(char: u8) bool {
    return char == '/' or char == '\\';
}

test "glob matching covers flat config selectors" {
    try std.testing.expect(globMatches("src/**/*.ts", "src/index.ts"));
    try std.testing.expect(globMatches("src/**/*.ts", "src/nested/index.ts"));
    try std.testing.expect(globMatches("**/*.{js,ts}", "packages/app/src/index.ts"));
    try std.testing.expect(globMatches("test/?oo.[jt]s", "test/foo.js"));
    try std.testing.expect(!globMatches("src/**/*.ts", "test/index.ts"));
}
