const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports require-atomic-updates for stale variable writes after await" {
    const source =
        \\let total = 0;
        \\async function add(value) {
        \\  total = total + await value;
        \\  total += await value;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.require_atomic_updates.id));
}

test "reports require-atomic-updates for stale property writes after await" {
    const source =
        \\async function update(obj, value) {
        \\  if (!obj.done) {
        \\    obj.count = await value;
        \\  }
        \\  obj.nested.count += await value;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.require_atomic_updates.id));
}

test "supports configured require-atomic-updates allowProperties" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowProperties\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    };
    try options.setByRuleConfigValue("require-atomic-updates", config.value);

    const source =
        \\let total = 0;
        \\async function update(obj, value) {
        \\  total += await value;
        \\  obj.count += await value;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.require_atomic_updates.id));
}

test "reports require-atomic-updates across yield in generators" {
    const source =
        \\let total = 0;
        \\function* add(value) {
        \\  total = total + (yield value);
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.require_atomic_updates.id));
}

test "does not report require-atomic-updates for local variables or rereads after await" {
    const source =
        \\async function local(value) {
        \\  let total = 0;
        \\  total = total + await value;
        \\  return total;
        \\}
        \\async function reread(obj, value) {
        \\  if (!obj.done) {
        \\    const next = await value;
        \\    if (!obj.done) {
        \\      obj.count = next;
        \\    }
        \\  }
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.require_atomic_updates.id));
}

test "does not report require-atomic-updates when the read occurs after await" {
    const source =
        \\let total = 0;
        \\async function add(value) {
        \\  total = await value + total;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.require_atomic_updates.id));
}

test "does not leak require-atomic-updates stale reads across exclusive branches" {
    const source =
        \\let total = 0;
        \\async function update(flag, value) {
        \\  if (flag) {
        \\    total;
        \\    await value;
        \\  } else {
        \\    total = 1;
        \\  }
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.require_atomic_updates.id));
}

test "can disable require-atomic-updates" {
    const source =
        \\let total = 0;
        \\async function add(value) {
        \\  total = total + await value;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .require_atomic_updates = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.require_atomic_updates.id));
}

test "captured shared property reads remain stale at write targets" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "const state = { count: 0 }; async function update(task) { const previous = state.count; await task(); state.count = previous + 1; }", .count = 1 },
        .{ .source = "const state = { count: 0 }; async function update(task) { const previous = state['count']; await task(); state['count'] = previous + 1; }", .count = 1 },
        .{ .source = "const state = { count: 0 }; async function update(task) { await task(); state.count = 1; }", .count = 0 },
        .{ .source = "const state = { count: 0 }; async function update(task) { const previous = state.count; await task(); state.count = state.count + 1; }", .count = 0 },
        .{ .source = "const state = { count: 0 }; async function update(task) { const previous = state.count; state.count = previous + 1; }", .count = 0 },
    };
    for (cases) |case| {
        for ([_]bool{ false, true }) |allow| {
            var options = lint.Options.allDisabled();
            options.require_atomic_updates = true;
            options.require_atomic_updates_allow_properties = allow;
            var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.js", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(if (allow) @as(usize, 0) else case.count, helpers.countRule(result, lint.rules.require_atomic_updates.id));
        }
    }
}
