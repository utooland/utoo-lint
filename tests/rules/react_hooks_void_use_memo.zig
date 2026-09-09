const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports block callbacks without values" {
    try check(
        \\import {useMemo} from 'react';
        \\function Component() {
        \\ const a = useMemo(() => { log(); }, []);
        \\ const b = useMemo(function () { return; }, []);
        \\ const c = useMemo(() => { function nested() { return 1; } }, []);
        \\ return [a,b,c];
        \\}
    , 2);
}

test "accepts values and throwing callbacks" {
    try check(
        \\function Component({value}) {
        \\ const a = useMemo(() => value, [value]);
        \\ const b = useMemo(() => { if (value) return 1; return 2; }, [value]);
        \\ const c = useMemo(() => { throw new Error('stop'); }, []);
        \\ return [a,b,c];
        \\}
    , 0);
}

test "resolves named namespace and default import aliases" {
    try check(
        \\import R, {useMemo as calculate} from 'react';
        \\import * as NS from 'react';
        \\const Component = () => [calculate(() => {}, []), R.useMemo(() => {}, []), NS['useMemo'](() => {}, [])];
    , 3);
}

test "respects shadowed foreign and type-only imports" {
    try check(
        \\import {useMemo as foreign} from 'other';
        \\import type {useMemo as typed} from 'react';
        \\import {useMemo} from 'react';
        \\function Component(useMemo, React) {
        \\ return [useMemo(() => {}, []), React.useMemo(() => {}, []), foreign(() => {}, []), typed(() => {}, [])];
        \\}
    , 0);
}

test "handles TypeScript wrappers and hooks" {
    try check(
        \\import {useMemo as calculate} from 'react';
        \\function useValue() { return (calculate as any)((() => {}) as () => void, []); }
    , 1);
}

test "does not treat ordinary or deferred functions as render" {
    try check(
        \\function calculate() { return useMemo(() => {}, []); }
        \\function Component() { useEffect(function Effect() { useMemo(() => {}, []); }, []); return null; }
    , 0);
}

test "does not count nested memo returns for the outer callback" {
    try check(
        \\function Component() { return useMemo(() => { const nested = useMemo(() => 1, []); }, []); }
    , 1);
}

test "is opt-in and supports rule configuration severity and disabling" {
    try std.testing.expect(!(lint.Options{}).react_hooks_void_use_memo);
    var options = lint.Options.allDisabled();
    try std.testing.expect(options.setByCliName("react-hooks/void-use-memo", true));
    try std.testing.expect(options.react_hooks_void_use_memo);
    var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "\"off\"", .{});
    defer config.deinit();
    try options.setByRuleConfigValue("react-hooks/void-use-memo", config.value);
    try std.testing.expect(!options.react_hooks_void_use_memo);
}

fn check(source: []const u8, count: usize) !void {
    var options = lint.Options.allDisabled();
    options.react_hooks_void_use_memo = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, "parse"));
    try std.testing.expectEqual(count, helpers.countRule(result, "react-hooks/void-use-memo"));
    for (result.diagnostics) |diagnostic| {
        try std.testing.expectEqual(.@"error", diagnostic.severity);
        try std.testing.expectEqual(@as(usize, 0), diagnostic.fixes.len);
    }
}

test "reports unused inline memo results but allows consumption" {
    try check(
        \\function Component() { useMemo(() => 1, []); (React.useMemo(() => 2, [])); const value = useMemo(() => 3, []); return value; }
    , 2);
}

test "checks named callbacks and each discarded call result" {
    try check(
        \\const {useMemo: memo} = require('react');
        \\function Component() { const calc = () => {}; return memo(calc, []); }
        \\function Other() { function calc() { return 1; } memo(calc, []); memo(calc, []); return memo(calc, []); }
    , 3);
}

test "preserves nested return and deferred callback boundaries" {
    try check(
        \\function Component() { const calc = () => { const inner = () => 1; }; return useMemo(calc, []); }
        \\function Other() { const calc = () => {}; return () => useMemo(calc, []); }
    , 1);
}
