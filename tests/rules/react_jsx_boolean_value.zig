const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports react/jsx-boolean-value for explicit true boolean attributes" {
    const source =
        \\const node = <Widget disabled={true} required={true} />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_jsx_boolean_value.id));
    try std.testing.expectEqualStrings("Value must be omitted for boolean attribute `disabled`", result.diagnostics[0].message);
}

test "allows omitted false and non-boolean JSX attribute values" {
    const source =
        \\const node = <Widget disabled checked={false} label="ok" count={1} />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_jsx_boolean_value.id));
}

test "reports react/jsx-boolean-value for omitted values when configured always" {
    const source =
        \\const node = <Widget disabled checked={true} label="ok" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", .{
        .eol_last = false,
        .react_jsx_boolean_value_style = .always,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_jsx_boolean_value.id));
    try std.testing.expectEqualStrings("Value must be set for boolean attribute `disabled`", result.diagnostics[0].message);
}

test "supports configured react/jsx-boolean-value always style" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\["error", "always"]
    ,
        .{},
    );
    defer config.deinit();

    var options = lint.Options{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    };
    try options.setByRuleConfigValue("react/jsx-boolean-value", config.value);

    const source =
        \\const node = <Widget disabled checked={true} />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_jsx_boolean_value.id));
}

test "can disable react/jsx-boolean-value" {
    const source =
        \\const node = <Widget disabled={true} />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", .{
        .eol_last = false,
        .react_jsx_boolean_value = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_jsx_boolean_value.id));
}

test "safe autofixes preserve comments and suppression" {
    const cases = [_]struct { source: []const u8, output: []const u8 }{
        .{ .source = "const x = <X disabled = {true} other={false} />;", .output = "const x = <X disabled other={false} />;" },
        .{ .source = "const x = <X disabled={/* keep */ true} />;", .output = "const x = <X disabled={/* keep */ true} />;" },
        .{ .source = "/* eslint-disable react/jsx-boolean-value */ const x = <X disabled={true} />;", .output = "/* eslint-disable react/jsx-boolean-value */ const x = <X disabled={true} />;" },
    };
    for (cases) |case| {
        var options = lint.Options.allDisabled();
        options.react_jsx_boolean_value = true;
        var result = try lint.lintSourceAndFix(std.testing.allocator, case.source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(case.output, result.output);
    }
}
