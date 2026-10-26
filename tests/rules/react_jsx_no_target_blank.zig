const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports react/jsx-no-target-blank for external and dynamic links without noreferrer" {
    const source =
        \\const external = <a href="https://example.com" target="_blank" />;
        \\const protocolRelative = <a href="//example.com" target="_blank" rel="noopener" />;
        \\const dynamic = <a href={url} target="_blank" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .jsx_a11y_anchor_has_content = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_jsx_no_target_blank.id));
    try std.testing.expectEqualStrings(
        "Using target=\"_blank\" without rel=\"noreferrer\" (which implies rel=\"noopener\") is a security risk in older browsers: see https://mathiasbynens.github.io/rel-noopener/#recommendations",
        result.diagnostics[0].message,
    );
}

test "allows secure rel non-external links and non-anchor elements" {
    const source =
        \\const secure = <a href="https://example.com" target="_blank" rel="noopener noreferrer" />;
        \\const relative = <a href="/docs" target="_blank" />;
        \\const button = <button href="https://example.com" target="_blank" />;
        \\const conditional = <a href={url} target={open ? "_blank" : "_self"} rel={open ? "noreferrer" : ""} />;
        \\const spread = <a {...props} />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_jsx_no_target_blank.id));
}

test "supports configured react/jsx-no-target-blank warnOnSpreadAttributes" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"warnOnSpreadAttributes\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("react/jsx-no-target-blank", config.value);
    options.eol_last = false;
    options.jsx_a11y_anchor_has_content = false;
    options.no_undef = false;
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const unsafe = <a {...props} />;
        \\const safeRel = <a {...props} rel="noreferrer" />;
        \\const safeTarget = <a {...props} target="_self" />;
        \\const safeHref = <a {...props} href="/docs" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_jsx_no_target_blank.id));
}

test "supports configured react/jsx-no-target-blank allowReferrer" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowReferrer\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("react/jsx-no-target-blank", config.value);
    options.eol_last = false;
    options.jsx_a11y_anchor_has_content = false;
    options.no_undef = false;
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const noopener = <a href="https://example.com" target="_blank" rel="noopener" />;
        \\const missing = <a href="https://example.com" target="_blank" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_jsx_no_target_blank.id));
}

test "supports configured react/jsx-no-target-blank enforceDynamicLinks never" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"enforceDynamicLinks\":\"never\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("react/jsx-no-target-blank", config.value);
    options.eol_last = false;
    options.jsx_a11y_anchor_has_content = false;
    options.no_undef = false;
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const dynamic = <a href={url} target="_blank" />;
        \\const external = <a href="https://example.com" target="_blank" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_jsx_no_target_blank.id));
}

test "supports configured react/jsx-no-target-blank links and forms" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"links\":false,\"forms\":true,\"warnOnSpreadAttributes\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("react/jsx-no-target-blank", config.value);
    options.eol_last = false;
    options.jsx_a11y_anchor_has_content = false;
    options.no_undef = false;
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\const link = <a href="https://example.com" target="_blank" />;
        \\const form = <form action="https://example.com" target="_blank" />;
        \\const dynamicForm = <form action={url} target="_blank" />;
        \\const relativeForm = <form action="/submit" target="_blank" />;
        \\const safeForm = <form action="https://example.com" target="_blank" rel="noreferrer" />;
        \\const spreadForm = <form {...props} />;
        \\const safeSpreadForm = <form {...props} action="/submit" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_jsx_no_target_blank.id));
}

test "can disable react/jsx-no-target-blank" {
    const source =
        \\const link = <a href="https://example.com" target="_blank" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_jsx_no_target_blank = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_jsx_no_target_blank.id));
}

