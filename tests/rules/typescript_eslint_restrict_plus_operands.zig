const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/restrict-plus-operands for mixed and invalid primitive operands" {
    const source =
        \\const count: number = 1;
        \\const label: string = "items";
        \\const enabled: boolean = true;
        \\const mystery: unknown = 1;
        \\count + label;
        \\enabled + count;
        \\mystery + count;
        \\1 + "x";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_restrict_plus_operands.id)) {
            try std.testing.expectEqual(lint.Severity.warning, diagnostic.severity);
        }
    }
}

test "allows @typescript-eslint/restrict-plus-operands compatible primitive operands" {
    const source =
        \\const left: number = 1;
        \\const right: number = 2;
        \\const first: string = "a";
        \\const second: string = "b";
        \\left + right;
        \\first + second;
        \\(1 as number) + <number>2;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
}

test "supports configured @typescript-eslint/restrict-plus-operands allowNumberAndString" {
    const source =
        \\const count: number = 1;
        \\const label: string = "items";
        \\const enabled: boolean = true;
        \\const mystery: unknown = 1;
        \\count + label;
        \\enabled + count;
        \\mystery + count;
        \\1 + "x";
    ;

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowNumberAndString\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    };
    try options.setByRuleConfigValue("@typescript-eslint/restrict-plus-operands", config.value);

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
}

test "can disable @typescript-eslint/restrict-plus-operands" {
    const source =
        \\const count: number = 1;
        \\const label: string = "items";
        \\count + label;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .typescript_eslint_restrict_plus_operands = false,
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
}

test "explicit any operands respect allowAny" {
    const sources = [_][]const u8{
        "export function example(value: any) { return value + 1; }",
        "export function example(value: any) { return 1 + value; }",
        "export function example(value: any, other) { return value + other; }",
        "const value: any = 1; export const result = value + 1;",
        "export const result = (1 as any) + 1;",
    };
    for ([_][]const u8{ "[\"error\",{\"allowAny\":false}]", "[\"error\",{\"allowAny\":true}]", "error" }) |config_source| {
        const json_source = if (std.mem.eql(u8, config_source, "error")) "\"error\"" else config_source;
        var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_source, .{});
        defer config.deinit();
        var options = lint.Options.allDisabled();
        try options.setByRuleConfigValue(lint.rules.typescript_eslint_restrict_plus_operands.id, config.value);
        for (sources) |source| {
            var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            const count: usize = if (std.mem.indexOf(u8, config_source, "false") != null) 1 else 0;
            try std.testing.expectEqual(count, helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
        }
    }
}

test "addition operand types follow scoped bindings" {
    var options = lint.Options.allDisabled();
    options.typescript_eslint_restrict_plus_operands = true;
    options.typescript_eslint_restrict_plus_operands_allow_any = false;
    const sources = [_][]const u8{
        "function numeric(value: number) { return value + 1; } function dynamic(value: any) { return value + 1; }",
        "function dynamic(value: any) { return value + 1; } function numeric(value: number) { return value + 1; }",
        "const value: any = 1; function numeric(value: number) { return value + 1; } value + 1;",
        "const value: any = 1; function numeric(value) { return value + 1; } value + 1;",
    };
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
    }
    options.typescript_eslint_restrict_plus_operands_allow_any = true;
    var result = try lint.lintSource(std.testing.allocator, "(1 as any) + true; false + (1 as any); (1 as any) + 2;", "fixture.ts", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
    for (result.diagnostics) |diagnostic| try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "`boolean`") != null);
}
