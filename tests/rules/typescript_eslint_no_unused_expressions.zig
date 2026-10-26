const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "documents assertion migration differences from TypeScript ESLint 5.62" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "export function f(value: unknown) { value as string; }", .count = 1 },
        .{ .source = "export function f(value: unknown) { value; }", .count = 1 },
        .{ .source = "export function f(value: () => void) { value(); }", .count = 0 },
    };
    var options = lint.Options.allDisabled();
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-expressions", .{ .string = "error" });
    for (cases) |case| {
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.count, result.diagnostics.len);
        for (result.diagnostics) |diagnostic| {
            try std.testing.expectEqualStrings(lint.rules.typescript_eslint_no_unused_expressions.id, diagnostic.rule_id);
            try std.testing.expectEqualStrings("Expected an assignment or function call and instead saw an expression.", diagnostic.message);
        }
    }
}

test "reports @typescript-eslint/no-unused-expressions for expressions without side effects" {
    const source =
        \\foo;
        \\1;
        \\`text`;
        \\foo + bar;
        \\foo && bar();
        \\foo ? bar() : baz();
        \\obj.prop;
        \\[foo];
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_expressions.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_unused_expressions.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_no_unused_expressions.id)) {
            try std.testing.expectEqual(lint.Severity.@"error", diagnostic.severity);
        }
    }
}

test "allows fishlint short circuit ternary and tagged template expressions" {
    const source =
        \\foo && bar();
        \\foo ? bar() : baz();
        \\tag`template`;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_unused_expressions.id));
}

test "honors @typescript-eslint/no-unused-expressions allow options" {
    const source =
        \\foo && bar();
        \\foo ? bar() : baz();
        \\tag`template`;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_expressions_allow_short_circuit = .no,
        .typescript_eslint_no_unused_expressions_allow_ternary = .no,
        .typescript_eslint_no_unused_expressions_allow_tagged_templates = .no,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_expressions.id));
}

test "can disable @typescript-eslint/no-unused-expressions and fall back to core rule" {
    const source =
        \\foo && bar();
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_expressions = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_unused_expressions.id));
    try std.testing.expect(helpers.hasRule(result, lint.rules.no_unused_expressions.id));
}
