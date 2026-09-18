const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

fn propTypesOnly() lint.Options {
    var options = lint.Options.allDisabled();
    options.react_prop_types = true;
    return options;
}

test "reports react/prop-types for missing function component props" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}{props.user.name}</div>;
        \\}
        \\Foo.propTypes = {
        \\  user: PropTypes.shape({
        \\    id: PropTypes.string,
        \\  }),
        \\};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", propTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_prop_types.id));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[0].message, "'name' is missing in props validation"));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[1].message, "'user.name' is missing in props validation"));
}

test "supports configured react/prop-types skipUndeclared" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"skipUndeclared\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("react/prop-types", config.value);

    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}</div>;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_prop_types.id));
}

test "supports configured react/prop-types ignore" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignore\":[\"name\",\"user\"]}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("react/prop-types", config.value);

    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}{props.user.name}{props.age}</div>;
        \\}
        \\Foo.propTypes = {};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_prop_types.id));
    var saw_age = false;
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.react_prop_types.id)) {
            saw_age = std.mem.eql(u8, diagnostic.message, "'age' is missing in props validation");
        }
    }
    try std.testing.expect(saw_age);
}

test "supports configured react/prop-types customValidators" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.outer.inner}</div>;
        \\}
        \\Foo.propTypes = {
        \\  outer: CustomValidator.shape({}),
        \\};
    ;

    var default_result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", propTypesOnly());
    defer default_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(default_result, lint.rules.react_prop_types.id));
    try std.testing.expect(std.mem.eql(u8, default_result.diagnostics[0].message, "'outer.inner' is missing in props validation"));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"customValidators\":[\"CustomValidator\"]}]",
        .{},
    );
    defer config.deinit();

    var options = propTypesOnly();
    try options.setByRuleConfigValue("react/prop-types", config.value);

    var configured_result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", options);
    defer configured_result.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(configured_result, lint.rules.react_prop_types.id));
}

test "allows react/prop-types declared object children" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.user.name}</div>;
        \\}
        \\Foo.propTypes = {
        \\  user: PropTypes.object,
        \\};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", propTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_prop_types.id));
}

test "reports react/prop-types for destructured parameters" {
    const source =
        \\import React from 'react';
        \\function Foo({ name, user: { id } }) {
        \\  return <div>{name}{id}</div>;
        \\}
        \\Foo.propTypes = {};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", propTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_prop_types.id));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[0].message, "'name' is missing in props validation"));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[1].message, "'user' is missing in props validation"));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[2].message, "'user.id' is missing in props validation"));
}

test "reports react/prop-types for class components" {
    const source =
        \\import React from 'react';
        \\class Foo extends React.Component {
        \\  render() {
        \\    return <div>{this.props.name}</div>;
        \\  }
        \\}
        \\Foo.propTypes = {};
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", propTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_prop_types.id));
    try std.testing.expect(std.mem.eql(u8, result.diagnostics[0].message, "'name' is missing in props validation"));
}

test "does not treat uppercase non components as react/prop-types components" {
    const source =
        \\function Foo(props) {
        \\  return props.name;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", propTypesOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_prop_types.id));
}

test "can disable react/prop-types" {
    const source =
        \\import React from 'react';
        \\function Foo(props) {
        \\  return <div>{props.name}</div>;
        \\}
    ;

    var options = propTypesOnly();
    options.react_prop_types = false;
    var result = try lint.lintSource(std.testing.allocator, source, "sample.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_prop_types.id));
}

test "React function component type arguments declare props" {
    const sources = [_][]const u8{
        "import React from 'react'; export const Example: React.FC<{ value: string }> = props => <span>{props.value}</span>;",
        "import * as R from 'react'; export const Example: R.FunctionComponent<{ value: string }> = ({ value }) => <span>{value}</span>;",
        "import type { FC as Component } from 'react'; type Props = { value: string }; export const Example: Component<Props> = props => <span>{props.value}</span>;",
        "import { FunctionComponent } from 'react'; interface Props { value: string } export const Example: FunctionComponent<Props> = props => <span>{props.value}</span>;",
    };
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", propTypesOnly());
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, lint.rules.react_prop_types.id));
    }
    for ([_][]const u8{
        "import React from 'react'; export const Example: React.FC<{ declared: string }> = props => <span>{props.missing}</span>;",
        "import { FC } from './other'; export const Example: FC<{ value: string }> = props => <span>{props.value}</span>;",
    }) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", propTypesOnly());
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_prop_types.id));
    }
}

test "checks anonymous default-export components" {
    const sources = [_][]const u8{
        "export default (props) => { const { value } = props; return <span>{value}</span>; };",
        "export default ({ value }) => <span>{value}</span>;",
        "export default ((props) => <span>{props.value}</span>);",
        "export default function(props) { return <span>{props.value}</span>; }",
    };
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", propTypesOnly());
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_prop_types.id));
        try std.testing.expectEqualStrings("'value' is missing in props validation", result.diagnostics[0].message);
    }
    for ([_][]const u8{
        "export default (props) => props.value;",
        "export default () => <span>hello</span>;",
    }) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", propTypesOnly());
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, lint.rules.react_prop_types.id));
    }
}

test "React FC props support wrappers intersections and methods" {
    const sources = [_][]const u8{
        "import React from 'react'; type Props = { value: string }; const Example: React.FC<Props> = React.memo(props => <span>{props.value}</span>);",
        "import React from 'react'; type Props = { value: string }; const Example: React.FC<Props> = React.forwardRef((props, ref) => <span>{props.value}</span>);",
        "import React from 'react'; type Base = { base: string }; type Props = Base & { value: string }; const Example: React.FC<Props> = props => <span>{props.base}{props.value}</span>;",
        "import React from 'react'; interface Props { onClick(): void } const Example: React.FC<Props> = props => <button onClick={() => props.onClick()}/>;",
    };
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", propTypesOnly());
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, lint.rules.react_prop_types.id));
    }
}

test "nested destructured props are checked against shape validators" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "function Example({ data }) { ({ data } = fallback); return <span>{data.name}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 0 },
        .{ .source = "function Example({ data }) { [data] = fallback; return <span>{data.name}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 0 },
        .{ .source = "function Example({ data }) { ({ nested: [data = {}] } = fallback); return <span>{data.name}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 0 },
        .{ .source = "function Example({ data }) { [...data] = fallback; return <span>{data.name}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 0 },
        .{ .source = "function Example({ data }) { return <span>{data.name}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 1 },
        .{ .source = "function Example({ data: alias }) { return <span>{alias.name}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 1 },
        .{ .source = "function Example(props) { const { data } = props; return <span>{data.name}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 1 },
        .{ .source = "function Example({ data }) { return <span>{data.name}</span>; } Example.propTypes = { data: PropTypes.shape({ name: PropTypes.string }) };", .count = 0 },
        .{ .source = "function Example({ data }) { function inner(data) { return data.name; } return <span>{inner({})}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 0 },
        .{ .source = "function Example({ data }) { data = {}; return <span>{data.name}</span>; } Example.propTypes = { data: PropTypes.shape({}) };", .count = 0 },
        .{ .source = "function Example({ data }) { return <span>{data.name}</span>; }", .count = 2 },
    };
    for (cases) |case| {
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.tsx", propTypesOnly());
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.react_prop_types.id));
        if (case.count == 1) try std.testing.expectEqualStrings("'data.name' is missing in props validation", result.diagnostics[0].message);
    }
}
