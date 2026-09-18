const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-unused-vars for unused declarations" {
    const source =
        \\const unused = 1;
        \\const used = 2;
        \\console.log(used);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .typescript_eslint_no_unused_vars = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(helpers.hasRule(result, lint.rules.no_unused_vars.id));
}

test "ignores unused catch parameters by default" {
    const source =
        \\try {
        \\  run();
        \\} catch (unusedError) {
        \\}
        \\try {
        \\  run();
        \\} catch (usedError) {
        \\  console.log(usedError);
        \\}
        \\try {
        \\  run();
        \\} catch {
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_undef = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars args all" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"args\":\"all\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\function demo(before, used, after) {
        \\  console.log(used);
        \\}
        \\demo(1, 2, 3);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars vars local" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"vars\":\"local\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const globalUnused = 1;
        \\function demo() {
        \\  const localUnused = 2;
        \\}
        \\demo();
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.cjs", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars caughtErrors none" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"caughtErrors\":\"none\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\try {
        \\  run();
        \\} catch (unusedError) {
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars ignoreRestSiblings" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreRestSiblings\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const data = { a: 1, b: 2 };
        \\const { a, ...rest } = data;
        \\console.log(rest);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars ignoreUsingDeclarations" {
    const source =
        \\using resource = acquire();
    ;

    var default_result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_undef = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer default_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(default_result, lint.rules.no_unused_vars.id));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreUsingDeclarations\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    var ignored_result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer ignored_result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(ignored_result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars ignoreClassWithStaticInitBlock" {
    const source =
        \\class IgnoredWithStatic {
        \\  static {
        \\    const stillReported = 1;
        \\    setup();
        \\  }
        \\}
        \\const reportedExpression = class {
        \\  static {
        \\    setup();
        \\  }
        \\};
        \\class ReportedPlain {}
    ;

    var default_result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_undef = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer default_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(default_result, lint.rules.no_unused_vars.id));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreClassWithStaticInitBlock\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    var ignored_result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer ignored_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(ignored_result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars varsIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"varsIgnorePattern\":\"^ignored\",\"args\":\"all\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_empty = false;
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const ignoredValue = 1;
        \\const unusedValue = 2;
        \\function demo(ignoredParam) {
        \\  try {
        \\    run();
        \\  } catch (ignoredError) {
        \\  }
        \\}
        \\demo();
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars argsIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"args\":\"all\",\"argsIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\function demo(ignoredParam, unusedParam, usedParam) {
        \\  console.log(usedParam);
        \\}
        \\demo(1, 2, 3);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars caughtErrorsIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"caughtErrors\":\"all\",\"caughtErrorsIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\try {
        \\  run();
        \\} catch (ignoredError) {
        \\}
        \\try {
        \\  run();
        \\} catch (unusedError) {
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars destructuredArrayIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"destructuredArrayIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const [ignoredItem, unusedItem, usedItem] = items;
        \\console.log(usedItem);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_unused_vars.id));
}

test "supports configured no-unused-vars reportUsedIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"args\":\"all\",\"argsIgnorePattern\":\"^ignored\",\"caughtErrors\":\"all\",\"caughtErrorsIgnorePattern\":\"^ignored\",\"destructuredArrayIgnorePattern\":\"^ignored\",\"reportUsedIgnorePattern\":true,\"varsIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-unused-vars", config.value);
    options.no_undef = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const ignoredValue = 1;
        \\function demo(ignoredParam) {
        \\  console.log(ignoredValue, ignoredParam);
        \\  try {
        \\    run();
        \\  } catch (ignoredError) {
        \\    console.log(ignoredError);
        \\  }
        \\  const [ignoredItem] = items;
        \\  console.log(ignoredItem);
        \\}
        \\demo(1);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.no_unused_vars.id));
}

test "underscore parameters follow args and argsIgnorePattern" {
    const cases = [_]struct { config: []const u8, count: usize }{
        .{ .config = "[\"error\",{\"args\":\"after-used\",\"argsIgnorePattern\":\"^NEVER$\"}]", .count = 2 },
        .{ .config = "[\"error\",{\"args\":\"after-used\"}]", .count = 2 },
        .{ .config = "[\"error\",{\"args\":\"all\"}]", .count = 2 },
        .{ .config = "[\"error\",{\"args\":\"all\",\"argsIgnorePattern\":\"^_\"}]", .count = 0 },
        .{ .config = "[\"error\",{\"args\":\"none\"}]", .count = 0 },
    };
    for ([_][]const u8{ "no-unused-vars", "@typescript-eslint/no-unused-vars" }) |rule_id| {
        for (cases) |case| {
            var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, case.config, .{});
            defer config.deinit();
            var options = lint.Options.allDisabled();
            try options.setByRuleConfigValue(rule_id, config.value);
            var result = try lint.lintSource(std.testing.allocator, "export function example(_first, _second) { return null; }", "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(case.count, helpers.countRule(result, rule_id));
        }
        var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "[\"error\",{\"args\":\"after-used\"}]", .{});
        defer config.deinit();
        var options = lint.Options.allDisabled();
        try options.setByRuleConfigValue(rule_id, config.value);
        var result = try lint.lintSource(std.testing.allocator, "export function example(_before, used, _after) { return used; }", "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, rule_id));
        try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[0].message, "_after") != null);
    }
}

test "underscore argsIgnorePattern supports regex classes groups and quantifiers" {
    for ([_][]const u8{ "no-unused-vars", "@typescript-eslint/no-unused-vars" }) |rule_id| {
        for ([_][]const u8{
            "^_[A-Z]+$",
            "^_(?:FOO|BAR)$",
            "^_[A-Z]{3}$",
            "^_F[A-Z]*$",
        }) |pattern| {
            var options = lint.Options.allDisabled();
            _ = options.setByCliName(rule_id, true);
            options.no_unused_vars_args = .all;
            options.typescript_eslint_no_unused_vars_args = .all;
            try options.no_unused_vars_args_ignore_pattern.set(pattern);
            try options.typescript_eslint_no_unused_vars_args_ignore_pattern.set(pattern);
            var result = try lint.lintSource(std.testing.allocator, "export function example(_FOO, _lower) { return null; }", "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, rule_id));
            try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[0].message, "_lower") != null);
        }
    }
}
