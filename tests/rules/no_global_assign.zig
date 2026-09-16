const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-global-assign for assignments to read-only globals" {
    const source =
        \\Object = null;
        \\NaN = 1;
        \\undefined = 2;
        \\globalThis = 3;
        \\Atomics = value;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .no_undefined = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), helpers.countRule(result, lint.rules.no_global_assign.id));
    try std.testing.expectEqualStrings("Read-only global 'Object' should not be modified.", result.diagnostics[0].message);
}

test "reports no-global-assign for updates and destructuring assignments" {
    const source =
        \\Infinity++;
        \\({ Array } = source);
        \\[Map] = source;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.no_global_assign.id));
}

test "reports no-global-assign for ESLint default read-only globals" {
    const source =
        \\AggregateError = 1;
        \\AsyncDisposableStack = 2;
        \\DisposableStack = 3;
        \\FinalizationRegistry = 4;
        \\Float16Array = 5;
        \\Iterator = 6;
        \\Proxy = 7;
        \\SharedArrayBuffer = 8;
        \\SuppressedError = 9;
        \\Temporal = 10;
        \\WeakRef = 11;
        \\decodeURI = 12;
        \\decodeURIComponent = 13;
        \\encodeURI = 14;
        \\encodeURIComponent = 15;
        \\escape = 16;
        \\isFinite = 17;
        \\isNaN = 18;
        \\isPrototypeOf = 19;
        \\parseFloat = 20;
        \\parseInt = 21;
        \\propertyIsEnumerable = 22;
        \\constructor = 23;
        \\hasOwnProperty = 24;
        \\toLocaleString = 25;
        \\toString = 26;
        \\unescape = 27;
        \\valueOf = 28;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 28), helpers.countRule(result, lint.rules.no_global_assign.id));
}

test "does not report no-global-assign for shadowed names or property writes" {
    const source =
        \\let Object = null;
        \\Object = {};
        \\let Temporal = null;
        \\Temporal = value;
        \\let parseFloat = null;
        \\parseFloat = fn;
        \\let constructor = null;
        \\constructor = value;
        \\globalThis.Object = {};
        \\Number.value = 1;
        \\window = value;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_global_assign.id));
}

test "supports no-global-assign exceptions option" {
    const source =
        \\Object = null;
        \\NaN = 1;
        \\undefined = 2;
    ;

    var options = lint.Options{
        .eol_last = false,
        .no_undef = false,
        .no_undefined = false,
        .parser_semantic_errors = false,
    };
    try options.no_global_assign_exceptions.append("Object");
    try options.no_global_assign_exceptions.append("NaN");

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_global_assign.id));
}

test "can disable no-global-assign" {
    const source =
        \\Object = null;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_global_assign = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_global_assign.id));
}

test "honours configured globals in no-global-assign" {
    var globals = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{\"APP_VERSION\":\"readonly\",\"__DEV__\":\"writable\",\"legacy\":false,\"Object\":\"writable\",\"window\":\"off\"}",
        .{},
    );
    defer globals.deinit();

    var options = lint.Options{};
    try options.setConfiguredGlobalsFromConfig(globals.value);
    options.eol_last = false;
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\APP_VERSION = "2";
        \\__DEV__ = true;
        \\legacy = 1;
        \\Object = null;
        \\window = null;
        \\Array = null;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.no_global_assign.id));
    try std.testing.expectEqualStrings("Read-only global 'APP_VERSION' should not be modified.", result.diagnostics[0].message);
    try std.testing.expectEqualStrings("Read-only global 'legacy' should not be modified.", result.diagnostics[1].message);
    try std.testing.expectEqualStrings("Read-only global 'Array' should not be modified.", result.diagnostics[2].message);
}
