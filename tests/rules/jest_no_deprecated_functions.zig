const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

const source_all =
    \\jest.resetModuleRegistry();
    \\jest.addMatchers({});
    \\require.requireMock("module");
    \\require.requireActual("module");
    \\jest.runTimersToTime(1000);
    \\jest.genMockFromModule("module");
;

test "reports deprecated Jest functions at their version thresholds" {
    const cases = [_]struct { version: u32, count: usize }{
        .{ .version = 14, .count = 0 },
        .{ .version = 15, .count = 1 },
        .{ .version = 17, .count = 2 },
        .{ .version = 20, .count = 2 },
        .{ .version = 21, .count = 4 },
        .{ .version = 22, .count = 5 },
        .{ .version = 26, .count = 6 },
        .{ .version = 30, .count = 6 },
    };

    for (cases) |case| {
        var result = try lint.lintSource(std.testing.allocator, source_all, "fixture.js", optionsFor(case.version));
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.jest_no_deprecated_functions.id));
    }
}

test "reports useful locations and applies upstream autofixes" {
    const source =
        \\jest.resetModuleRegistry();
        \\jest['addMatchers']({});
        \\require.requireMock("module");
        \\require["requireActual"]("module");
        \\jest.runTimersToTime(1000);
        \\jest.genMockFromModule("module");
    ;
    const expected =
        \\jest.resetModules();
        \\expect['extend']({});
        \\jest.requireMock("module");
        \\jest['requireActual']("module");
        \\jest.advanceTimersByTime(1000);
        \\jest.createMockFromModule("module");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", optionsFor(30));
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(result, lint.rules.jest_no_deprecated_functions.id));
    for (result.diagnostics) |diagnostic| {
        if (!std.mem.eql(u8, diagnostic.rule_id, lint.rules.jest_no_deprecated_functions.id)) continue;
        try std.testing.expectEqual(@as(usize, 2), diagnostic.fixes.len);
        const reported = source[diagnostic.span.start..diagnostic.span.end];
        try std.testing.expect(std.mem.endsWith(u8, reported, ")"));
    }
    try std.testing.expectEqualStrings(
        "`jest.resetModuleRegistry` has been deprecated in favor of `jest.resetModules`",
        result.diagnostics[0].message,
    );

    var fixed = try lint.applyFixes(std.testing.allocator, source, result.diagnostics);
    defer fixed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(expected, fixed.output);
}

test "allows functions before deprecation and non-call references" {
    const source =
        \\jest.resetModuleRegistry;
        \\jest.addMatchers;
        \\const actual = require.requireActual;
        \\other.resetModuleRegistry();
        \\jest[method]();
        \\jest.runTimersToTime();
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", optionsFor(21));
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(result, lint.rules.jest_no_deprecated_functions.id));
}

test "ignores shadowed Jest and require objects" {
    const source =
        \\function run(jest, require) {
        \\  jest.resetModuleRegistry();
        \\  jest.addMatchers({});
        \\  require.requireActual("module");
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", optionsFor(30));
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(result, lint.rules.jest_no_deprecated_functions.id));
}

test "supports aliased @jest/globals imports without unsafe replacements" {
    const source =
        \\import { expect as assertion, jest as testJest } from "@jest/globals";
        \\testJest.resetModuleRegistry();
        \\testJest.addMatchers({});
    ;
    const expected =
        \\import { expect as assertion, jest as testJest } from "@jest/globals";
        \\testJest.resetModules();
        \\assertion.extend({});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", optionsFor(30));
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.jest_no_deprecated_functions.id));

    var fixed = try lint.applyFixes(std.testing.allocator, source, result.diagnostics);
    defer fixed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(expected, fixed.output);

    const shadowed_replacement =
        \\function load(jest) {
        \\  return require.requireActual("module");
        \\}
    ;
    var shadowed_result = try lint.lintSource(std.testing.allocator, shadowed_replacement, "fixture.js", optionsFor(30));
    defer shadowed_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(shadowed_result, lint.rules.jest_no_deprecated_functions.id));
    try std.testing.expectEqual(@as(usize, 0), shadowed_result.diagnostics[0].fixes.len);
}

test "supports JavaScript TypeScript JSX and TSX" {
    const cases = [_]struct { source: []const u8, file_name: []const u8 }{
        .{ .source = "jest.genMockFromModule('x');", .file_name = "fixture.js" },
        .{ .source = "jest.genMockFromModule<Type>('x');", .file_name = "fixture.ts" },
        .{ .source = "const node = <div />; jest.genMockFromModule('x');", .file_name = "fixture.jsx" },
        .{ .source = "const node: JSX.Element = <div />; jest.genMockFromModule<Type>('x');", .file_name = "fixture.tsx" },
    };

    for (cases) |case| {
        var result = try lint.lintSource(std.testing.allocator, case.source, case.file_name, optionsFor(30));
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.jest_no_deprecated_functions.id));
    }
}

test "detects the closest installed Jest version and honors explicit settings" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "node_modules/jest");
    try tmp.dir.createDirPath(std.testing.io, "project/node_modules/jest");
    try tmp.dir.createDirPath(std.testing.io, "project/src");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "node_modules/jest/package.json",
        .data = "{\"version\":\"30.0.0\"}\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "project/node_modules/jest/package.json",
        .data = "{\"version\":\"21.4.0\"}\n",
    });
    const file_path = try std.fs.path.resolve(std.testing.allocator, &.{
        ".zig-cache",
        "tmp",
        &tmp.sub_path,
        "project",
        "src",
        "fixture.js",
    });
    defer std.testing.allocator.free(file_path);

    const automatic_options = optionsFor(0);
    var detected = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source_all, file_path, automatic_options);
    defer detected.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(detected, lint.rules.jest_no_deprecated_functions.id));
    try std.testing.expectEqual(@as(u32, 0), automatic_options.jest_version);

    // Reusing the same options without filesystem access falls back to the
    // latest version rather than retaining the prior project's detected version.
    var local = try lint.lintSource(std.testing.allocator, source_all, file_path, automatic_options);
    defer local.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(local, lint.rules.jest_no_deprecated_functions.id));
    try std.testing.expectEqual(@as(u32, 0), automatic_options.jest_version);

    var explicit = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source_all, file_path, optionsFor(14));
    defer explicit.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(explicit, lint.rules.jest_no_deprecated_functions.id));
}

test "parses numeric and semver Jest settings" {
    var options = lint.Options.allDisabled();
    try options.setJestVersionFromConfig(.{ .integer = 26 });
    try std.testing.expectEqual(@as(u32, 26), options.jest_version);
    try options.setJestVersionFromConfig(.{ .string = "27.0.0-next.11" });
    try std.testing.expectEqual(@as(u32, 27), options.jest_version);
    try std.testing.expectError(error.InvalidJestVersion, options.setJestVersionFromConfig(.{ .string = "latest" }));
}

fn optionsFor(version: u32) lint.Options {
    var options = lint.Options.allDisabled();
    options.jest_no_deprecated_functions = true;
    options.jest_version = version;
    return options;
}
