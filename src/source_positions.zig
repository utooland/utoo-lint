const std = @import("std");
const SourcePosition = @import("core.zig").SourcePosition;

/// Indexes LF line starts for one-based byte columns, as used by text diagnostics.
pub const ByteLineIndex = struct {
    line_starts: []const usize,
    source_len: usize,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!ByteLineIndex {
        var line_starts: std.ArrayList(usize) = .empty;
        errdefer line_starts.deinit(allocator);
        try line_starts.append(allocator, 0);
        var start: usize = 0;
        while (std.mem.indexOfScalarPos(u8, source, start, '\n')) |newline| {
            start = newline + 1;
            try line_starts.append(allocator, start);
        }
        return .{
            .line_starts = try line_starts.toOwnedSlice(allocator),
            .source_len = source.len,
        };
    }

    pub fn deinit(self: *ByteLineIndex, allocator: std.mem.Allocator) void {
        allocator.free(self.line_starts);
        self.* = undefined;
    }

    pub fn position(self: ByteLineIndex, offset: u32) SourcePosition {
        const end = @min(@as(usize, offset), self.source_len);
        var low: usize = 0;
        var high = self.line_starts.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.line_starts[middle] <= end) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        return .{ .line = low, .column = end - self.line_starts[low - 1] + 1 };
    }
};
