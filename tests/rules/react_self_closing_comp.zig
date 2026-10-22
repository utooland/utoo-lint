const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports react/self-closing-comp for empty JSX elements" {
    const source =
        \\const html = <div></div>;
        \\const component = <Widget></Widget>;
        \\const member = <UI.Widget></UI.Widget>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_void_dom_elements_no_children = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_self_closing_comp.id));
    try std.testing.expectEqualStrings(
        "Empty components are self-closing",
        result.diagnostics[0].message,
    );
}

test "reports react/self-closing-comp for multiline whitespace children" {
    const source =
        \\const html = <div>
        \\</div>;
        \\const component = <Widget>
        \\  </Widget>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_void_dom_elements_no_children = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_self_closing_comp.id));
}

test "allows react/self-closing-comp when elements have children or are already self closing" {
    const source =
        \\const selfClosing = <div />;
        \\const text = <div>text</div>;
        \\const expression = <Widget>{child}</Widget>;
        \\const namespaced = <svg:path></svg:path>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_void_dom_elements_no_children = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_self_closing_comp.id));
}

test "supports configured react/self-closing-comp component option" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"component\":false,\"html\":true}]",
        .{},
    );
    defer config.deinit();

    var options = baseOptions();
    try options.setByRuleConfigValue("react/self-closing-comp", config.value);

    const source =
        \\const html = <div></div>;
        \\const component = <Widget></Widget>;
        \\const member = <UI.Widget></UI.Widget>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_self_closing_comp.id));
}

test "supports configured react/self-closing-comp html option" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"component\":true,\"html\":false}]",
        .{},
    );
    defer config.deinit();

    var options = baseOptions();
    try options.setByRuleConfigValue("react/self-closing-comp", config.value);

    const source =
        \\const html = <div></div>;
        \\const component = <Widget></Widget>;
        \\const member = <UI.Widget></UI.Widget>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_self_closing_comp.id));
}

test "can disable react/self-closing-comp" {
    const source =
        \\const html = <div></div>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_self_closing_comp = false,
        .react_void_dom_elements_no_children = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_self_closing_comp.id));
}

fn baseOptions() lint.Options {
    return .{
        .eol_last = false,
        .react_void_dom_elements_no_children = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    };
}

test "decodes JSX entities when checking empty multiline children" {
    const source =
        \\const empty = <Widget>&#10;&#32;&#x9;</Widget>;
        \\const nonbreaking = <Widget>&#10;&nbsp;</Widget>;
        \\const content = <Widget>&#10;&amp;</Widget>;
    ;
    var options = lint.Options.allDisabled();
    options.react_self_closing_comp = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_self_closing_comp.id));
}
