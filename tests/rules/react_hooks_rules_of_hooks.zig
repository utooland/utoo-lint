const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

fn optionsOnly() lint.Options {
    var options = lint.Options.allDisabled();
    options.react_hooks_rules_of_hooks = true;
    return options;
}

test "allows react-hooks/rules-of-hooks in components hooks memo and forwardRef" {
    const source =
        \\function Component() {
        \\  useState();
        \\  React.useEffect(() => {});
        \\}
        \\function useFeature() {
        \\  useMemo(() => 1, []);
        \\}
        \\const Wrapped = React.memo(() => {
        \\  useState();
        \\  return null;
        \\});
        \\const Refed = forwardRef((props, ref) => {
        \\  useImperativeHandle(ref, () => ({}));
        \\});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_hooks_rules_of_hooks.id));
}

test "reports react-hooks/rules-of-hooks for conditional and looped hooks" {
    const source =
        \\function Component() {
        \\  if (flag) {
        \\    useState();
        \\  }
        \\  while (flag) {
        \\    React.useEffect(() => {});
        \\  }
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_hooks_rules_of_hooks.id));
    try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[0].message, "is called conditionally") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[1].message, "may be executed more than once") != null);
}

test "reports react-hooks/rules-of-hooks invalid scopes" {
    const source =
        \\useState();
        \\function helper() {
        \\  useEffect(() => {});
        \\}
        \\class View {
        \\  render() {
        \\    useMemo(() => 1, []);
        \\  }
        \\}
        \\function Component() {
        \\  return items.map(() => {
        \\    useCallback(() => {}, []);
        \\  });
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.react_hooks_rules_of_hooks.id));
    try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[0].message, "cannot be called at the top level") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[1].message, "function \"helper\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[2].message, "cannot be called in a class component") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[3].message, "cannot be called inside a callback") != null);
}

test "can disable react-hooks/rules-of-hooks" {
    const source =
        \\function helper() {
        \\  useState();
        \\}
    ;

    var options = optionsOnly();
    options.react_hooks_rules_of_hooks = false;
    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_hooks_rules_of_hooks.id));
}

test "reports hooks after conditional returns without leaking nested returns" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "export default function Example({ready}) { if (!ready) { return null; } useEffect(() => {}, []); return null; }", .count = 1 },
        .{ .source = "function Example({ready}) { if (!ready) return null; return useMemo(() => 1, []); }", .count = 1 },
        .{ .source = "const Example = ({ready}) => { if (!ready) return null; useState(0); return null; };", .count = 1 },
        .{ .source = "function Example({ready}) { useState(0); if (!ready) return null; return null; }", .count = 0 },
        .{ .source = "function Example({ready}) { function helper() { if (!ready) return null; } useState(0); return null; }", .count = 0 },
        .{ .source = "function Example() { useEffect(() => { return () => {}; }, []); useState(0); return null; }", .count = 0 },
        .{ .source = "function Example({ready}) { if (!ready) return null; return null; useState(0); }", .count = 0 },
    };
    for (cases) |case| {
        var options = lint.Options.allDisabled();
        options.react_hooks_rules_of_hooks = true;
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.tsx", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.react_hooks_rules_of_hooks.id));
    }
}
