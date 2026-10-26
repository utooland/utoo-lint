const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports restricted syntax selectors" {
    const source =
        \\with (scope) {
        \\  value;
        \\}
        \\label: while (value) {
        \\  break label;
        \\}
    ;

    const options = try optionsWithConfig(
        "[\"error\",\"WithStatement\",{\"selector\":\"labeled_statement\",\"message\":\"Labels are not allowed.\"}]",
    );
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.cjs", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_restricted_syntax.id));
    try std.testing.expect(hasMessage(result, "Using 'WithStatement' is not allowed."));
    try std.testing.expect(hasMessage(result, "Labels are not allowed."));
}

test "supports cli-style selector entries" {
    const source =
        \\debugger;
    ;

    var options = baseOptions();
    var entry = lint.NoRestrictedSyntaxEntry{};
    try std.testing.expect(entry.setSelector("DebuggerStatement"));
    try std.testing.expect(options.no_restricted_syntax_entries.append(entry));
    options.no_restricted_syntax = true;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_restricted_syntax.id));
}

test "does not treat complex esquery selectors as node selectors" {
    const source =
        \\setTimeout(work, 100);
    ;

    const options = try optionsWithConfig(
        "[\"error\",\"CallExpression[callee.name='setTimeout']\"]",
    );
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_restricted_syntax.id));
}

test "parses no-restricted-syntax config" {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"WithStatement\",{\"selector\":\"LabeledStatement\",\"message\":\"No labels.\"}]",
        .{},
    );
    defer parsed.deinit();

    var options = baseOptions();
    try options.setByRuleConfigValue("no-restricted-syntax", parsed.value);

    try std.testing.expect(options.no_restricted_syntax);
    try std.testing.expectEqual(@as(usize, 2), options.no_restricted_syntax_entries.count);
    try std.testing.expectEqualStrings("WithStatement", options.no_restricted_syntax_entries.at(0).selector());
    try std.testing.expectEqualStrings("LabeledStatement", options.no_restricted_syntax_entries.at(1).selector());
    try std.testing.expectEqualStrings("No labels.", options.no_restricted_syntax_entries.at(1).message().?);
}

test "can disable no-restricted-syntax" {
    const source =
        \\with (scope) {
        \\  value;
        \\}
    ;

    var options = try optionsWithConfig("[\"error\",\"WithStatement\"]");
    options.no_restricted_syntax = false;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.cjs", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_restricted_syntax.id));
}

fn optionsWithConfig(config: []const u8) !lint.Options {
    var options = baseOptions();
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, config, .{});
    defer parsed.deinit();
    try options.setByRuleConfigValue("no-restricted-syntax", parsed.value);
    return options;
}

fn baseOptions() lint.Options {
    var options = lint.Options.allDisabled();
    options.parser_semantic_errors = false;
    return options;
}

fn hasMessage(result: lint.Result, needle: []const u8) bool {
    for (result.diagnostics) |diagnostic| {
        if (!std.mem.eql(u8, diagnostic.rule_id, lint.rules.no_restricted_syntax.id)) continue;
        if (std.mem.indexOf(u8, diagnostic.message, needle) != null) return true;
    }
    return false;
}
