const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

fn optionsOnly() lint.Options {
    var options = lint.Options.allDisabled();
    options.alipay_ant_prefer_import_from_stdlib = true;
    options.parser_semantic_errors = false;
    return options;
}

test "reports @alipay/ant/prefer-import-from-stdlib for appfw dependency versions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try writeProject(&tmp, "appfw.config.js");
    const source =
        \\import lodash from 'lodash';
        \\import debounce from 'lodash/debounce';
        \\import cx from 'classnames';
        \\import dayjs from 'dayjs';
        \\import request from '@example/request';
        \\import zustand from 'zustand/middleware';
        \\import lodashEs from 'lodash-es';
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "src/entry.js", .data = source });

    const file_path = try entryPath(&tmp);
    defer std.testing.allocator.free(file_path);

    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 7), helpers.countRule(result, lint.rules.alipay_ant_prefer_import_from_stdlib.id));
    try std.testing.expectEqualStrings(
        "推荐通过 appfw:stdlib/lodash 使用 lodash, 可以统一依赖版本，防止 tree-shaking 失效。",
        result.diagnostics[0].message,
    );
    try std.testing.expectEqualStrings(
        "推荐通过 appfw:stdlib/request 使用 @example/request, 可以统一依赖版本，防止 tree-shaking 失效。",
        result.diagnostics[4].message,
    );
    try std.testing.expectEqual(.warning, result.diagnostics[0].severity);
}

test "reports @alipay/ant/prefer-import-from-stdlib for appmini stdlib package" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try writeProject(&tmp, "appmini.config.ts");
    const source = "import lodash from 'lodash';\n";
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "src/entry.js", .data = source });

    const file_path = try entryPath(&tmp);
    defer std.testing.allocator.free(file_path);

    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.alipay_ant_prefer_import_from_stdlib.id));
    try std.testing.expectEqualStrings(
        "推荐通过 @example/stdlib/lodash 使用 lodash, 可以统一依赖版本，防止 tree-shaking 失效。",
        result.diagnostics[0].message,
    );
}

test "does not report @alipay/ant/prefer-import-from-stdlib outside matching projects or versions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "src");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "package.json",
        .data =
        \\{
        \\  "dependencies": {
        \\    "lodash": "^3.10.1",
        \\    "dayjs": "workspace:*"
        \\  }
        \\}
        ,
    });
    const source =
        \\import lodash from 'lodash';
        \\import dayjs from 'dayjs';
        \\import already from 'appfw:stdlib/lodash';
        \\import local from './lodash';
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "src/entry.js", .data = source });

    const file_path = try entryPath(&tmp);
    defer std.testing.allocator.free(file_path);

    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.alipay_ant_prefer_import_from_stdlib.id));
}

test "reports Smallfish stdlib imports with the original module name" {
    const cases = [_]struct { config: []const u8, stdlib: []const u8 }{
        .{ .config = "smallfish.config.js", .stdlib = "smallfish:stdlib" },
        .{ .config = "smallfish.config.ts", .stdlib = "smallfish:stdlib" },
    };
    for (cases) |case| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        try writeProject(&tmp, case.config);
        const source =
            \\import lodash from 'lodash';
            \\import request from '@example/request';
            \\import requestSubpath from '@example/request/client';
            \\import already from 'smallfish:stdlib/lodash';
        ;
        const file_path = try entryPath(&tmp);
        defer std.testing.allocator.free(file_path);
        var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, optionsOnly());
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.alipay_ant_prefer_import_from_stdlib.id));
        const expected_lodash = try std.fmt.allocPrint(std.testing.allocator, "推荐通过 {s}/lodash 使用 lodash, 可以统一依赖版本，防止 tree-shaking 失效。", .{case.stdlib});
        defer std.testing.allocator.free(expected_lodash);
        const expected_request = try std.fmt.allocPrint(std.testing.allocator, "推荐通过 {s}/request 使用 @example/request, 可以统一依赖版本，防止 tree-shaking 失效。", .{case.stdlib});
        defer std.testing.allocator.free(expected_request);
        try std.testing.expectEqualStrings(expected_lodash, result.diagnostics[0].message);
        try std.testing.expectEqualStrings(expected_request, result.diagnostics[1].message);
        try std.testing.expectEqualStrings(expected_request, result.diagnostics[2].message);
    }
}

