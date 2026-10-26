const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/no-namespace for non-declare namespaces and modules" {
    const source =
        \\namespace Internal {
        \\  export const value = 1;
        \\}
        \\module Legacy {
        \\  export const value = 1;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_prefer_namespace_keyword = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_no_namespace.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_no_namespace.id)) {
            try std.testing.expectEqual(lint.Severity.@"error", diagnostic.severity);
        }
    }
}

test "allows declare namespaces and modules" {
    const source =
        \\declare namespace Internal {
        \\  export const value: number;
        \\}
        \\declare module "external" {
        \\  export const value: number;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_prefer_namespace_keyword = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_namespace.id));
}

test "reports declared namespaces but allows external modules when allowDeclarations is false" {
    const source =
        \\declare namespace Internal {
        \\  export const value: number;
        \\}
        \\declare module "external" {
        \\  export const value: number;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_prefer_namespace_keyword = false,
        .typescript_eslint_no_namespace_allow_declarations = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_namespace.id));
}

test "allows external modules and augmentations with both namespace allowances disabled" {
    for ([_][]const u8{ "fixture.ts", "fixture.d.ts" }) |file_path| {
        const source =
            \\export {};
            \\declare module 'foo' { export const value: number; }
            \\declare module "hast" { interface Element { extra?: string; } }
            \\declare namespace Internal { const value: number; }
            \\declare module Legacy { const value: number; }
        ;
        var result = try lint.lintSource(std.testing.allocator, source, file_path, .{
            .no_unused_vars = false,
            .typescript_eslint_no_namespace_allow_declarations = false,
            .typescript_eslint_no_namespace_allow_definition_files = false,
            .parser_semantic_errors = false,
        });
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_no_namespace.id));
        for (result.diagnostics) |diagnostic| {
            if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_no_namespace.id)) {
                const reported = source[diagnostic.span.start..diagnostic.span.end];
                try std.testing.expect(std.mem.startsWith(u8, reported, "declare namespace Internal") or
                    std.mem.startsWith(u8, reported, "declare module Legacy"));
            }
        }
    }
}

test "allows namespaces in definition files" {
    const source =
        \\namespace Internal {
        \\  export const value: number;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.d.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_prefer_namespace_keyword = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_namespace.id));
}

test "reports namespaces in definition files when allowDefinitionFiles is false" {
    const source =
        \\namespace Internal {
        \\  export const value: number;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.d.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_prefer_namespace_keyword = false,
        .typescript_eslint_no_namespace_allow_definition_files = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_namespace.id));
}

test "supports configured @typescript-eslint/no-namespace options" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\["error", {"allowDeclarations": false, "allowDefinitionFiles": false}]
    ,
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-namespace", config.value);

    try std.testing.expect(options.typescript_eslint_no_namespace);
    try std.testing.expect(!options.typescript_eslint_no_namespace_allow_declarations);
    try std.testing.expect(!options.typescript_eslint_no_namespace_allow_definition_files);
}

test "can disable @typescript-eslint/no-namespace" {
    const source =
        \\namespace Internal {
        \\  export const value = 1;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_no_namespace = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_namespace.id));
}
