const std = @import("std");
const parser = @import("parser");
const core = @import("core.zig");
const fixer = @import("fixer.zig");
const semantic_compat = @import("semantic_compat.zig");
const suppressions = @import("suppressions.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const Severity = core.Severity;
pub const Options = core.Options;
pub const Diagnostic = core.Diagnostic;
pub const Suppression = core.Suppression;
pub const Fix = core.Fix;
pub const Suggestion = core.Suggestion;
pub const Result = core.Result;
pub const ApplyFixesResult = fixer.ApplyResult;
pub const max_autofix_passes = 10;
pub const SourcePosition = core.SourcePosition;
pub const NoRestrictedImportEntry = core.NoRestrictedImportEntry;
pub const NoRestrictedImportKind = core.NoRestrictedImportKind;
pub const NoRestrictedSyntaxEntry = core.NoRestrictedSyntaxEntry;
pub const SortImportsMemberSyntax = core.SortImportsMemberSyntax;
pub const rules = @import("rules/root.zig");

pub fn applyFixes(
    allocator: Allocator,
    source: []const u8,
    diagnostics: []const Diagnostic,
) Allocator.Error!ApplyFixesResult {
    return fixer.apply(allocator, source, diagnostics);
}

pub const LintAndFixResult = struct {
    output: []u8,
    result: Result,
    fixed: bool,
    passes: usize,
    applied_diagnostics: usize,

    pub fn deinit(self: *LintAndFixResult, allocator: Allocator) void {
        allocator.free(self.output);
        self.result.deinit(allocator);
    }
};

pub fn lintSourceAndFix(
    allocator: Allocator,
    source: []const u8,
    path: []const u8,
    options: Options,
) Allocator.Error!LintAndFixResult {
    return lintSourceAndFixInternal(false, allocator, {}, source, path, options);
}

pub fn lintSourceAndFixWithIo(
    allocator: Allocator,
    io: ?std.Io,
    source: []const u8,
    path: []const u8,
    options: Options,
) Allocator.Error!LintAndFixResult {
    if (io) |actual_io| {
        return lintSourceAndFixInternal(true, allocator, actual_io, source, path, options);
    }
    return lintSourceAndFixInternal(false, allocator, {}, source, path, options);
}

fn lintSourceAndFixInternal(
    comptime with_io: bool,
    allocator: Allocator,
    io: if (with_io) std.Io else void,
    source: []const u8,
    path: []const u8,
    options: Options,
) Allocator.Error!LintAndFixResult {
    var output = try allocator.dupe(u8, source);
    errdefer allocator.free(output);

    var passes: usize = 0;
    var applied_diagnostics: usize = 0;

    while (passes < max_autofix_passes) {
        var result = try lintSourceInternal(with_io, allocator, io, output, path, options);
        var applied = applyFixes(allocator, output, result.diagnostics) catch |err| {
            result.deinit(allocator);
            return err;
        };

        if (!applied.fixed) {
            applied.deinit(allocator);
            return .{
                .output = output,
                .result = result,
                .fixed = passes > 0,
                .passes = passes,
                .applied_diagnostics = applied_diagnostics,
            };
        }

        result.deinit(allocator);
        allocator.free(output);
        output = applied.output;
        passes += 1;
        applied_diagnostics += applied.applied_diagnostics;
    }

    return .{
        .output = output,
        .result = try lintSourceInternal(with_io, allocator, io, output, path, options),
        .fixed = true,
        .passes = passes,
        .applied_diagnostics = applied_diagnostics,
    };
}

pub fn lintSource(
    allocator: Allocator,
    source: []const u8,
    path: []const u8,
    options: Options,
) Allocator.Error!Result {
    return lintSourceInternal(false, allocator, {}, source, path, options);
}

pub fn lintSourceWithIo(
    allocator: Allocator,
    io: ?std.Io,
    source: []const u8,
    path: []const u8,
    options: Options,
) Allocator.Error!Result {
    if (io) |actual_io| {
        return lintSourceInternal(true, allocator, actual_io, source, path, options);
    }
    return lintSourceInternal(false, allocator, {}, source, path, options);
}

fn lintSourceInternal(
    comptime with_io: bool,
    allocator: Allocator,
    io: if (with_io) std.Io else void,
    source: []const u8,
    path: []const u8,
    options: Options,
) Allocator.Error!Result {
    var diagnostics: core.DiagnosticList = .empty;
    errdefer core.freeDiagnostics(allocator, &diagnostics);
    var suppressed_diagnostics: core.DiagnosticList = .empty;
    errdefer core.freeDiagnostics(allocator, &suppressed_diagnostics);

    var effective_options = options;
    if (isDefinitionFile(path) and effective_options.typescript_eslint_no_namespace_allow_definition_files) {
        effective_options.typescript_eslint_no_namespace = false;
    }
    if (effective_options.jest_no_deprecated_functions and effective_options.jest_version == 0) {
        if (comptime with_io) {
            effective_options.jest_version = (try rules.jest_no_deprecated_functions.detectJestVersion(
                allocator,
                io,
                path,
            )) orelse rules.jest_no_deprecated_functions.latest_jest_version;
        } else {
            effective_options.jest_version = rules.jest_no_deprecated_functions.latest_jest_version;
        }
    }

    var tree = try parseSource(allocator, source, path);
    defer tree.deinit();

    const needs_semantic = hasSemanticRules(effective_options);

    if (needs_semantic) {
        const semantic_model = try parser.semantic.analyze(&tree);
        var semantic_result = semantic_compat.Result.init(&tree, semantic_model);
        try semantic_result.symbol_table.resolveAll(semantic_result.scope_tree);
        try appendParserDiagnostics(allocator, &diagnostics, &tree, effective_options);
        try rules.runBasicWithOptionsPtr(allocator, &diagnostics, &tree, path, &effective_options);
        if (with_io) {
            try rules.runSemanticWithIo(allocator, &diagnostics, &tree, io, path, semantic_result, effective_options);
        } else {
            try rules.runSemantic(allocator, &diagnostics, &tree, semantic_result, effective_options);
        }
    } else {
        try appendParserDiagnostics(allocator, &diagnostics, &tree, effective_options);
        try rules.runBasicWithOptionsPtr(allocator, &diagnostics, &tree, path, &effective_options);
    }

    try suppressions.apply(allocator, &diagnostics, &suppressed_diagnostics, &tree);

    const owned_diagnostics = try diagnostics.toOwnedSlice(allocator);
    errdefer core.freeDiagnosticSlice(allocator, owned_diagnostics);
    const owned_suppressed_diagnostics = try suppressed_diagnostics.toOwnedSlice(allocator);

    return .{
        .diagnostics = owned_diagnostics,
        .suppressed_diagnostics = owned_suppressed_diagnostics,
    };
}

fn parseSource(allocator: Allocator, source: []const u8, path: []const u8) Allocator.Error!ast.Tree {
    var tree = try parser.parse(allocator, source, .{
        .source_type = ast.SourceType.fromPath(path),
        .lang = ast.Lang.fromPath(path),
    });

    const fallback_lang = jsxFallbackLang(path) orelse return tree;
    if (!tree.hasErrors()) return tree;

    var fallback_tree = try parser.parse(allocator, source, .{
        .source_type = ast.SourceType.fromPath(path),
        .lang = fallback_lang,
    });
    if (fallback_tree.hasErrors()) {
        fallback_tree.deinit();
        return tree;
    }

    tree.deinit();
    return fallback_tree;
}

fn jsxFallbackLang(path: []const u8) ?ast.Lang {
    if (std.mem.endsWith(u8, path, ".js") or
        std.mem.endsWith(u8, path, ".mjs") or
        std.mem.endsWith(u8, path, ".cjs"))
    {
        return .jsx;
    }

    if (std.mem.endsWith(u8, path, ".ts") or
        std.mem.endsWith(u8, path, ".mts") or
        std.mem.endsWith(u8, path, ".cts"))
    {
        return .tsx;
    }

    return null;
}

pub fn isLintablePath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".js") or
        std.mem.endsWith(u8, path, ".jsx") or
        std.mem.endsWith(u8, path, ".ts") or
        std.mem.endsWith(u8, path, ".tsx") or
        std.mem.endsWith(u8, path, ".mjs") or
        std.mem.endsWith(u8, path, ".cjs") or
        std.mem.endsWith(u8, path, ".mts") or
        std.mem.endsWith(u8, path, ".cts");
}

