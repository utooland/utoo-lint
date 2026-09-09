const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports direct useState setter calls" {
    try check(
        \\import {useState} from 'react';
        \\function Component() { const [count, setCount] = useState(0); setCount(1); return <div>{setCount(2)}</div>; }
    , 2);
}

test "resolves aliased and namespace hooks" {
    try check(
        \\import R, {useState as state} from 'react';
        \\const Component = () => { const [, update] = state(0); update(1); return null; };
        \\function useCounter() { const [,update] = R['useState'](0); update(2); }
    , 2);
}

test "accepts effects events lazy initializers and callbacks" {
    try check(
        \\function Component() {
        \\ const [count, setCount] = useState(0);
        \\ useEffect(() => { setCount(1); }, []);
        \\ const update = () => setCount(2);
        \\ useState(() => setCount(3));
        \\ return <button onClick={() => setCount(4)} />;
        \\}
    , 0);
}

test "accepts conditional updates including prior early returns" {
    try check(
        \\function Component({items}) {
        \\ const [prev, setPrev] = useState(items);
        \\ if (items !== prev) setPrev(items);
        \\ items && setPrev(items);
        \\ items ? setPrev(items) : null;
        \\ if (!items) return null;
        \\ setPrev(items);
        \\ return null;
        \\}
    , 0);
}

test "respects hook and setter shadowing and reassignment" {
    try check(
        \\import {useState as state} from 'other';
        \\function Component(useState) { const [,setCount] = useState(0); setCount(1); }
        \\function Other() { const [,update] = state(0); update(1); }
        \\function Third() { let [,update] = React.useState(0); update = () => {}; update(1); }
        \\function Fourth() { const [,update] = React.useState(0); { const update = () => {}; update(); } }
    , 0);
}

test "checks synchronous memo and IIFE calls" {
    try check(
        \\function Component() { const [,update] = useState(0); const value = useMemo(() => { update(1); return 1; }, []); (() => update(2))(); return value; }
    , 2);
}

test "distinguishes setter aliases from ordinary names and reducer dispatch" {
    try check(
        \\function Component() { const [, dispatch] = useReducer(reducer, 0); dispatch(1); const [,setter] = useState(0); const alias = setter; alias(1); const setCount = () => {}; setCount(1); }
    , 1);
}

test "supports TypeScript setter and initializer wrappers" {
    try check(
        \\const Component = () => { const [,update] = (React.useState<number>(0) as any); (update as any)(1); return null; };
    , 1);
}

test "does not flag unreachable calls or optional argument evaluation" {
    try check(
        \\function Component() { const [,update] = useState(0); return null; update(1); }
        \\function Other({fn}) { const [,update] = useState(0); fn?.(update(1)); fn?.method(update(2)); }
    , 0);
}

test "is opt-in and supports rule configuration severity and disabling" {
    try std.testing.expect(!(lint.Options{}).react_hooks_set_state_in_render);
    var options = lint.Options.allDisabled();
    try std.testing.expect(options.setByCliName("react-hooks/set-state-in-render", true));
    try std.testing.expect(options.react_hooks_set_state_in_render);
    var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "\"off\"", .{});
    defer config.deinit();
    try options.setByRuleConfigValue("react-hooks/set-state-in-render", config.value);
    try std.testing.expect(!options.react_hooks_set_state_in_render);
}

fn check(source: []const u8, count: usize) !void {
    var options = lint.Options.allDisabled();
    options.react_hooks_set_state_in_render = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, "parse"));
    try std.testing.expectEqual(count, helpers.countRule(result, "react-hooks/set-state-in-render"));
    for (result.diagnostics) |diagnostic| {
        try std.testing.expectEqual(.@"error", diagnostic.severity);
        try std.testing.expectEqual(@as(usize, 0), diagnostic.fixes.len);
    }
}

test "resolves setter aliases and CommonJS state hooks" {
    try check(
        \\const React = require('react'); const {useState: state} = React;
        \\function Component() { const [,setCount] = state(0); const update = setCount; const again = update; again(1); return null; }
        \\function Other() { const [,setCount] = require('react').useState(0); const update = setCount; update(1); }
    , 2);
}

test "checks named memo callbacks at unconditional invocation sites" {
    try check(
        \\function Component() { const [,setter] = useState(0); const calc = () => { setter(1); return 1; }; return useMemo(calc, []); }
        \\function Other({flag}) { const [,setter] = useState(0); const calc = () => { setter(1); return 1; }; if (flag) return useMemo(calc, []); return null; }
    , 1);
}

test "reports setters after loops and branches that complete normally" {
    try check(
        \\function Component({items}) { const [,setter] = useState(0); for (let i=0; i<3; i++) { if (i===1) continue; if (i===2) break; } setter(1); }
        \\function Other({items}) { const [,setter] = useState(0); for (const item of items) { console.log(item); } setter(1); }
        \\function Third({flag}) { const [,setter] = useState(0); if (flag) { console.log(flag); } setter(1); }
    , 3);
}

test "preserves early exits and reassigned setter alias boundaries" {
    try check(
        \\function Component({items}) { const [,setter] = useState(0); for (const item of items) { if (item) return null; } setter(1); }
        \\function Other() { const [,setter] = useState(0); let update = setter; update = () => {}; update(1); }
        \\function Third(require) { const [,setter] = require('react').useState(0); setter(1); }
        \\function Fourth() { const [,setter] = useState(0); for (;;) {} setter(1); }
    , 0);
}

test "terminates recursive memo graphs before checking the render callsite" {
    try check(
        \\function Component() { const [,setter] = useState(0); const calc = () => { setter(1); useMemo(calc, []); return useMemo(calc, []); }; return useMemo(calc, []); }
    , 1);
}

test "keeps setters conditional after a loop with a throw" {
    try check(
        \\function Component({items}) { const [,setter] = useState(0); for (const item of items) { if (item) throw Error(); } setter(1); }
    , 0);
}
