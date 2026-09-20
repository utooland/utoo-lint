const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/no-inferrable-types for literal variables and properties" {
    const source =
        \\const name: string = "Ada";
        \\const count: number = -1;
        \\const enabled: boolean = Boolean(false);
        \\const missing: undefined = undefined;
        \\const pattern: RegExp = /x/;
        \\class Example {
        \\  value: number = 1;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(result, lint.rules.typescript_eslint_no_inferrable_types.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_no_inferrable_types.id)) {
            try std.testing.expectEqual(lint.Severity.@"error", diagnostic.severity);
        }
    }
}

test "reports @typescript-eslint/no-inferrable-types for defaulted parameters" {
    const source =
        \\function visit(name: string = "Ada", count: number = Number(1)) {
        \\  return name + count;
        \\}
        \\const arrow = (enabled: boolean = true) => enabled;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.typescript_eslint_no_inferrable_types.id));
}

test "supports configured @typescript-eslint/no-inferrable-types ignored parameters and properties" {
    const source =
        \\const name: string = "Ada";
        \\function visit(count: number = 1) {
        \\  return count;
        \\}
        \\class Example {
        \\  value: number = 1;
        \\}
    ;

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreParameters\":true,\"ignoreProperties\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    };
    try options.setByRuleConfigValue("@typescript-eslint/no-inferrable-types", config.value);

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_inferrable_types.id));
}

test "does not report @typescript-eslint/no-inferrable-types for non-inferrable annotations" {
    const source =
        \\const value: string | number = "Ada";
        \\const count: number = getCount();
        \\class Example {
        \\  readonly value: number = 1;
        \\  optional?: number = 1;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_inferrable_types.id));
}

test "can disable @typescript-eslint/no-inferrable-types" {
    const source =
        \\const name: string = "Ada";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_no_inferrable_types = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_inferrable_types.id));
}

test "safe autofixes preserve comments and suppression" {
    const cases = [_]struct { source: []const u8, output: []const u8 }{
        .{ .source = "const x: number = 1; function f(a: string = \"hi\") { return a; } class C { x!: number = 1; }", .output = "const x = 1; function f(a = \"hi\") { return a; } class C { x = 1; }" },
        .{ .source = "const x: /* keep */ number = 1;", .output = "const x: /* keep */ number = 1;" },
        .{ .source = "const x /* keep */: number = 1;", .output = "const x /* keep */ = 1;" },
        .{ .source = "class C { readonly x: number = 1; x?: number = 1; }", .output = "class C { readonly x: number = 1; x?: number = 1; }" },
        .{ .source = "/* eslint-disable @typescript-eslint/no-inferrable-types */ const x: number = 1;", .output = "/* eslint-disable @typescript-eslint/no-inferrable-types */ const x: number = 1;" },
    };
    for (cases) |case| {
        var options = lint.Options.allDisabled();
        options.typescript_eslint_no_inferrable_types = true;
        var result = try lint.lintSourceAndFix(std.testing.allocator, case.source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(case.output, result.output);
    }
}
