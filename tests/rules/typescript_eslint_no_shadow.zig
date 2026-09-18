const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/no-shadow for TypeScript value and type shadows" {
    const source =
        \\const value = 1;
        \\type Box = {};
        \\interface Shape {}
        \\declare const ambient: string;
        \\function f(value: number) {
        \\  type Box = {};
        \\  interface Shape {}
        \\  return value;
        \\}
        \\function g<Box>() {
        \\  return null as Box;
        \\}
        \\function h(ambient: string) {
        \\  return ambient;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .typescript_eslint_consistent_type_definitions = false,
        .typescript_eslint_no_empty_interface = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), helpers.countRule(result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_shadow.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_no_shadow.id)) {
            try std.testing.expectEqual(lint.Severity.@"error", diagnostic.severity);
        }
    }
}

test "allows @typescript-eslint/no-shadow TypeScript class interface merging" {
    const source =
        \\class Model {}
        \\function f() {
        \\  interface Model {}
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .typescript_eslint_no_empty_interface = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_shadow.id));
}

test "supports configured @typescript-eslint/no-shadow allow names" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"value\"]}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-shadow", config.value);
    options.no_unused_vars = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const value = 1;
        \\const other = 2;
        \\function f(value: number) {
        \\  return value;
        \\}
        \\function g(other: number) {
        \\  return other;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_shadow.id));
}

test "supports configured @typescript-eslint/no-shadow built-in globals" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"builtinGlobals\":true,\"allow\":[\"Object\"]}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-shadow", config.value);
    options.no_unused_vars = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\function allowed(Object: unknown) {
        \\  return Object;
        \\}
        \\function reported(Array: unknown) {
        \\  return Array;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_shadow.id));
}

test "supports configured @typescript-eslint/no-shadow hoist option" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"hoist\":\"never\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-shadow", config.value);
    options.no_unused_vars = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\function f() {
        \\  {
        \\    const laterValue = 1;
        \\  }
        \\  const laterValue = 2;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_shadow.id));
}

test "supports configured @typescript-eslint/no-shadow ignoreOnInitialization" {
    const source =
        \\function wrapper(fn) {
        \\  return fn;
        \\}
        \\const callback = wrapper(function(callback) {
        \\  return callback;
        \\});
        \\const immediate = (function(immediate) {
        \\  return immediate;
        \\})();
        \\const direct = direct => direct;
    ;

    var default_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer default_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(default_result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(default_result, lint.rules.no_shadow.id));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreOnInitialization\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-shadow", config.value);
    options.no_unused_vars = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    var ignored_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer ignored_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(ignored_result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(ignored_result, lint.rules.no_shadow.id));
}

test "supports configured @typescript-eslint/no-shadow ignoreTypeValueShadow" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreTypeValueShadow\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-shadow", config.value);
    options.no_unused_vars = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\type TypeName = string;
        \\const valueName = 1;
        \\const other = 2;
        \\function f(TypeName: string) {
        \\  return TypeName;
        \\}
        \\function g() {
        \\  type valueName = string;
        \\  return null as valueName;
        \\}
        \\function h(other: string) {
        \\  return other;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_shadow.id));
}

test "supports configured @typescript-eslint/no-shadow ignoreFunctionTypeParameterNameValueShadow" {
    const source =
        \\const value = 1;
        \\type Fn = (value: string) => typeof value;
    ;

    var default_options = lint.Options{};
    default_options.no_unused_vars = false;
    default_options.typescript_eslint_no_unused_vars = false;
    default_options.parser_semantic_errors = false;

    var default_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", default_options);
    defer default_result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(default_result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(default_result, lint.rules.no_shadow.id));

    var report_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreFunctionTypeParameterNameValueShadow\":false}]",
        .{},
    );
    defer report_config.deinit();

    var report_options = lint.Options{};
    try report_options.setByRuleConfigValue("@typescript-eslint/no-shadow", report_config.value);
    report_options.no_unused_vars = false;
    report_options.typescript_eslint_no_unused_vars = false;
    report_options.parser_semantic_errors = false;

    var report_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", report_options);
    defer report_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(report_result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expect(!helpers.hasRule(report_result, lint.rules.no_shadow.id));
}

test "can disable @typescript-eslint/no-shadow and fall back to no-shadow" {
    const source =
        \\const value = 1;
        \\function f(value: number) {
        \\  return value;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .typescript_eslint_no_shadow = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_shadow.id));
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_shadow.id));
}

test "type-only imports respect ignoreTypeValueShadow" {
    const cases = [_]struct { source: []const u8, ignored_count: usize }{
        .{ .source = "import type { Item } from './types'; export function example() { const Item: Item = { value: 1 }; return Item; }", .ignored_count = 0 },
        .{ .source = "import { type Item } from './types'; export function example() { const Item = 1; return Item; }", .ignored_count = 0 },
        .{ .source = "import type Item from './types'; export function example(Item: number) { return Item; }", .ignored_count = 0 },
        .{ .source = "import type * as Item from './types'; export function example() { const Item = 1; return Item; }", .ignored_count = 0 },
        .{ .source = "import { Item } from './types'; export function example() { const Item = 1; return Item; }", .ignored_count = 1 },
        .{ .source = "import type { Item } from './types'; export function example() { type Item = number; }", .ignored_count = 1 },
    };
    for (cases) |case| {
        for ([_]bool{ true, false }) |ignore| {
            var options = lint.Options.allDisabled();
            options.typescript_eslint_no_shadow = true;
            options.typescript_eslint_no_shadow_ignore_type_value_shadow = ignore;
            var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(if (ignore) case.ignored_count else @as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_shadow.id));
        }
    }
}

test "type-value shadows are ignored by default in every configuration form" {
    try std.testing.expect((lint.Options{}).typescript_eslint_no_shadow_ignore_type_value_shadow);
    try std.testing.expect(lint.Options.allDisabled().typescript_eslint_no_shadow_ignore_type_value_shadow);
    const source = "import type { Item } from './types'; export function example() { const Item: Item = { value: 1 }; return Item; }";
    for ([_][]const u8{ "true", "2", "\"error\"", "[\"error\"]", "[\"error\",{}]" }) |json| {
        var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
        defer config.deinit();
        var options = lint.Options.allDisabled();
        // Reconfiguring a rule must restore omitted options to their defaults.
        options.typescript_eslint_no_shadow_ignore_type_value_shadow = false;
        try options.setByRuleConfigValue("@typescript-eslint/no-shadow", config.value);
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, lint.rules.typescript_eslint_no_shadow.id));
    }
}
