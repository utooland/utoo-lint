const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/prefer-as-const for literal assertions" {
    const source =
        \\const a = 'alpha' as 'alpha';
        \\const b = <42>42;
        \\const c = true as true;
        \\const d = 10n as 10n;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.typescript_eslint_prefer_as_const.id));
}

test "reports @typescript-eslint/prefer-as-const for literal type annotations" {
    const source =
        \\const a: 'alpha' = 'alpha';
        \\class Example {
        \\  field: 42 = 42;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_prefer_as_const.id));
}

test "does not report @typescript-eslint/prefer-as-const for nonmatching literal types" {
    const source =
        \\const a = 'alpha' as string;
        \\const b = 1 as 2;
        \\const c: 'alpha' = 'beta';
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_prefer_as_const.id));
}

test "can disable @typescript-eslint/prefer-as-const" {
    const source =
        \\const a = 'alpha' as 'alpha';
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_prefer_as_const = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_prefer_as_const.id));
}

test "safe autofixes preserve comments and suppression" {
    const cases = [_]struct { source: []const u8, output: []const u8 }{
        .{ .source = "const x = 'value' as 'value';", .output = "const x = 'value' as const;" },
        .{ .source = "const x = 'value' as /* keep */ 'value';", .output = "const x = 'value' as /* keep */ const;" },
        .{ .source = "const x: 'value' = 'value';", .output = "const x: 'value' = 'value';" },
        .{ .source = "/* eslint-disable @typescript-eslint/prefer-as-const */ const x = 1 as 1;", .output = "/* eslint-disable @typescript-eslint/prefer-as-const */ const x = 1 as 1;" },
    };
    for (cases) |case| {
        var options = lint.Options.allDisabled();
        options.typescript_eslint_prefer_as_const = true;
        var result = try lint.lintSourceAndFix(std.testing.allocator, case.source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(case.output, result.output);
    }
}
