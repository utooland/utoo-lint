//! Freestanding WebAssembly entry point for browser and worker runtimes.
//!
//! ABI version 1:
//!   abi_version() -> u32
//!   alloc(len) -> ptr
//!   free(ptr, len)
//!   lint(source_ptr, source_len, options_ptr, options_len) -> ptr
//!
//! `options` is UTF-8 JSON. The result is a length-prefixed UTF-8 JSON buffer:
//! `[u32 byte_length little-endian][byte_length bytes]`. The caller owns every
//! allocation and must release it with `free`.

const std = @import("std");
const lint_engine = @import("utoo_lint");

const Allocator = std.mem.Allocator;
const gpa = std.heap.wasm_allocator;
const current_abi_version: u32 = 1;
const max_source_size = 64 * 1024 * 1024;
const max_options_size = 1024 * 1024;

const FixMode = enum {
    none,
    apply,
};

const Failure = struct {
    code: []const u8 = "INTERNAL_ERROR",
    message: []const u8 = "utoo-lint failed",
    rule_id: ?[]u8 = null,

    fn deinit(self: *Failure, allocator: Allocator) void {
        if (self.rule_id) |rule_id| allocator.free(rule_id);
    }
};

const Config = struct {
    options: lint_engine.Options,
    severities: std.StringHashMap(lint_engine.Severity),
    skipped_rules: std.ArrayList([]const u8) = .empty,
    file_path: []const u8,
    fix_mode: FixMode,

    fn deinit(self: *Config, allocator: Allocator) void {
        self.severities.deinit();
        self.skipped_rules.deinit(allocator);
    }
};

const Utf16Position = struct {
    line: usize,
    column: usize,
};

export fn abi_version() u32 {
    return current_abi_version;
}

export fn alloc(len: usize) usize {
    const allocation = gpa.alloc(u8, allocationLength(len)) catch return 0;
    return @intFromPtr(allocation.ptr);
}

export fn free(ptr: [*]u8, len: usize) void {
    gpa.free(ptr[0..allocationLength(len)]);
}

export fn lint(
    source_ptr: [*]const u8,
    source_len: usize,
    options_ptr: [*]const u8,
    options_len: usize,
) usize {
    if (source_len > max_source_size) {
        const output = writeErrorResponse(gpa, .{
            .code = "REQUEST_TOO_LARGE",
            .message = "source exceeds the 64 MiB WebAssembly limit",
        }) catch return 0;
        return @intFromPtr(output.ptr);
    }
    if (options_len > max_options_size) {
        const output = writeErrorResponse(gpa, .{
            .code = "REQUEST_TOO_LARGE",
            .message = "options exceed the 1 MiB WebAssembly limit",
        }) catch return 0;
        return @intFromPtr(output.ptr);
    }

    var failure: Failure = .{};
    defer failure.deinit(gpa);
    const output = run(
        gpa,
        source_ptr[0..source_len],
        options_ptr[0..options_len],
        &failure,
    ) catch |err| {
        if (err == error.OutOfMemory or err == error.ResponseTooLarge) return 0;
        const error_output = writeErrorResponse(gpa, failure) catch return 0;
        return @intFromPtr(error_output.ptr);
    };
    return @intFromPtr(output.ptr);
}

fn allocationLength(len: usize) usize {
    return if (len == 0) 1 else len;
}

fn run(
    allocator: Allocator,
    source: []const u8,
    options_json: []const u8,
    failure: *Failure,
) ![]u8 {
    if (!std.unicode.utf8ValidateSlice(source)) {
        failure.* = .{
            .code = "INVALID_UTF8",
            .message = "source must be valid UTF-8",
        };
        return error.InvalidUtf8;
    }

    var parsed_options: ?std.json.Parsed(std.json.Value) = null;
    defer if (parsed_options) |*parsed| parsed.deinit();

    const root: ?std.json.ObjectMap = if (options_json.len == 0)
        null
    else options: {
        parsed_options = std.json.parseFromSlice(std.json.Value, allocator, options_json, .{}) catch {
            failure.* = .{
                .code = "INVALID_OPTIONS_JSON",
                .message = "options must be valid JSON",
            };
            return error.InvalidOptions;
        };
        break :options switch (parsed_options.?.value) {
            .object => |object| object,
            else => {
                failure.* = .{
                    .code = "INVALID_OPTIONS",
                    .message = "options must be a JSON object",
                };
                return error.InvalidOptions;
            },
        };
    };

    var config = try parseConfig(allocator, root, failure);
    defer config.deinit(allocator);

    if (config.fix_mode == .apply) {
        var fixed = lint_engine.lintSourceAndFix(allocator, source, config.file_path, config.options) catch |err| {
            if (err == error.OutOfMemory) return err;
            failure.* = .{
                .code = "FIX_FAILED",
                .message = "the lint engine could not apply fixes",
            };
            return error.FixFailed;
        };
        defer fixed.deinit(allocator);
        return writeSuccessResponse(
            allocator,
            fixed.output,
            config.file_path,
            fixed.result,
            &config.severities,
            config.skipped_rules.items,
            &fixed,
            .apply,
        );
    }

    var result = lint_engine.lintSource(allocator, source, config.file_path, config.options) catch |err| {
        if (err == error.OutOfMemory) return err;
        failure.* = .{
            .code = "LINT_FAILED",
            .message = "the lint engine could not process the source",
        };
        return error.LintFailed;
    };
    defer result.deinit(allocator);
    return writeSuccessResponse(
        allocator,
        source,
        config.file_path,
        result,
        &config.severities,
        config.skipped_rules.items,
        null,
        .none,
    );
}

