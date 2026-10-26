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

test "strict syntax remains a fatal parse error when lint rules are disabled" {
    const cases = [_]struct { source: []const u8, path: []const u8 }{
        .{ .source = "let x = 1; delete x;", .path = "fixture.js" },
        .{ .source = "with (obj) { value; }", .path = "fixture.mjs" },
        .{ .source = "'use strict'; delete (x);", .path = "fixture.cjs" },
        .{ .source = "'use strict'; with (obj) {}", .path = "fixture.cjs" },
        .{ .source = "function f() { 'use strict'; delete x; }", .path = "fixture.cjs" },
        .{ .source = "function f() { 'use strict'; function g() { with (obj) {} } }", .path = "fixture.cjs" },
        .{ .source = "const f = () => { 'use strict'; delete x; };", .path = "fixture.cjs" },
        .{ .source = "class C { method() { with (obj) {} } }", .path = "fixture.cjs" },
        .{ .source = "/* eslint-disable */\n'use strict'; delete x;", .path = "fixture.cjs" },
    };
    for (cases) |case| {
        var options = lint.Options.allDisabled();
        var result = try lint.lintSource(std.testing.allocator, case.source, case.path, options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
        try std.testing.expectEqualStrings("parse", result.diagnostics[0].rule_id);
        try std.testing.expectEqual(lint.Severity.@"error", result.diagnostics[0].severity);
        try std.testing.expectEqual(@as(usize, 0), result.suppressed_diagnostics.len);

        options.no_delete_var = true;
        options.no_with = true;
        options.no_array_constructor = true;
        var enabled = try lint.lintSource(std.testing.allocator, case.source, case.path, options);
        defer enabled.deinit(std.testing.allocator);
        try std.testing.expectEqualDeep(result.diagnostics, enabled.diagnostics);
    }
}

test "strict syntax respects sloppy scripts and lexical directive boundaries" {
    const sources = [_][]const u8{
        "let x = 1; delete x; with (obj) {}",
        "function f() { 'use strict'; return 1; } delete x; with (obj) {}",
        "0; 'use strict'; delete x; with (obj) {}",
        "('use strict'); delete x; with (obj) {}",
        "'use\\x20strict'; delete x; with (obj) {}",
        "{ 'use strict'; delete x; with (obj) {} }",
        "const obj = { method() { delete x; with (obj) {} } };",
        "'use strict'; delete obj.x; delete obj[key]; delete (0, x); delete x?.p;",
    };
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.cjs", lint.Options.allDisabled());
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    }
}

test "strict syntax follows configured source type instead of the file extension" {
    var options = lint.Options.allDisabled();
    options.source_type = .script;
    var script = try lint.lintSource(std.testing.allocator, "delete x; with (obj) {}", "fixture.js", options);
    defer script.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), script.diagnostics.len);

    options.source_type = .commonjs;
    var commonjs = try lint.lintSource(std.testing.allocator, "delete x; with (obj) {}", "fixture.js", options);
    defer commonjs.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), commonjs.diagnostics.len);

    options.source_type = .module;
    var module = try lint.lintSource(std.testing.allocator, "delete x; with (obj) {}", "fixture.cjs", options);
    defer module.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), module.diagnostics.len);
    for (module.diagnostics) |diagnostic| try std.testing.expectEqualStrings("parse", diagnostic.rule_id);
}
