const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-script-url for javascript urls" {
    const source =
        \\const first = "javascript:alert(1)";
        \\const second = `JaVaScRiPt:alert(2)`;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_script_url.id));
}

test "does not report no-script-url for non-script urls or interpolated templates" {
    const source =
        \\const first = "https://example.com";
        \\const second = `java${scheme}:alert(1)`;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_script_url.id));
}

test "decodes JSX URL entities while keeping diagnostic source spans" {
    const literal = "\"java&#115;cript:alert(1)\"";
    const source =
        \\const first = <a href="java&#115;cript:alert(1)">link</a>;
        \\const second = <a href={"java&#115;cript:alert(1)"}>link</a>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.no_script_url.id));
    const start = std.mem.indexOf(u8, source, literal).?;
    for (result.diagnostics) |diagnostic| {
        if (!std.mem.eql(u8, diagnostic.rule_id, lint.rules.no_script_url.id)) continue;
        try std.testing.expectEqual(@as(u32, @intCast(start)), diagnostic.span.start);
        try std.testing.expectEqual(@as(u32, @intCast(start + literal.len)), diagnostic.span.end);
    }
}

test "can disable no-script-url" {
    const source =
        \\const url = "javascript:alert(1)";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_script_url = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_script_url.id));
}
