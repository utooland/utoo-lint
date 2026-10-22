const std = @import("std");
const lint = @import("utoo_lint");

test "indexed text positions preserve byte columns and LF-only line endings" {
    const sources = [_][]const u8{
        "",
        "first\nsecond\n",
        "first\r\nsecond\rthird\n",
        "é😀\n中\u{2028}value\u{2029}\xff\r\nlast",
    };
    for (sources) |source| {
        var index = try lint.ByteLineIndex.init(std.testing.allocator, source);
        defer index.deinit(std.testing.allocator);
        // Reverse order also covers arbitrary rule emission order and offsets past EOF.
        var offset = source.len + 3;
        while (true) : (offset -= 1) {
            try std.testing.expectEqual(
                lint.offsetToLineColumn(source, @intCast(offset)),
                index.position(@intCast(offset)),
            );
            if (offset == 0) break;
        }
    }

    const source = "é😀\r\u{2028}x";
    var index = try lint.ByteLineIndex.init(std.testing.allocator, source);
    defer index.deinit(std.testing.allocator);
    try std.testing.expectEqual(lint.SourcePosition{ .line = 1, .column = 11 }, index.position(10));
    try std.testing.expectEqual(lint.SourcePosition{ .line = 3, .column = 1 }, lint.offsetToUtf16LineColumn(source, 10));
    try std.testing.expectEqual(lint.SourcePosition{ .line = 1, .column = 7 }, index.position(6));
    try std.testing.expectEqual(lint.SourcePosition{ .line = 1, .column = 4 }, lint.offsetToUtf16LineColumn(source, 6));
}

test "text positions need only the prefix through the last diagnostic" {
    const source = "é\r\nfirst\n😀\nlast\n";
    for (0..source.len + 1) |max_offset| {
        var index = try lint.ByteLineIndex.init(std.testing.allocator, source[0..max_offset]);
        defer index.deinit(std.testing.allocator);
        for (0..max_offset + 1) |offset| {
            try std.testing.expectEqual(
                lint.offsetToLineColumn(source, @intCast(offset)),
                index.position(@intCast(offset)),
            );
        }
    }
}
