const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-import-assign for reassigned imported bindings" {
    const source =
        \\import def, { named } from "mod";
        \\import * as ns from "ns";
        \\def = replacement;
        \\named++;
        \\ns = replacement;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_plusplus = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.no_import_assign.id));
}

test "reports no-import-assign for namespace import mutation" {
    const source =
        \\import * as ns from "ns";
        \\ns.value = replacement;
        \\ns["value"]++;
        \\Object.assign(ns, { value: replacement });
        \\Object[`assign`](ns, { value: replacement });
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_plusplus = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.no_import_assign.id));
}

test "reports no-import-assign for imported bindings in destructuring assignment targets" {
    const source =
        \\import { a, b, c, d } from "mod";
        \\({ x: a } = obj);
        \\[b] = arr;
        \\({ c = 1 } = obj);
        \\[...d] = arr;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.no_import_assign.id));
}

test "no-import-assign distinguishes global Object.assign from shadowed Object and namespace bindings" {
    const source =
        \\import * as ns from "mod";
        \\Object.assign(ns, { value: 1 });
        \\(Object).assign((ns), { value: 2 });
        \\function update(Object) {
        \\  Object.assign(ns, { value: 3 });
        \\  (Object)[`assign`]((ns), { value: 4 });
        \\}
        \\function local(ns) {
        \\  Object.assign(ns, { value: 5 });
        \\}
    ;

    var options = lint.Options.allDisabled();
    options.no_import_assign = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_import_assign.id));
}

test "does not report no-import-assign for local shadowing or imported object property writes" {
    const source =
        \\import def, { named } from "mod";
        \\import * as ns from "ns";
        \\def.value = replacement;
        \\named.value = replacement;
        \\function update(ns) {
        \\  ns.value = replacement;
        \\}
        \\function local(named) {
        \\  ({ x: named } = obj);
        \\}
        \\Object[`ass${suffix}`](ns, { value: replacement });
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_empty_function = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_import_assign.id));
}

test "can disable no-import-assign" {
    const source =
        \\import def from "mod";
        \\def = replacement;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_import_assign = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_import_assign.id));
}
