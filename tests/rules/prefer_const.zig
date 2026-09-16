const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports prefer-const for initialized let declarations that are never reassigned" {
    const source =
        \\let a = 1;
        \\let { b } = obj;
        \\let [c] = list;
        \\for (let key in obj) {
        \\  console.log(key);
        \\}
        \\for (let value of list) {
        \\  console.log(value);
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), helpers.countRule(result, lint.rules.prefer_const.id));
}

test "autofixes fully const-compatible let declarations" {
    const source =
        \\let a = 1;
        \\let b = 2, c = 3;
        \\let { d, e } = obj;
        \\for (let key in obj) {
        \\  console.log(key);
        \\}
        \\for (let value of list) {
        \\  console.log(value);
        \\}
        \\let/* keep */ f = 4;
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .capitalized_comments = false,
        .eol_last = false,
        .no_console = false,
        .no_for_in = false,
        .no_undef = false,
        .no_unused_vars = false,
        .one_var = false,
        .prefer_destructuring = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\const a = 1;
        \\const b = 2, c = 3;
        \\const { d, e } = obj;
        \\for (const key in obj) {
        \\  console.log(key);
        \\}
        \\for (const value of list) {
        \\  console.log(value);
        \\}
        \\const/* keep */ f = 4;
    , result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.prefer_const.id));
}

test "autofix refuses partially compatible or delayed let declarations" {
    const source =
        \\let safe = 1;
        \\let stable = 1, changed = 2;
        \\changed++;
        \\let delayed;
        \\delayed = 1;
        \\let { left, right } = obj;
        \\right = 2;
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_plusplus = false,
        .no_undef = false,
        .no_unused_vars = false,
        .one_var = false,
        .prefer_destructuring = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\const safe = 1;
        \\let stable = 1, changed = 2;
        \\changed++;
        \\let delayed;
        \\delayed = 1;
        \\let { left, right } = obj;
        \\right = 2;
    , result.output);
    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result.result, lint.rules.prefer_const.id));
    for (result.result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.prefer_const.id)) {
            try std.testing.expectEqual(@as(usize, 0), diagnostic.fixes.len);
        }
    }
}

test "autofixes destructuring only when all bindings qualify in all mode" {
    const source =
        \\let { a, b } = first;
        \\let { c, d } = second;
        \\d = 2;
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .prefer_const_destructuring = .all,
        .prefer_destructuring = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\const { a, b } = first;
        \\let { c, d } = second;
        \\d = 2;
    , result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.prefer_const.id));
}

test "does not report prefer-const for reassigned let bindings or read-before-assign declarations by default" {
    const source =
        \\let a = 1;
        \\a = 2;
        \\let b = 1;
        \\b++;
        \\let c;
        \\console.log(c);
        \\c = 1;
        \\for (let key in obj) {
        \\  key = "other";
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.prefer_const.id));
}

test "supports configured prefer-const ignoreReadBeforeAssign false" {
    const source =
        \\let assignedOnce;
        \\assignedOnce = 1;
        \\console.log(assignedOnce);
        \\let readBefore;
        \\console.log(readBefore);
        \\readBefore = 1;
        \\let reassigned;
        \\reassigned = 1;
        \\reassigned = 2;
    ;

    var default_result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer default_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(default_result, lint.rules.prefer_const.id));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreReadBeforeAssign\":false}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("prefer-const", config.value);
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    var configured_result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer configured_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(configured_result, lint.rules.prefer_const.id));
}

test "reports prefer-const for destructuring any by default" {
    const source =
        \\let { a, b } = obj;
        \\b = 2;
        \\let [c, d] = list;
        \\d++;
        \\for (let [e, f] of entries) {
        \\  f = 2;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.prefer_const.id));
}

test "reports prefer-const for destructuring only when all bindings qualify in all mode" {
    const source =
        \\let { a, b } = obj;
        \\b = 2;
        \\let [c, d] = list;
        \\let { e: { f }, ...rest } = other;
        \\rest = {};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .prefer_const_destructuring = .all,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.prefer_const.id));
}

test "uses configured prefer-const destructuring all mode" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"destructuring\":\"all\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("prefer-const", config.value);
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\let { a, b } = obj;
        \\b = 2;
        \\let [c, d] = list;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.prefer_const.id));
}

test "does not report prefer-const for delayed assignments outside the declaration's statement list" {
    const source =
        \\let value;
        \\try {
        \\  value = 1;
        \\} catch (error) {
        \\  throw error;
        \\}
        \\console.log(value);
        \\let branch;
        \\if (value) branch = 1;
        \\console.log(branch);
        \\let nested;
        \\{
        \\  nested = 2;
        \\}
        \\console.log(nested);
        \\let labeled;
        \\done: labeled = 3;
        \\console.log(labeled);
        \\let inline;
        \\console.log(inline = 4);
        \\let sequenced;
        \\sequenced = 5, console.log(sequenced);
        \\function scoped() {
        \\  let local;
        \\  if (value) {
        \\    local = 6;
        \\  }
        \\  return local;
        \\}
        \\scoped();
        \\export let exported;
        \\{
        \\  exported = 7;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_console = false,
        .no_unused_vars = false,
        .no_unused_expressions = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.prefer_const.id));
}

test "reports prefer-const for delayed assignments in the declaration's statement list" {
    const source =
        \\let top;
        \\top = 1;
        \\console.log(top);
        \\function scoped() {
        \\  let local;
        \\  local = 2;
        \\  return local;
        \\}
        \\switch (scoped()) {
        \\  case 1:
        \\    let shared;
        \\    break;
        \\  default:
        \\    shared = 3;
        \\    console.log(shared);
        \\}
        \\class Holder {
        \\  static {
        \\    let inner;
        \\    inner = 4;
        \\    console.log(inner);
        \\  }
        \\}
        \\export let exported;
        \\exported = 5;
        \\let wrapped;
        \\((wrapped = 6));
        \\console.log(wrapped);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_case_declarations = false,
        .no_console = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(result, lint.rules.prefer_const.id));
}

test "can disable prefer-const" {
    const source =
        \\let a = 1;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .prefer_const = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.prefer_const.id));
}