fn parseConfig(
    allocator: Allocator,
    root: ?std.json.ObjectMap,
    failure: *Failure,
) !Config {
    const file_path = if (root) |object|
        if (object.get("filePath")) |value| switch (value) {
            .string => |path| path,
            else => {
                failure.* = .{
                    .code = "INVALID_OPTIONS",
                    .message = "filePath must be a string",
                };
                return error.InvalidOptions;
            },
        } else "input.js"
    else
        "input.js";

    const fix_mode: FixMode = if (root) |object|
        if (object.get("fix")) |value| switch (value) {
            .string => |mode| if (std.mem.eql(u8, mode, "none"))
                .none
            else if (std.mem.eql(u8, mode, "apply"))
                .apply
            else {
                failure.* = .{
                    .code = "INVALID_OPTIONS",
                    .message = "fix must be either \"none\" or \"apply\"",
                };
                return error.InvalidOptions;
            },
            else => {
                failure.* = .{
                    .code = "INVALID_OPTIONS",
                    .message = "fix must be either \"none\" or \"apply\"",
                };
                return error.InvalidOptions;
            },
        } else .none
    else
        .none;

    if (root) |object| {
        if (object.get("version")) |value| {
            const version = switch (value) {
                .integer => |integer| integer,
                else => {
                    failure.* = .{
                        .code = "UNSUPPORTED_VERSION",
                        .message = "options version must be 1",
                    };
                    return error.UnsupportedOptionsVersion;
                },
            };
            if (version != current_abi_version) {
                failure.* = .{
                    .code = "UNSUPPORTED_VERSION",
                    .message = "options version must be 1",
                };
                return error.UnsupportedOptionsVersion;
            }
        }
    }

    var config = Config{
        .options = .{},
        .severities = std.StringHashMap(lint_engine.Severity).init(allocator),
        .file_path = file_path,
        .fix_mode = fix_mode,
    };
    errdefer config.deinit(allocator);

    const rules_value = if (root) |object| object.get("rules") else null;
    if (rules_value) |value| {
        const rules = switch (value) {
            .object => |object| object,
            else => {
                failure.* = .{
                    .code = "INVALID_OPTIONS",
                    .message = "rules must be a JSON object",
                };
                return error.InvalidOptions;
            },
        };

        config.options = lint_engine.Options.allDisabled();
        var iterator = rules.iterator();
        while (iterator.next()) |entry| {
            config.options.setByRuleConfigValue(entry.key_ptr.*, entry.value_ptr.*) catch |err| {
                failure.* = .{
                    .code = if (err == error.UnknownRule) "UNKNOWN_RULE" else "INVALID_RULE_CONFIG",
                    .message = @errorName(err),
                    // The parsed JSON is released before the ABI error response
                    // is encoded, so retain the rule id independently.
                    .rule_id = try allocator.dupe(u8, entry.key_ptr.*),
                };
                return error.InvalidRuleConfig;
            };

            const severity = lint_engine.Options.severityFromRuleConfigValue(entry.value_ptr.*) catch |err| {
                failure.* = .{
                    .code = "INVALID_RULE_CONFIG",
                    .message = @errorName(err),
                    .rule_id = try allocator.dupe(u8, entry.key_ptr.*),
                };
                return error.InvalidRuleConfig;
            };
            if (severity) |configured_severity| {
                try config.severities.put(entry.key_ptr.*, configured_severity);
            }
        }
    }

    if (root) |object| {
        if (object.get("sourceType")) |source_type| {
            config.options.setSourceTypeFromConfig(source_type) catch {
                failure.* = .{ .code = "INVALID_OPTIONS", .message = "sourceType must be module, script, or commonjs" };
                return error.InvalidOptions;
            };
        }
    }

    const settings_value = if (root) |object| object.get("settings") else null;
    if (settings_value) |value| {
        const settings = switch (value) {
            .object => |object| object,
            else => {
                failure.* = .{ .code = "INVALID_OPTIONS", .message = "settings must be a JSON object" };
                return error.InvalidOptions;
            },
        };
        if (settings.get("jest")) |jest_value| {
            const jest = switch (jest_value) {
                .object => |object| object,
                else => {
                    failure.* = .{ .code = "INVALID_OPTIONS", .message = "settings.jest must be a JSON object" };
                    return error.InvalidOptions;
                },
            };
            if (jest.get("version")) |version| {
                config.options.setJestVersionFromConfig(version) catch |err| {
                    failure.* = .{ .code = "INVALID_OPTIONS", .message = @errorName(err) };
                    return error.InvalidOptions;
                };
            }
            if (jest.get("globalAliases")) |aliases| {
                config.options.setJestGlobalAliasesFromConfig(aliases) catch |err| {
                    failure.* = .{ .code = "INVALID_OPTIONS", .message = @errorName(err) };
                    return error.InvalidOptions;
                };
            }
        }
    }

    try appendSkippedRules(allocator, &config.skipped_rules, config.options);
    return config;
}

