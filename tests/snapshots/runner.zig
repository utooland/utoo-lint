const std = @import("std");
const lint = @import("utoo_lint");

const Allocator = std.mem.Allocator;
const specs_root = "tests/snapshots/specs";
const max_fixture_size = 1024 * 1024;

const CaseOptions = struct {
    expect: enum { diagnostics, clean },
    diagnostic_count: usize,
    fixes: enum { required, forbidden, any },
    rule_options: ?std.json.Value = null,
    semantic_errors: bool = false,
};

const Mode = enum {
    verify,
    update,
};

const Summary = struct {
    checked: usize = 0,
    updated: usize = 0,
    failed: usize = 0,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const mode = try parseMode(args[1..]);

    var fixture_paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (fixture_paths.items) |path| allocator.free(path);
        fixture_paths.deinit(allocator);
    }

    var specs_dir = try std.Io.Dir.cwd().openDir(io, specs_root, .{ .iterate = true });
    defer specs_dir.close(io);

    var walker = try specs_dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !isFixturePath(entry.path)) continue;
        try fixture_paths.append(allocator, try allocator.dupe(u8, entry.path));
    }

    std.mem.sort([]const u8, fixture_paths.items, {}, pathLessThan);

    var summary: Summary = .{};
    try checkSnapshotInventory(allocator, io, mode, fixture_paths.items, &summary);
    for (fixture_paths.items) |relative_path| {
        processFixture(allocator, io, mode, relative_path, &summary) catch |err| {
            summary.failed += 1;
            std.debug.print("snapshot fixture {s} failed: {s}\n", .{ relative_path, @errorName(err) });
        };
    }

    if (fixture_paths.items.len == 0) {
        std.debug.print("no rule snapshot fixtures found under {s}\n", .{specs_root});
        return error.NoSnapshotFixtures;
    }

    switch (mode) {
        .verify => std.debug.print("rule snapshots: {d} checked, {d} failed\n", .{ summary.checked, summary.failed }),
        .update => std.debug.print("rule snapshots: {d} checked, {d} updated, {d} failed\n", .{
            summary.checked,
            summary.updated,
            summary.failed,
        }),
    }
    if (summary.failed != 0) return error.SnapshotMismatch;
}

fn checkSnapshotInventory(
    allocator: Allocator,
    io: std.Io,
    mode: Mode,
    fixture_paths: []const []const u8,
    summary: *Summary,
) !void {
    var specs_dir = try std.Io.Dir.cwd().openDir(io, specs_root, .{ .iterate = true });
    defer specs_dir.close(io);

    var walker = try specs_dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.endsWith(u8, entry.path, ".snap.new")) {
            const candidate_path = try std.fs.path.join(allocator, &.{ specs_root, entry.path });
            defer allocator.free(candidate_path);
            if (mode == .update) {
                try std.Io.Dir.cwd().deleteFile(io, candidate_path);
            } else {
                std.debug.print("stale snapshot candidate must be reviewed or removed: {s}\n", .{candidate_path});
                summary.failed += 1;
            }
            continue;
        }

        if (!std.mem.endsWith(u8, entry.path, ".snap")) continue;
        const fixture_relative_path = entry.path[0 .. entry.path.len - ".snap".len];
        if (containsPath(fixture_paths, fixture_relative_path)) continue;

        const snapshot_path = try std.fs.path.join(allocator, &.{ specs_root, entry.path });
        defer allocator.free(snapshot_path);
        std.debug.print("orphan rule snapshot has no fixture: {s}\n", .{snapshot_path});
        summary.failed += 1;
    }
}

fn containsPath(paths: []const []const u8, needle: []const u8) bool {
    for (paths) |path| {
        if (std.mem.eql(u8, path, needle)) return true;
    }
    return false;
}

fn parseMode(args: []const []const u8) !Mode {
    var mode: Mode = .verify;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--update")) {
            mode = .update;
        } else {
            std.debug.print("unknown rule snapshot argument: {s}\n", .{arg});
            return error.InvalidArgument;
        }
    }
    return mode;
}