test "Smallfish stdlib recommendations retain package major version constraints" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "src");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "smallfish.config.ts", .data = "export default {};\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "package.json", .data = "{\"dependencies\":{\"lodash\":\"^3.10.1\",\"@example/request\":\"^2.0.0\"}}" });
    const source = "import lodash from 'lodash';\nimport request from '@example/request';\n";
    const file_path = try entryPath(&tmp);
    defer std.testing.allocator.free(file_path);
    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, optionsOnly());
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(result, lint.rules.alipay_ant_prefer_import_from_stdlib.id));
}

test "can disable @alipay/ant/prefer-import-from-stdlib" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try writeProject(&tmp, "appfw.config.js");
    const source = "import lodash from 'lodash';\n";
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "src/entry.js", .data = source });

    const file_path = try entryPath(&tmp);
    defer std.testing.allocator.free(file_path);

    var options = optionsOnly();
    options.alipay_ant_prefer_import_from_stdlib = false;
    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.alipay_ant_prefer_import_from_stdlib.id));
}

fn writeProject(tmp: *std.testing.TmpDir, config_name: []const u8) !void {
    try tmp.dir.createDirPath(std.testing.io, "src");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = config_name, .data = "export default {};\n" });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "package.json",
        .data =
        \\{
        \\  "devDependencies": {
        \\    "lodash": "^3.10.1"
        \\  },
        \\  "dependencies": {
        \\    "lodash": "^4.17.21",
        \\    "classnames": "^2.3.2",
        \\    "lodash-es": "~4.17.21",
        \\    "@example/request": "^1.0.0",
        \\    "@example/custom-request": "^1.0.0",
        \\    "dayjs": "^1.11.0",
        \\    "zustand": "^4.4.0"
        \\  }
        \\}
        ,
    });
}

fn entryPath(tmp: *std.testing.TmpDir) ![]u8 {
    return std.fs.path.resolve(std.testing.allocator, &.{
        ".zig-cache",
        "tmp",
        &tmp.sub_path,
        "src",
        "entry.js",
    });
}

test "stdlib recommendations apply generic external package mappings and major versions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeProject(&tmp, "smallfish.config.ts");
    const source =
        \\import request from '@example/custom-request';
        \\import subpath from '@example/custom-request/client';
        \\import lodash from 'lodash';
    ;
    const file_path = try entryPath(&tmp);
    defer std.testing.allocator.free(file_path);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\["warn", {"externalPackages": {"@example/custom-request": {"stdlibPath": "request", "version": 1}}}]
    , .{});
    defer parsed.deinit();
    var options = optionsOnly();
    try options.setByRuleConfigValue(lint.rules.alipay_ant_prefer_import_from_stdlib.id, parsed.value);
    var configured = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, options);
    defer configured.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(configured, lint.rules.alipay_ant_prefer_import_from_stdlib.id));
    const expected = "推荐通过 smallfish:stdlib/request 使用 @example/custom-request, 可以统一依赖版本，防止 tree-shaking 失效。";
    try std.testing.expectEqualStrings(expected, configured.diagnostics[0].message);
    try std.testing.expectEqualStrings(expected, configured.diagnostics[1].message);

    var defaults = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, optionsOnly());
    defer defaults.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(defaults, lint.rules.alipay_ant_prefer_import_from_stdlib.id));

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "package.json", .data = "{\"dependencies\":{\"@example/custom-request\":\"^2.0.0\"}}" });
    var wrong_version = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, options);
    defer wrong_version.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(wrong_version, lint.rules.alipay_ant_prefer_import_from_stdlib.id));
}