fn appendSkippedRules(
    allocator: Allocator,
    skipped_rules: *std.ArrayList([]const u8),
    options: lint_engine.Options,
) Allocator.Error!void {
    if (options.alipay_ant_no_phantom_dependencies) try skipped_rules.append(allocator, "@alipay/ant/no-phantom-dependencies");
    if (options.alipay_ant_prefer_import_from_stdlib) try skipped_rules.append(allocator, "@alipay/ant/prefer-import-from-stdlib");
    if (options.import_default) try skipped_rules.append(allocator, "import/default");
    if (options.import_export) try skipped_rules.append(allocator, "import/export");
    if (options.import_named) try skipped_rules.append(allocator, "import/named");
    if (options.import_namespace) try skipped_rules.append(allocator, "import/namespace");
    if (options.import_no_cycle) try skipped_rules.append(allocator, "import/no-cycle");
    if (options.import_no_named_as_default) try skipped_rules.append(allocator, "import/no-named-as-default");
    if (options.import_no_named_as_default_member) try skipped_rules.append(allocator, "import/no-named-as-default-member");
    if (options.import_no_unresolved) try skipped_rules.append(allocator, "import/no-unresolved");
}

fn writeSuccessResponse(
    allocator: Allocator,
    source: []const u8,
    file_path: []const u8,
    result: lint_engine.Result,
    severities: *const std.StringHashMap(lint_engine.Severity),
    skipped_rules: []const []const u8,
    fixed_result: ?*const lint_engine.LintAndFixResult,
    fix_mode: FixMode,
) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    try writer.writeAll("\x00\x00\x00\x00{\"version\":1,\"ok\":true,\"mode\":");
    try writeJsonValue(writer, if (fix_mode == .apply) "fix" else "lint");
    try writer.writeAll(",\"offsetEncoding\":\"utf-16\",\"diagnosticsSource\":");
    try writeJsonValue(writer, if (fix_mode == .apply) "output" else "input");
    try writer.writeAll(",\"filePath\":");
    try writeJsonValue(writer, file_path);
    try writer.writeAll(",\"diagnostics\":");
    try writeDiagnostics(writer, source, result.diagnostics, severities);
    try writer.writeAll(",\"suppressedDiagnostics\":");
    try writeDiagnostics(writer, source, result.suppressed_diagnostics, severities);
    try writer.writeAll(",\"skippedRules\":");
    try writeStringArray(writer, skipped_rules);

    if (fixed_result) |fixed| {
        try writer.writeAll(",\"fixed\":");
        try writer.writeAll(if (fixed.fixed) "true" else "false");
        try writer.print(",\"passes\":{d},\"appliedDiagnostics\":{d},\"output\":", .{
            fixed.passes,
            fixed.applied_diagnostics,
        });
        try writeJsonValue(writer, fixed.output);
    } else {
        try writer.writeAll(",\"fixed\":false,\"passes\":0,\"appliedDiagnostics\":0");
    }
    try writer.writeByte('}');
    return finishResponse(allocator, &output);
}

fn writeErrorResponse(allocator: Allocator, failure: Failure) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    try writer.writeAll("\x00\x00\x00\x00{\"version\":1,\"ok\":false,\"error\":{\"code\":");
    try writeJsonValue(writer, failure.code);
    try writer.writeAll(",\"message\":");
    try writeJsonValue(writer, failure.message);
    if (failure.rule_id) |rule_id| {
        try writer.writeAll(",\"ruleId\":");
        try writeJsonValue(writer, rule_id);
    }
    try writer.writeAll("}}");
    return finishResponse(allocator, &output);
}

