const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-eval for direct indirect and global eval calls" {
    const source =
        \\eval("code");
        \\(eval)("code");
        \\(0, eval)("code");
        \\globalThis["eval"]("code");
        \\globalThis[`eval`]("code");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_comma_operator = false,
        .no_sequences = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), helpers.countRule(result, lint.rules.no_eval.id));
}

test "reports no-eval for eval references outside call callees" {
    const source =
        \\var evalAlias = eval;
        \\foo(eval);
        \\const values = [eval];
        \\const wrapped = (eval);
        \\eval("code");
        \\(0, eval)("code");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_comma_operator = false,
        .no_sequences = false,
        .no_var = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(result, lint.rules.no_eval.id));
}

test "reports no-eval for unshadowed browser window calls" {
    const source =
        \\window.eval("code");
        \\window["eval"]("code");
        \\window[`eval`]("code");
        \\(window.eval)("code");
        \\window?.eval("code");
        \\window.eval?.("code");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(result, lint.rules.no_eval.id));
}

test "does not report no-eval for shadowed browser window or dynamic members" {
    const source =
        \\function callSandbox(window) {
        \\    window.eval("code");
        \\    window["eval"]("code");
        \\    window?.eval("code");
        \\}
        \\{
        \\    const window = sandbox;
        \\    window.eval("code");
        \\}
        \\window[method]("code");
        \\window[`ev${suffix}`]("code");
        \\window.other("code");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_eval.id));
}

test "does not report no-eval for non-global eval members" {
    const source =
        \\const object = { eval() {} };
        \\object.eval("code");
        \\object["eval"]("code");
        \\object[`eval`]("code");
        \\globalThis[`ev${suffix}`]("code");
        \\const window = sandbox;
        \\window.eval("code");
        \\global.eval("code");
        \\self.eval("code");
        \\this.eval("code");
        \\window["eval"]("code");
        \\global[`eval`]("code");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_empty_function = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_eval.id));
}

test "supports configured no-eval allowIndirect option" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowIndirect\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-eval", config.value);
    options.no_comma_operator = false;
    options.no_sequences = false;
    options.no_var = false;
    options.no_unused_vars = false;
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\eval("code");
        \\(eval)("code");
        \\(0, eval)("code");
        \\globalThis["eval"]("code");
        \\globalThis[`eval`]("code");
        \\window.eval("code");
        \\window["eval"]("code");
        \\window[`eval`]("code");
        \\window?.eval("code");
        \\window.eval?.("code");
        \\var evalAlias = eval;
        \\foo(eval);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_eval.id));
}

test "can disable no-eval" {
    const source =
        \\eval("code");
        \\window.eval("code");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_eval = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_eval.id));
}
