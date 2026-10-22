const std = @import("std");
const lint = @import("utoo_lint");

test "semantic checking preserves full diagnostics without constructing the model" {
    const cases = [_]struct {
        source: []const u8,
        path: []const u8,
        has_errors: bool = true,
        suppressed_count: usize = 0,
    }{
        .{ .source = "let value; const value = 1; export { missing };", .path = "fixture.js" },
        .{ .source = "'use strict'; function sum(a, a) { return a; }", .path = "fixture.cjs" },
        .{ .source = "let value: number; let value: number; export { missing };", .path = "fixture.ts" },
        .{
            .source =
            \\namespace NS { export interface Item { value: number; } }
            \\namespace NS { export interface Item { label: string; } }
            \\const item: NS.Item = { value: 1, label: 'one' };
            \\export { item };
            ,
            .path = "fixture.ts",
            .has_errors = false,
        },
        .{
            .source =
            \\// utlint-ignore no-debugger: generated breakpoint
            \\debugger;
            \\let value; let value;;
            ,
            .path = "fixture.js",
            .suppressed_count = 1,
        },
        .{ .source = "const = ;", .path = "fixture.js" },
    };
    for (cases) |case| {
        var check_options = lint.Options.allDisabled();
        check_options.parser_semantic_errors = true;
        check_options.no_debugger = true;
        check_options.no_extra_semi = true;
        var checked = try lint.lintSource(std.testing.allocator, case.source, case.path, check_options);
        defer checked.deinit(std.testing.allocator);

        var model_options = check_options;
        // This rule needs the model, but none of these fixtures calls Array.
        model_options.no_array_constructor = true;
        var analyzed = try lint.lintSource(std.testing.allocator, case.source, case.path, model_options);
        defer analyzed.deinit(std.testing.allocator);

        try std.testing.expectEqual(case.has_errors, checked.hasErrors());
        try std.testing.expectEqual(case.suppressed_count, checked.suppressed_diagnostics.len);
        try std.testing.expectEqualDeep(analyzed.diagnostics, checked.diagnostics);
        try std.testing.expectEqualDeep(analyzed.suppressed_diagnostics, checked.suppressed_diagnostics);
    }
}

test "model-dependent rules retain semantic errors when the standalone check is disabled" {
    const source = "let value; let value;";
    var options = lint.Options.allDisabled();
    var unchecked = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer unchecked.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), unchecked.diagnostics.len);

    options.no_array_constructor = true;
    var analyzed = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer analyzed.deinit(std.testing.allocator);
    try std.testing.expect(analyzed.hasErrors());

    options.no_array_constructor = false;
    options.parser_semantic_errors = true;
    var checked = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer checked.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(analyzed.diagnostics, checked.diagnostics);
}
