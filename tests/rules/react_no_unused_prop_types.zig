const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

fn noUnusedPropTypesOnly() lint.Options {
    var options = lint.Options.allDisabled();
    options.react_no_unused_prop_types = true;
    options.react_no_unused_prop_types_skip_shape_props = true;
    return options;
}

test "reports react/no-unused-prop-types for unused prop type declarations" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}</div>;
        \\}
        \\Foo.propTypes = {
        \\  name: PropTypes.string,
        \\  age: PropTypes.number,
        \\};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", noUnusedPropTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[0].message, "'age' PropType is defined but prop is never used"));
}

test "skips react/no-unused-prop-types shape props for fishlint configuration" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}</div>;
        \\}
        \\Foo.propTypes = {
        \\  name: PropTypes.string,
        \\  user: PropTypes.shape({
        \\    age: PropTypes.number,
        \\  }),
        \\};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", noUnusedPropTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_no_unused_prop_types.id));
}

test "reports react/no-unused-prop-types shape props when configured" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}</div>;
        \\}
        \\Foo.propTypes = {
        \\  name: PropTypes.string,
        \\  user: PropTypes.shape({
        \\    age: PropTypes.number,
        \\  }),
        \\};
    ;

    var options = noUnusedPropTypesOnly();
    options.react_no_unused_prop_types_skip_shape_props = false;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
    try std.testing.expect(hasMessage(result, "'user' PropType is defined but prop is never used"));
    try std.testing.expect(hasMessage(result, "'user.age' PropType is defined but prop is never used"));
}

test "reports react/no-unused-prop-types object props" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}</div>;
        \\}
        \\Foo.propTypes = {
        \\  name: PropTypes.string,
        \\  user: PropTypes.object,
        \\};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", noUnusedPropTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[0].message, "'user' PropType is defined but prop is never used"));
}

test "supports configured react/no-unused-prop-types ignore" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignore\":[\"age\",\"user\"]}]",
        .{},
    );
    defer config.deinit();

    var options = noUnusedPropTypesOnly();
    try options.setByRuleConfigValue("react/no-unused-prop-types", config.value);

    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}</div>;
        \\}
        \\Foo.propTypes = {
        \\  name: PropTypes.string,
        \\  age: PropTypes.number,
        \\  user: PropTypes.shape({
        \\    id: PropTypes.number,
        \\  }),
        \\  role: PropTypes.string,
        \\};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
    try std.testing.expect(hasMessage(result, "'role' PropType is defined but prop is never used"));
}

test "supports configured react/no-unused-prop-types customValidators" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.outer}</div>;
        \\}
        \\Foo.propTypes = {
        \\  outer: CustomValidator.shape({
        \\    inner: CustomValidator.string,
        \\  }),
        \\};
    ;

    var default_options = noUnusedPropTypesOnly();
    default_options.react_no_unused_prop_types_skip_shape_props = false;
    var default_result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", default_options);
    defer default_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(default_result, lint.rules.react_no_unused_prop_types.id));
    try std.testing.expect(hasMessage(default_result, "'outer.inner' PropType is defined but prop is never used"));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"skipShapeProps\":false,\"customValidators\":[\"CustomValidator\"]}]",
        .{},
    );
    defer config.deinit();

    var options = noUnusedPropTypesOnly();
    try options.setByRuleConfigValue("react/no-unused-prop-types", config.value);

    var configured_result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", options);
    defer configured_result.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(configured_result, lint.rules.react_no_unused_prop_types.id));
}

test "reports react/no-unused-prop-types for class components" {
    const source =
        \\import React from 'react';
        \\class Foo extends React.Component {
        \\  render() {
        \\    return <div>{this.props.name}</div>;
        \\  }
        \\}
        \\Foo.propTypes = {
        \\  name: PropTypes.string,
        \\  age: PropTypes.number,
        \\};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", noUnusedPropTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[0].message, "'age' PropType is defined but prop is never used"));
}

test "can disable react/no-unused-prop-types" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}</div>;
        \\}
        \\Foo.propTypes = {
        \\  name: PropTypes.string,
        \\  age: PropTypes.number,
        \\};
    ;

    var options = noUnusedPropTypesOnly();
    options.react_no_unused_prop_types = false;
    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_no_unused_prop_types.id));
}

fn hasMessage(result: lint.Result, expected: []const u8) bool {
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.message, expected)) return true;
    }
    return false;
}

test "reports unused TypeScript parameter props" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "export const Example = (props: { unused?: string }) => <span>hello</span>;", .count = 1 },
        .{ .source = "export function Example(props: { used: string; unused?: number }) { return <span>{props.used}</span>; }", .count = 1 },
        .{ .source = "export const Example = ({ used }: { used: string; unused?: number }) => <span>{used}</span>;", .count = 1 },
        .{ .source = "type Props = { unused: string }; export const Example = (props: Props) => <span />;", .count = 1 },
        .{ .source = "export const Example = (props: { used: string }) => <span>{props.used}</span>;", .count = 0 },
    };
    for (cases) |case| {
        var options = lint.Options.allDisabled();
        options.react_no_unused_prop_types = true;
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
        if (case.count > 0) try std.testing.expectEqualStrings("'unused' PropType is defined but prop is never used", result.diagnostics[0].message);
    }
}