fn isFixturePath(path: []const u8) bool {
    const extensions = [_][]const u8{ ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts" };
    for (extensions) |extension| {
        if (std.mem.endsWith(u8, path, extension)) return true;
    }
    return false;
}

fn pathLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

fn processFixture(
    allocator: Allocator,
    io: std.Io,
    mode: Mode,
    relative_path: []const u8,
    summary: *Summary,
) !void {
    const fixture_path = try std.fs.path.join(allocator, &.{ specs_root, relative_path });
    defer allocator.free(fixture_path);
    const snapshot_path = try std.fmt.allocPrint(allocator, "{s}.snap", .{fixture_path});
    defer allocator.free(snapshot_path);
    const candidate_path = try std.fmt.allocPrint(allocator, "{s}.new", .{snapshot_path});
    defer allocator.free(candidate_path);

    const display_path = try normalizedPath(allocator, fixture_path);
    defer allocator.free(display_path);
    const normalized_relative_path = try normalizedPath(allocator, relative_path);
    defer allocator.free(normalized_relative_path);
    const rule_id = try ruleIdFromPath(allocator, normalized_relative_path);
    defer allocator.free(rule_id);

    const source = try std.Io.Dir.cwd().readFileAlloc(io, fixture_path, allocator, .limited(max_fixture_size));
    defer allocator.free(source);

    const sidecar_path = try optionsPath(allocator, fixture_path);
    defer allocator.free(sidecar_path);
    var parsed_options = try readCaseOptions(allocator, io, sidecar_path);
    defer parsed_options.deinit();

    const expectation = parsed_options.value;
    var options = isolatedRuleOptions();
    if (expectation.rule_options) |rule_config| {
        options.setByRuleConfigValue(rule_id, rule_config) catch |err| {
            std.debug.print("invalid rule options for {s} in {s}: {s}\n", .{
                rule_id,
                sidecar_path,
                @errorName(err),
            });
            return err;
        };
    } else if (!options.setByCliName(rule_id, true)) {
        std.debug.print("unknown rule inferred from fixture path {s}: {s}\n", .{ display_path, rule_id });
        return error.UnknownRule;
    }
    options.parser_semantic_errors = expectation.semantic_errors;

    var result = try lint.lintSourceWithIo(allocator, io, source, fixture_path, options);
    defer result.deinit(allocator);
    try validateFixtureResult(display_path, rule_id, expectation, source, result.diagnostics);

    var applied = try lint.applyFixes(allocator, source, result.diagnostics);
    defer applied.deinit(allocator);
    switch (expectation.fixes) {
        .required => if (!applied.fixed) return error.ExpectedApplicableFix,
        .forbidden => if (applied.fixed) return error.UnexpectedAppliedFix,
        .any => {},
    }
    var remaining: ?lint.Result = null;
    defer if (remaining) |*remaining_result| remaining_result.deinit(allocator);
    if (applied.fixed) {
        remaining = try lint.lintSourceWithIo(allocator, io, applied.output, fixture_path, options);
        for (remaining.?.diagnostics) |diagnostic| {
            if (!std.mem.eql(u8, diagnostic.rule_id, rule_id)) {
                std.debug.print("{s}: fix introduced diagnostic from {s}\n", .{ display_path, diagnostic.rule_id });
                return error.InvalidFixedOutput;
            }
            try validateDiagnosticSpans(display_path, applied.output, diagnostic);
        }
    }

    const rendered = try renderSnapshot(
        allocator,
        display_path,
        rule_id,
        source,
        result.diagnostics,
        applied,
        if (remaining) |remaining_result| remaining_result.diagnostics else &.{},
    );
    defer allocator.free(rendered);

    summary.checked += 1;
    switch (mode) {
        .update => {
            const old_snapshot = std.Io.Dir.cwd().readFileAlloc(
                io,
                snapshot_path,
                allocator,
                .limited(max_fixture_size * 4),
            ) catch |err| switch (err) {
                error.FileNotFound => null,
                else => return err,
            };
            defer if (old_snapshot) |old| allocator.free(old);
            if (old_snapshot == null or !std.mem.eql(u8, old_snapshot.?, rendered)) {
                try writeFileAtomic(io, snapshot_path, rendered);
                summary.updated += 1;
                std.debug.print("updated {s}\n", .{snapshot_path});
            }
            std.Io.Dir.cwd().deleteFile(io, candidate_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        },
        .verify => {
            const expected = std.Io.Dir.cwd().readFileAlloc(
                io,
                snapshot_path,
                allocator,
                .limited(max_fixture_size * 4),
            ) catch |err| switch (err) {
                error.FileNotFound => {
                    try writeFileAtomic(io, candidate_path, rendered);
                    std.debug.print("missing {s}; wrote {s}\n", .{ snapshot_path, candidate_path });
                    return error.MissingSnapshot;
                },
                else => return err,
            };
            defer allocator.free(expected);
            if (!std.mem.eql(u8, expected, rendered)) {
                try writeFileAtomic(io, candidate_path, rendered);
                const difference = firstDifference(expected, rendered);
                std.debug.print("snapshot mismatch at {s}:{d}:{d}; wrote {s}\n", .{
                    snapshot_path,
                    difference.line,
                    difference.column,
                    candidate_path,
                });
                return error.SnapshotMismatch;
            }
        },
    }
}

fn writeFileAtomic(io: std.Io, path: []const u8, data: []const u8) !void {
    var atomic_file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .make_path = true,
        .replace = true,
    });
    defer atomic_file.deinit(io);

    var buffer: [4096]u8 = undefined;
    var file_writer = atomic_file.file.writer(io, &buffer);
    try file_writer.interface.writeAll(data);
    try file_writer.flush();
    try atomic_file.replace(io);
}

