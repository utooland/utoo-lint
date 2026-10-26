const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-unsafe-optional-chaining for unsafe member call and constructor usage" {
    const source =
        \\(obj?.foo).bar;
        \\(obj?.foo)();
        \\new (obj?.foo)();
        \\(obj?.foo)`template`;
        \\
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.no_unsafe_optional_chaining.id));
    try std.testing.expectEqualStrings(
        "Unsafe usage of optional chaining. If it short-circuits with 'undefined' the evaluation will throw TypeError.",
        result.diagnostics[0].message,
    );
}

test "reports no-unsafe-optional-chaining for spread iteration and destructuring usage" {
    const source =
        \\foo(...obj?.args);
        \\const items = [...obj?.items];
        \\for (const item of obj?.items) {}
        \\for (const key in obj?.items) {}
        \\const { value } = obj?.data;
        \\let first;
        \\[first] = obj?.items;
        \\
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(result, lint.rules.no_unsafe_optional_chaining.id));
}

test "reports no-unsafe-optional-chaining for object binary with and extends usage" {
    const source =
        \\"value" in obj?.data;
        \\value instanceof obj?.Ctor;
        \\with (obj?.data) {}
        \\class Example extends obj?.Base {}
        \\
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.cjs", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.no_unsafe_optional_chaining.id));
}

test "allows no-unsafe-optional-chaining for safe optional continuation" {
    const source =
        \\obj?.foo;
        \\obj?.foo.bar;
        \\obj?.foo?.bar;
        \\(obj?.foo)?.bar;
        \\(obj?.foo)?.();
        \\const value = obj?.foo ?? fallback;
        \\const copy = { ...obj?.data };
        \\
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_unsafe_optional_chaining.id));
}

test "allows arithmetic optional chains by default" {
    const source =
        \\+obj?.value;
        \\obj?.value - 1;
        \\total += obj?.value;
        \\
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_unsafe_optional_chaining.id));
}

test "reports arithmetic optional chains when configured" {
    const source =
        \\+obj?.first;
        \\-obj?.second;
        \\obj?.third - 1;
        \\1 * obj?.fourth;
        \\total += obj?.fifth;
        \\
    ;

    var options = baseOptions();
    options.no_unsafe_optional_chaining_disallow_arithmetic_operators = true;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), helpers.countRule(result, lint.rules.no_unsafe_optional_chaining.id));
}

test "can disable no-unsafe-optional-chaining" {
    const source =
        \\(obj?.foo).bar;
        \\
    ;

    var options = baseOptions();
    options.no_unsafe_optional_chaining = false;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_unsafe_optional_chaining.id));
}

fn baseOptions() lint.Options {
    return .{
        .no_empty = false,
        .no_empty_block_statements = false,
        .no_undef = false,
        .no_unused_vars = false,
        .no_unused_expressions = false,
        .parser_semantic_errors = false,
    };
}
