const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

fn optionsOnly() lint.Options {
    var options = lint.Options.allDisabled();
    options.alipay_ant_no_phantom_dependencies = true;
    return options;
}

test "no phantom dependencies honors Smallfish config aliases and framework dependencies" {
    for ([_][]const u8{ "smallfish.config.js", "smallfish.config.ts", "appfw.config.js" }) |config_name| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        try tmp.dir.createDirPath(std.testing.io, "src");
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "package.json", .data = "{}" });
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = config_name,
            .data = "export default { alias: { virtualAlias: './src', 'exactAlias$': './src' } };\n",
        });
        const source =
            \\import alias from 'virtualAlias/components';
            \\import exact from 'exactAlias';
            \\import react from 'react';
            \\import reactDom from 'react-dom/client';
            \\import mobile from 'antd-mobile';
            \\import missing from 'missing-package';
        ;
        var result = try lintProject(&tmp, source);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.alipay_ant_no_phantom_dependencies.id));
        try std.testing.expectEqualStrings("检测到未在 package.json 中声明的依赖: missing-package", result.diagnostics[0].message);
    }
}

test "no phantom dependencies keeps Smallfish TypeScript config precedence" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "src");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "package.json", .data = "{}" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "smallfish.config.js", .data = "export default { alias: { oldAlias: './src' } };\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "smallfish.config.ts", .data = "export default { alias: { newAlias: './src' } };\n" });

    var result = try lintProject(&tmp, "import current from 'newAlias';\nimport old from 'oldAlias';\n");
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.alipay_ant_no_phantom_dependencies.id));
    try std.testing.expectEqualStrings("检测到未在 package.json 中声明的依赖: oldAlias", result.diagnostics[0].message);
}

test "no phantom dependencies allows legacy virtual modules without hiding ordinary packages" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "src");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "package.json", .data = "{}" });
    const source =
        \\import stdlib from 'smallfish:stdlib/lodash';
        \\import framework from '@smallfish/runtime';
        \\import generic from 'appfw:stdlib/lodash';
        \\import genericMini from 'appmini:config';
        \\import other from 'smallfish-package';
        \\import scoped from '@smallfish-other/pkg';
        \\import undeclaredReact from 'react';
    ;
    var result = try lintProject(&tmp, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.alipay_ant_no_phantom_dependencies.id));
    try std.testing.expectEqualStrings("检测到未在 package.json 中声明的依赖: smallfish-package", result.diagnostics[0].message);
    try std.testing.expectEqualStrings("检测到未在 package.json 中声明的依赖: @smallfish-other/pkg", result.diagnostics[1].message);
    try std.testing.expectEqualStrings("检测到未在 package.json 中声明的依赖: react", result.diagnostics[2].message);
}

fn lintProject(tmp: *std.testing.TmpDir, source: []const u8) !lint.Result {
    return lintProjectWithOptions(tmp, source, optionsOnly());
}

fn lintProjectWithOptions(tmp: *std.testing.TmpDir, source: []const u8, options: lint.Options) !lint.Result {
    const file_path = try std.fs.path.resolve(std.testing.allocator, &.{ ".zig-cache", "tmp", &tmp.sub_path, "src", "entry.js" });
    defer std.testing.allocator.free(file_path);
    return lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, options);
}

test "no phantom dependencies applies external aliases and dependencies only when configured" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "src");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "package.json", .data = "{}" });
    const source =
        \\import runtime from '@example/runtime/widget';
        \\import virtual from 'virtual:config';
        \\import exact from 'specificAlias';
        \\import framework from '@example/framework/sub';
        \\import declared from 'custom-package';
        \\import adjacent from '@example/runtime-other/pkg';
        \\import missing from 'missing-package';
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\["warn", {
        \\  "externalAlias": ["@example/runtime/", {"name": "virtual:", "type": "framework"}, "specificAlias$"],
        \\  "externalDependencies": ["custom-package", {"name": "@example/framework", "type": "framework"}]
        \\}]
    , .{});
    defer parsed.deinit();
    var options = optionsOnly();
    try options.setByRuleConfigValue(lint.rules.alipay_ant_no_phantom_dependencies.id, parsed.value);
    var configured = try lintProjectWithOptions(&tmp, source, options);
    defer configured.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(configured, lint.rules.alipay_ant_no_phantom_dependencies.id));
    try std.testing.expectEqualStrings("检测到未在 package.json 中声明的依赖: @example/runtime-other", configured.diagnostics[0].message);
    try std.testing.expectEqualStrings("检测到未在 package.json 中声明的依赖: missing-package", configured.diagnostics[1].message);

    var defaults = try lintProject(&tmp, source);
    defer defaults.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 7), helpers.countRule(defaults, lint.rules.alipay_ant_no_phantom_dependencies.id));
}