test "react/jsx-no-target-blank fixes missing and literal rel without losing tokens" {
    const cases = [_]struct { source: []const u8, output: []const u8 }{
        .{
            .source = "export const x = <a href=\"https://x\" target=\"_blank\" />;",
            .output = "export const x = <a href=\"https://x\" target=\"_blank\" rel=\"noreferrer\" />;",
        },
        .{
            .source = "const x = <a href={url} target=\"_blank\">link</a>;",
            .output = "const x = <a href={url} target=\"_blank\" rel=\"noreferrer\">link</a>;",
        },
        .{
            .source = "const x = <a rel='nofollow noopener' href='//x' target='_blank' />;",
            .output = "const x = <a rel='nofollow noopener noreferrer' href='//x' target='_blank' />;",
        },
        .{
            .source = "const x = <a href='https://x' target='_blank' rel=\"\" />;",
            .output = "const x = <a href='https://x' target='_blank' rel=\"noreferrer\" />;",
        },
        .{
            .source = "const x = <a href={url} target={'_blank'} rel={/* keep */ 'noopener'} />;",
            .output = "const x = <a href={url} target={'_blank'} rel={/* keep */ 'noopener noreferrer'} />;",
        },
        .{
            .source = "const x = <a href={url} target={`_blank`} rel={`nofollow`} />;",
            .output = "const x = <a href={url} target={`_blank`} rel={`nofollow noreferrer`} />;",
        },
        .{
            .source = "const x = <a\n href='https://x'\n target='_blank'\n />; // keep",
            .output = "const x = <a\n href='https://x'\n target='_blank' rel=\"noreferrer\"\n />; // keep",
        },
    };
    var options = lint.Options.allDisabled();
    options.react_jsx_no_target_blank = true;
    for (cases) |case| try expectFix(case.source, case.output, options);
}

test "react/jsx-no-target-blank autofix respects configured applicability" {
    var options = lint.Options.allDisabled();
    options.react_jsx_no_target_blank = true;
    options.react_jsx_no_target_blank_allow_referrer = true;
    try expectFix(
        "const x = <a href='https://x' target='_blank' />;",
        "const x = <a href='https://x' target='_blank' rel=\"noopener\" />;",
        options,
    );
    try expectFix(
        "const x = <a href='https://x' target='_blank' rel='nofollow' />;",
        "const x = <a href='https://x' target='_blank' rel='nofollow noopener' />;",
        options,
    );
    options.react_jsx_no_target_blank_allow_referrer = false;
    options.react_jsx_no_target_blank_links = false;
    options.react_jsx_no_target_blank_forms = true;
    try expectFix(
        "const x = <form action={url} target='_blank' />;",
        "const x = <form action={url} target='_blank' rel=\"noreferrer\" />;",
        options,
    );
    try expectUnchanged("const x = <a href='https://x' target='_blank' />;", options, 0);
    options.react_jsx_no_target_blank_links = true;
    options.react_jsx_no_target_blank_enforce_dynamic_links = false;
    try expectUnchanged("const x = <a href={url} target='_blank' />;", options, 0);
}

test "react/jsx-no-target-blank leaves ambiguous attributes diagnostic only" {
    const cases = [_][]const u8{
        "const x = <a href='https://x' target='_blank' {...props} />;",
        "const x = <a {...props} href='https://x' target='_blank' />;",
        "const x = <a href='https://x' target='_blank' rel={value} />;",
        "const x = <a href='https://x' target='_blank' rel />;",
        "const x = <a href='https://x' target='_blank' rel='nofollow' rel='noopener' />;",
        "const x = <a href='https://x' target={open ? '_blank' : '_self'} />;",
        "const x = <a href='https://x' target='_blank' rel={`nofollow ${value}`} />;",
    };
    var options = lint.Options.allDisabled();
    options.react_jsx_no_target_blank = true;
    for (cases) |source| try expectUnchanged(source, options, 1);
    options.react_jsx_no_target_blank_warn_on_spread_attributes = true;
    try expectUnchanged("const x = <a {...props} />;", options, 1);
}

test "react/jsx-no-target-blank autofix preserves secure rel and suppression" {
    var options = lint.Options.allDisabled();
    options.react_jsx_no_target_blank = true;
    const cases = [_][]const u8{
        "const x = <a href='https://x' target='_blank' rel='noopener noreferrer' />;",
        "const x = <a href='/docs' target='_blank' />;",
        "/* eslint-disable react/jsx-no-target-blank */ const x = <a href='https://x' target='_blank' />;",
    };
    for (cases) |source| try expectUnchanged(source, options, 0);
}

fn expectFix(source: []const u8, expected: []const u8, options: lint.Options) !void {
    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.tsx", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(expected, result.output);
    try std.testing.expect(result.fixed);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.react_jsx_no_target_blank.id));
    var second = try lint.lintSourceAndFix(std.testing.allocator, result.output, "fixture.tsx", options);
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(expected, second.output);
    try std.testing.expect(!second.fixed);
}

fn expectUnchanged(source: []const u8, options: lint.Options, count: usize) !void {
    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.tsx", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(source, result.output);
    try std.testing.expect(!result.fixed);
    try std.testing.expectEqual(count, helpers.countRule(result.result, lint.rules.react_jsx_no_target_blank.id));
    for (result.result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.react_jsx_no_target_blank.id)) {
            try std.testing.expectEqual(@as(usize, 0), diagnostic.fixes.len);
        }
    }
}
