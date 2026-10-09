const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "treats TypeScript constructor parameter properties as implicitly used" {
    const source =
        \\export class Message {
        \\  constructor(
        \\    public readonly id: string,
        \\    readonly body: string,
        \\    protected handler: () => void,
        \\    private label: string = "message",
        \\  ) {}
        \\  read() { return this.body; }
        \\}
    ;
    var options = lint.Options.allDisabled();
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", .{ .string = "error" });
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}

test "counts parameter properties as used when checking trailing unused arguments" {
    const source =
        \\export class Message {
        \\  constructor(before: string, public id: string, after: string) {}
        \\}
    ;
    var options = lint.Options.allDisabled();
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", .{ .string = "error" });
    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
    try std.testing.expectEqualStrings("'after' is declared but never used.", result.diagnostics[0].message);
}

test "reports @typescript-eslint/no-unused-vars while ignoring catch parameters by default" {
    const source =
        \\const unused = 1;
        \\const used = 2;
        \\console.log(used);
        \\
        \\function demo(before: string, usedParam: string, after: string) {
        \\  console.log(usedParam);
        \\}
        \\demo("before", "used", "after");
        \\
        \\try {
        \\  demo("before", "used", "after");
        \\} catch (unusedError) {
        \\}
        \\
        \\type UnusedType = string;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_unused_vars.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_no_unused_vars.id)) {
            try std.testing.expectEqual(lint.Severity.@"error", diagnostic.severity);
        }
    }
}

test "does not report TypeScript member bindings or expression names as unused variables" {
    const source =
        \\export enum Mode {
        \\  Read = "read",
        \\  Write = "write",
        \\}
        \\export type EnvMap = {
        \\  [key in "DEV" | "PROD"]: number;
        \\};
        \\export const Component = wrap(function DisplayName() {
        \\  return null;
        \\});
        \\export const Constructor = wrap(class ClassName {});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "ignores type signature parameters while checking runtime and type parameters" {
    const source =
        \\export type FunctionType<UnusedType> = (input: string) => void;
        \\export type ConstructorType = new (options: object) => object;
        \\export interface API {
        \\  method(value: string): void;
        \\  (request: string): void;
        \\  new (seed: string): API;
        \\  [key: string]: unknown;
        \\}
        \\export abstract class Base {
        \\  abstract method(abstractInput: string): void;
        \\}
        \\export function overloaded(overloadInput: string): void;
        \\export function overloaded() {}
        \\export function runtime(unused: string) {}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(
        @as(usize, 2),
        helpers.countRule(result, lint.rules.typescript_eslint_no_unused_vars.id),
    );
    for (result.diagnostics) |diagnostic| {
        if (!std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_no_unused_vars.id)) continue;
        try std.testing.expect(
            std.mem.eql(u8, diagnostic.message, "'UnusedType' is declared but never used.") or
                std.mem.eql(u8, diagnostic.message, "'unused' is declared but never used."),
        );
    }
}

test "ignores rest siblings for object destructuring" {
    const source =
        \\const data = { a: 1, b: 2 };
        \\const { a, ...rest } = data;
        \\console.log(rest);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars ignoreRestSiblings false" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreRestSiblings\":false}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\const data = { a: 1, b: 2 };
        \\const { a, ...rest } = data;
        \\console.log(rest);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars ignoreUsingDeclarations" {
    const source =
        \\using resource = acquire();
    ;

    var default_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer default_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(default_result, lint.rules.typescript_eslint_no_unused_vars.id));
    try std.testing.expect(!helpers.hasRule(default_result, lint.rules.no_unused_vars.id));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreUsingDeclarations\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    var ignored_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer ignored_result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(ignored_result, lint.rules.typescript_eslint_no_unused_vars.id));
    try std.testing.expect(!helpers.hasRule(ignored_result, lint.rules.no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars ignoreClassWithStaticInitBlock" {
    const source =
        \\class IgnoredWithStatic {
        \\  static {
        \\    const stillReported: number = 1;
        \\    setup();
        \\  }
        \\}
        \\const reportedExpression = class {
        \\  static {
        \\    setup();
        \\  }
        \\};
        \\class ReportedPlain {}
    ;

    var default_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer default_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(default_result, lint.rules.typescript_eslint_no_unused_vars.id));
    try std.testing.expect(!helpers.hasRule(default_result, lint.rules.no_unused_vars.id));

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreClassWithStaticInitBlock\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    var ignored_result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer ignored_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(ignored_result, lint.rules.typescript_eslint_no_unused_vars.id));
    try std.testing.expect(!helpers.hasRule(ignored_result, lint.rules.no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars args none" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"args\":\"none\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\function demo(before: string, used: string, after: string) {
        \\  console.log(used);
        \\}
        \\demo("before", "used", "after");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars argsIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"args\":\"all\",\"argsIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\function demo(ignoredParam: string, unusedParam: string, usedParam: string) {
        \\  console.log(usedParam);
        \\}
        \\demo("ignored", "unused", "used");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars vars local" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"vars\":\"local\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\type GlobalUnused = string;
        \\const globalUnused = 1;
        \\function demo() {
        \\  type LocalUnused = number;
        \\  const localUnused = 2;
        \\}
        \\demo();
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.cts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars caughtErrors none" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"caughtErrors\":\"none\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\try {
        \\  run();
        \\} catch (unusedError) {
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars caughtErrorsIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"caughtErrors\":\"all\",\"caughtErrorsIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\try {
        \\  run();
        \\} catch (ignoredError) {
        \\}
        \\try {
        \\  run();
        \\} catch (unusedError) {
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars destructuredArrayIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"destructuredArrayIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\const [ignoredItem, unusedItem, usedItem]: string[] = items;
        \\console.log(usedItem);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "supports configured @typescript-eslint/no-unused-vars reportUsedIgnorePattern" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"args\":\"all\",\"argsIgnorePattern\":\"^ignored\",\"caughtErrors\":\"all\",\"caughtErrorsIgnorePattern\":\"^ignored\",\"destructuredArrayIgnorePattern\":\"^ignored\",\"reportUsedIgnorePattern\":true,\"varsIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{};
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", config.value);
    options.no_undef = false;
    options.parser_semantic_errors = false;

    const source =
        \\const ignoredValue = 1;
        \\function demo(ignoredParam: string) {
        \\  console.log(ignoredValue, ignoredParam);
        \\  try {
        \\    run();
        \\  } catch (ignoredError) {
        \\    console.log(ignoredError);
        \\  }
        \\  const [ignoredItem]: string[] = items;
        \\  console.log(ignoredItem);
        \\}
        \\demo("ignored");
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
}

test "can disable @typescript-eslint/no-unused-vars and fall back to core rule" {
    const source =
        \\const unused = 1;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_no_unused_vars.id));
    try std.testing.expect(helpers.hasRule(result, lint.rules.no_unused_vars.id));
}