fn isDefinitionFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".d.ts") or
        std.mem.endsWith(u8, path, ".d.mts") or
        std.mem.endsWith(u8, path, ".d.cts");
}

fn hasSemanticRules(options: Options) bool {
    return options.parser_semantic_errors or
        options.block_scoped_var or
        options.no_array_constructor or
        options.no_alert or
        options.no_async_promise_executor or
        options.alipay_ant_exhaustive_deps or
        options.react_hooks_exhaustive_deps or
        options.react_hooks_use_memo or
        options.alipay_ant_prefer_click_with_debounce or
        options.no_buffer_constructor or
        options.no_console or
        options.alipay_ant_no_spread_params or
        options.alipay_ant_prefer_import_from_stdlib or
        options.no_class_assign or
        options.no_const_assign or
        options.no_eval or
        options.no_ex_assign or
        options.no_extend_native or
        options.no_extra_boolean_cast or
        options.no_func_assign or
        options.no_global_assign or
        options.no_global_is_finite or
        options.no_global_is_nan or
        options.no_implied_eval or
        options.no_import_assign or
        options.no_invalid_this or
        options.no_unmodified_loop_condition or
        options.alipay_ant_no_phantom_dependencies or
        options.import_default or
        options.import_export or
        options.import_named or
        options.import_namespace or
        options.import_no_cycle or
        options.import_no_named_as_default or
        options.import_no_named_as_default_member or
        options.import_no_unresolved or
        options.jest_no_conditional_expect or
        options.jest_no_deprecated_functions or
        options.jest_no_export or
        options.jest_no_focused_tests or
        options.jest_no_identical_title or
        options.jest_no_interpolation_in_snapshots or
        options.jest_no_jasmine_globals or
        options.jest_no_standalone_expect or
        options.jest_valid_describe_callback or
        options.jest_valid_expect_in_promise or
        options.jest_valid_expect or
        options.jest_valid_title or
        options.no_invalid_regexp or
        options.no_label_var or
        options.no_loop_func or
        options.no_misleading_character_class or
        options.no_new_func or
        options.no_new_native_nonconstructor or
        options.no_new_object or
        options.no_new_symbol or
        options.no_new_wrappers or
        options.no_obj_calls or
        options.no_object_constructor or
        options.no_promise_executor_return or
        options.no_redeclare or
        (options.no_restricted_globals and options.no_restricted_globals_entries.count != 0) or
        options.no_regex_spaces or
        options.no_shadow or
        options.no_unassigned_vars or
        options.no_undef_init or
        options.no_undef or
        options.no_var or
        options.react_jsx_no_undef or
        options.react_no_forward_ref or
        options.no_unused_vars or
        options.no_useless_assignment or
        options.no_useless_backreference or
        options.no_use_before_define or
        options.prefer_const or
        options.prefer_exponentiation_operator or
        options.prefer_named_capture_group or
        options.prefer_numeric_literals or
        options.prefer_object_has_own or
        options.prefer_object_spread or
        options.prefer_promise_reject_errors or
        options.promise_no_nesting or
        options.preserve_caught_error or
        options.prefer_regex_literals or
        options.radix or
        options.require_atomic_updates or
        options.require_unicode_regexp or
        options.symbol_description or
        options.typescript_eslint_no_redeclare or
        options.typescript_eslint_no_require_imports or
        options.typescript_eslint_no_loop_func or
        options.typescript_eslint_no_shadow or
        options.typescript_eslint_no_unsafe_declaration_merging or
        options.typescript_eslint_no_unsafe_function_type or
        options.typescript_eslint_no_unused_vars or
        options.typescript_eslint_no_use_before_define or
        options.typescript_eslint_no_var_requires or
        options.unused_imports_no_unused_imports;
}

