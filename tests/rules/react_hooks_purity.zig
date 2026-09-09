const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports known impure globals during render" {
    try check(
        \\function Component() { return [Math.random(), Date.now(), new Date(), Date(), crypto.randomUUID(), performance.now(), Math['random']()]; }
    , 7);
}

test "accepts deterministic constructors and ordinary functions" {
    try check(
        \\const time = Date.now();
        \\function utility() { return Math.random(); }
        \\function Component() { return [new Date(0), new Date('2020-01-01'), Math.floor(1.5)]; }
    , 0);
}

test "accepts effects events callbacks and lazy state initialization" {
    try check(
        \\function Component() {
        \\ const [time] = useState(() => Date.now());
        \\ useReducer(reducer, 0, function Initializer() { return Date.now(); });
        \\ useEffect(function Effect() { console.log(Math.random()); }, []);
        \\ const handleClick = () => Date.now();
        \\ const callback = useCallback(() => Math.random(), []);
        \\ return <button onClick={() => crypto.randomUUID()} />;
        \\}
    , 0);
}

test "respects local shadowing and imports" {
    try check(
        \\import {crypto} from 'other';
        \\function Component(Math, Date, performance) { return [Math.random(), Date.now(), new Date(), crypto.randomUUID(), performance.now()]; }
    , 0);
}

test "checks memo callbacks synchronous IIFEs and React wrappers" {
    try check(
        \\import {useMemo as calculate, memo as wrap, forwardRef as withRef} from 'react';
        \\const Component = wrap(() => calculate(() => Math.random(), []));
        \\const Other = withRef(() => Date.now());
        \\function useTime() { return performance.now(); }
        \\function App() { return [(() => new Date())(), (function() { return crypto.randomUUID(); })()]; }
    , 5);
}

test "avoids class methods object methods and foreign wrappers" {
    try check(
        \\import {memo} from 'other';
        \\class Service { Render() { return Math.random(); } }
        \\class Store { callback = function Callback() { return Date.now(); }; }
        \\const api = { Render() { return Date.now(); } };
        \\const Component = memo(() => Math.random());
    , 0);
}

test "supports TypeScript wrappers" {
    try check(
        \\const Component = (() => (Math as any).random()) satisfies () => number;
    , 1);
}

test "is opt-in and supports rule configuration severity and disabling" {
    try std.testing.expect(!(lint.Options{}).react_hooks_purity);
    var options = lint.Options.allDisabled();
    try std.testing.expect(options.setByCliName("react-hooks/purity", true));
    try std.testing.expect(options.react_hooks_purity);
    var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "\"off\"", .{});
    defer config.deinit();
    try options.setByRuleConfigValue("react-hooks/purity", config.value);
    try std.testing.expect(!options.react_hooks_purity);
}

fn check(source: []const u8, count: usize) !void {
    var options = lint.Options.allDisabled();
    options.react_hooks_purity = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, "parse"));
    try std.testing.expectEqual(count, helpers.countRule(result, "react-hooks/purity"));
    for (result.diagnostics) |diagnostic| {
        try std.testing.expectEqual(.@"error", diagnostic.severity);
        try std.testing.expectEqual(@as(usize, 0), diagnostic.fixes.len);
    }
}

test "resolves API aliases destructuring and constructors" {
    try check(
        \\const M = Math; const {random: rand} = M; const random = rand; const now = Date.now; const D = Date;
        \\function Component() { random(); now(); D(); new D(); new D(0); return null; }
    , 4);
}

test "checks indirect memo execution but preserves deferred boundaries" {
    try check(
        \\const {useMemo: memo} = require('react'); const calculate = () => Math.random();
        \\function Component() { const calc = () => { Date.now(); return () => Math.random(); }; return [memo(calculate, []), memo(calc, [])]; }
        \\function Other() { const calc = () => Math.random(); return () => memo(calc, []); }
    , 2);
}

test "rejects reassigned aliases shadows and cycles" {
    try check(
        \\let random = Math.random; random = () => 1; const a = b; const b = a;
        \\function Component(Math) { const rand = Math.random; rand(); random(); a(); return null; }
    , 0);
}

test "terminates recursive memo graphs and still finds render invocations" {
    try check(
        \\const calc = () => { Math.random(); useMemo(calc, []); return useMemo(calc, []); }; function Component() { return useMemo(calc, []); }
    , 1);
}

test "does not invent render owners for cyclic memo callbacks" {
    try check(
        \\const first = () => { Math.random(); useMemo(second, []); return useMemo(second, []); }; const second = () => useMemo(first, []);
    , 0);
}
