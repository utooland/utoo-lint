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

test "typed component parameters preserve defaults and generic scope" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "const defaults = { unused: 'x' }; const Example = (props: { unused: string } = defaults) => <span />;", .count = 1 },
        .{ .source = "type T = { unused: string }; function Example<T extends { value: string }>(props: T) { return <span>{props.value}</span>; }", .count = 0 },
        .{ .source = "type T = { unused: string }; function Example<T>(props: T) { return <span />; }", .count = 0 },
    };
    for (cases) |case| {
        var options = lint.Options.allDisabled();
        options.react_no_unused_prop_types = true;
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
    }
}

test "TypeScript nested fields are not unused runtime shape declarations" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "type Data = {name:string; unused:string}; function Example(props:{data:Data}) { const {data}=props; const {name}=data; return <span>{name}</span>; }", .count = 0 },
        .{ .source = "type Data = {name:string}; function Example(props:{data:Data}) { const {data}=props; const {name}=data||{}; return <span>{name}</span>; }", .count = 0 },
        .{ .source = "function Example(props:{data:{name:string}}) { return <span/>; }", .count = 1 },
        .{ .source = "function Example(props:{data:{name:string}; unused:string}) { return <span>{props.data.name}</span>; }", .count = 1 },
    };
    for ([_]bool{ true, false }) |skip_shape_props| {
        var options = noUnusedPropTypesOnly();
        options.react_no_unused_prop_types_skip_shape_props = skip_shape_props;
        for (cases) |case| {
            var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.tsx", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
        }
    }
}

test "fallback destructuring records used runtime shape fields" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "function Example({data}) { const {name}=data||{}; return <span>{name}</span>; }", .count = 1 },
        .{ .source = "function Example({data}) { const {name}=data??{}; return <span>{name}</span>; }", .count = 1 },
        .{ .source = "function Example({data}) { const alias=(data||{}); const {name}=alias; return <span>{name}</span>; }", .count = 1 },
        .{ .source = "function Example({data}) { return <span>{(data||{}).name}</span>; }", .count = 1 },
        .{ .source = "function Example({data}) { const {name}=other||{}; return <span>{name}</span>; }", .count = 2 },
        .{ .source = "function Example({data}) { function inner(data) { const {name}=data||{}; return name; } return <span>{inner({})}</span>; }", .count = 2 },
        .{ .source = "function Example({data}) { data={}; const {name}=data||{}; return <span>{name}</span>; }", .count = 2 },
    };
    var options = noUnusedPropTypesOnly();
    options.react_no_unused_prop_types_skip_shape_props = false;
    for (cases) |case| {
        const source = try std.fmt.allocPrint(std.testing.allocator, "{s} Example.propTypes = {{data: PropTypes.shape({{name: PropTypes.string, unused: PropTypes.string}})}};", .{case.source});
        defer std.testing.allocator.free(source);
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
        try std.testing.expect(hasMessage(result, "'data.unused' PropType is defined but prop is never used"));
        try std.testing.expectEqual(case.count == 2, hasMessage(result, "'data.name' PropType is defined but prop is never used"));
    }
}

test "JSX spreads forward props and aliases without marking unrelated props used" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "interface Props {value:string;other:number} function Example(props:Props) { const {other}=props; return <Child {...props} other={other}/>; }", .count = 0 },
        .{ .source = "function Example(props:{value:string}) { const alias=props; return <Child {...alias}/>; }", .count = 0 },
        .{ .source = "function Example({other,...rest}:{value:string;other:number}) { return <Child {...rest} other={other}/>; }", .count = 0 },
        .{ .source = "function Example(props:{value:string}) { function inner(props) { return <Child {...props}/>; } return <Child/>; }", .count = 1 },
        .{ .source = "function Example(props:{value:string}) { const alias={}; return <Child {...alias}/>; }", .count = 1 },
        .{ .source = "function Example(props:{value:string}) { props={value:''}; return <Child {...props}/>; }", .count = 1 },
        .{ .source = "function Example(props:{value:string}) { return <Child value={props.value}/>; }", .count = 0 },
        .{ .source = "function Example(props:{value:string}) { return <Child/>; } function Other(props:{other:string}) { return <Child {...props}/>; }", .count = 1 },
    };
    for (cases) |case| {
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.tsx", noUnusedPropTypesOnly());
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
    }
    var options = noUnusedPropTypesOnly();
    options.react_no_unused_prop_types_skip_shape_props = false;
    var result = try lint.lintSource(std.testing.allocator, "function Example(props) { return <Child {...props.data}/>; } Example.propTypes={data:PropTypes.shape({name:PropTypes.string}),other:PropTypes.string};", "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_no_unused_prop_types.id));
    try std.testing.expect(hasMessage(result, "'other' PropType is defined but prop is never used"));
}
