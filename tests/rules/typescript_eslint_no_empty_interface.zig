const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/no-empty-interface for empty interfaces" {
    const source =
        \\interface Empty {}
        \\interface SingleExtends extends Base {}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_no_empty_interface.id));
}

test "does not report @typescript-eslint/no-empty-interface for non-empty or multi-extends interfaces" {
    const source =
        \\interface WithMember {
        \\  value: string;
        \\}
        \\interface MultiExtends extends Base, Other {}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_empty_interface.id));
}

test "supports configured @typescript-eslint/no-empty-interface allowSingleExtends" {
    const source =
        \\interface Empty {}
        \\interface SingleExtends extends Base {}
    ;

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowSingleExtends\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    };
    try options.setByRuleConfigValue("@typescript-eslint/no-empty-interface", config.value);

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_empty_interface.id));
}

test "can disable @typescript-eslint/no-empty-interface" {
    const source =
        \\interface Empty {}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_no_empty_interface = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_empty_interface.id));
}

test "autofixes @typescript-eslint/no-empty-interface single-base declarations and is idempotent" {
    const cases = [_]struct { source: []const u8, expected: []const u8 }{
        .{
            .source = "interface A { a: number; } export interface B extends A {}",
            .expected = "interface A { a: number; } export type B = A",
        },
        .{
            .source = "export interface B<T extends object = object> extends NS.Base<T> {}",
            .expected = "export type B<T extends object = object> = NS.Base<T>",
        },
        .{
            .source = "export {}; interface B extends A {}\nconst value = 1;",
            .expected = "export {}; type B = A;\nconst value = 1;",
        },
        .{
            .source = "export default interface B<T> extends A<T> {}",
            .expected = "type B<T> = A<T>; export type { B as default };",
        },
        .{
            .source = "function f() { interface B extends A {} return 1; }",
            .expected = "function f() { type B = A; return 1; }",
        },
        .{
            .source = "// Keep documentation\nexport interface B extends A {} // trailing comment",
            .expected = "// Keep documentation\nexport type B = A; // trailing comment",
        },
        .{
            .source = "export namespace N { export interface B extends A {} }",
            .expected = "export namespace N { export type B = A }",
        },
        .{
            .source = "import Alias = require('foo'); interface B extends A {}",
            .expected = "import Alias = require('foo'); type B = A",
        },
        .{
            .source = "export interface B extends A {}\n[1].forEach(f);",
            .expected = "export type B = A;\n[1].forEach(f);",
        },
        .{
            .source = "export type A<T> = T[]; interface C extends B { value: number; } export interface B extends A<C> {}",
            .expected = "export type A<T> = T[]; interface C extends B { value: number; } export type B = A<C>",
        },
        .{
            .source = "type A = { next: A }; export interface B extends A {}",
            .expected = "type A = { next: A }; export type B = A",
        },
        .{
            .source = "export type A<T> = T[]; type C<T = number> = T; export interface B extends A<C> {}",
            .expected = "export type A<T> = T[]; type C<T = number> = T; export type B = A<C>",
        },
        .{
            .source = "export type A<T> = T[]; type C<T extends object = object> = T; export interface B extends A<C> {}",
            .expected = "export type A<T> = T[]; type C<T extends object = object> = T; export type B = A<C>",
        },
    };
    var options = lint.Options.allDisabled();
    options.typescript_eslint_no_empty_interface = true;
    for (cases) |case| {
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_empty_interface.id));
        var fixed = try lint.applyFixes(std.testing.allocator, case.source, result.diagnostics);
        defer fixed.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(case.expected, fixed.output);
        var next = try lint.lintSource(std.testing.allocator, fixed.output, "fixture.ts", options);
        defer next.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), next.diagnostics.len);
        try std.testing.expect(!helpers.hasRule(next, lint.rules.typescript_eslint_no_empty_interface.id));
        var fixed_again = try lint.applyFixes(std.testing.allocator, fixed.output, next.diagnostics);
        defer fixed_again.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(fixed.output, fixed_again.output);
    }
}

test "does not autofix @typescript-eslint/no-empty-interface when comments or declaration merging are unsafe" {
    const sources = [_][]const u8{
        "interface B extends A {}",
        "import Alias = NS.Value; interface B extends A {}",
        "export type A<T> = T[]; export interface B extends A<B> {}",
        "export type A<T> = T[]; type C = B; export interface B extends A<C> {}",
        "export type A<T> = T[]; type C = D; type D = B; export interface B extends A<C> {}",
        "export type A<T> = T[]; type C<T = B> = T; export interface B extends A<C> {}",
        "export type A<T> = T[]; type C<T extends B = B> = T; export interface B extends A<C> {}",
        "export type A<T> = T[]; type C<T = D> = T; type D = B; export interface B extends A<C> {}",
        "export type A<T> = T[]; interface C extends B {} export interface B extends A<C> {}",
        "export {}; declare interface B extends A {}",
        "export {}; interface B extends A {} interface B { value: number; }",
        "export {}; class B { value = 1; } interface B extends A {}",
        "export {}; namespace B {} interface B extends A {}",
        "export {}; declare global { interface B extends A {} }",
        "export {}; declare module 'foo' { interface B extends A {} }",
        "export {}; declare namespace N { interface B extends A {} }",
        "export {}; namespace N { export interface B extends A {} } namespace N { export interface B { value: number; } }",
        "export interface B /* keep header */ extends A {}",
        "export interface B extends /* keep base */ A {}",
        "export interface B extends A { /* keep body */ }",
        "export default /* keep export */ interface B extends A {}",
    };
    var options = lint.Options.allDisabled();
    options.typescript_eslint_no_empty_interface = true;
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expect(helpers.hasRule(result, lint.rules.typescript_eslint_no_empty_interface.id));
        var fixed = try lint.applyFixes(std.testing.allocator, source, result.diagnostics);
        defer fixed.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(source, fixed.output);
    }
    const declaration_file = "export interface B extends A {}";
    var result = try lint.lintSource(std.testing.allocator, declaration_file, "fixture.d.ts", options);
    defer result.deinit(std.testing.allocator);
    var fixed = try lint.applyFixes(std.testing.allocator, declaration_file, result.diagnostics);
    defer fixed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(declaration_file, fixed.output);
}

test "no-empty-interface preserves recursive defaults when other interfaces are converted" {
    const source = "export type A<T> = T[]; interface C<T = B> extends D<T> {} interface D<T> { value: T; } export interface B extends A<C> {}";
    const expected = "export type A<T> = T[]; type C<T = B> = D<T>; interface D<T> { value: T; } export interface B extends A<C> {}";
    var options = lint.Options.allDisabled();
    options.typescript_eslint_no_empty_interface = true;
    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(expected, result.output);
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result.result, lint.rules.typescript_eslint_no_empty_interface.id));
    var second = try lint.lintSourceAndFix(std.testing.allocator, result.output, "fixture.ts", options);
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(expected, second.output);
    try std.testing.expect(!second.fixed);
}

test "does not autofix @typescript-eslint/no-empty-interface when single-base declarations are allowed" {
    const source = "export interface B extends A {}";
    var options = lint.Options.allDisabled();
    options.typescript_eslint_no_empty_interface = true;
    options.typescript_eslint_no_empty_interface_allow_single_extends = true;
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_empty_interface.id));
}
