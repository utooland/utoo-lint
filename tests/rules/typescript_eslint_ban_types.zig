const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/ban-types for fishlint banned default types" {
    const source =
        \\let text: String;
        \\let flag: Boolean;
        \\let count: Number;
        \\let sym: Symbol;
        \\let big: BigInt;
        \\let fn: Function;
        \\let value: Object;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .no_undef = false,
        .typescript_eslint_no_wrapper_object_types = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 7), helpers.countRule(result, lint.rules.typescript_eslint_ban_types.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_ban_types.id)) {
            try std.testing.expectEqual(lint.Severity.@"error", diagnostic.severity);
        }
    }
}

test "does not report @typescript-eslint/ban-types for fishlint allowed object forms" {
    const source =
        \\let value: object;
        \\let empty: {};
        \\let text: string;
        \\let count: number;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_ban_types.id));
}

test "supports @typescript-eslint/ban-types custom type config" {
    const source =
        \\let text: String;
        \\let value: object;
        \\let empty: {};
        \\let custom: CustomType;
    ;

    var config: @TypeOf((lint.Options{}).typescript_eslint_ban_types_config) = .{
        .extend_defaults = false,
    };
    try config.custom.append("object", "Use a named object shape.");
    try config.custom.append("{}", "Use Record<string, unknown>.");
    try config.custom.append("CustomType", "Use BetterType instead.");

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .no_undef = false,
        .typescript_eslint_ban_types_config = config,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.typescript_eslint_ban_types.id));
    try std.testing.expect(hasMessage(result, "Don't use `object` as a type. Use a named object shape."));
    try std.testing.expect(hasMessage(result, "Don't use `{}` as a type. Use Record<string, unknown>."));
    try std.testing.expect(hasMessage(result, "Don't use `CustomType` as a type. Use BetterType instead."));
}

test "supports @typescript-eslint/ban-types disabled default types" {
    const source =
        \\let text: String;
        \\let count: Number;
    ;

    var config: @TypeOf((lint.Options{}).typescript_eslint_ban_types_config) = .{};
    try config.disabled.append("String");

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .no_undef = false,
        .typescript_eslint_no_wrapper_object_types = false,
        .typescript_eslint_ban_types_config = config,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_ban_types.id));
    try std.testing.expect(hasMessage(result, "Don't use `Number` as a type. Use number instead"));
}

test "can disable @typescript-eslint/ban-types" {
    const source =
        \\let text: String;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_ban_types = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_ban_types.id));
}

fn hasMessage(result: lint.Result, expected: []const u8) bool {
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.message, expected)) return true;
    }
    return false;
}

