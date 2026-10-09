const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports react/jsx-no-comment-textnodes for text comments in JSX children" {
    const source =
        \\const node = <div>
        \\  // text comment
        \\  /* block text comment */
        \\</div>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_jsx_no_comment_textnodes.id));
    try std.testing.expectEqualStrings("Comments inside children section of tag should be placed inside braces", result.diagnostics[0].message);
}

test "allows JSX expression comments and ordinary JSX text" {
    const source =
        \\const node = <div>
        \\  {/* real comment */}
        \\  / not a comment
        \\  text
        \\</div>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_jsx_no_comment_textnodes.id));
}

test "allows entity-escaped comment delimiters in JSX text" {
    const source =
        \\const node = <div>
        \\  <pre>&#x2F;&#x2F; text</pre>
        \\  <pre>&#47;&#42; text &#42;&#47;</pre>
        \\  <pre>&#32;// text</pre>
        \\</div>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", .{
        .eol_last = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_jsx_no_comment_textnodes.id));
}

test "can disable react/jsx-no-comment-textnodes" {
    const source =
        \\const node = <div>// text comment</div>;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.tsx", .{
        .eol_last = false,
        .react_jsx_no_comment_textnodes = false,
        .no_undef = false,
        .no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_jsx_no_comment_textnodes.id));
}
