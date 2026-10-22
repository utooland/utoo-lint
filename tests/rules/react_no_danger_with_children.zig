const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports react/no-danger-with-children for JSX children and dangerous html" {
    const source =
        \\const text = <div dangerouslySetInnerHTML={{ __html: html }}>child</div>;
        \\const prop = <div children="child" dangerouslySetInnerHTML={{ __html: html }} />;
        \\const props = { dangerouslySetInnerHTML: { __html: html } };
        \\const spread = <section {...props}>child</section>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_no_danger = false,
        .react_no_children_prop = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_no_danger_with_children.id));
    try std.testing.expectEqualStrings(
        "Only set one of `children` or `props.dangerouslySetInnerHTML`",
        result.diagnostics[0].message,
    );
}

test "reports react/no-danger-with-children for createElement props" {
    const source =
        \\const props = { dangerouslySetInnerHTML: { __html: html } };
        \\const nested = { children: "child" };
        \\const spreadProps = { ...nested, dangerouslySetInnerHTML: { __html: html } };
        \\const a = React.createElement("div", { dangerouslySetInnerHTML: { __html: html } }, "child");
        \\const b = React.createElement("div", { children: "child", dangerouslySetInnerHTML: { __html: html } });
        \\const c = React.createElement("div", props, "child");
        \\const d = React.createElement("div", spreadProps);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_no_children_prop = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.react_no_danger_with_children.id));
}

test "allows non-overlapping danger and children cases" {
    const source =
        \\const onlyDanger = <div dangerouslySetInnerHTML={{ __html: html }} />;
        \\const onlyChildren = <div>child</div>;
        \\const blank =
        \\  <div dangerouslySetInnerHTML={{ __html: html }}>
        \\  </div>;
        \\const callOnlyDanger = React.createElement("div", { dangerouslySetInnerHTML: { __html: html } });
        \\const callOnlyChildren = React.createElement("div", { children: "child" });
        \\const ignoredCall = createElement("div", { children: "child", dangerouslySetInnerHTML: { __html: html } });
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_no_children_prop = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_no_danger_with_children.id));
}

test "can disable react/no-danger-with-children" {
    const source =
        \\const text = <div dangerouslySetInnerHTML={{ __html: html }}>child</div>;
        \\const call = React.createElement("div", { dangerouslySetInnerHTML: { __html: html } }, "child");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .eol_last = false,
        .react_no_danger_with_children = false,
        .react_no_danger = false,
        .react_no_children_prop = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_no_danger_with_children.id));
}

test "decodes JSX entities when checking dangerous HTML children" {
    const source =
        \\const empty = <div dangerouslySetInnerHTML={{ __html: html }}>&#10;&#32;&#x9;</div>;
        \\const nonbreaking = <div dangerouslySetInnerHTML={{ __html: html }}>&#10;&nbsp;</div>;
        \\const content = <div dangerouslySetInnerHTML={{ __html: html }}>&#10;&amp;</div>;
    ;
    var options = lint.Options.allDisabled();
    options.react_no_danger_with_children = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_no_danger_with_children.id));
}
