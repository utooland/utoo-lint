const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports no-new for constructor calls used as statements" {
    const source =
        \\new Widget();
        \\new namespace.Widget(value);
        \\(new Widget());
        \\((new Widget()));
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.no_new.id));
}

test "does not report no-new when constructed values are used" {
    const source =
        \\const widget = new Widget();
        \\returnValue(new Widget());
        \\function makeWidget() {
        \\  return new Widget();
        \\}
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_new.id));
}

test "preserves visitor ancestry beyond Yuku's recursive walk depth" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "(() => { new Deep(); })()");
    for (0..512) |_| try source.appendSlice(std.testing.allocator, " + 0");
    try source.appendSlice(std.testing.allocator, "; new Shallow();");

    var options = lint.Options.allDisabled();
    options.no_new = true;
    var result = try lint.lintSource(std.testing.allocator, source.items, "fixture.js", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.no_new.id));
    try std.testing.expectEqualStrings("new Deep()", source.items[result.diagnostics[0].span.start..result.diagnostics[0].span.end]);
    try std.testing.expectEqualStrings("new Shallow()", source.items[result.diagnostics[1].span.start..result.diagnostics[1].span.end]);
}

test "can disable no-new" {
    const source =
        \\new Widget();
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.js", .{
        .no_new = false,
        .no_unused_vars = false,
        .no_undef = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.no_new.id));
}
