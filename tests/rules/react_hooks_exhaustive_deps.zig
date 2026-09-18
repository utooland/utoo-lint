const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

fn optionsOnly() lint.Options {
    var options = lint.Options.allDisabled();
    options.react_hooks_exhaustive_deps = true;
    return options;
}

test "reports react-hooks/exhaustive-deps missing dependencies for effects and memoization" {
    const source =
        \\function App({ userId }) {
        \\  useEffect(() => { sendAnalytics(userId); }, []);
        \\  const doubled = useMemo(() => userId * 2, []);
        \\  const log = useCallback(() => console.log(userId), []);
        \\  return doubled + log;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_hooks_exhaustive_deps.id));
    for (result.diagnostics) |diagnostic| {
        if (!std.mem.eql(u8, diagnostic.rule_id, lint.rules.react_hooks_exhaustive_deps.id)) continue;
        try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "missing dependency: 'userId'") != null);
    }
}

test "allows complete react-hooks/exhaustive-deps arrays and stable values" {
    const source =
        \\const moduleValue = compute();
        \\function helper() {}
        \\function App(props) {
        \\  const literal = 1;
        \\  const ref = useRef();
        \\  const [state, setState] = useState(0);
        \\  useEffect(() => {
        \\    const local = props.value;
        \\    console.log(moduleValue, literal, ref.current, local, state);
        \\    helper();
        \\    setState(props.value);
        \\  }, [props.value, state]);
        \\  return useMemo(() => props.value * 2, [props.value]);
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "test.js", optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_hooks_exhaustive_deps.id));
}

test "reports react-hooks/exhaustive-deps unnecessary and unstable dependencies" {
    const source =
        \\function App({ value, extra }) {
        \\  const options = {};
        \\  const handler = () => value;
        \\  useMemo(() => value, [value, extra]);
        \\  useEffect(() => console.log(options), [options]);
        \\  useCallback(() => handler(), [handler]);
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_hooks_exhaustive_deps.id));
    try std.testing.expect(hasMessage(result, "unnecessary dependency: 'extra'"));
    try std.testing.expect(hasMessage(result, "unstable dependency: 'options'"));
    try std.testing.expect(hasMessage(result, "unstable dependency: 'handler'"));
}

test "supports react-hooks/exhaustive-deps additionalHooks configuration" {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"additionalHooks\":\"(useMyEffect|useTrackedEffect)\"}]",
        .{},
    );
    defer parsed.deinit();

    var options = lint.Options.allDisabled();
    try options.setByRuleConfigValue(lint.rules.react_hooks_exhaustive_deps.id, parsed.value);

    const source =
        \\function App({ value }) {
        \\  useMyEffect(() => console.log(value), []);
        \\  useOtherEffect(() => console.log(value), []);
        \\}
    ;
    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_hooks_exhaustive_deps.id));
    try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[0].message, "missing dependency: 'value'") != null);
}

test "parses react-hooks/exhaustive-deps TypeScript and TSX callbacks" {
    const source =
        \\type Props = { value: number };
        \\function App({ value }: Props) {
        \\  const doubled = useMemo<number>(() => value * 2, []);
        \\  return <span>{doubled}</span>;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "test.tsx", optionsOnly());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_hooks_exhaustive_deps.id));
    try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[0].message, "missing dependency: 'value'") != null);
}

test "react-hooks/exhaustive-deps is configurable and can be disabled" {
    var options = lint.Options.allDisabled();
    try std.testing.expect(options.setByCliName(lint.rules.react_hooks_exhaustive_deps.id, true));
    try std.testing.expect(options.react_hooks_exhaustive_deps);
    try std.testing.expect(options.setByCliName(lint.rules.react_hooks_exhaustive_deps.id, false));

    const source =
        \\function App({ value }) {
        \\  useEffect(() => console.log(value), []);
        \\}
    ;
    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_hooks_exhaustive_deps.id));
}

test "default exhaustive dependency checks use the standard rule id once" {
    const source =
        \\function App({ value }) {
        \\  useEffect(() => console.log(value), []);
        \\}
    ;
    var result = try lint.lintSource(std.testing.allocator, source, "test.jsx", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_hooks_exhaustive_deps.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.alipay_ant_exhaustive_deps.id));
}

fn hasMessage(result: lint.Result, needle: []const u8) bool {
    for (result.diagnostics) |diagnostic| {
        if (!std.mem.eql(u8, diagnostic.rule_id, lint.rules.react_hooks_exhaustive_deps.id)) continue;
        if (std.mem.indexOf(u8, diagnostic.message, needle) != null) return true;
    }
    return false;
}

test "method calls and ref current accesses depend on their objects" {
    const cases = [_]struct { expression: []const u8, dependency: []const u8 }{
        .{ .expression = "items.map(x => x)", .dependency = "items" },
        .{ .expression = "inputRef.current = 1", .dependency = "inputRef" },
        .{ .expression = "inputRef.current.focus()", .dependency = "inputRef" },
        .{ .expression = "data.items.map(x => x)", .dependency = "data.items" },
        .{ .expression = "data.name", .dependency = "data.name" },
    };
    for (cases) |case| {
        for ([_]bool{ false, true }) |include| {
            const source = try std.fmt.allocPrint(std.testing.allocator, "function Example({{ items, inputRef, data }}) {{ return useMemo(() => {{ return {s}; }}, [{s}]); }}", .{ case.expression, if (include) case.dependency else "" });
            defer std.testing.allocator.free(source);
            var options = lint.Options.allDisabled();
            options.react_hooks_exhaustive_deps = true;
            var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, if (include) 0 else 1), helpers.countRule(result, lint.rules.react_hooks_exhaustive_deps.id));
            if (!include) {
                const expected = try std.fmt.allocPrint(std.testing.allocator, "React Hook useMemo has a missing dependency: '{s}'. Either include it or remove the dependency array.", .{case.dependency});
                defer std.testing.allocator.free(expected);
                try std.testing.expectEqualStrings(expected, result.diagnostics[0].message);
            }
        }
    }
}
