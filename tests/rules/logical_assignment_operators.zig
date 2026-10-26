const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports logical-assignment-operators for self logical assignments" {
    const source =
        \\let first;
        \\let second;
        \\let third;
        \\first = first || fallback;
        \\second = second && fallback;
        \\third = third ?? fallback;
        \\object.value = object.value || fallback;
        \\this.ready = this.ready && fallback;
        \\object[`value`] = object[`value`] || fallback;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), helpers.countRule(result, lint.rules.logical_assignment_operators.id));
}

test "autofixes self logical assignments for identifiers" {
    const source =
        \\first = first || fallback;
        \\second = second && fallback;
        \\third = third ?? fallback;
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\first ||= fallback;
        \\second &&= fallback;
        \\third ??= fallback;
    , result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "does not autofix repeated property access or identifiers inside with" {
    const source =
        \\first = first || fallback;
        \\object.value = object.value || fallback;
        \\this.ready = this.ready && fallback;
        \\with (scope) {
        \\  value = value ?? fallback;
        \\}
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.cjs", .{
        .eol_last = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\first ||= fallback;
        \\object.value = object.value || fallback;
        \\this.ready = this.ready && fallback;
        \\with (scope) {
        \\  value = value ?? fallback;
        \\}
    , result.output);
    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "reports logical-assignment-operators for short-circuit assignment expressions" {
    const source =
        \\let first;
        \\let second;
        \\let third;
        \\first || (first = fallback);
        \\second && (second = fallback);
        \\third ?? (third = fallback);
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_unused_expressions = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.logical_assignment_operators.id));
    try std.testing.expectEqualStrings("Assignment can be replaced with `||=`.", result.diagnostics[0].message);
}

test "autofixes short-circuit assignment expressions for identifiers" {
    const source =
        \\first || (first = fallback);
        \\second && (second = fallback);
        \\third ?? (third = fallback);
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_expressions = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\first ||= fallback;
        \\second &&= fallback;
        \\third ??= fallback;
    , result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "autofixes single property short-circuit expressions but not nested access" {
    const source =
        \\object.value || (object.value = fallback);
        \\this.ready && (this.ready = fallback);
        \\object.value.current ?? (object.value.current = fallback);
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_expressions = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\object.value ||= fallback;
        \\this.ready &&= fallback;
        \\object.value.current ?? (object.value.current = fallback);
    , result.output);
    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "parenthesizes short-circuit replacements used by a larger logical expression" {
    const source = "const result = first || (first = fallback) || other;";

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings("const result = (first ||= fallback) || other;", result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "reports logical-assignment-operators for if statements when enabled" {
    const source =
        \\if (first) first = fallback;
        \\if (!second) {
        \\  second = fallback;
        \\}
        \\if (third == null) third = fallback;
        \\if (null == fourth) fourth = fallback;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .curly = false,
        .eol_last = false,
        .logical_assignment_operators_enforce_for_if_statements = .yes,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.logical_assignment_operators.id));
    try std.testing.expectEqualStrings("Assignment can be replaced with `&&=`.", result.diagnostics[0].message);
    try std.testing.expectEqualStrings("Assignment can be replaced with `||=`.", result.diagnostics[1].message);
    try std.testing.expectEqualStrings("Assignment can be replaced with `??=`.", result.diagnostics[2].message);
}

test "autofixes if statements to logical assignments when enabled" {
    const source =
        \\if (first) first = fallback;
        \\if (!second) {
        \\  second = fallback;
        \\}
        \\if (third == null) third = fallback;
        \\if (null == fourth) {
        \\  fourth = fallback;
        \\}
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .curly = false,
        .eol_last = false,
        .logical_assignment_operators_enforce_for_if_statements = .yes,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\first &&= fallback;
        \\second ||= fallback;
        \\third ??= fallback;
        \\fourth ??= fallback;
    , result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "if autofix allows single properties but rejects nested access and with" {
    const source =
        \\if (object.value) object.value = fallback;
        \\if (!this.ready) {
        \\  this.ready = fallback;
        \\}
        \\if (object.value.current) object.value.current = fallback;
        \\with (scope) {
        \\  if (value) value = fallback;
        \\}
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.cjs", .{
        .curly = false,
        .eol_last = false,
        .logical_assignment_operators_enforce_for_if_statements = .yes,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\object.value &&= fallback;
        \\this.ready ||= fallback;
        \\if (object.value.current) object.value.current = fallback;
        \\with (scope) {
        \\  if (value) value = fallback;
        \\}
    , result.output);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "autofixes without discarding comments" {
    const source =
        \\safe = safe || fallback;
        \\commented = commented /* keep assignment */ || fallback;
        \\shortValue || (shortValue = /* keep short */ fallback);
        \\if (condition) {
        \\  condition = /* keep if */ fallback;
        \\}
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .capitalized_comments = false,
        .curly = false,
        .eol_last = false,
        .logical_assignment_operators_enforce_for_if_statements = .yes,
        .no_undef = false,
        .no_unused_expressions = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\safe ||= fallback;
        \\commented = commented /* keep assignment */ || fallback;
        \\shortValue || (shortValue = /* keep short */ fallback);
        \\if (condition) {
        \\  condition = /* keep if */ fallback;
        \\}
    , result.output);
    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "comment markers inside literals do not suppress autofix" {
    const source =
        \\url = url || "https://example.test/path";
        \\marker = marker || "/* not a comment */";
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\url ||= "https://example.test/path";
        \\marker ||= "/* not a comment */";
    , result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "does not report logical-assignment-operators for if statements by default" {
    const source =
        \\if (value) value = fallback;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .curly = false,
        .eol_last = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.logical_assignment_operators.id));
}

test "does not report logical-assignment-operators when shorthand would change meaning" {
    const source =
        \\let value;
        \\value = fallback || value;
        \\value = value + fallback;
        \\value ||= fallback;
        \\value || (other = fallback);
        \\object[getKey()] = object[getKey()] || fallback;
        \\object[`val${suffix}`] = object[`val${suffix}`] || fallback;
        \\object.value = other.value || fallback;
        \\if (value) other = fallback;
        \\if (value != null) value = fallback;
        \\if (value === null) value = fallback;
        \\if (value) {
        \\  value = fallback;
        \\  other = fallback;
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .curly = false,
        .logical_assignment_operators_enforce_for_if_statements = .yes,
        .no_unused_expressions = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.logical_assignment_operators.id));
}

