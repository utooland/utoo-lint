const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-undef for missing references" {
    const source =
        \\const value = missing;
        \\console.log(value);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(helpers.hasRule(result, lint.rules.no_undef.id));
}

test "does not report no-undef for direct typeof identifier operands by default" {
    const source =
        \\typeof missing;
        \\typeof (alsoMissing);
        \\typeof missing === "undefined";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_expressions = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_undef.id));
}

test "reports no-undef for direct typeof identifier operands when configured" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"typeof\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("no-undef", config.value);
    options.no_unused_expressions = false;
    options.parser_semantic_errors = false;

    const source =
        \\typeof missing;
        \\typeof (alsoMissing);
        \\typeof missing.member;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.no_undef.id));
}

test "reports no-undef for unresolved member objects inside typeof" {
    const source =
        \\typeof missing.prop;
        \\typeof (alsoMissing.prop);
        \\missing.prop;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_expressions = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.no_undef.id));
}

test "does not report configured globals in no-undef and reports globals turned off" {
    var globals = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{\"allowed\":\"readonly\",\"mutable\":\"writable\",\"legacy\":true,\"window\":\"off\"}",
        .{},
    );
    defer globals.deinit();

    var options = lint.Options{};
    try options.setConfiguredGlobalsFromConfig(globals.value);
    options.no_console = false;
    options.parser_semantic_errors = false;

    const source =
        \\allowed();
        \\console.log(mutable, legacy);
        \\missing();
        \\window.alert(1);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_undef.id));
    var reported = std.ArrayList([]const u8).empty;
    defer reported.deinit(std.testing.allocator);
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.no_undef.id)) {
            try reported.append(std.testing.allocator, diagnostic.message);
        }
    }
    try std.testing.expectEqualStrings("'missing' is not defined.", reported.items[0]);
    try std.testing.expectEqualStrings("'window' is not defined.", reported.items[1]);
}

test "later configured global entries override earlier ones in no-undef" {
    var first = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{\"first\":\"readonly\",\"shared\":\"readonly\"}",
        .{},
    );
    defer first.deinit();
    var second = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"shared\":\"off\"}", .{});
    defer second.deinit();

    var options = lint.Options{};
    try options.setConfiguredGlobalsFromConfig(first.value);
    try options.setConfiguredGlobalsFromConfig(second.value);
    options.parser_semantic_errors = false;

    const source =
        \\first();
        \\shared();
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_undef.id));
}
