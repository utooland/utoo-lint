const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports import/no-duplicates for repeated module sources" {
    const source =
        \\import foo from "alpha";
        \\import { bar } from "alpha";
        \\import "beta";
        \\import "beta";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.import_no_duplicates.id));
    try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, lint.rules.no_duplicate_imports.id));
    try std.testing.expectEqualStrings("'alpha' imported multiple times.", result.diagnostics[0].message);
}

test "does not report import/no-duplicates for distinct module sources" {
    const source =
        \\import foo from "alpha";
        \\import { bar } from "beta";
        \\import "gamma";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.import_no_duplicates.id));
}

test "allows namespace imports alongside other import groups" {
    const cases = [_][]const u8{
        \\import { value } from "alpha";
        \\import * as namespace from "alpha";
        ,
        \\import * as namespace from "alpha";
        \\import value from "alpha";
        ,
        \\import value, * as namespace from "alpha";
        \\import { other } from "alpha";
        ,
        \\import "alpha";
        \\import * as namespace from "alpha";
        ,
        \\import type DefaultType from "alpha";
        \\import type { NamedType } from "alpha";
        \\import { value } from "alpha";
        \\import * as namespace from "alpha";
        ,
        \\import type * as Types from "alpha";
        \\import * as namespace from "alpha";
        ,
        \\import { type NamedType, value } from "alpha";
        \\import { other } from "alpha";
    };

    var options = lint.Options.allDisabled();
    options.import_no_duplicates = true;
    for (cases) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    }
}

test "reports duplicates within namespace and type import groups" {
    const cases = [_][]const u8{
        \\import * as first from "alpha";
        \\import * as second from "alpha";
        ,
        \\import value, * as first from "alpha";
        \\import * as second from "alpha";
        ,
        \\import type FirstType from "alpha";
        \\import type SecondType from "alpha";
        ,
        \\import type { FirstType } from "alpha";
        \\import type { SecondType } from "alpha";
        ,
        \\import type * as Types from "alpha";
        \\import type { NamedType } from "alpha";
        ,
        \\import { type FirstType, value } from "alpha";
        \\import type { SecondType } from "alpha";
    };

    var options = lint.Options.allDisabled();
    options.import_no_duplicates = true;
    for (cases) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 2), result.diagnostics.len);
        for (result.diagnostics) |diagnostic| {
            try std.testing.expectEqualStrings(lint.rules.import_no_duplicates.id, diagnostic.rule_id);
            try std.testing.expectEqualStrings("\"alpha\"", source[diagnostic.span.start..diagnostic.span.end]);
        }
    }
}

test "reports every real duplicate around a namespace import without reporting the namespace" {
    const source =
        \\import { first } from "alpha";
        \\import * as namespace from "alpha";
        \\import { second } from "alpha";
        \\import { third } from "alpha";
    ;

    var options = lint.Options.allDisabled();
    options.import_no_duplicates = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    const expected_starts = [_]usize{
        std.mem.indexOf(u8, source, "\"alpha\"").?,
        std.mem.indexOfPos(u8, source, std.mem.indexOf(u8, source, "import { second }").?, "\"alpha\"").?,
        std.mem.indexOfPos(u8, source, std.mem.indexOf(u8, source, "import { third }").?, "\"alpha\"").?,
    };
    try std.testing.expectEqual(expected_starts.len, result.diagnostics.len);
    for (result.diagnostics, expected_starts) |diagnostic, expected_start| {
        try std.testing.expectEqualStrings(lint.rules.import_no_duplicates.id, diagnostic.rule_id);
        try std.testing.expectEqual(@as(u32, @intCast(expected_start)), diagnostic.span.start);
        try std.testing.expectEqualStrings("'alpha' imported multiple times.", diagnostic.message);
    }
}

test "reports import/no-duplicates for repeated module sources with query strings by default" {
    const source =
        \\import view from "./template?raw";
        \\import compiled from "./template?compiled";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.import_no_duplicates.id));
}

test "supports configured import/no-duplicates considerQueryString option" {
    const source =
        \\import view from "./template?raw";
        \\import compiled from "./template?compiled";
    ;

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"considerQueryString\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options.allDisabled();
    try options.setByRuleConfigValue("import/no-duplicates", config.value);
    options.parser_semantic_errors = false;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.import_no_duplicates.id));
}

test "applies considerQueryString within each import group" {
    const cases = [_]struct { source: []const u8, distinguish_queries: bool, expected_count: usize }{
        .{
            .source =
            \\import { first } from "./template?raw";
            \\import * as firstNamespace from "./template?raw";
            \\import { second } from "./template?compiled";
            \\import * as secondNamespace from "./template?compiled";
            ,
            .distinguish_queries = false,
            .expected_count = 4,
        },
        .{
            .source =
            \\import { first } from "./template?raw";
            \\import * as firstNamespace from "./template?raw";
            \\import { second } from "./template?compiled";
            \\import * as secondNamespace from "./template?compiled";
            ,
            .distinguish_queries = true,
            .expected_count = 0,
        },
        .{
            .source =
            \\import { first } from "./template?raw";
            \\import * as firstNamespace from "./template?raw";
            \\import { second } from "./template?raw";
            \\import * as secondNamespace from "./template?raw";
            ,
            .distinguish_queries = true,
            .expected_count = 4,
        },
    };

    for (cases) |case| {
        var options = lint.Options.allDisabled();
        options.import_no_duplicates = true;
        options.import_no_duplicates_consider_query_string = case.distinguish_queries;
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.js", options);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(case.expected_count, helpers.countRule(result, lint.rules.import_no_duplicates.id));
    }
}

test "falls back to no-duplicate-imports when import/no-duplicates is disabled" {
    const source =
        \\import foo from "alpha";
        \\import { bar } from "alpha";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .import_no_duplicates = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.import_no_duplicates.id));
    try std.testing.expect(helpers.hasRule(result, lint.rules.no_duplicate_imports.id));
}