fn finishResponse(allocator: Allocator, output: *std.Io.Writer.Allocating) ![]u8 {
    const owned = try output.toOwnedSlice();
    errdefer allocator.free(owned);
    const payload_len = owned.len - 4;
    if (payload_len > std.math.maxInt(u32)) return error.ResponseTooLarge;
    std.mem.writeInt(u32, owned[0..4], @intCast(payload_len), .little);
    return owned;
}

fn writeDiagnostics(
    writer: *std.Io.Writer,
    source: []const u8,
    diagnostics: []const lint_engine.Diagnostic,
    severities: *const std.StringHashMap(lint_engine.Severity),
) !void {
    try writer.writeByte('[');
    for (diagnostics, 0..) |diagnostic, index| {
        if (index != 0) try writer.writeByte(',');
        try writeDiagnostic(writer, source, diagnostic, severities);
    }
    try writer.writeByte(']');
}

fn writeDiagnostic(
    writer: *std.Io.Writer,
    source: []const u8,
    diagnostic: lint_engine.Diagnostic,
    severities: *const std.StringHashMap(lint_engine.Severity),
) !void {
    const start = utf16Position(source, diagnostic.span.start);
    const end = utf16Position(source, diagnostic.span.end);
    const start_offset = lint_engine.offsetToUtf16Offset(source, diagnostic.span.start);
    const end_offset = lint_engine.offsetToUtf16Offset(source, diagnostic.span.end);
    const severity = severities.get(diagnostic.rule_id) orelse diagnostic.severity;

    try writer.writeAll("{\"ruleId\":");
    try writeJsonValue(writer, diagnostic.rule_id);
    try writer.writeAll(",\"severity\":");
    try writeJsonValue(writer, severity.toString());
    try writer.writeAll(",\"message\":");
    try writeJsonValue(writer, diagnostic.message);
    try writer.print(",\"range\":[{d},{d}],\"line\":{d},\"column\":{d},\"endLine\":{d},\"endColumn\":{d},\"fixes\":", .{
        start_offset,
        end_offset,
        start.line,
        start.column,
        end.line,
        end.column,
    });
    try writeFixes(writer, source, diagnostic.fixes);
    try writer.writeAll(",\"suggestions\":");
    try writeSuggestions(writer, source, diagnostic.suggestions);
    if (diagnostic.suppression) |suppression| {
        try writer.writeAll(",\"suppression\":{\"kind\":\"directive\",\"justification\":");
        try writeJsonValue(writer, suppression.justification);
        try writer.writeByte('}');
    }
    if (diagnostic.suppressions.len > 0) {
        try writer.writeAll(",\"suppressions\":[");
        for (diagnostic.suppressions, 0..) |suppression, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeAll("{\"kind\":\"directive\",\"justification\":");
            try writeJsonValue(writer, suppression.justification);
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
    }
    try writer.writeByte('}');
}

fn writeSuggestions(
    writer: *std.Io.Writer,
    source: []const u8,
    suggestions: []const lint_engine.Suggestion,
) !void {
    try writer.writeByte('[');
    for (suggestions, 0..) |suggestion, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll("{\"desc\":");
        try writeJsonValue(writer, suggestion.message);
        try writer.writeAll(",\"fix\":");
        try writeFixes(writer, source, suggestion.fixes);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeFixes(
    writer: *std.Io.Writer,
    source: []const u8,
    fixes: []const lint_engine.Fix,
) !void {
    try writer.writeByte('[');
    for (fixes, 0..) |fix_item, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print("{{\"range\":[{d},{d}],\"text\":", .{
            lint_engine.offsetToUtf16Offset(source, fix_item.span.start),
            lint_engine.offsetToUtf16Offset(source, fix_item.span.end),
        });
        try writeJsonValue(writer, fix_item.replacement);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeStringArray(writer: *std.Io.Writer, values: []const []const u8) !void {
    try writer.writeByte('[');
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try writeJsonValue(writer, value);
    }
    try writer.writeByte(']');
}

fn writeJsonValue(writer: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn utf16Position(source: []const u8, offset: u32) Utf16Position {
    const end = @min(@as(usize, @intCast(offset)), source.len);
    var line: usize = 1;
    var column: usize = 1;
    var byte_index: usize = 0;
    while (byte_index < end) {
        if (source[byte_index] == '\n') {
            line += 1;
            column = 1;
            byte_index += 1;
            continue;
        }

        const sequence_len = std.unicode.utf8ByteSequenceLength(source[byte_index]) catch 1;
        if (byte_index + sequence_len > end or byte_index + sequence_len > source.len) {
            column += 1;
            byte_index += 1;
            continue;
        }
        column += if (sequence_len == 4) 2 else 1;
        byte_index += sequence_len;
    }
    return .{ .line = line, .column = column };
}