fn isolatedRuleOptions() lint.Options {
    @setEvalBranchQuota(100_000);

    var options = lint.Options{};
    inline for (@typeInfo(lint.rules).@"struct".decl_names) |declaration_name| {
        const candidate = @field(lint.rules, declaration_name);
        if (@TypeOf(candidate) == type) {
            if (@hasDecl(candidate, "id")) {
                if (!options.setByCliName(candidate.id, false)) {
                    std.debug.print("snapshot isolation skipped unknown exported rule: {s}\n", .{candidate.id});
                }
            }
        }
    }
    options.parser_semantic_errors = false;
    return options;
}

fn optionsPath(allocator: Allocator, fixture_path: []const u8) ![]u8 {
    const extension = std.fs.path.extension(fixture_path);
    if (extension.len == 0) return error.InvalidFixturePath;
    return std.fmt.allocPrint(allocator, "{s}.options.json", .{fixture_path[0 .. fixture_path.len - extension.len]});
}

fn readCaseOptions(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
) !std.json.Parsed(CaseOptions) {
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_fixture_size)) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("missing required rule snapshot options: {s}\n", .{path});
            return error.MissingSnapshotOptions;
        },
        else => return err,
    };
    defer allocator.free(source);
    return try std.json.parseFromSlice(CaseOptions, allocator, source, .{
        .ignore_unknown_fields = false,
    });
}

fn validateFixtureResult(
    display_path: []const u8,
    rule_id: []const u8,
    expectation: CaseOptions,
    source: []const u8,
    diagnostics: []const lint.Diagnostic,
) !void {
    if ((expectation.expect == .clean) != (expectation.diagnostic_count == 0)) {
        return error.InvalidSnapshotExpectation;
    }
    if (expectation.expect == .clean and expectation.fixes != .forbidden) {
        return error.InvalidSnapshotExpectation;
    }
    if (diagnostics.len != expectation.diagnostic_count) {
        std.debug.print("{s}: expected {d} diagnostics, but received {d}\n", .{
            display_path,
            expectation.diagnostic_count,
            diagnostics.len,
        });
        return error.UnexpectedDiagnosticCount;
    }

    var fix_count: usize = 0;
    for (diagnostics) |diagnostic| {
        if (!std.mem.eql(u8, diagnostic.rule_id, rule_id)) {
            std.debug.print("{s}: expected only {s}, but received diagnostic from {s}\n", .{
                display_path,
                rule_id,
                diagnostic.rule_id,
            });
            return error.UnexpectedRuleDiagnostic;
        }
        try validateDiagnosticSpans(display_path, source, diagnostic);
        fix_count += diagnostic.fixes.len;
    }

    switch (expectation.fixes) {
        .required => if (fix_count == 0) return error.ExpectedFixes,
        .forbidden => if (fix_count != 0) return error.UnexpectedFixes,
        .any => {},
    }
}