pub fn offsetToLineColumn(source: []const u8, offset: u32) SourcePosition {
    const offset_usize: usize = @intCast(offset);
    const end = @min(offset_usize, source.len);
    var line: usize = 1;
    var column: usize = 1;
    var index: usize = 0;

    while (index < end) : (index += 1) {
        if (source[index] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    return .{ .line = line, .column = column };
}

pub fn offsetToUtf16Offset(source: []const u8, offset: u32) usize {
    const end = @min(@as(usize, @intCast(offset)), source.len);
    var byte_index: usize = 0;
    var utf16_offset: usize = 0;

    while (byte_index < end) {
        const sequence_len = std.unicode.utf8ByteSequenceLength(source[byte_index]) catch 1;
        if (byte_index + sequence_len > end or byte_index + sequence_len > source.len) {
            byte_index += 1;
            utf16_offset += 1;
            continue;
        }

        utf16_offset += if (sequence_len == 4) 2 else 1;
        byte_index += sequence_len;
    }

    return utf16_offset;
}

/// ESLint positions are one-based UTF-16 columns and recognize every JS line terminator.
pub fn offsetToUtf16LineColumn(source: []const u8, offset: u32) SourcePosition {
    const end = @min(@as(usize, @intCast(offset)), source.len);
    var line: usize = 1;
    var column: usize = 1;
    var byte_index: usize = 0;

    while (byte_index < end) {
        const byte = source[byte_index];
        if (byte < 0x80) {
            const partial_crlf = byte == '\r' and byte_index + 1 == end and end < source.len and source[end] == '\n';
            if ((byte == '\r' and !partial_crlf) or byte == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
            byte_index += 1;
            if (byte == '\r' and byte_index < end and source[byte_index] == '\n') byte_index += 1;
            continue;
        }
        if (byte == 0xe2 and byte_index + 2 < end and source[byte_index + 1] == 0x80 and
            (source[byte_index + 2] == 0xa8 or source[byte_index + 2] == 0xa9))
        {
            line += 1;
            column = 1;
            byte_index += 3;
            continue;
        }

        const sequence_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
        if (byte_index + sequence_len > end) {
            column += 1;
            byte_index += 1;
            continue;
        }
        column += if (sequence_len == 4) 2 else 1;
        byte_index += sequence_len;
    }

    return .{ .line = line, .column = column };
}

fn appendParserDiagnostics(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    options: Options,
) Allocator.Error!void {
    for (tree.diagnostics.items) |diagnostic| {
        if (reactNoUnescapedEntitiesCoversParserDiagnostic(tree, diagnostic, options)) continue;

        try core.addDiagnostic(
            allocator,
            diagnostics,
            if (diagnostic.severity == .@"error") .@"error" else .warning,
            "parse",
            diagnostic.message,
            diagnostic.span,
        );
    }
}

fn reactNoUnescapedEntitiesCoversParserDiagnostic(
    tree: *const ast.Tree,
    diagnostic: ast.Diagnostic,
    options: Options,
) bool {
    if (!options.react_no_unescaped_entities) return false;

    const offset: usize = @intCast(diagnostic.span.start);
    if (offset >= tree.source.len) return false;

    const byte = tree.source[offset];
    return switch (byte) {
        '>' => options.react_no_unescaped_entities_forbid_gt and
            std.mem.eql(u8, diagnostic.message, "Unexpected '>' in JSX text"),
        '}' => options.react_no_unescaped_entities_forbid_closing_brace and
            std.mem.eql(u8, diagnostic.message, "Unexpected '}' in JSX text"),
        else => false,
    };
}
