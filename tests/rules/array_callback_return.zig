const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports array-callback-return when callbacks can fall through" {
    const source =
        \\items.map((item) => {
        \\  if (item) {
        \\    return item * 2;
        \\  }
        \\});
        \\items.filter(function(item) {
        \\  return void item;
        \\});
        \\items[`map`](function(item) {
        \\  item.value;
        \\});
        \\Array.from(items, function(item) {
        \\  item.toString();
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_undef = false,
        .no_unused_vars = false,
        .no_useless_return = false,
        .no_void = false,
        .eol_last = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.array_callback_return.id));
}

test "does not report array-callback-return for callbacks that return on all paths" {
    const source =
        \\items.map((item) => item * 2);
        \\items.filter(function(item) {
        \\  if (item) {
        \\    return item;
        \\  }
        \\  return fallback;
        \\});
        \\items.some((item) => {
        \\  if (item) {
        \\    return true;
        \\  }
        \\  throw error;
        \\});
        \\Array.from(items, (item) => item.id);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_undef = false,
        .no_unused_vars = false,
        .no_useless_return = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.array_callback_return.id));
}

test "does not report async or generator array callbacks" {
    const source =
        \\items.map(async (item) => {
        \\  await item.load();
        \\});
        \\items.map(function* (item) {
        \\  yield item;
        \\});
        \\items.forEach(async (item) => {
        \\  return item.save();
        \\});
        \\items.forEach(function* (item) {
        \\  return item;
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .array_callback_return_check_for_each = .yes,
        .no_undef = false,
        .no_unused_vars = false,
        .no_useless_return = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.array_callback_return.id));
}

test "reports array-callback-return for implicit returns by default" {
    const source =
        \\items.filter(function(item) {
        \\  if (item) {
        \\    return item;
        \\  }
        \\  return;
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_undef = false,
        .no_unused_vars = false,
        .no_useless_return = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.array_callback_return.id));
}

test "allows implicit returns when allowImplicit is enabled" {
    const source =
        \\items.filter(function(item) {
        \\  if (item) {
        \\    return item;
        \\  }
        \\  return;
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .array_callback_return_allow_implicit = .yes,
        .no_undef = false,
        .no_unused_vars = false,
        .no_useless_return = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.array_callback_return.id));
}

test "ignores forEach callbacks and non-function callback references" {
    const source =
        \\items.forEach((item) => {
        \\  return item.id;
        \\});
        \\items.forEach((item) => {
        \\  item.toString();
        \\});
        \\items.map(callback);
        \\items[`ma${suffix}`](function(item) {
        \\  item.value;
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.array_callback_return.id));
}

test "reports array-callback-return for forEach return values when checkForEach is enabled" {
    const source =
        \\items.forEach((item) => item.id);
        \\items.forEach(function(item) {
        \\  if (item.ready) {
        \\    return item.id;
        \\  }
        \\  return;
        \\});
        \\items.forEach((item) => {
        \\  return void item.touch();
        \\});
        \\items[`forEach`](function(item) {
        \\  return item.id;
        \\});
        \\items.forEach((item) => {
        \\  item.touch();
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .array_callback_return_check_for_each = .yes,
        .no_undef = false,
        .no_unused_vars = false,
        .no_useless_return = false,
        .no_void = false,
        .eol_last = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.array_callback_return.id));
    try std.testing.expectEqualStrings(
        "Array.prototype.forEach() expects no useless return value from callback.",
        result.diagnostics[0].message,
    );
}

test "allows void returns from forEach callbacks when allowVoid is enabled" {
    const source =
        \\items.forEach((item) => void item.touch());
        \\items.forEach(function(item) {
        \\  return void item.touch();
        \\});
        \\items.forEach(function(item) {
        \\  return item.id;
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .array_callback_return_check_for_each = .yes,
        .array_callback_return_allow_void = .yes,
        .no_undef = false,
        .no_unused_vars = false,
        .no_useless_return = false,
        .no_void = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.array_callback_return.id));
}

test "can disable array-callback-return" {
    const source =
        \\items.map((item) => {
        \\  item.toString();
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .array_callback_return = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.array_callback_return.id));
}

test "switch callback completion tracks default fallthrough and break paths" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "[1].map(x=>{switch(x){case 1:return x;default:return 0;}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:return x;default:throw new Error();}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:return x;}});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:return x;}return 0;});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 0:case 1:return x;default:return 0;}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){default:case 1:return x;}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:return x;default:}});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:break;default:return 0;}});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:break;default:return 0;}return 1;});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:break;return;default:return 0;}return 1;});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:if(x>1)break;return 1;default:return 0;}});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:if(x>1)break;return;default:return 0;}return 1;});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:if(x>1)return 2;else return 3;default:return 0;}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:return;default:return 0;}});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:{return x;}default:return 0;}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:while(x){break;}return 1;default:return 0;}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:switch(x){case 2:break;default:break;}return 1;default:return 0;}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:try{break;}finally{}return 1;default:return 0;}});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:try{break;}finally{return 1;}default:return 0;}});", .count = 0 },
        .{ .source = "[1].map(x=>{switch(x){case 1:try{return 1;}finally{break;}default:return 0;}});", .count = 1 },
        .{ .source = "[1].map(x=>{switch(x){case 1:const f=()=>1;default:}});", .count = 1 },
    };
    var options = lint.Options.allDisabled();
    options.array_callback_return = true;
    for (cases) |case| {
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.js", options);
        defer result.deinit(std.testing.allocator);
        const actual = helpers.countRule(result, lint.rules.array_callback_return.id);
        if (actual != case.count) std.debug.print("switch case: {s}\n", .{case.source});
        try std.testing.expectEqual(case.count, actual);
    }
}