test "ban-types safely fixes boxed primitives and preserves comments" {
    const cases = [_]struct { source: []const u8, output: []const u8, remaining: usize = 0 }{
        .{ .source = "export type A = String;", .output = "export type A = string;" },
        .{ .source = "type A = [String, Boolean, Number, Symbol, BigInt];", .output = "type A = [string, boolean, number, symbol, bigint];" },
        .{ .source = "type A = /* keep */ String[];", .output = "type A = /* keep */ string[];" },
        .{ .source = "type A = String<Other>;", .output = "type A = String<Other>;", .remaining = 1 },
        .{ .source = "type A = Function | Object;", .output = "type A = Function | Object;", .remaining = 2 },
        .{ .source = "// eslint-disable-next-line @typescript-eslint/ban-types\ntype A = String;", .output = "// eslint-disable-next-line @typescript-eslint/ban-types\ntype A = String;" },
    };
    for (cases) |case| {
        var options = lint.Options.allDisabled();
        options.typescript_eslint_ban_types = true;
        var result = try lint.lintSourceAndFix(std.testing.allocator, case.source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(case.output, result.output);
        try std.testing.expectEqual(case.remaining, helpers.countRule(result.result, lint.rules.typescript_eslint_ban_types.id));
        var second = try lint.lintSourceAndFix(std.testing.allocator, result.output, "fixture.ts", options);
        defer second.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(result.output, second.output);
        try std.testing.expect(!second.fixed);
    }
}

test "ban-types honors configured fixWith and disabled defaults" {
    const cases = [_]struct { config: []const u8, source: []const u8, output: []const u8, remaining: usize = 0 }{
        .{ .config = "[\"error\",{\"types\":{\"String\":false}}]", .source = "type A = String;", .output = "type A = String;" },
        .{ .config = "[\"error\",{\"types\":{\"String\":{\"message\":\"keep diagnostic\"}}}]", .source = "type A = String;", .output = "type A = String;", .remaining = 1 },
        .{ .config = "[\"error\",{\"extendDefaults\":false,\"types\":{\"Old\":{\"fixWith\":\"New\"}}}]", .source = "type A = Old;", .output = "type A = New;" },
        .{ .config = "[\"error\",{\"types\":{\"Old\":{\"fixWith\":\"string | number\"}}}]", .source = "type A = Old[];", .output = "type A = (string | number)[];" },
        .{ .config = "[\"error\",{\"types\":{\"{}\":{\"fixWith\":\"object\"}}}]", .source = "type A = {};", .output = "type A = object;" },
        .{ .config = "[\"error\",{\"types\":{\"{}\":{\"fixWith\":\"object\"}}}]", .source = "type A = { /* keep */ };", .output = "type A = { /* keep */ };", .remaining = 1 },
        .{ .config = "[\"error\",{\"types\":{\"object\":{\"fixWith\":\"unknown\"}}}]", .source = "type A = object;", .output = "type A = unknown;" },
        .{ .config = "[\"error\",{\"types\":{\"Old\":{\"fixWith\":\"Old | number\"}}}]", .source = "type A = Old;", .output = "type A = Old;", .remaining = 1 },
        .{ .config = "[\"error\",{\"types\":{\"Old\":{\"fixWith\":\"New\"},\"New\":{\"fixWith\":\"Old\"}}}]", .source = "type A = Old;", .output = "type A = Old;", .remaining = 1 },
        .{ .config = "[\"error\",{\"types\":{\"Old\":{\"fixWith\":\"New\"},\"New\":{\"fixWith\":\"number\"}}}]", .source = "type A = Old;", .output = "type A = number;" },
        .{ .config = "[\"error\",{\"types\":{\"Old\":{\"fixWith\":\"X; type Injected = number\"}}}]", .source = "type A = Old;", .output = "type A = Old;", .remaining = 1 },
    };
    for (cases) |case| {
        var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, case.config, .{});
        defer config.deinit();
        var options = lint.Options.allDisabled();
        try options.setByRuleConfigValue(lint.rules.typescript_eslint_ban_types.id, config.value);
        var result = try lint.lintSourceAndFix(std.testing.allocator, case.source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(case.output, result.output);
        try std.testing.expectEqual(case.remaining, helpers.countRule(result.result, lint.rules.typescript_eslint_ban_types.id));
        var second = try lint.lintSourceAndFix(std.testing.allocator, result.output, "fixture.ts", options);
        defer second.deinit(std.testing.allocator);
        try std.testing.expect(!second.fixed);
    }
}

test "ban-types respects the fix pass budget for replacement chains" {
    for ([_]usize{ lint.max_autofix_passes, lint.max_autofix_passes + 1 }) |length| {
        var options = lint.Options.allDisabled();
        options.typescript_eslint_ban_types = true;
        for (0..length) |index| {
            var name_buf: [8]u8 = undefined;
            var next_buf: [8]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buf, "T{d}", .{index});
            const replacement = if (index == length - 1) "number" else try std.fmt.bufPrint(&next_buf, "T{d}", .{index + 1});
            try options.typescript_eslint_ban_types_config.custom.appendWithFix(name, "Use replacement", replacement);
        }
        const source = "export type A = T0;";
        const within_budget = length <= lint.max_autofix_passes;
        var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(if (within_budget) "export type A = number;" else source, result.output);
        try std.testing.expectEqual(within_budget, result.fixed);
        try std.testing.expectEqual(@as(usize, if (within_budget) 0 else 1), helpers.countRule(result.result, lint.rules.typescript_eslint_ban_types.id));
        var second = try lint.lintSourceAndFix(std.testing.allocator, result.output, "fixture.ts", options);
        defer second.deinit(std.testing.allocator);
        try std.testing.expect(!second.fixed);
    }
}

test "ban-types memoized branches retain their remaining chain depth" {
    var options = lint.Options.allDisabled();
    options.typescript_eslint_ban_types = true;
    try options.typescript_eslint_ban_types_config.custom.appendWithFix("T0", "Use replacement", "T10 | T1");
    for (1..11) |index| {
        var name_buf: [8]u8 = undefined;
        var next_buf: [8]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "T{d}", .{index});
        const replacement = if (index == 10) "number" else try std.fmt.bufPrint(&next_buf, "T{d}", .{index + 1});
        try options.typescript_eslint_ban_types_config.custom.appendWithFix(name, "Use replacement", replacement);
    }
    for ([_]struct { source: []const u8, output: []const u8 }{
        .{ .source = "export type A = T0;", .output = "export type A = T0;" },
        .{ .source = "export type A = T1;", .output = "export type A = number;" },
    }) |case| {
        var result = try lint.lintSourceAndFix(std.testing.allocator, case.source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(case.output, result.output);
        var second = try lint.lintSourceAndFix(std.testing.allocator, result.output, "fixture.ts", options);
        defer second.deinit(std.testing.allocator);
        try std.testing.expect(!second.fixed);
    }
}
