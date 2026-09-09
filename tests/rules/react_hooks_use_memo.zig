const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "rejects callback parameters including destructuring and rest" {
    try check(
        \\function Component({value}) { return [useMemo(x => value, []), useMemo(({x}) => x, []), useMemo((...xs) => xs, [])]; }
    , 3);
}

test "rejects async and generator callbacks" {
    try check(
        \\import React, {useMemo as calculate} from 'react';
        \\function Component() { return [calculate(async () => 1, []), React.useMemo(async function() { return 1; }, []), useMemo(function* () { yield 1; }, [])]; }
    , 3);
}

test "reports captured writes but permits callback-local writes" {
    try check(
        \\function Component({value}) { let count = 0; return useMemo(() => { let local = 0; local++; count++; value = 2; return local; }, []); }
    , 2);
}

test "respects shadowed captured names and nested deferred callbacks" {
    try check(
        \\function Component() { let count = 0; return useMemo(() => { let count = 1; count++; return () => { count++; }; }, []); }
    , 0);
}

test "respects foreign imports local hooks and ordinary utilities" {
    try check(
        \\import {useMemo as calculate} from 'other';
        \\function Component(useMemo) { return [useMemo(async x => x, []), calculate(async x => x, [])]; }
        \\function utility() { return React.useMemo(async x => x, []); }
    , 0);
}

test "supports TypeScript wrappers" {
    try check(
        \\import {useMemo as calculate} from 'react';
        \\function useValue() { return (calculate as any)(((x: number) => x) as any, []); }
    , 1);
}

test "leaves no-value and unused-result diagnostics to void-use-memo" {
    try check(
        \\function Component() { useMemo(() => {}, []); useMemo(() => 1, []); }
    , 0);
}

test "is opt-in and supports rule configuration severity and disabling" {
    try std.testing.expect(!(lint.Options{}).react_hooks_use_memo);
    var options = lint.Options.allDisabled();
    try std.testing.expect(options.setByCliName("react-hooks/use-memo", true));
    try std.testing.expect(options.react_hooks_use_memo);
    var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "\"off\"", .{});
    defer config.deinit();
    try options.setByRuleConfigValue("react-hooks/use-memo", config.value);
    try std.testing.expect(!options.react_hooks_use_memo);
}

fn check(source: []const u8, count: usize) !void {
    var options = lint.Options.allDisabled();
    options.react_hooks_use_memo = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, "parse"));
    try std.testing.expectEqual(count, helpers.countRule(result, "react-hooks/use-memo"));
    for (result.diagnostics) |diagnostic| {
        try std.testing.expectEqual(.@"error", diagnostic.severity);
        try std.testing.expectEqual(@as(usize, 0), diagnostic.fixes.len);
    }
}

test "resolves stable named callbacks and CommonJS hook aliases" {
    try check(
        \\const React = require('react'); const {useMemo: memoize} = React; const memo = memoize;
        \\const calculate = async value => value; const alias = calculate;
        \\function Component() { return memo(alias, []); }
        \\function Other() { function* calc() { yield 1; } return React.useMemo(calc, []); }
    , 3);
}

test "checks captured writes in named memo callbacks once" {
    try check(
        \\function Component() { let n = 0; const calc = () => { n++; return n; }; return [useMemo(calc, []), useMemo(calc, [])]; }
    , 1);
}

test "does not resolve reassigned cyclic foreign or deferred callbacks" {
    try check(
        \\const {useMemo: foreign} = require('other');
        \\function Component(require) { const {useMemo: local} = require('react'); return [local(async x => x, []), foreign(async x => x, [])]; }
        \\function Other() { let calc = async x => x; calc = () => 1; const a = b; const b = a; return [useMemo(calc, []), useMemo(a, [])]; }
        \\function Third() { const calc = async x => x; return () => useMemo(calc, []); }
    , 0);
}

test "ignores dynamic module names and destructuring defaults" {
    try check(
        \\const react = 'other'; const {useMemo: memo} = require(react); function Component() { const {useMemo: other = memo} = unknown; return [memo(async x => x, []), other(async x => x, [])]; }
    , 0);
}

test "terminates recursive memo invocation graphs without render owners" {
    try check(
        \\const calc = value => { useMemo(calc, []); return useMemo(calc, []); };
    , 0);
}