test "reports logical-assignment-operators for logical assignments in never mode" {
    const source =
        \\first ||= fallback;
        \\second &&= fallback;
        \\third ??= fallback;
        \\fourth = fourth || fallback;
        \\fourth || (fourth = fallback);
        \\if (fourth) fourth = fallback;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .curly = false,
        .eol_last = false,
        .logical_assignment_operators_style = .never,
        .logical_assignment_operators_enforce_for_if_statements = .yes,
        .no_unused_expressions = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.logical_assignment_operators.id));
    try std.testing.expectEqualStrings("Unexpected logical assignment operator `||=`.", result.diagnostics[0].message);
    try std.testing.expectEqualStrings("Unexpected logical assignment operator `&&=`.", result.diagnostics[1].message);
    try std.testing.expectEqualStrings("Unexpected logical assignment operator `??=`.", result.diagnostics[2].message);
}

test "autofixes logical assignments in never mode for identifiers" {
    const source =
        \\first ||= fallback;
        \\second &&= fallback;
        \\third ??= fallback;
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .logical_assignment_operators_style = .never,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\first = first || fallback;
        \\second = second && fallback;
        \\third = third ?? fallback;
    , result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "never-mode autofix parenthesizes lower-precedence and mixed logical operands" {
    const source =
        \\first &&= condition ? yes : no;
        \\second ??= fallback || other;
        \\third ||= fallback ?? other;
        \\fourth ||= target = fallback;
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .eol_last = false,
        .logical_assignment_operators_style = .never,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\first = first && (condition ? yes : no);
        \\second = second ?? (fallback || other);
        \\third = third || (fallback ?? other);
        \\fourth = fourth || (target = fallback);
    , result.output);
    try std.testing.expect(!helpers.hasRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "never-mode autofix preserves comments and avoids repeated property evaluation" {
    const source =
        \\safe ||= fallback;
        \\commented &&= /* keep */ fallback;
        \\object.value ??= fallback;
    ;

    var result = try lint.lintSourceAndFix(std.testing.allocator, source, "fixture.js", .{
        .capitalized_comments = false,
        .eol_last = false,
        .logical_assignment_operators_style = .never,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.fixed);
    try std.testing.expectEqualStrings(
        \\safe = safe || fallback;
        \\commented &&= /* keep */ fallback;
        \\object.value ??= fallback;
    , result.output);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result.result, lint.rules.logical_assignment_operators.id));
}

test "can disable logical-assignment-operators" {
    const source =
        \\let value;
        \\value = value || fallback;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .logical_assignment_operators = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.logical_assignment_operators.id));
}