fn validateDiagnosticSpans(display_path: []const u8, source: []const u8, diagnostic: lint.Diagnostic) !void {
    if (!validSpan(source, diagnostic.span.start, diagnostic.span.end)) {
        std.debug.print("{s}: diagnostic from {s} has invalid span {d}..{d} for {d} source bytes\n", .{
            display_path,
            diagnostic.rule_id,
            diagnostic.span.start,
            diagnostic.span.end,
            source.len,
        });
        return error.InvalidDiagnosticSpan;
    }
    for (diagnostic.fixes) |fix| {
        if (!validSpan(source, fix.span.start, fix.span.end)) {
            std.debug.print("{s}: diagnostic from {s} has invalid fix span {d}..{d} for {d} source bytes\n", .{
                display_path,
                diagnostic.rule_id,
                fix.span.start,
                fix.span.end,
                source.len,
            });
            return error.InvalidFixSpan;
        }
    }
}

fn validSpan(source: []const u8, start: u32, end: u32) bool {
    return start <= end and end <= source.len;
}

fn normalizedPath(allocator: Allocator, path: []const u8) ![]u8 {
    const normalized = try allocator.dupe(u8, path);
    if (std.fs.path.sep != '/') {
        std.mem.replaceScalar(u8, normalized, std.fs.path.sep, '/');
    }
    return normalized;
}

fn ruleIdFromPath(allocator: Allocator, normalized_relative_path: []const u8) ![]u8 {
    var parts = std.mem.splitScalar(u8, normalized_relative_path, '/');
    const category = parts.next() orelse return error.InvalidFixturePath;
    const rule_name = parts.next() orelse return error.InvalidFixturePath;
    const case_name = parts.next() orelse return error.InvalidFixturePath;
    if (case_name.len == 0 or parts.next() != null) return error.InvalidFixturePath;

    const prefix = if (std.mem.eql(u8, category, "core"))
        ""
    else if (std.mem.eql(u8, category, "typescript-eslint"))
        "@typescript-eslint/"
    else if (std.mem.eql(u8, category, "react"))
        "react/"
    else if (std.mem.eql(u8, category, "react-hooks"))
        "react-hooks/"
    else if (std.mem.eql(u8, category, "unused-imports"))
        "unused-imports/"
    else if (std.mem.eql(u8, category, "jsx-a11y"))
        "jsx-a11y/"
    else if (std.mem.eql(u8, category, "import"))
        "import/"
    else if (std.mem.eql(u8, category, "eslint-comments"))
        "eslint-comments/"
    else if (std.mem.eql(u8, category, "alipay-ant"))
        "@alipay/ant/"
    else if (std.mem.eql(u8, category, "alipay-spmlint"))
        "@alipay/spmLint/"
    else
        return error.UnknownRuleCategory;

    return std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, rule_name });
}

