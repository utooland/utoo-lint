const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/no-use-before-define for classes and variables but not functions" {
    const source =
        \\f();
        \\function f() {}
        \\
        \\new C();
        \\class C {}
        \\
        \\a;
        \\let a = 1;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_no_use_before_define.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_use_before_define.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_no_use_before_define.id)) {
            try std.testing.expectEqual(lint.Severity.@"error", diagnostic.severity);
        }
    }
}

test "does not report @typescript-eslint/no-use-before-define for type references" {
    const source =
        \\let value: Later;
        \\type Later = string;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_use_before_define.id));
}

test "ignores erased exports and typeof queries unless type references are configured" {
    const source =
        \\export type { Later };
        \\export { type Other };
        \\type Query = typeof value;
        \\type Later = string;
        \\type Other = number;
        \\const value = 1;
    ;

    var options = lint.Options{};
    options.parser_semantic_errors = false;

    var ignored = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer ignored.deinit(std.testing.allocator);
    try std.testing.expect(!helpers.hasRule(ignored, lint.rules.typescript_eslint_no_use_before_define.id));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreTypeReferences\":false}]",
        .{},
    );
    defer config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", config.value);

    var checked = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer checked.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        @as(usize, 3),
        helpers.countRule(checked, lint.rules.typescript_eslint_no_use_before_define.id),
    );
}

test "type-only value exports preserve no-use-before-define declaration options" {
    const source =
        \\export type { laterValue, laterFunction, LaterType };
        \\const laterValue = 1;
        \\function laterFunction() {}
        \\type LaterType = number;
    ;
    const cases = [_]struct { config: []const u8, count: usize }{
        .{
            .config = "[\"error\",{\"ignoreTypeReferences\":false,\"functions\":true}]",
            .count = 3,
        },
        .{
            .config = "[\"error\",{\"ignoreTypeReferences\":false,\"functions\":false}]",
            .count = 2,
        },
        .{
            .config = "[\"error\",{\"ignoreTypeReferences\":false,\"functions\":true,\"typedefs\":false}]",
            .count = 2,
        },
    };
    for (cases) |case| {
        var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, case.config, .{});
        defer config.deinit();

        var options = lint.Options{};
        try options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", config.value);
        options.parser_semantic_errors = false;

        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(
            case.count,
            helpers.countRule(result, lint.rules.typescript_eslint_no_use_before_define.id),
        );
    }
}

test "supports configured @typescript-eslint/no-use-before-define ignoreTypeReferences false" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreTypeReferences\":false}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", config.value);
    options.no_unused_vars = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\type AliasUser = LaterAlias;
        \\type InterfaceUser = LaterInterface;
        \\type LaterAlias = string;
        \\interface LaterInterface {
        \\  value: string;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_no_use_before_define.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_use_before_define.id));
}

test "supports configured @typescript-eslint/no-use-before-define typedefs false" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreTypeReferences\":false,\"typedefs\":false}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", config.value);
    options.no_unused_vars = false;
    options.typescript_eslint_no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\type AliasUser = LaterAlias;
        \\type InterfaceUser = LaterInterface;
        \\type LaterAlias = string;
        \\interface LaterInterface {
        \\  value: string;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_use_before_define.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_use_before_define.id));
}

test "supports configured @typescript-eslint/no-use-before-define enums false" {
    const source =
        \\type EnumUser = LaterEnum;
        \\enum LaterEnum {
        \\  A,
        \\}
    ;

    var report_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreTypeReferences\":false}]",
        .{},
    );
    defer report_config.deinit();

    var report_options = lint.Options{};
    try report_options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", report_config.value);
    report_options.no_unused_vars = false;
    report_options.typescript_eslint_no_unused_vars = false;
    report_options.parser_semantic_errors = false;

    var report_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", report_options);
    defer report_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(report_result, lint.rules.typescript_eslint_no_use_before_define.id));
    try std.testing.expect(!helpers.hasRule(report_result, lint.rules.no_use_before_define.id));

    var ignore_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreTypeReferences\":false,\"enums\":false}]",
        .{},
    );
    defer ignore_config.deinit();

    var ignore_options = lint.Options{};
    try ignore_options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", ignore_config.value);
    ignore_options.no_unused_vars = false;
    ignore_options.typescript_eslint_no_unused_vars = false;
    ignore_options.parser_semantic_errors = false;

    var ignore_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", ignore_options);
    defer ignore_result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(ignore_result, lint.rules.typescript_eslint_no_use_before_define.id));
    try std.testing.expect(!helpers.hasRule(ignore_result, lint.rules.no_use_before_define.id));
}

test "uses configured @typescript-eslint/no-use-before-define function and class checks" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"functions\":true,\"classes\":false}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", config.value);
    options.eol_last = false;
    options.no_empty_block_statements = false;
    options.no_empty_function = false;
    options.typescript_eslint_no_empty_function = false;
    options.no_new = false;
    options.no_unused_expressions = false;
    options.typescript_eslint_no_unused_expressions = false;
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\f();
        \\function f() {}
        \\
        \\new C();
        \\class C {}
        \\
        \\a;
        \\let a = 1;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_no_use_before_define.id));
}

test "supports configured @typescript-eslint/no-use-before-define variables false" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"functions\":true,\"classes\":false,\"variables\":false}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", config.value);
    options.eol_last = false;
    options.no_empty_block_statements = false;
    options.no_empty_function = false;
    options.typescript_eslint_no_empty_function = false;
    options.no_new = false;
    options.no_unused_expressions = false;
    options.typescript_eslint_no_unused_expressions = false;
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\f();
        \\function f() {}
        \\
        \\new C();
        \\class C {}
        \\
        \\function nested() {
        \\  outer;
        \\}
        \\let outer = 1;
        \\sameScope;
        \\let sameScope = 2;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_no_use_before_define.id));
}

test "supports configured @typescript-eslint/no-use-before-define allowNamedExports" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowNamedExports\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", config.value);
    options.no_unused_expressions = false;
    options.typescript_eslint_no_unused_expressions = false;
    options.no_unused_vars = false;
    options.parser_semantic_errors = false;

    const source =
        \\export { allowed };
        \\reported;
        \\const allowed = 1;
        \\const reported = 2;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_use_before_define.id));
}

test "can disable @typescript-eslint/no-use-before-define and fall back to core rule" {
    const source =
        \\f();
        \\function f() {}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_vars = false,
        .typescript_eslint_no_use_before_define = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_use_before_define.id));
    try std.testing.expect(helpers.hasRule(result, lint.rules.no_use_before_define.id));
}
