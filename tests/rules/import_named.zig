const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports import/named for missing named imports and re-exports" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "src");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "src/mod.ts",
        .data =
        \\export const named = 1;
        \\export const alias = 2;
        \\export default 3;
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "src/extra.ts",
        .data = "export const star = 1;\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "src/barrel.ts",
        .data =
        \\export * from './extra';
        \\export { alias as renamed } from './mod';
        ,
    });

    const source =
        \\import { named, alias, missing } from "./mod";
        \\import { star, renamed } from "./barrel";
        \\export { named, absent as stillAbsent } from "./mod";
    ;

    const file_path = try std.fs.path.resolve(std.testing.allocator, &.{
        ".zig-cache",
        "tmp",
        &tmp.sub_path,
        "src",
        "entry.ts",
    });
    defer std.testing.allocator.free(file_path);

    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, .{
        .eol_last = false,
        .import_newline_after_import = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.import_named.id));
    try std.testing.expectEqualStrings("missing not found in './mod'", result.diagnostics[0].message);
    try std.testing.expectEqualStrings("absent not found in './mod'", result.diagnostics[1].message);
    try std.testing.expectEqual(.@"error", result.diagnostics[0].severity);
}

test "does not report import/named for defaults side effects type imports or unresolved modules" {
    const source =
        \\import defaultValue from "./mod";
        \\import "./setup";
        \\import type { MissingType } from "./mod";
        \\import { anything } from "pkg";
        \\export { local };
        \\const local = 1;
    ;

    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, "fixture.ts", .{
        .eol_last = false,
        .import_newline_after_import = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.import_named.id));
}

test "can disable import/named" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "src");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "src/mod.ts",
        .data = "export const named = 1;\n",
    });

    const source =
        \\import { missing } from "./mod";
    ;
    const file_path = try std.fs.path.resolve(std.testing.allocator, &.{
        ".zig-cache",
        "tmp",
        &tmp.sub_path,
        "src",
        "entry.ts",
    });
    defer std.testing.allocator.free(file_path);

    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, .{
        .eol_last = false,
        .import_named = false,
        .import_newline_after_import = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.import_named.id));
}

test "import named resolves exported interfaces aliases and type reexports" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "types.ts", .data = "export interface Example { count: number; } export type Alias = Example; interface Private {}" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "barrel.ts", .data = "export type { Example as Renamed } from './types'; export type * from './types';" });
    const file_path = try std.fs.path.resolve(std.testing.allocator, &.{ ".zig-cache", "tmp", &tmp.sub_path, "entry.ts" });
    defer std.testing.allocator.free(file_path);
    const source = "import { Example, Alias, Private, Missing } from './types';" ++
        "import { Renamed, Example as ThroughStar } from './barrel';" ++
        "export const value: Example = { count: 1 };";
    var options = lint.Options.allDisabled();
    options.import_named = true;
    var result = try lint.lintSourceWithIo(std.testing.allocator, std.testing.io, source, file_path, options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.import_named.id));
    try std.testing.expectEqualStrings("Private not found in './types'", result.diagnostics[0].message);
    try std.testing.expectEqualStrings("Missing not found in './types'", result.diagnostics[1].message);
}
