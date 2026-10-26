const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-invalid-regexp for invalid RegExp constructor arguments" {
    const source =
        \\RegExp("(", "g");
        \\new RegExp("[abc", "i");
        \\RegExp("abc", "zz");
        \\RegExp("abc", "gg");
        \\RegExp("abc", "uv");
        \\RegExp(pattern, "z");
        \\RegExp(`abc`, "z");
        \\function local(RegExp) {
        \\  RegExp("(", "z");
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .prefer_regex_literals = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 8), helpers.countRule(result, lint.rules.no_invalid_regexp.id));
}

test "reports no-invalid-regexp when only the rule is enabled" {
    const source =
        \\RegExp("[");
        \\new RegExp("[", "z");
    ;

    var options = lint.Options.allDisabled();
    options.no_invalid_regexp = true;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_invalid_regexp.id));
}

test "does not report no-invalid-regexp for valid or non-static RegExp calls" {
    const source =
        \\RegExp("abc", "gi");
        \\new RegExp("[abc]", "u");
        \\RegExp(pattern, flags);
        \\RegExp(`[`, `z`);
        \\RegExp(pattern, `z`);
        \\globalThis.RegExp("(", "z");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .prefer_regex_literals = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_invalid_regexp.id));
}

test "supports configured no-invalid-regexp allowConstructorFlags" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowConstructorFlags\":[\"z\"]}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{
        .prefer_regex_literals = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    };
    try options.setByRuleConfigValue("no-invalid-regexp", config.value);

    const source =
        \\RegExp("abc", "z");
        \\RegExp("abc", "zz");
        \\RegExp("abc", "gz");
        \\RegExp("abc", "q");
        \\RegExp("abc", "Z");
        \\RegExp("abc", "uv");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.no_invalid_regexp.id));
}

test "can disable no-invalid-regexp" {
    const source =
        \\RegExp("(", "g");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_invalid_regexp = false,
        .prefer_regex_literals = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_invalid_regexp.id));
}

test "reports no-invalid-regexp for duplicate capture names that can participate together" {
    const sources = [_][]const u8{
        \\RegExp("(?<a>x)(?<a>y)");
        ,
        \\new RegExp("(?<a>x)(?<a>y)", "u");
        ,
        \\RegExp("(?<a>(?<a>x))");
        ,
        \\RegExp("(?:(?<a>x)|y)(?<a>z)");
        ,
        \\RegExp("(?:(?<a>x)|(?<a>y))(?<a>z)");
        ,
        \\RegExp("(?<a>x)|(?:(?<a>y)(?<a>z))");
        ,
        \\RegExp("(?<a>x)\\|(?<a>y)");
        ,
        \\RegExp("(?<a>x)[|](?<a>y)");
        ,
        \\RegExp("(?<a>x)(?=x)(?<a>y)");
        ,
        \\RegExp("(?<a>x)(?<\\u0061>y)");
        ,
        \\RegExp("(?<\\u{61}>x)(?<a>y)", "u");
        ,
        \\RegExp("(?<𐐀>x)(?<\\uD801\\uDC00>y)", "u");
        ,
        \\RegExp("(?<\\u{10400}>x)(?<𐐀>y)", "u");
        ,
    };

    var options = lint.Options.allDisabled();
    options.no_invalid_regexp = true;
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_invalid_regexp.id));
        try std.testing.expectEqualStrings("Invalid regular expression: duplicate capture group name.", result.diagnostics[0].message);
    }
}

test "does not report no-invalid-regexp for unique or mutually exclusive capture names" {
    const source =
        \\RegExp("(?<a>x)(?<b>y)");
        \\RegExp("(?<a>x)|(?<a>y)");
        \\RegExp("(?:(?<a>x)|(?<a>y))+");
        \\RegExp("(?<a>x)|(?:(?<a>y)|(?<a>z))");
        \\RegExp("(?:(?<a>x)|(?<a>y))(?:(?<b>x)|(?<b>y))");
        \\RegExp("(?<\\u0061>x)|(?<a>y)", "u");
        \\RegExp("(?<=x)(?<!y)(?<a>z)");
        \\RegExp("[(?<a>)](?<a>x)");
        \\RegExp("\\(\\?<a>x\\)(?<a>y)");
        \\RegExp("[[x]\\(\\?<a>](?<a>y)", "v");
        \\RegExp("(?<a>x)(?<A>y)");
    ;

    var options = lint.Options.allDisabled();
    options.no_invalid_regexp = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_invalid_regexp.id));
}

test "reports no-invalid-regexp for malformed capture names without corrupting group nesting" {
    const source =
        \\RegExp("(?<a(b)>x)");
        \\RegExp("(?<a)(b>x)");
        \\RegExp("(?<a[]b>x)");
        \\RegExp("(?<a|b>x)");
        \\RegExp("(?<1a>x)");
        \\RegExp("(?<>x)");
        \\RegExp("(?<\\u0028>x)");
    ;
    var options = lint.Options.allDisabled();
    options.no_invalid_regexp = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 7), helpers.countRule(result, lint.rules.no_invalid_regexp.id));
}