fn renderSnapshot(
    allocator: Allocator,
    fixture_path: []const u8,
    rule_id: []const u8,
    source: []const u8,
    diagnostics: []const lint.Diagnostic,
    applied: lint.ApplyFixesResult,
    remaining_diagnostics: []const lint.Diagnostic,
) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();
    const writer = &allocating.writer;

    try writer.writeAll("---\nfixture: ");
    try writeJsonString(writer, fixture_path);
    try writer.writeAll("\nrule: ");
    try writeJsonString(writer, rule_id);
    try writer.writeAll("\n---\n\n# Input\n\n");
    try writeCodeBlock(writer, source, languageFromPath(fixture_path));
    try writer.print("\n# Diagnostics\n\ncount: {d}\n", .{diagnostics.len});

    for (diagnostics, 0..) |diagnostic, diagnostic_index| {
        const start = lint.offsetToLineColumn(source, diagnostic.span.start);
        const end = lint.offsetToLineColumn(source, diagnostic.span.end);
        try writer.print("\n## Diagnostic {d}\n\n", .{diagnostic_index + 1});
        try writer.writeAll("- rule: ");
        try writeJsonString(writer, diagnostic.rule_id);
        try writer.writeAll("\n- severity: ");
        try writeJsonString(writer, diagnostic.severity.toString());
        try writer.writeAll("\n- message: ");
        try writeJsonString(writer, diagnostic.message);
        try writer.print("\n- byte span: {d}..{d}\n- start: {d}:{d}\n- end: {d}:{d}\n- source: ", .{
            diagnostic.span.start,
            diagnostic.span.end,
            start.line,
            start.column,
            end.line,
            end.column,
        });
        try writeSpanSource(writer, source, diagnostic.span.start, diagnostic.span.end);
        try writer.print("\n- fixes: {d}\n", .{diagnostic.fixes.len});

        for (diagnostic.fixes, 0..) |fix, fix_index| {
            const fix_start = lint.offsetToLineColumn(source, fix.span.start);
            const fix_end = lint.offsetToLineColumn(source, fix.span.end);
            try writer.print("\n### Fix {d}.{d}\n\n- byte span: {d}..{d}\n- start: {d}:{d}\n- end: {d}:{d}\n- source: ", .{
                diagnostic_index + 1,
                fix_index + 1,
                fix.span.start,
                fix.span.end,
                fix_start.line,
                fix_start.column,
                fix_end.line,
                fix_end.column,
            });
            try writeSpanSource(writer, source, fix.span.start, fix.span.end);
            try writer.writeAll("\n- replacement: ");
            try writeJsonString(writer, fix.replacement);
            try writer.writeByte('\n');
        }
    }

    try writer.writeAll("\n# First fix pass\n\n- fixed: ");
    try writer.writeAll(if (applied.fixed) "true" else "false");
    try writer.print("\n- applied diagnostics: {d}\n", .{applied.applied_diagnostics});
    if (applied.fixed) {
        try writer.print("- remaining diagnostics: {d}\n\n", .{remaining_diagnostics.len});
        try writeCodeBlock(writer, applied.output, languageFromPath(fixture_path));
        if (remaining_diagnostics.len != 0) {
            try writer.writeAll("\n## Remaining diagnostics\n");
            for (remaining_diagnostics, 0..) |diagnostic, index| {
                try writer.print("\n### Remaining diagnostic {d}\n\n- rule: ", .{index + 1});
                try writeJsonString(writer, diagnostic.rule_id);
                try writer.writeAll("\n- severity: ");
                try writeJsonString(writer, diagnostic.severity.toString());
                try writer.writeAll("\n- message: ");
                try writeJsonString(writer, diagnostic.message);
                try writer.print("\n- byte span: {d}..{d}\n", .{ diagnostic.span.start, diagnostic.span.end });
            }
        }
    }

    return allocating.toOwnedSlice();
}

fn writeJsonString(writer: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn writeSpanSource(writer: *std.Io.Writer, source: []const u8, start: u32, end: u32) !void {
    const start_index: usize = @intCast(start);
    const end_index: usize = @intCast(end);
    if (start_index > end_index or end_index > source.len) {
        try writer.writeAll("null");
        return;
    }
    try writeJsonString(writer, source[start_index..end_index]);
}

fn languageFromPath(path: []const u8) []const u8 {
    const extension = std.fs.path.extension(path);
    return if (extension.len > 1) extension[1..] else "text";
}

fn writeCodeBlock(writer: *std.Io.Writer, source: []const u8, language: []const u8) !void {
    const fence_length = @max(maxBacktickRun(source) + 1, 3);
    try writeBackticks(writer, fence_length);
    try writer.writeAll(language);
    try writer.writeByte('\n');
    try writer.writeAll(source);
    if (source.len == 0 or source[source.len - 1] != '\n') try writer.writeByte('\n');
    try writeBackticks(writer, fence_length);
    try writer.writeByte('\n');
}

fn maxBacktickRun(source: []const u8) usize {
    var maximum: usize = 0;
    var current: usize = 0;
    for (source) |byte| {
        if (byte == '`') {
            current += 1;
            maximum = @max(maximum, current);
        } else {
            current = 0;
        }
    }
    return maximum;
}

fn writeBackticks(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte('`');
}

const Difference = struct {
    line: usize,
    column: usize,
};

fn firstDifference(expected: []const u8, actual: []const u8) Difference {
    const common_length = @min(expected.len, actual.len);
    var line: usize = 1;
    var column: usize = 1;
    var index: usize = 0;
    while (index < common_length and expected[index] == actual[index]) : (index += 1) {
        if (expected[index] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{ .line = line, .column = column };
}
