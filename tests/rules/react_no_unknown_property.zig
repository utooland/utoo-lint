const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports react/no-unknown-property for unknown and incorrectly cased DOM props" {
    const source =
        \\const view = (
        \\  <div class="box" tabindex="0" unknownProp="x" />
        \\);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_no_unknown_property.id));
    try std.testing.expect(hasMessage(result, "Unknown property 'class' found, use 'className' instead"));
    try std.testing.expect(hasMessage(result, "Unknown property 'tabindex' found, use 'tabIndex' instead"));
    try std.testing.expect(hasMessage(result, "Unknown property 'unknownProp' found"));
}

test "reports react/no-unknown-property for tag-restricted DOM props" {
    const source =
        \\const view = (
        \\  <>
        \\    <div checked />
        \\    <span viewBox="0 0 10 10" />
        \\    <video onLoad={play} />
        \\  </>
        \\);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_no_unknown_property.id));
    try std.testing.expect(hasMessage(result, "Invalid property 'checked' found on tag 'div', but it is only allowed on: input"));
    try std.testing.expect(hasMessage(result, "Invalid property 'viewBox' found on tag 'span', but it is only allowed on: marker, pattern, svg, symbol, view"));
    try std.testing.expect(hasMessage(result, "Invalid property 'onLoad' found on tag 'video', but it is only allowed on: script, img, link, picture, iframe, object, source"));
}

test "allows react/no-unknown-property for known DOM props and skipped JSX tags" {
    const source =
        \\const view = (
        \\  <>
        \\    <div className="box" data-Foo="bar" aria-label="label" role="button" suppressHydrationWarning />
        \\    <svg viewBox="0 0 10 10" xlinkHref="#a" xmlLang="en" />
        \\    <rect transform-origin="center" />
        \\    <Button class="box" />
        \\    <my-widget class="box" />
        \\    <div is="x-foo" class="box" />
        \\  </>
        \\);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_no_unknown_property.id));
}

test "supports configured react/no-unknown-property ignore list" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignore\":[\"class\",\"unknownProp\"]}]",
        .{},
    );
    defer config.deinit();

    var options = baseOptions();
    try options.setByRuleConfigValue("react/no-unknown-property", config.value);

    const source =
        \\const view = <div class="box" unknownProp="x" tabindex="0" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_no_unknown_property.id));
    try std.testing.expect(hasMessage(result, "Unknown property 'tabindex' found, use 'tabIndex' instead"));
}

test "supports configured react/no-unknown-property requireDataLowercase" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"requireDataLowercase\":true}]",
        .{},
    );
    defer config.deinit();

    var options = baseOptions();
    try options.setByRuleConfigValue("react/no-unknown-property", config.value);

    const source =
        \\const view = <div data-foo="a" data-Foo="b" data-fooBar="c" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_no_unknown_property.id));
    try std.testing.expect(hasMessage(result, "Unknown property 'data-Foo' found"));
    try std.testing.expect(hasMessage(result, "Unknown property 'data-fooBar' found"));
}

test "reports react/no-unknown-property for namespaced SVG attributes" {
    const source =
        \\const view = <svg xlink:href="#a" xml:lang="en" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", baseOptions());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_no_unknown_property.id));
    try std.testing.expect(hasMessage(result, "Unknown property 'xlink:href' found, use 'xlinkHref' instead"));
    try std.testing.expect(hasMessage(result, "Unknown property 'xml:lang' found, use 'xmlLang' instead"));
}

test "can disable react/no-unknown-property" {
    const source =
        \\const view = <div class="box" unknownProp="x" />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
        .react_no_unknown_property = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_no_unknown_property.id));
}

fn baseOptions() lint.Options {
    return .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
        .react_jsx_no_undef = false,
        .react_jsx_uses_react = false,
        .react_jsx_uses_vars = false,
    };
}

fn hasMessage(result: lint.Result, expected: []const u8) bool {
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.react_no_unknown_property.id) and
            std.mem.eql(u8, diagnostic.message, expected))
        {
            return true;
        }
    }
    return false;
}

test "autofixes DOM property names while preserving values and surrounding source" {
    const cases = [_]struct { source: []const u8, expected: []const u8 }{
        .{ .source = "export const view=<div class='example'/>;", .expected = "export const view=<div className='example'/>;" },
        .{ .source = "const view=<div /* before */ class /* after */ = {name} />;", .expected = "const view=<div /* before */ className /* after */ = {name} />;" },
        .{ .source = "const view=<label for=\"field\" tabindex={0} />;", .expected = "const view=<label htmlFor=\"field\" tabIndex={0} />;" },
        .{ .source = "const view=<svg xlink:href='#icon' stroke-width={2} />;", .expected = "const view=<svg xlinkHref='#icon' strokeWidth={2} />;" },
        .{ .source = "const view=<div {...props} class={name} />;", .expected = "const view=<div {...props} className={name} />;" },
    };
    var options = lint.Options.allDisabled();
    options.react_no_unknown_property = true;
    for (cases) |case| {
        var result = try lint.lintSourceAndFix(std.testing.allocator, case.source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expect(result.fixed);
        try std.testing.expectEqualStrings(case.expected, result.output);
        try std.testing.expectEqual(@as(usize, 0), result.result.diagnostics.len);
    }
}

test "refuses property renames that create collisions or invalid properties" {
    const cases = [_][]const u8{
        "const view=<div class='a' className='b' />;",
        "const view=<div className='b' class='a' />;",
        "const view=<div class='a' class='b' />;",
        "const view=<div class='a' classname='b' />;",
        "const view=<svg xlink:href='#a' xlinkHref='#b' />;",
        "const view=<div viewbox='0 0 1 1' />;",
        "const view=<div unknownProp='x' />;",
    };
    var options = lint.Options.allDisabled();
    options.react_no_unknown_property = true;
    for (cases) |source| {
        var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expect(!result.fixed);
        try std.testing.expectEqualStrings(source, result.output);
        try std.testing.expect(result.result.diagnostics.len > 0);
        for (result.result.diagnostics) |diagnostic| try std.testing.expectEqual(@as(usize, 0), diagnostic.fixes.len);
    }
}

test "suppressed and ignored unknown properties do not produce fixes" {
    const cases = [_][]const u8{
        "// eslint-disable-next-line react/no-unknown-property\nconst view=<div class='a' />;",
        "// utlint-ignore react/no-unknown-property: intentional\nconst view=<div class='a' />;",
        "const view=<Button class='a' />;",
        "const view=<my-widget class='a' />;",
        "const view=<div is='my-widget' class='a' />;",
    };
    var options = lint.Options.allDisabled();
    options.react_no_unknown_property = true;
    for (cases) |source| {
        var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expect(!result.fixed);
        try std.testing.expectEqualStrings(source, result.output);
        try std.testing.expectEqual(@as(usize, 0), result.result.diagnostics.len);
    }
    var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "[\"error\",{\"ignore\":[\"class\"]}]", .{});
    defer config.deinit();
    try options.setByRuleConfigValue("react/no-unknown-property", config.value);
    const source = "const view=<div class='a' />;";
    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.tsx", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(source, result.output);
    try std.testing.expectEqual(@as(usize, 0), result.result.diagnostics.len);
}
