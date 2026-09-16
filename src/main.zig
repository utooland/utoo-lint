const std = @import("std");
const lint = @import("utoo_lint");
const flat_config = @import("flat_config.zig");

const max_file_size = 64 * 1024 * 1024;
const max_config_file_size = 1024 * 1024;

const Stats = struct {
    files: usize = 0,
    diagnostics: usize = 0,
    errors: usize = 0,
    fixable: usize = 0,
    fixed: usize = 0,

    fn add(self: *Stats, other: Stats) void {
        self.files += other.files;
        self.diagnostics += other.diagnostics;
        self.errors += other.errors;
        self.fixable += other.fixable;
        self.fixed += other.fixed;
    }
};

const OutputFormat = enum {
    text,
    json,
};

const FixMode = enum {
    none,
    write,
    dry_run,
};

const JsonFix = struct {
    range: [2]usize,
    text: []const u8,
};

const JsonSuggestion = struct {
    desc: []const u8,
    fix: []const JsonFix,
};

const JsonSuppression = struct {
    kind: []const u8,
    justification: []const u8,
};

const JsonDiagnostic = struct {
    filePath: []const u8,
    line: usize,
    column: usize,
    endLine: ?usize = null,
    endColumn: ?usize = null,
    severity: []const u8,
    message: []const u8,
    ruleId: []const u8,
    fixes: []const JsonFix,
    suggestions: []const JsonSuggestion,
    suppression: ?JsonSuppression = null,
    suppressions: []const JsonSuppression = &.{},
};

const JsonDiagnosticList = std.ArrayList(JsonDiagnostic);

const JsonOutput = struct {
    filePath: []const u8,
    output: []const u8,
};

const JsonOutputList = std.ArrayList(JsonOutput);
const RuleSeverityMap = flat_config.RuleSeverityMap;

const JsonReport = struct {
    files: usize,
    filePaths: []const []const u8,
    diagnostics: []const JsonDiagnostic,
    suppressedDiagnostics: []const JsonDiagnostic,
    outputs: []const JsonOutput,
};

const WorkQueue = struct {
    io: std.Io,
    files: []const []const u8,
    options: lint.Options,
    rule_severities: *const RuleSeverityMap,
    config: ?*const flat_config.FlatConfig,
    fix_mode: FixMode,
    use_color: bool,
    next_index: std.atomic.Value(usize) = .init(0),
    print_mutex: std.Io.Mutex = .init,
};

const WorkerResult = struct {
    stats: Stats = .{},
    err: ?anyerror = null,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (hasHelpArg(args[1..])) {
        printHelp();
        return;
    }

    var options = lint.Options{};
    var rule_severities = RuleSeverityMap.init(allocator);
    defer {
        clearRuleSeverities(allocator, &rule_severities);
        rule_severities.deinit();
    }
    const config = parseConfigArgs(args[1..]);
    var loaded_flat_config: ?flat_config.FlatConfig = null;
    defer if (loaded_flat_config) |*loaded| loaded.deinit(allocator);
    if (config.enabled) {
        if (config.path) |path| {
            loaded_flat_config = try loadConfigFile(allocator, io, path, config.root, config.cwd, true, &options, &rule_severities);
        } else if (try findDefaultConfig(allocator, io)) |path| {
            defer allocator.free(path);
            loaded_flat_config = try loadConfigFile(allocator, io, path, config.root, config.cwd, false, &options, &rule_severities);
        }
    }

    var thread_count_override: ?usize = null;
    var output_format: OutputFormat = .text;
    var fix_mode: FixMode = .none;
    var color_override: ?bool = null;
    var targets: std.ArrayList([]const u8) = .empty;
    defer targets.deinit(allocator);

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--no-config")) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "--config-root=")) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "--config-cwd=")) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "--threads=")) {
            const value = arg["--threads=".len..];
            const parsed = std.fmt.parseInt(usize, value, 10) catch {
                std.debug.print("utoo-lint: invalid --threads value: {s}\n", .{value});
                std.process.exit(2);
            };
            if (parsed == 0) {
                std.debug.print("utoo-lint: --threads must be greater than 0\n", .{});
                std.process.exit(2);
            }
            thread_count_override = parsed;
        } else if (std.mem.eql(u8, arg, "--json")) {
            output_format = .json;
        } else if (std.mem.eql(u8, arg, "--color")) {
            color_override = true;
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            color_override = false;
        } else if (std.mem.eql(u8, arg, "--fix")) {
            if (fix_mode == .dry_run) {
                std.debug.print("utoo-lint: --fix and --fix-dry-run cannot be used together\n", .{});
                std.process.exit(2);
            }
            fix_mode = .write;
        } else if (std.mem.eql(u8, arg, "--fix-dry-run")) {
            if (fix_mode == .write) {
                std.debug.print("utoo-lint: --fix and --fix-dry-run cannot be used together\n", .{});
                std.process.exit(2);
            }
            fix_mode = .dry_run;
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            output_format = parseOutputFormat(value) orelse {
                std.debug.print("utoo-lint: invalid --format value: {s}\n", .{value});
                std.process.exit(2);
            };
        } else if (std.mem.startsWith(u8, arg, "--rules=")) {
            const jest_global_aliases = options.jest_global_aliases;
            const jest_version = options.jest_version;
            options = lint.Options.allDisabled();
            options.jest_global_aliases = jest_global_aliases;
            options.jest_version = jest_version;
            clearRuleSeverities(allocator, &rule_severities);
            try parseEnabledRules(allocator, arg["--rules=".len..], &options, &rule_severities);
        } else if (std.mem.eql(u8, arg, "--accessor-pairs=off")) {
            options.accessor_pairs = false;
        } else if (std.mem.eql(u8, arg, "--accessor-pairs-get-without-set=on")) {
            options.accessor_pairs_get_without_set = .yes;
        } else if (std.mem.eql(u8, arg, "--accessor-pairs-set-without-get=off")) {
            options.accessor_pairs_set_without_get = .no;
        } else if (std.mem.eql(u8, arg, "--consistent-return=off")) {
            options.consistent_return = false;
        } else if (std.mem.eql(u8, arg, "--consistent-this=off")) {
            options.consistent_this = false;
        } else if (std.mem.eql(u8, arg, "--consistent-this=on")) {
            options.consistent_this = true;
        } else if (std.mem.startsWith(u8, arg, "--consistent-this-alias=")) {
            appendConsistentThisAlias(arg["--consistent-this-alias=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--constructor-super=off")) {
            options.constructor_super = false;
        } else if (std.mem.eql(u8, arg, "--array-callback-return=off")) {
            options.array_callback_return = false;
        } else if (std.mem.eql(u8, arg, "--array-callback-return-allow-implicit=on")) {
            options.array_callback_return_allow_implicit = .yes;
        } else if (std.mem.eql(u8, arg, "--array-callback-return-allow-implicit=off")) {
            options.array_callback_return_allow_implicit = .no;
        } else if (std.mem.eql(u8, arg, "--array-callback-return-check-for-each=on")) {
            options.array_callback_return_check_for_each = .yes;
        } else if (std.mem.eql(u8, arg, "--array-callback-return-allow-void=on")) {
            options.array_callback_return_allow_void = .yes;
        } else if (std.mem.eql(u8, arg, "--arrow-body-style=off")) {
            options.arrow_body_style = false;
        } else if (std.mem.eql(u8, arg, "--arrow-body-style=on")) {
            options.arrow_body_style = true;
        } else if (std.mem.eql(u8, arg, "--arrow-body-style=always")) {
            options.arrow_body_style = true;
            options.arrow_body_style_style = .always;
        } else if (std.mem.eql(u8, arg, "--arrow-body-style=as-needed")) {
            options.arrow_body_style = true;
            options.arrow_body_style_style = .as_needed;
        } else if (std.mem.eql(u8, arg, "--arrow-body-style=never")) {
            options.arrow_body_style = true;
            options.arrow_body_style_style = .never;
        } else if (std.mem.eql(u8, arg, "--arrow-body-style-require-return-for-object-literal=on")) {
            options.arrow_body_style = true;
            options.arrow_body_style_require_return_for_object_literal = true;
        } else if (std.mem.eql(u8, arg, "--block-scoped-var=off")) {
            options.block_scoped_var = false;
        } else if (std.mem.eql(u8, arg, "--camelcase=off")) {
            options.camelcase = false;
        } else if (std.mem.eql(u8, arg, "--camelcase=on")) {
            options.camelcase = true;
        } else if (std.mem.eql(u8, arg, "--camelcase-properties=always")) {
            options.camelcase = true;
            options.camelcase_properties = .always;
        } else if (std.mem.eql(u8, arg, "--camelcase-properties=never")) {
            options.camelcase = true;
            options.camelcase_properties = .never;
        } else if (std.mem.eql(u8, arg, "--camelcase-ignore-destructuring=on")) {
            options.camelcase = true;
            options.camelcase_ignore_destructuring = true;
        } else if (std.mem.eql(u8, arg, "--camelcase-ignore-imports=on")) {
            options.camelcase = true;
            options.camelcase_ignore_imports = true;
        } else if (std.mem.startsWith(u8, arg, "--camelcase-allow=")) {
            appendCamelcaseAllow(arg["--camelcase-allow=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--capitalized-comments=off")) {
            options.capitalized_comments = false;
        } else if (std.mem.eql(u8, arg, "--capitalized-comments=never")) {
            options.capitalized_comments_mode = .never;
        } else if (std.mem.eql(u8, arg, "--capitalized-comments-ignore-inline-comments=on")) {
            options.capitalized_comments_ignore_inline_comments = .yes;
        } else if (std.mem.eql(u8, arg, "--class-methods-use-this=on")) {
            options.class_methods_use_this = true;
        } else if (std.mem.eql(u8, arg, "--class-methods-use-this=off")) {
            options.class_methods_use_this = false;
        } else if (std.mem.eql(u8, arg, "--class-methods-use-this-enforce-for-class-fields=off")) {
            options.class_methods_use_this = true;
            options.class_methods_use_this_enforce_for_class_fields = false;
        } else if (std.mem.startsWith(u8, arg, "--class-methods-use-this-except-method=")) {
            appendClassMethodsUseThisExceptMethod(arg["--class-methods-use-this-except-method=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--class-methods-use-this-ignore-override-methods=on")) {
            options.class_methods_use_this = true;
            options.class_methods_use_this_ignore_override_methods = true;
        } else if (std.mem.startsWith(u8, arg, "--class-methods-use-this-ignore-classes-with-implements=")) {
            parseClassMethodsUseThisIgnoreClassesWithImplements(arg["--class-methods-use-this-ignore-classes-with-implements=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--complexity=off")) {
            options.complexity = false;
        } else if (std.mem.startsWith(u8, arg, "--complexity-max=")) {
            parseComplexityMax(arg["--complexity-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--complexity-variant=classic")) {
            options.complexity_variant = .classic;
        } else if (std.mem.eql(u8, arg, "--complexity-variant=modified")) {
            options.complexity_variant = .modified;
        } else if (std.mem.eql(u8, arg, "--curly=off")) {
            options.curly = false;
        } else if (std.mem.eql(u8, arg, "--dot-notation=off")) {
            options.dot_notation = false;
        } else if (std.mem.eql(u8, arg, "--default-case=off")) {
            options.default_case = false;
        } else if (std.mem.eql(u8, arg, "--default-case-last=off")) {
            options.default_case_last = false;
        } else if (std.mem.eql(u8, arg, "--default-param-last=off")) {
            options.default_param_last = false;
        } else if (std.mem.eql(u8, arg, "--eol-last=off")) {
            options.eol_last = false;
        } else if (std.mem.eql(u8, arg, "--eslint-comments-no-restricted-disable=off")) {
            options.eslint_comments_no_restricted_disable = false;
        } else if (std.mem.eql(u8, arg, "--for-direction=off")) {
            options.for_direction = false;
        } else if (std.mem.eql(u8, arg, "--func-name-matching=off")) {
            options.func_name_matching = false;
        } else if (std.mem.eql(u8, arg, "--func-name-matching=never")) {
            options.func_name_matching_style = .never;
        } else if (std.mem.eql(u8, arg, "--func-names=off")) {
            options.func_names = false;
        } else if (std.mem.eql(u8, arg, "--func-names=as-needed")) {
            options.func_names_style = .as_needed;
        } else if (std.mem.eql(u8, arg, "--func-names=never")) {
            options.func_names_style = .never;
        } else if (std.mem.eql(u8, arg, "--func-style=off")) {
            options.func_style = false;
        } else if (std.mem.eql(u8, arg, "--func-style=expression")) {
            options.func_style = true;
            options.func_style_style = .expression;
        } else if (std.mem.eql(u8, arg, "--func-style=declaration")) {
            options.func_style = true;
            options.func_style_style = .declaration;
        } else if (std.mem.eql(u8, arg, "--func-style-allow-arrow-functions=on")) {
            options.func_style = true;
            options.func_style_allow_arrow_functions = true;
        } else if (std.mem.eql(u8, arg, "--getter-return=off")) {
            options.getter_return = false;
        } else if (std.mem.eql(u8, arg, "--grouped-accessor-pairs=off")) {
            options.grouped_accessor_pairs = false;
        } else if (std.mem.eql(u8, arg, "--grouped-accessor-pairs=get-before-set")) {
            options.grouped_accessor_pairs_style = .get_before_set;
        } else if (std.mem.eql(u8, arg, "--grouped-accessor-pairs=set-before-get")) {
            options.grouped_accessor_pairs_style = .set_before_get;
        } else if (std.mem.eql(u8, arg, "--guard-for-in=off")) {
            options.guard_for_in = false;
        } else if (std.mem.eql(u8, arg, "--init-declarations=always")) {
            options.init_declarations = true;
            options.init_declarations_mode = .always;
        } else if (std.mem.eql(u8, arg, "--init-declarations=off")) {
            options.init_declarations = false;
        } else if (std.mem.eql(u8, arg, "--init-declarations=never")) {
            options.init_declarations = true;
            options.init_declarations_mode = .never;
        } else if (std.mem.eql(u8, arg, "--init-declarations-ignore-for-loop-init=on")) {
            options.init_declarations = true;
            options.init_declarations_ignore_for_loop_init = true;
        } else if (std.mem.eql(u8, arg, "--linebreak-style=off")) {
            options.linebreak_style = false;
        } else if (std.mem.eql(u8, arg, "--new-cap=off")) {
            options.new_cap = false;
        } else if (std.mem.eql(u8, arg, "--new-parens=off")) {
            options.new_parens = false;
        } else if (std.mem.eql(u8, arg, "--no-async-promise-executor=off")) {
            options.no_async_promise_executor = false;
        } else if (std.mem.eql(u8, arg, "--no-array-constructor=off")) {
            options.no_array_constructor = false;
        } else if (std.mem.eql(u8, arg, "--no-await-in-loop=off")) {
            options.no_await_in_loop = false;
        } else if (std.mem.eql(u8, arg, "--no-alert=off")) {
            options.no_alert = false;
        } else if (std.mem.eql(u8, arg, "--no-bitwise=off")) {
            options.no_bitwise = false;
        } else if (std.mem.eql(u8, arg, "--no-buffer-constructor=off")) {
            options.no_buffer_constructor = false;
        } else if (std.mem.eql(u8, arg, "--no-caller=off")) {
            options.no_caller = false;
        } else if (std.mem.eql(u8, arg, "--no-case-declarations=off")) {
            options.no_case_declarations = false;
        } else if (std.mem.eql(u8, arg, "--no-class-assign=off")) {
            options.no_class_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-confusing-arrow=off")) {
            options.no_confusing_arrow = false;
        } else if (std.mem.eql(u8, arg, "--no-confusing-arrow-allow-parens=off")) {
            options.no_confusing_arrow_allow_parens = .no;
        } else if (std.mem.eql(u8, arg, "--no-cond-assign=off")) {
            options.no_cond_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-compare-neg-zero=off")) {
            options.no_compare_neg_zero = false;
        } else if (std.mem.eql(u8, arg, "--no-constant-binary-expression=off")) {
            options.no_constant_binary_expression = false;
        } else if (std.mem.eql(u8, arg, "--no-constant-condition=off")) {
            options.no_constant_condition = false;
        } else if (std.mem.eql(u8, arg, "--no-const-assign=off")) {
            options.no_const_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-control-regex=off")) {
            options.no_control_regex = false;
        } else if (std.mem.eql(u8, arg, "--no-console=off")) {
            options.no_console = false;
        } else if (std.mem.startsWith(u8, arg, "--no-console-allow=")) {
            parseNoConsoleAllow(arg["--no-console-allow=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--no-comma-operator=off")) {
            options.no_comma_operator = false;
        } else if (std.mem.eql(u8, arg, "--no-continue=off")) {
            options.no_continue = false;
        } else if (std.mem.eql(u8, arg, "--no-constructor-return=off")) {
            options.no_constructor_return = false;
        } else if (std.mem.eql(u8, arg, "--no-debugger=off")) {
            options.no_debugger = false;
        } else if (std.mem.eql(u8, arg, "--no-dupe-else-if=off")) {
            options.no_dupe_else_if = false;
        } else if (std.mem.eql(u8, arg, "--no-duplicate-case=off")) {
            options.no_duplicate_case = false;
        } else if (std.mem.eql(u8, arg, "--no-duplicate-imports=off")) {
            options.no_duplicate_imports = false;
        } else if (std.mem.eql(u8, arg, "--no-dupe-args=off")) {
            options.no_dupe_args = false;
        } else if (std.mem.eql(u8, arg, "--no-dupe-class-members=off")) {
            options.no_dupe_class_members = false;
        } else if (std.mem.eql(u8, arg, "--no-dupe-keys=off")) {
            options.no_dupe_keys = false;
        } else if (std.mem.eql(u8, arg, "--no-delete-var=off")) {
            options.no_delete_var = false;
        } else if (std.mem.eql(u8, arg, "--no-div-regex=off")) {
            options.no_div_regex = false;
        } else if (std.mem.eql(u8, arg, "--no-empty=off")) {
            options.no_empty = false;
        } else if (std.mem.eql(u8, arg, "--no-empty-allow-empty-catch=on")) {
            options.no_empty_allow_empty_catch = .yes;
        } else if (std.mem.eql(u8, arg, "--no-empty-block-statements=off")) {
            options.no_empty_block_statements = false;
        } else if (std.mem.eql(u8, arg, "--no-empty-character-class=off")) {
            options.no_empty_character_class = false;
        } else if (std.mem.eql(u8, arg, "--no-empty-function=off")) {
            options.no_empty_function = false;
        } else if (std.mem.startsWith(u8, arg, "--no-empty-function-allow=")) {
            parseNoEmptyFunctionAllow(arg["--no-empty-function-allow=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--no-empty-pattern=off")) {
            options.no_empty_pattern = false;
        } else if (std.mem.eql(u8, arg, "--no-empty-static-block=off")) {
            options.no_empty_static_block = false;
        } else if (std.mem.eql(u8, arg, "--no-else-return=off")) {
            options.no_else_return = false;
        } else if (std.mem.eql(u8, arg, "--no-eq-null=off")) {
            options.no_eq_null = false;
        } else if (std.mem.eql(u8, arg, "--no-eval=off")) {
            options.no_eval = false;
        } else if (std.mem.eql(u8, arg, "--no-ex-assign=off")) {
            options.no_ex_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-extend-native=off")) {
            options.no_extend_native = false;
        } else if (std.mem.eql(u8, arg, "--no-extra-bind=off")) {
            options.no_extra_bind = false;
        } else if (std.mem.eql(u8, arg, "--no-extra-label=off")) {
            options.no_extra_label = false;
        } else if (std.mem.eql(u8, arg, "--no-extra-semi=off")) {
            options.no_extra_semi = false;
        } else if (std.mem.eql(u8, arg, "--no-extra-boolean-cast=off")) {
            options.no_extra_boolean_cast = false;
        } else if (std.mem.eql(u8, arg, "--no-floating-decimal=off")) {
            options.no_floating_decimal = false;
        } else if (std.mem.eql(u8, arg, "--no-fallthrough=off")) {
            options.no_fallthrough = false;
        } else if (std.mem.eql(u8, arg, "--no-fallthrough-allow-empty-case=on")) {
            options.no_fallthrough_allow_empty_case = .yes;
        } else if (std.mem.eql(u8, arg, "--no-for-in=off")) {
            options.no_for_in = false;
        } else if (std.mem.eql(u8, arg, "--no-func-assign=off")) {
            options.no_func_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-global-assign=off")) {
            options.no_global_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-global-is-finite=off")) {
            options.no_global_is_finite = false;
        } else if (std.mem.eql(u8, arg, "--no-global-is-nan=off")) {
            options.no_global_is_nan = false;
        } else if (std.mem.eql(u8, arg, "--no-implicit-coercion=off")) {
            options.no_implicit_coercion = false;
        } else if (std.mem.eql(u8, arg, "--no-implicit-coercion-boolean=off")) {
            options.no_implicit_coercion_boolean = .no;
        } else if (std.mem.eql(u8, arg, "--no-implicit-coercion-number=off")) {
            options.no_implicit_coercion_number = .no;
        } else if (std.mem.eql(u8, arg, "--no-implicit-coercion-string=off")) {
            options.no_implicit_coercion_string = .no;
        } else if (std.mem.eql(u8, arg, "--no-implicit-globals=off")) {
            options.no_implicit_globals = false;
        } else if (std.mem.eql(u8, arg, "--no-implicit-globals=on")) {
            options.no_implicit_globals = true;
        } else if (std.mem.eql(u8, arg, "--no-implicit-globals-lexical-bindings=on")) {
            options.no_implicit_globals_lexical_bindings = true;
        } else if (std.mem.eql(u8, arg, "--no-implied-eval=off")) {
            options.no_implied_eval = false;
        } else if (std.mem.eql(u8, arg, "--no-import-assign=off")) {
            options.no_import_assign = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-disallow-typos=off")) {
            options.alipay_ant_disallow_typos = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-exhaustive-deps=off")) {
            options.alipay_ant_exhaustive_deps = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-jsx-handler-names=off")) {
            options.alipay_ant_jsx_handler_names = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-no-deprecated-dependence=off")) {
            options.alipay_ant_no_deprecated_dependence = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-no-deprecated-variable=off")) {
            options.alipay_ant_no_deprecated_variable = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-no-import-files-from-pages-in-common=off")) {
            options.alipay_ant_no_import_files_from_pages_in_common = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-no-negative-conditionals=off")) {
            options.alipay_ant_no_negative_conditionals = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-no-import-src=off")) {
            options.alipay_ant_no_import_src = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-no-phantom-dependencies=off")) {
            options.alipay_ant_no_phantom_dependencies = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-no-too-large-file=off")) {
            options.alipay_ant_no_too_large_file = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-prefer-elseif-end-with-else=off")) {
            options.alipay_ant_prefer_elseif_end_with_else = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-prefer-catch-unsafe-func-call=off")) {
            options.alipay_ant_prefer_catch_unsafe_func_call = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-prefer-click-with-debounce=off")) {
            options.alipay_ant_prefer_click_with_debounce = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-prefer-import-as-required=off")) {
            options.alipay_ant_prefer_import_as_required = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-no-spread-params=off")) {
            options.alipay_ant_no_spread_params = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-prefer-managed-resource=off")) {
            options.alipay_ant_prefer_managed_resource = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-prefer-safe-image-renderer=off")) {
            options.alipay_ant_prefer_safe_image_renderer = false;
        } else if (std.mem.eql(u8, arg, "--alipay-ant-prefer-import-from-stdlib=off")) {
            options.alipay_ant_prefer_import_from_stdlib = false;
        } else if (std.mem.eql(u8, arg, "--alipay-spmlint-use-labeled-spm=off")) {
            options.alipay_spmlint_use_labeled_spm = false;
        } else if (std.mem.eql(u8, arg, "--alipay-spmlint-valid-manual-click=off")) {
            options.alipay_spmlint_valid_manual_click = false;
        } else if (std.mem.eql(u8, arg, "--alipay-spmlint-valid-manual-expo=off")) {
            options.alipay_spmlint_valid_manual_expo = false;
        } else if (std.mem.eql(u8, arg, "--alipay-spmlint-valid-manual-param=off")) {
            options.alipay_spmlint_valid_manual_param = false;
        } else if (std.mem.eql(u8, arg, "--alipay-spmlint-valid-manual-pv=off")) {
            options.alipay_spmlint_valid_manual_pv = false;
        } else if (std.mem.eql(u8, arg, "--import-default=off")) {
            options.import_default = false;
        } else if (std.mem.eql(u8, arg, "--import-export=off")) {
            options.import_export = false;
        } else if (std.mem.eql(u8, arg, "--import-first=off")) {
            options.import_first = false;
        } else if (std.mem.eql(u8, arg, "--import-named=off")) {
            options.import_named = false;
        } else if (std.mem.eql(u8, arg, "--import-namespace=off")) {
            options.import_namespace = false;
        } else if (std.mem.eql(u8, arg, "--import-newline-after-import=off")) {
            options.import_newline_after_import = false;
        } else if (std.mem.eql(u8, arg, "--import-no-amd=off")) {
            options.import_no_amd = false;
        } else if (std.mem.eql(u8, arg, "--import-no-cycle=off")) {
            options.import_no_cycle = false;
        } else if (std.mem.eql(u8, arg, "--import-no-duplicates=off")) {
            options.import_no_duplicates = false;
        } else if (std.mem.eql(u8, arg, "--import-no-named-as-default=off")) {
            options.import_no_named_as_default = false;
        } else if (std.mem.eql(u8, arg, "--import-no-named-as-default-member=off")) {
            options.import_no_named_as_default_member = false;
        } else if (std.mem.eql(u8, arg, "--import-no-unresolved=off")) {
            options.import_no_unresolved = false;
        } else if (std.mem.eql(u8, arg, "--import-no-self-import=off")) {
            options.import_no_self_import = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-alt-text=off")) {
            options.jsx_a11y_alt_text = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-anchor-has-content=off")) {
            options.jsx_a11y_anchor_has_content = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-aria-props=off")) {
            options.jsx_a11y_aria_props = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-aria-proptypes=off")) {
            options.jsx_a11y_aria_proptypes = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-aria-role=off")) {
            options.jsx_a11y_aria_role = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-aria-unsupported-elements=off")) {
            options.jsx_a11y_aria_unsupported_elements = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-iframe-has-title=off")) {
            options.jsx_a11y_iframe_has_title = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-img-redundant-alt=off")) {
            options.jsx_a11y_img_redundant_alt = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-no-access-key=off")) {
            options.jsx_a11y_no_access_key = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-no-distracting-elements=off")) {
            options.jsx_a11y_no_distracting_elements = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-role-has-required-aria-props=off")) {
            options.jsx_a11y_role_has_required_aria_props = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-role-supports-aria-props=off")) {
            options.jsx_a11y_role_supports_aria_props = false;
        } else if (std.mem.eql(u8, arg, "--jsx-a11y-scope=off")) {
            options.jsx_a11y_scope = false;
        } else if (std.mem.eql(u8, arg, "--no-invalid-regexp=off")) {
            options.no_invalid_regexp = false;
        } else if (std.mem.eql(u8, arg, "--no-invalid-this=on")) {
            options.no_invalid_this = true;
        } else if (std.mem.eql(u8, arg, "--no-invalid-this=off")) {
            options.no_invalid_this = false;
        } else if (std.mem.eql(u8, arg, "--no-invalid-this-cap-is-constructor=off")) {
            options.no_invalid_this = true;
            options.no_invalid_this_cap_is_constructor = .no;
        } else if (std.mem.eql(u8, arg, "--no-irregular-whitespace=off")) {
            options.no_irregular_whitespace = false;
        } else if (std.mem.eql(u8, arg, "--no-inline-comments=off")) {
            options.no_inline_comments = false;
        } else if (std.mem.eql(u8, arg, "--no-inner-declarations=off")) {
            options.no_inner_declarations = false;
        } else if (std.mem.eql(u8, arg, "--no-iterator=off")) {
            options.no_iterator = false;
        } else if (std.mem.eql(u8, arg, "--no-label-var=off")) {
            options.no_label_var = false;
        } else if (std.mem.eql(u8, arg, "--no-labels=off")) {
            options.no_labels = false;
        } else if (std.mem.eql(u8, arg, "--no-lone-blocks=off")) {
            options.no_lone_blocks = false;
        } else if (std.mem.eql(u8, arg, "--no-lonely-if=off")) {
            options.no_lonely_if = false;
        } else if (std.mem.eql(u8, arg, "--no-loop-func=off")) {
            options.no_loop_func = false;
        } else if (std.mem.eql(u8, arg, "--no-loss-of-precision=off")) {
            options.no_loss_of_precision = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers=on")) {
            options.no_magic_numbers = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers=off")) {
            options.no_magic_numbers = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-detect-objects=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_detect_objects = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-detect-objects=off")) {
            options.no_magic_numbers_detect_objects = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-enforce-const=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_enforce_const = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-enforce-const=off")) {
            options.no_magic_numbers_enforce_const = false;
        } else if (std.mem.startsWith(u8, arg, "--no-magic-numbers-ignore=")) {
            parseNoMagicNumbersIgnore(arg["--no-magic-numbers-ignore=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-array-indexes=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_ignore_array_indexes = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-array-indexes=off")) {
            options.no_magic_numbers_ignore_array_indexes = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-default-values=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_ignore_default_values = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-default-values=off")) {
            options.no_magic_numbers_ignore_default_values = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-class-field-initial-values=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_ignore_class_field_initial_values = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-class-field-initial-values=off")) {
            options.no_magic_numbers_ignore_class_field_initial_values = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-enums=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_ignore_enums = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-enums=off")) {
            options.no_magic_numbers_ignore_enums = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-numeric-literal-types=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_ignore_numeric_literal_types = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-numeric-literal-types=off")) {
            options.no_magic_numbers_ignore_numeric_literal_types = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-readonly-class-properties=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_ignore_readonly_class_properties = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-readonly-class-properties=off")) {
            options.no_magic_numbers_ignore_readonly_class_properties = false;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-type-indexes=on")) {
            options.no_magic_numbers = true;
            options.no_magic_numbers_ignore_type_indexes = true;
        } else if (std.mem.eql(u8, arg, "--no-magic-numbers-ignore-type-indexes=off")) {
            options.no_magic_numbers_ignore_type_indexes = false;
        } else if (std.mem.eql(u8, arg, "--no-multi-str=off")) {
            options.no_multi_str = false;
        } else if (std.mem.eql(u8, arg, "--no-multi-assign=off")) {
            options.no_multi_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-multi-spaces=off")) {
            options.no_multi_spaces = false;
        } else if (std.mem.eql(u8, arg, "--no-multi-spaces-ignore-eol-comments=on")) {
            options.no_multi_spaces_ignore_eol_comments = .yes;
        } else if (std.mem.eql(u8, arg, "--no-mixed-spaces-and-tabs=off")) {
            options.no_mixed_spaces_and_tabs = false;
        } else if (std.mem.eql(u8, arg, "--no-misleading-character-class=off")) {
            options.no_misleading_character_class = false;
        } else if (std.mem.eql(u8, arg, "--no-multiple-empty-lines=off")) {
            options.no_multiple_empty_lines = false;
        } else if (std.mem.startsWith(u8, arg, "--no-multiple-empty-lines-max=")) {
            parseNoMultipleEmptyLinesMax(arg["--no-multiple-empty-lines-max=".len..], &options);
        } else if (std.mem.startsWith(u8, arg, "--no-multiple-empty-lines-max-bof=")) {
            parseNoMultipleEmptyLinesMaxBof(arg["--no-multiple-empty-lines-max-bof=".len..], &options);
        } else if (std.mem.startsWith(u8, arg, "--no-multiple-empty-lines-max-eof=")) {
            parseNoMultipleEmptyLinesMaxEof(arg["--no-multiple-empty-lines-max-eof=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--no-nonoctal-decimal-escape=off")) {
            options.no_nonoctal_decimal_escape = false;
        } else if (std.mem.eql(u8, arg, "--no-new=off")) {
            options.no_new = false;
        } else if (std.mem.eql(u8, arg, "--no-nested-ternary=off")) {
            options.no_nested_ternary = false;
        } else if (std.mem.eql(u8, arg, "--no-negated-condition=off")) {
            options.no_negated_condition = false;
        } else if (std.mem.eql(u8, arg, "--no-new-native-nonconstructor=off")) {
            options.no_new_native_nonconstructor = false;
        } else if (std.mem.eql(u8, arg, "--no-new-func=off")) {
            options.no_new_func = false;
        } else if (std.mem.eql(u8, arg, "--no-new-require=off")) {
            options.no_new_require = false;
        } else if (std.mem.eql(u8, arg, "--no-obj-calls=off")) {
            options.no_obj_calls = false;
        } else if (std.mem.eql(u8, arg, "--no-new-object=off")) {
            options.no_new_object = false;
        } else if (std.mem.eql(u8, arg, "--no-new-symbol=off")) {
            options.no_new_symbol = false;
        } else if (std.mem.eql(u8, arg, "--no-new-wrappers=off")) {
            options.no_new_wrappers = false;
        } else if (std.mem.eql(u8, arg, "--no-octal=off")) {
            options.no_octal = false;
        } else if (std.mem.eql(u8, arg, "--no-octal-escape=off")) {
            options.no_octal_escape = false;
        } else if (std.mem.eql(u8, arg, "--no-object-constructor=off")) {
            options.no_object_constructor = false;
        } else if (std.mem.eql(u8, arg, "--no-param-reassign=off")) {
            options.no_param_reassign = false;
        } else if (std.mem.eql(u8, arg, "--no-param-reassign-props=on")) {
            options.no_param_reassign_props = .yes;
        } else if (std.mem.startsWith(u8, arg, "--no-param-reassign-ignore-property-modifications-for=")) {
            parseNoParamReassignIgnorePropertyModificationsFor(
                arg["--no-param-reassign-ignore-property-modifications-for=".len..],
                &options,
            );
        } else if (std.mem.eql(u8, arg, "--no-path-concat=off")) {
            options.no_path_concat = false;
        } else if (std.mem.eql(u8, arg, "--no-plusplus=off")) {
            options.no_plusplus = false;
        } else if (std.mem.eql(u8, arg, "--no-plusplus-allow-for-loop-afterthoughts=on")) {
            options.no_plusplus_allow_for_loop_afterthoughts = .yes;
        } else if (std.mem.eql(u8, arg, "--no-promise-executor-return=off")) {
            options.no_promise_executor_return = false;
        } else if (std.mem.eql(u8, arg, "--no-proto=off")) {
            options.no_proto = false;
        } else if (std.mem.eql(u8, arg, "--no-process-env=off")) {
            options.no_process_env = false;
        } else if (std.mem.eql(u8, arg, "--no-process-exit=off")) {
            options.no_process_exit = false;
        } else if (std.mem.eql(u8, arg, "--no-prototype-builtins=off")) {
            options.no_prototype_builtins = false;
        } else if (std.mem.eql(u8, arg, "--no-redeclare=off")) {
            options.no_redeclare = false;
        } else if (std.mem.eql(u8, arg, "--no-redeclare-builtin-globals=on")) {
            options.no_redeclare_builtin_globals = .yes;
        } else if (std.mem.eql(u8, arg, "--no-restricted-exports=off")) {
            options.no_restricted_exports = false;
        } else if (std.mem.eql(u8, arg, "--no-restricted-exports=on")) {
            options.no_restricted_exports = true;
        } else if (std.mem.startsWith(u8, arg, "--no-restricted-exports-name=")) {
            appendNoRestrictedExportName(arg["--no-restricted-exports-name=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--no-restricted-exports-default-direct=on")) {
            options.no_restricted_exports = true;
            options.no_restricted_exports_default.direct = true;
        } else if (std.mem.eql(u8, arg, "--no-restricted-exports-default-named=on")) {
            options.no_restricted_exports = true;
            options.no_restricted_exports_default.named = true;
        } else if (std.mem.eql(u8, arg, "--no-restricted-exports-default-from=on")) {
            options.no_restricted_exports = true;
            options.no_restricted_exports_default.default_from = true;
        } else if (std.mem.eql(u8, arg, "--no-restricted-exports-named-from=on")) {
            options.no_restricted_exports = true;
            options.no_restricted_exports_default.named_from = true;
        } else if (std.mem.eql(u8, arg, "--no-restricted-exports-namespace-from=on")) {
            options.no_restricted_exports = true;
            options.no_restricted_exports_default.namespace_from = true;
        } else if (std.mem.eql(u8, arg, "--no-restricted-globals=off")) {
            options.no_restricted_globals = false;
        } else if (std.mem.eql(u8, arg, "--no-restricted-globals=on")) {
            options.no_restricted_globals = true;
        } else if (std.mem.startsWith(u8, arg, "--no-restricted-globals-name=")) {
            appendNoRestrictedGlobalName(arg["--no-restricted-globals-name=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--no-restricted-imports=off")) {
            options.no_restricted_imports = false;
        } else if (std.mem.eql(u8, arg, "--no-restricted-imports=on")) {
            options.no_restricted_imports = true;
        } else if (std.mem.startsWith(u8, arg, "--no-restricted-imports-name=")) {
            appendNoRestrictedImportName(arg["--no-restricted-imports-name=".len..], &options, .path);
        } else if (std.mem.startsWith(u8, arg, "--no-restricted-imports-pattern=")) {
            appendNoRestrictedImportName(arg["--no-restricted-imports-pattern=".len..], &options, .pattern);
        } else if (std.mem.eql(u8, arg, "--no-restricted-modules=off")) {
            options.no_restricted_modules = false;
        } else if (std.mem.eql(u8, arg, "--no-restricted-modules=on")) {
            options.no_restricted_modules = true;
        } else if (std.mem.startsWith(u8, arg, "--no-restricted-modules-name=")) {
            appendNoRestrictedModuleName(arg["--no-restricted-modules-name=".len..], &options, .path);
        } else if (std.mem.startsWith(u8, arg, "--no-restricted-modules-pattern=")) {
            appendNoRestrictedModuleName(arg["--no-restricted-modules-pattern=".len..], &options, .pattern);
        } else if (std.mem.eql(u8, arg, "--no-restricted-properties=off")) {
            options.no_restricted_properties = false;
        } else if (std.mem.eql(u8, arg, "--no-restricted-syntax=off")) {
            options.no_restricted_syntax = false;
        } else if (std.mem.eql(u8, arg, "--no-restricted-syntax=on")) {
            options.no_restricted_syntax = true;
        } else if (std.mem.startsWith(u8, arg, "--no-restricted-syntax-selector=")) {
            appendNoRestrictedSyntaxSelector(arg["--no-restricted-syntax-selector=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--no-regex-spaces=off")) {
            options.no_regex_spaces = false;
        } else if (std.mem.eql(u8, arg, "--no-return-await=off")) {
            options.no_return_await = false;
        } else if (std.mem.eql(u8, arg, "--no-return-assign=off")) {
            options.no_return_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-return-assign=always")) {
            options.no_return_assign_style = .always;
        } else if (std.mem.eql(u8, arg, "--no-useless-return=off")) {
            options.no_useless_return = false;
        } else if (std.mem.eql(u8, arg, "--no-script-url=off")) {
            options.no_script_url = false;
        } else if (std.mem.eql(u8, arg, "--no-self-assign=off")) {
            options.no_self_assign = false;
        } else if (std.mem.eql(u8, arg, "--no-self-compare=off")) {
            options.no_self_compare = false;
        } else if (std.mem.eql(u8, arg, "--no-setter-return=off")) {
            options.no_setter_return = false;
        } else if (std.mem.eql(u8, arg, "--no-shadow=off")) {
            options.no_shadow = false;
        } else if (std.mem.eql(u8, arg, "--no-shadow-restricted-names=off")) {
            options.no_shadow_restricted_names = false;
        } else if (std.mem.eql(u8, arg, "--no-sequences=off")) {
            options.no_sequences = false;
        } else if (std.mem.eql(u8, arg, "--no-sequences-allow-in-parentheses=off")) {
            options.no_sequences_allow_in_parentheses = .no;
        } else if (std.mem.eql(u8, arg, "--no-sparse-arrays=off")) {
            options.no_sparse_arrays = false;
        } else if (std.mem.eql(u8, arg, "--no-ternary=off")) {
            options.no_ternary = false;
        } else if (std.mem.eql(u8, arg, "--no-template-curly-in-string=off")) {
            options.no_template_curly_in_string = false;
        } else if (std.mem.eql(u8, arg, "--no-throw-literal=off")) {
            options.no_throw_literal = false;
        } else if (std.mem.eql(u8, arg, "--no-this-before-super=off")) {
            options.no_this_before_super = false;
        } else if (std.mem.eql(u8, arg, "--no-tabs=off")) {
            options.no_tabs = false;
        } else if (std.mem.eql(u8, arg, "--no-trailing-spaces=off")) {
            options.no_trailing_spaces = false;
        } else if (std.mem.eql(u8, arg, "--no-unreachable=off")) {
            options.no_unreachable = false;
        } else if (std.mem.eql(u8, arg, "--no-unreachable-loop=off")) {
            options.no_unreachable_loop = false;
        } else if (std.mem.eql(u8, arg, "--no-undef-init=off")) {
            options.no_undef_init = false;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle=off")) {
            options.no_underscore_dangle = false;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle-allow-after-this=on")) {
            options.no_underscore_dangle_allow_after_this = true;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle-allow-after-super=on")) {
            options.no_underscore_dangle_allow_after_super = true;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle-allow-after-this-constructor=on")) {
            options.no_underscore_dangle_allow_after_this_constructor = true;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle-allow-function-params=off")) {
            options.no_underscore_dangle_allow_function_params = .no;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle-allow-in-array-destructuring=off")) {
            options.no_underscore_dangle_allow_in_array_destructuring = .no;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle-allow-in-object-destructuring=off")) {
            options.no_underscore_dangle_allow_in_object_destructuring = .no;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle-enforce-in-method-names=on")) {
            options.no_underscore_dangle_enforce_in_method_names = true;
        } else if (std.mem.eql(u8, arg, "--no-underscore-dangle-enforce-in-class-fields=on")) {
            options.no_underscore_dangle_enforce_in_class_fields = true;
        } else if (std.mem.eql(u8, arg, "--no-undefined=off")) {
            options.no_undefined = false;
        } else if (std.mem.eql(u8, arg, "--unicode-bom=off")) {
            options.unicode_bom = false;
        } else if (std.mem.eql(u8, arg, "--no-unneeded-ternary=off")) {
            options.no_unneeded_ternary = false;
        } else if (std.mem.eql(u8, arg, "--no-unexpected-multiline=off")) {
            options.no_unexpected_multiline = false;
        } else if (std.mem.eql(u8, arg, "--no-unmodified-loop-condition=on")) {
            options.no_unmodified_loop_condition = true;
        } else if (std.mem.eql(u8, arg, "--no-unmodified-loop-condition=off")) {
            options.no_unmodified_loop_condition = false;
        } else if (std.mem.eql(u8, arg, "--no-unused-labels=off")) {
            options.no_unused_labels = false;
        } else if (std.mem.eql(u8, arg, "--no-unsafe-finally=off")) {
            options.no_unsafe_finally = false;
        } else if (std.mem.eql(u8, arg, "--no-unsafe-negation=off")) {
            options.no_unsafe_negation = false;
        } else if (std.mem.eql(u8, arg, "--no-unsafe-optional-chaining=off")) {
            options.no_unsafe_optional_chaining = false;
        } else if (std.mem.eql(u8, arg, "--no-unsafe-optional-chaining-disallow-arithmetic-operators=on")) {
            options.no_unsafe_optional_chaining_disallow_arithmetic_operators = true;
        } else if (std.mem.eql(u8, arg, "--no-useless-computed-key=off")) {
            options.no_useless_computed_key = false;
        } else if (std.mem.eql(u8, arg, "--no-useless-computed-key-enforce-for-class-members=off")) {
            options.no_useless_computed_key_enforce_for_class_members = .no;
        } else if (std.mem.eql(u8, arg, "--no-useless-backreference=off")) {
            options.no_useless_backreference = false;
        } else if (std.mem.eql(u8, arg, "--no-useless-call=off")) {
            options.no_useless_call = false;
        } else if (std.mem.eql(u8, arg, "--no-useless-concat=off")) {
            options.no_useless_concat = false;
        } else if (std.mem.eql(u8, arg, "--no-useless-constructor=off")) {
            options.no_useless_constructor = false;
        } else if (std.mem.eql(u8, arg, "--no-useless-assignment=off")) {
            options.no_useless_assignment = false;
        } else if (std.mem.eql(u8, arg, "--no-useless-catch=off")) {
            options.no_useless_catch = false;
        } else if (std.mem.eql(u8, arg, "--no-useless-escape=off")) {
            options.no_useless_escape = false;
        } else if (std.mem.eql(u8, arg, "--no-useless-rename=off")) {
            options.no_useless_rename = false;
        } else if (std.mem.eql(u8, arg, "--no-unused-private-class-members=off")) {
            options.no_unused_private_class_members = false;
        } else if (std.mem.eql(u8, arg, "--no-unused-expressions=off")) {
            options.no_unused_expressions = false;
        } else if (std.mem.eql(u8, arg, "--no-unused-expressions-allow-short-circuit=on")) {
            options.no_unused_expressions_allow_short_circuit = .yes;
        } else if (std.mem.eql(u8, arg, "--no-unused-expressions-allow-ternary=on")) {
            options.no_unused_expressions_allow_ternary = .yes;
        } else if (std.mem.eql(u8, arg, "--no-unused-expressions-allow-tagged-templates=on")) {
            options.no_unused_expressions_allow_tagged_templates = .yes;
        } else if (std.mem.eql(u8, arg, "--no-warning-comments=off")) {
            options.no_warning_comments = false;
        } else if (std.mem.eql(u8, arg, "--no-warning-comments-location=anywhere")) {
            options.no_warning_comments_location = .anywhere;
        } else if (std.mem.eql(u8, arg, "--no-warning-comments-decoration=asterisk")) {
            options.no_warning_comments_decoration = .asterisk;
        } else if (std.mem.eql(u8, arg, "--no-warning-comments-decoration=slash")) {
            options.no_warning_comments_decoration = .slash;
        } else if (std.mem.eql(u8, arg, "--no-warning-comments-decoration=slash-asterisk")) {
            options.no_warning_comments_decoration = .slash_asterisk;
        } else if (std.mem.startsWith(u8, arg, "--no-warning-comments-terms=")) {
            parseNoWarningCommentsTerms(arg["--no-warning-comments-terms=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--no-void=off")) {
            options.no_void = false;
        } else if (std.mem.eql(u8, arg, "--no-void-allow-as-statement=on")) {
            options.no_void_allow_as_statement = .yes;
        } else if (std.mem.eql(u8, arg, "--no-with=off")) {
            options.no_with = false;
        } else if (std.mem.eql(u8, arg, "--no-var=off")) {
            options.no_var = false;
        } else if (std.mem.eql(u8, arg, "--id-length=off")) {
            options.id_length = false;
        } else if (std.mem.eql(u8, arg, "--id-length=on")) {
            options.id_length = true;
        } else if (std.mem.startsWith(u8, arg, "--id-length-min=")) {
            parseIdLengthMin(arg["--id-length-min=".len..], &options);
        } else if (std.mem.startsWith(u8, arg, "--id-length-max=")) {
            parseIdLengthMax(arg["--id-length-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--id-length-properties=always")) {
            options.id_length = true;
            options.id_length_properties = .always;
        } else if (std.mem.eql(u8, arg, "--id-length-properties=never")) {
            options.id_length = true;
            options.id_length_properties = .never;
        } else if (std.mem.startsWith(u8, arg, "--id-length-exception=")) {
            appendIdLengthException(arg["--id-length-exception=".len..], &options);
        } else if (std.mem.startsWith(u8, arg, "--id-length-exception-pattern=")) {
            appendIdLengthExceptionPattern(arg["--id-length-exception-pattern=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--id-match=off")) {
            options.id_match = false;
        } else if (std.mem.eql(u8, arg, "--id-match=on")) {
            options.id_match = true;
        } else if (std.mem.startsWith(u8, arg, "--id-match-pattern=")) {
            setIdMatchPattern(arg["--id-match-pattern=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--id-match-properties=on")) {
            options.id_match = true;
            options.id_match_properties = true;
        } else if (std.mem.eql(u8, arg, "--id-match-class-fields=on")) {
            options.id_match = true;
            options.id_match_class_fields = true;
        } else if (std.mem.eql(u8, arg, "--id-match-only-declarations=on")) {
            options.id_match = true;
            options.id_match_only_declarations = true;
        } else if (std.mem.eql(u8, arg, "--id-match-ignore-destructuring=on")) {
            options.id_match = true;
            options.id_match_ignore_destructuring = true;
        } else if (std.mem.eql(u8, arg, "--id-denylist=off")) {
            options.id_denylist = false;
        } else if (std.mem.startsWith(u8, arg, "--id-denylist-name=")) {
            appendIdDenylistName(arg["--id-denylist-name=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--one-var=off")) {
            options.one_var = false;
        } else if (std.mem.eql(u8, arg, "--object-shorthand=off")) {
            options.object_shorthand = false;
        } else if (std.mem.eql(u8, arg, "--logical-assignment-operators=off")) {
            options.logical_assignment_operators = false;
        } else if (std.mem.eql(u8, arg, "--logical-assignment-operators=never")) {
            options.logical_assignment_operators_style = .never;
        } else if (std.mem.eql(u8, arg, "--logical-assignment-operators-enforce-for-if-statements=on")) {
            options.logical_assignment_operators_enforce_for_if_statements = .yes;
        } else if (std.mem.eql(u8, arg, "--max-classes-per-file=off")) {
            options.max_classes_per_file = false;
        } else if (std.mem.startsWith(u8, arg, "--max-classes-per-file-max=")) {
            parseMaxClassesPerFileMax(arg["--max-classes-per-file-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--max-classes-per-file-ignore-expressions=on")) {
            options.max_classes_per_file_ignore_expressions = true;
        } else if (std.mem.eql(u8, arg, "--max-depth=off")) {
            options.max_depth = false;
        } else if (std.mem.startsWith(u8, arg, "--max-depth-max=")) {
            parseMaxDepthMax(arg["--max-depth-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--max-lines=off")) {
            options.max_lines = false;
        } else if (std.mem.eql(u8, arg, "--max-lines=on")) {
            options.max_lines = true;
        } else if (std.mem.startsWith(u8, arg, "--max-lines-max=")) {
            parseMaxLinesMax(arg["--max-lines-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--max-lines-skip-blank-lines=on")) {
            options.max_lines = true;
            options.max_lines_skip_blank_lines = true;
        } else if (std.mem.eql(u8, arg, "--max-lines-skip-comments=on")) {
            options.max_lines = true;
            options.max_lines_skip_comments = true;
        } else if (std.mem.eql(u8, arg, "--max-lines-per-function=off")) {
            options.max_lines_per_function = false;
        } else if (std.mem.eql(u8, arg, "--max-lines-per-function=on")) {
            options.max_lines_per_function = true;
        } else if (std.mem.startsWith(u8, arg, "--max-lines-per-function-max=")) {
            parseMaxLinesPerFunctionMax(arg["--max-lines-per-function-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--max-lines-per-function-skip-blank-lines=on")) {
            options.max_lines_per_function = true;
            options.max_lines_per_function_skip_blank_lines = true;
        } else if (std.mem.eql(u8, arg, "--max-lines-per-function-skip-comments=on")) {
            options.max_lines_per_function = true;
            options.max_lines_per_function_skip_comments = true;
        } else if (std.mem.eql(u8, arg, "--max-lines-per-function-iifes=on")) {
            options.max_lines_per_function = true;
            options.max_lines_per_function_iifes = true;
        } else if (std.mem.eql(u8, arg, "--max-nested-callbacks=off")) {
            options.max_nested_callbacks = false;
        } else if (std.mem.startsWith(u8, arg, "--max-nested-callbacks-max=")) {
            parseMaxNestedCallbacksMax(arg["--max-nested-callbacks-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--max-params=off")) {
            options.max_params = false;
        } else if (std.mem.startsWith(u8, arg, "--max-params-max=")) {
            parseMaxParamsMax(arg["--max-params-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--max-statements=off")) {
            options.max_statements = false;
        } else if (std.mem.startsWith(u8, arg, "--max-statements-max=")) {
            parseMaxStatementsMax(arg["--max-statements-max=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--max-statements-ignore-top-level-functions=on")) {
            options.max_statements_ignore_top_level_functions = true;
        } else if (std.mem.eql(u8, arg, "--operator-assignment=off")) {
            options.operator_assignment = false;
        } else if (std.mem.eql(u8, arg, "--eqeqeq=off")) {
            options.eqeqeq = false;
        } else if (std.mem.eql(u8, arg, "--use-isnan=off")) {
            options.use_isnan = false;
        } else if (std.mem.eql(u8, arg, "--no-unused-vars=off")) {
            options.no_unused_vars = false;
        } else if (std.mem.eql(u8, arg, "--no-unassigned-vars=off")) {
            options.no_unassigned_vars = false;
        } else if (std.mem.eql(u8, arg, "--no-use-before-define=off")) {
            options.no_use_before_define = false;
        } else if (std.mem.eql(u8, arg, "--no-undef=off")) {
            options.no_undef = false;
        } else if (std.mem.eql(u8, arg, "--prefer-arrow-callback=off")) {
            options.prefer_arrow_callback = false;
        } else if (std.mem.eql(u8, arg, "--prefer-arrow-callback=on")) {
            options.prefer_arrow_callback = true;
        } else if (std.mem.eql(u8, arg, "--prefer-arrow-callback-allow-named-functions=on")) {
            options.prefer_arrow_callback_allow_named_functions = true;
        } else if (std.mem.eql(u8, arg, "--prefer-arrow-callback-allow-unbound-this=off")) {
            options.prefer_arrow_callback_allow_unbound_this = false;
        } else if (std.mem.eql(u8, arg, "--prefer-const=off")) {
            options.prefer_const = false;
        } else if (std.mem.eql(u8, arg, "--prefer-const-destructuring=all")) {
            options.prefer_const_destructuring = .all;
        } else if (std.mem.eql(u8, arg, "--prefer-exponentiation-operator=off")) {
            options.prefer_exponentiation_operator = false;
        } else if (std.mem.eql(u8, arg, "--prefer-named-capture-group=on")) {
            options.prefer_named_capture_group = true;
        } else if (std.mem.eql(u8, arg, "--prefer-named-capture-group=off")) {
            options.prefer_named_capture_group = false;
        } else if (std.mem.eql(u8, arg, "--prefer-numeric-literals=off")) {
            options.prefer_numeric_literals = false;
        } else if (std.mem.eql(u8, arg, "--prefer-promise-reject-errors=off")) {
            options.prefer_promise_reject_errors = false;
        } else if (std.mem.eql(u8, arg, "--preserve-caught-error=off")) {
            options.preserve_caught_error = false;
        } else if (std.mem.eql(u8, arg, "--preserve-caught-error-require-catch-parameter=on")) {
            options.preserve_caught_error = true;
            options.preserve_caught_error_require_catch_parameter = true;
        } else if (std.mem.eql(u8, arg, "--prefer-destructuring=off")) {
            options.prefer_destructuring = false;
        } else if (std.mem.eql(u8, arg, "--prefer-regex-literals=off")) {
            options.prefer_regex_literals = false;
        } else if (std.mem.eql(u8, arg, "--prefer-object-has-own=off")) {
            options.prefer_object_has_own = false;
        } else if (std.mem.eql(u8, arg, "--prefer-object-spread=off")) {
            options.prefer_object_spread = false;
        } else if (std.mem.eql(u8, arg, "--prefer-rest-params=off")) {
            options.prefer_rest_params = false;
        } else if (std.mem.eql(u8, arg, "--prefer-spread=off")) {
            options.prefer_spread = false;
        } else if (std.mem.eql(u8, arg, "--prefer-template=off")) {
            options.prefer_template = false;
        } else if (std.mem.eql(u8, arg, "--react-default-props-match-prop-types=off")) {
            options.react_default_props_match_prop_types = false;
        } else if (std.mem.eql(u8, arg, "--react-display-name=off")) {
            options.react_display_name = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-boolean-value=off")) {
            options.react_jsx_boolean_value = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-filename-extension=off")) {
            options.react_jsx_filename_extension = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-no-duplicate-props=off")) {
            options.react_jsx_no_duplicate_props = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-no-comment-textnodes=off")) {
            options.react_jsx_no_comment_textnodes = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-no-bind=off")) {
            options.react_jsx_no_bind = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-key=off")) {
            options.react_jsx_key = false;
        } else if (std.mem.eql(u8, arg, "--react-button-has-type=off")) {
            options.react_button_has_type = false;
        } else if (std.mem.eql(u8, arg, "--react-require-render-return=off")) {
            options.react_require_render_return = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-no-target-blank=off")) {
            options.react_jsx_no_target_blank = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-no-undef=off")) {
            options.react_jsx_no_undef = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-pascal-case=off")) {
            options.react_jsx_pascal_case = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-uses-react=off")) {
            options.react_jsx_uses_react = false;
        } else if (std.mem.eql(u8, arg, "--react-jsx-uses-vars=off")) {
            options.react_jsx_uses_vars = false;
        } else if (std.mem.eql(u8, arg, "--react-no-danger=off")) {
            options.react_no_danger = false;
        } else if (std.mem.eql(u8, arg, "--react-no-danger-with-children=off")) {
            options.react_no_danger_with_children = false;
        } else if (std.mem.eql(u8, arg, "--react-no-access-state-in-setstate=off")) {
            options.react_no_access_state_in_setstate = false;
        } else if (std.mem.eql(u8, arg, "--react-no-direct-mutation-state=off")) {
            options.react_no_direct_mutation_state = false;
        } else if (std.mem.eql(u8, arg, "--react-no-deprecated=off")) {
            options.react_no_deprecated = false;
        } else if (std.mem.eql(u8, arg, "--react-forbid-prop-types=off")) {
            options.react_forbid_prop_types = false;
        } else if (std.mem.eql(u8, arg, "--react-no-array-index-key=off")) {
            options.react_no_array_index_key = false;
        } else if (std.mem.eql(u8, arg, "--react-no-children-prop=off")) {
            options.react_no_children_prop = false;
        } else if (std.mem.eql(u8, arg, "--react-no-find-dom-node=off")) {
            options.react_no_find_dom_node = false;
        } else if (std.mem.eql(u8, arg, "--react-no-is-mounted=off")) {
            options.react_no_is_mounted = false;
        } else if (std.mem.eql(u8, arg, "--react-no-multi-comp=off")) {
            options.react_no_multi_comp = false;
        } else if (std.mem.eql(u8, arg, "--react-no-redundant-should-component-update=off")) {
            options.react_no_redundant_should_component_update = false;
        } else if (std.mem.eql(u8, arg, "--react-no-render-return-value=off")) {
            options.react_no_render_return_value = false;
        } else if (std.mem.eql(u8, arg, "--react-no-will-update-set-state=off")) {
            options.react_no_will_update_set_state = false;
        } else if (std.mem.eql(u8, arg, "--react-no-this-in-sfc=off")) {
            options.react_no_this_in_sfc = false;
        } else if (std.mem.eql(u8, arg, "--react-no-typos=off")) {
            options.react_no_typos = false;
        } else if (std.mem.eql(u8, arg, "--react-no-unknown-property=off")) {
            options.react_no_unknown_property = false;
        } else if (std.mem.eql(u8, arg, "--react-prop-types=off")) {
            options.react_prop_types = false;
        } else if (std.mem.eql(u8, arg, "--react-no-unused-prop-types=off")) {
            options.react_no_unused_prop_types = false;
        } else if (std.mem.eql(u8, arg, "--react-no-unused-state=off")) {
            options.react_no_unused_state = false;
        } else if (std.mem.eql(u8, arg, "--react-no-string-refs=off")) {
            options.react_no_string_refs = false;
        } else if (std.mem.eql(u8, arg, "--react-no-unescaped-entities=off")) {
            options.react_no_unescaped_entities = false;
        } else if (std.mem.eql(u8, arg, "--react-prefer-es6-class=off")) {
            options.react_prefer_es6_class = false;
        } else if (std.mem.eql(u8, arg, "--react-self-closing-comp=off")) {
            options.react_self_closing_comp = false;
        } else if (std.mem.eql(u8, arg, "--react-style-prop-object=off")) {
            options.react_style_prop_object = false;
        } else if (std.mem.eql(u8, arg, "--react-void-dom-elements-no-children=off")) {
            options.react_void_dom_elements_no_children = false;
        } else if (std.mem.eql(u8, arg, "--react-hooks-rules-of-hooks=off")) {
            options.react_hooks_rules_of_hooks = false;
        } else if (std.mem.eql(u8, arg, "--radix=off")) {
            options.radix = false;
        } else if (std.mem.eql(u8, arg, "--require-await=off")) {
            options.require_await = false;
        } else if (std.mem.eql(u8, arg, "--require-atomic-updates=off")) {
            options.require_atomic_updates = false;
        } else if (std.mem.eql(u8, arg, "--require-unicode-regexp=off")) {
            options.require_unicode_regexp = false;
        } else if (std.mem.eql(u8, arg, "--require-unicode-regexp-require-flag=u")) {
            options.require_unicode_regexp_require_flag = .u;
        } else if (std.mem.eql(u8, arg, "--require-unicode-regexp-require-flag=v")) {
            options.require_unicode_regexp_require_flag = .v;
        } else if (std.mem.eql(u8, arg, "--require-yield=off")) {
            options.require_yield = false;
        } else if (std.mem.eql(u8, arg, "--sort-imports=on")) {
            options.sort_imports = true;
        } else if (std.mem.eql(u8, arg, "--sort-imports=off")) {
            options.sort_imports = false;
        } else if (std.mem.eql(u8, arg, "--sort-imports-ignore-case=on")) {
            options.sort_imports = true;
            options.sort_imports_ignore_case = true;
        } else if (std.mem.eql(u8, arg, "--sort-imports-ignore-declaration-sort=on")) {
            options.sort_imports = true;
            options.sort_imports_ignore_declaration_sort = true;
        } else if (std.mem.eql(u8, arg, "--sort-imports-ignore-member-sort=on")) {
            options.sort_imports = true;
            options.sort_imports_ignore_member_sort = true;
        } else if (std.mem.eql(u8, arg, "--sort-imports-allow-separated-groups=on")) {
            options.sort_imports = true;
            options.sort_imports_allow_separated_groups = true;
        } else if (std.mem.eql(u8, arg, "--sort-keys=on")) {
            options.sort_keys = true;
        } else if (std.mem.eql(u8, arg, "--sort-keys=off")) {
            options.sort_keys = false;
        } else if (std.mem.eql(u8, arg, "--sort-keys=desc")) {
            options.sort_keys = true;
            options.sort_keys_order = .desc;
        } else if (std.mem.eql(u8, arg, "--sort-keys-case-sensitive=off")) {
            options.sort_keys = true;
            options.sort_keys_case_sensitive = false;
        } else if (std.mem.eql(u8, arg, "--sort-keys-natural=on")) {
            options.sort_keys = true;
            options.sort_keys_natural = true;
        } else if (std.mem.startsWith(u8, arg, "--sort-keys-min-keys=")) {
            parseSortKeysMinKeys(arg["--sort-keys-min-keys=".len..], &options);
        } else if (std.mem.eql(u8, arg, "--sort-keys-allow-line-separated-groups=on")) {
            options.sort_keys = true;
            options.sort_keys_allow_line_separated_groups = true;
        } else if (std.mem.eql(u8, arg, "--sort-vars=on")) {
            options.sort_vars = true;
        } else if (std.mem.eql(u8, arg, "--sort-vars=off")) {
            options.sort_vars = false;
        } else if (std.mem.eql(u8, arg, "--sort-vars-ignore-case=on")) {
            options.sort_vars = true;
            options.sort_vars_ignore_case = true;
        } else if (std.mem.eql(u8, arg, "--spaced-comment=off")) {
            options.spaced_comment = false;
        } else if (std.mem.eql(u8, arg, "--spaced-comment=never")) {
            options.spaced_comment_style = .never;
        } else if (std.mem.eql(u8, arg, "--strict=off")) {
            options.strict = false;
        } else if (std.mem.eql(u8, arg, "--strict=safe")) {
            options.strict = true;
            options.strict_mode = .safe;
        } else if (std.mem.eql(u8, arg, "--strict=global")) {
            options.strict = true;
            options.strict_mode = .global;
        } else if (std.mem.eql(u8, arg, "--strict=function")) {
            options.strict = true;
            options.strict_mode = .function;
        } else if (std.mem.eql(u8, arg, "--strict=never")) {
            options.strict = true;
            options.strict_mode = .never;
        } else if (std.mem.eql(u8, arg, "--symbol-description=off")) {
            options.symbol_description = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-adjacent-overload-signatures=off")) {
            options.typescript_eslint_adjacent_overload_signatures = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-array-type=off")) {
            options.typescript_eslint_array_type = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-class-literal-property-style=off")) {
            options.typescript_eslint_class_literal_property_style = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-consistent-type-assertions=off")) {
            options.typescript_eslint_consistent_type_assertions = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-consistent-type-definitions=off")) {
            options.typescript_eslint_consistent_type_definitions = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-dot-notation=off")) {
            options.typescript_eslint_dot_notation = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-array-constructor=off")) {
            options.typescript_eslint_no_array_constructor = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-ban-types=off")) {
            options.typescript_eslint_ban_types = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-ban-ts-comment=off")) {
            options.typescript_eslint_ban_ts_comment = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-ban-tslint-comment=off")) {
            options.typescript_eslint_ban_tslint_comment = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-explicit-member-accessibility=off")) {
            options.typescript_eslint_explicit_member_accessibility = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-member-ordering=off")) {
            options.typescript_eslint_member_ordering = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-method-signature-style=off")) {
            options.typescript_eslint_method_signature_style = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-confusing-non-null-assertion=off")) {
            options.typescript_eslint_no_confusing_non_null_assertion = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-dupe-class-members=off")) {
            options.typescript_eslint_no_dupe_class_members = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-empty-function=off")) {
            options.typescript_eslint_no_empty_function = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-empty-interface=off")) {
            options.typescript_eslint_no_empty_interface = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-extra-semi=off")) {
            options.typescript_eslint_no_extra_semi = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-extra-non-null-assertion=off")) {
            options.typescript_eslint_no_extra_non_null_assertion = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-duplicate-enum-values=off")) {
            options.typescript_eslint_no_duplicate_enum_values = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-inferrable-types=off")) {
            options.typescript_eslint_no_inferrable_types = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-invalid-void-type=off")) {
            options.typescript_eslint_no_invalid_void_type = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-loss-of-precision=off")) {
            options.typescript_eslint_no_loss_of_precision = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-loop-func=off")) {
            options.typescript_eslint_no_loop_func = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-misused-new=off")) {
            options.typescript_eslint_no_misused_new = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-namespace=off")) {
            options.typescript_eslint_no_namespace = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-non-null-asserted-optional-chain=off")) {
            options.typescript_eslint_no_non_null_asserted_optional_chain = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-redeclare=off")) {
            options.typescript_eslint_no_redeclare = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-require-imports=off")) {
            options.typescript_eslint_no_require_imports = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-shadow=off")) {
            options.typescript_eslint_no_shadow = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-this-alias=off")) {
            options.typescript_eslint_no_this_alias = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-unsafe-declaration-merging=off")) {
            options.typescript_eslint_no_unsafe_declaration_merging = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-triple-slash-reference=off")) {
            options.typescript_eslint_triple_slash_reference = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-typedef=off")) {
            options.typescript_eslint_typedef = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-unified-signatures=off")) {
            options.typescript_eslint_unified_signatures = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-unnecessary-parameter-property-assignment=off")) {
            options.typescript_eslint_no_unnecessary_parameter_property_assignment = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-unnecessary-type-constraint=off")) {
            options.typescript_eslint_no_unnecessary_type_constraint = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-useless-constructor=off")) {
            options.typescript_eslint_no_useless_constructor = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-useless-empty-export=off")) {
            options.typescript_eslint_no_useless_empty_export = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-unused-expressions=off")) {
            options.typescript_eslint_no_unused_expressions = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-unused-vars=off")) {
            options.typescript_eslint_no_unused_vars = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-use-before-define=off")) {
            options.typescript_eslint_no_use_before_define = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-var-requires=off")) {
            options.typescript_eslint_no_var_requires = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-no-wrapper-object-types=off")) {
            options.typescript_eslint_no_wrapper_object_types = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-prefer-as-const=off")) {
            options.typescript_eslint_prefer_as_const = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-prefer-namespace-keyword=off")) {
            options.typescript_eslint_prefer_namespace_keyword = false;
        } else if (std.mem.eql(u8, arg, "--typescript-eslint-restrict-plus-operands=off")) {
            options.typescript_eslint_restrict_plus_operands = false;
        } else if (std.mem.eql(u8, arg, "--valid-typeof=off")) {
            options.valid_typeof = false;
        } else if (std.mem.eql(u8, arg, "--vars-on-top=off")) {
            options.vars_on_top = false;
        } else if (std.mem.eql(u8, arg, "--wrap-iife=off")) {
            options.wrap_iife = false;
        } else if (std.mem.eql(u8, arg, "--wrap-iife=outside")) {
            options.wrap_iife_style = .outside;
        } else if (std.mem.eql(u8, arg, "--wrap-iife=inside")) {
            options.wrap_iife_style = .inside;
        } else if (std.mem.eql(u8, arg, "--wrap-iife=any")) {
            options.wrap_iife_style = .any;
        } else if (std.mem.eql(u8, arg, "--semantic-errors=off")) {
            options.parser_semantic_errors = false;
        } else if (std.mem.eql(u8, arg, "--yoda=off")) {
            options.yoda = false;
        } else if (std.mem.eql(u8, arg, "--yoda=always")) {
            options.yoda_style = .always;
        } else {
            try targets.append(allocator, arg);
        }
    }

    const uses_default_targets = targets.items.len == 0;
    if (uses_default_targets) {
        try targets.append(allocator, ".");
    }

    var files: std.ArrayList([]const u8) = .empty;
    defer {
        for (files.items) |file| {
            allocator.free(file);
        }
        files.deinit(allocator);
    }

    var json_diagnostics: JsonDiagnosticList = .empty;
    defer freeJsonDiagnostics(allocator, &json_diagnostics);
    var json_suppressed_diagnostics: JsonDiagnosticList = .empty;
    defer freeJsonDiagnostics(allocator, &json_suppressed_diagnostics);
    var json_outputs: JsonOutputList = .empty;
    defer freeJsonOutputs(allocator, &json_outputs);
    const json_diagnostics_ptr: ?*JsonDiagnosticList = if (output_format == .json) &json_diagnostics else null;

    var stats = Stats{};
    for (targets.items) |target| {
        try collectLintablePaths(allocator, io, target, &files, &stats, json_diagnostics_ptr, if (loaded_flat_config) |*loaded| loaded else null, uses_default_targets);
    }

    const resolve_flat_rules = !hasRuleOverrideArg(args[1..]);
    const flat_config_for_lint: ?*const flat_config.FlatConfig = if (resolve_flat_rules)
        if (loaded_flat_config) |*loaded| loaded else null
    else
        null;
    if (output_format == .json) {
        try lintFilesJson(allocator, io, files.items, options, &rule_severities, flat_config_for_lint, fix_mode, &stats, &json_diagnostics, &json_suppressed_diagnostics, &json_outputs);
        try writeJsonReport(io, stats, files.items, json_diagnostics.items, json_suppressed_diagnostics.items, json_outputs.items);
    } else {
        const use_color = color_override orelse detectColorSupport(io, init.environ_map.*);
        try lintFiles(allocator, io, files.items, options, &rule_severities, flat_config_for_lint, fix_mode, thread_count_override, use_color, &stats);
        printTextSummary(stats, fix_mode, use_color);
    }

    if (stats.errors > 0) {
        std.process.exit(1);
    }
}

fn hasRuleOverrideArg(args: []const []const u8) bool {
    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) continue;
        if (std.mem.eql(u8, arg, "--no-config") or
            std.mem.eql(u8, arg, "--json") or
            std.mem.eql(u8, arg, "--color") or
            std.mem.eql(u8, arg, "--no-color") or
            std.mem.eql(u8, arg, "--fix") or
            std.mem.eql(u8, arg, "--fix-dry-run") or
            std.mem.startsWith(u8, arg, "--config=") or
            std.mem.startsWith(u8, arg, "--config-root=") or
            std.mem.startsWith(u8, arg, "--config-cwd=") or
            std.mem.startsWith(u8, arg, "--threads=") or
            std.mem.startsWith(u8, arg, "--format=")) continue;
        return true;
    }
    return false;
}

fn hasHelpArg(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return true;
    }
    return false;
}

const ConfigArgs = struct {
    enabled: bool = true,
    path: ?[]const u8 = null,
    root: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
};

fn parseConfigArgs(args: []const []const u8) ConfigArgs {
    var config = ConfigArgs{};
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--no-config")) {
            config.enabled = false;
            config.path = null;
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            config.enabled = true;
            config.path = arg["--config=".len..];
            if (config.path.?.len == 0) {
                std.debug.print("utoo-lint: --config requires a path\n", .{});
                std.process.exit(2);
            }
        } else if (std.mem.startsWith(u8, arg, "--config-root=")) {
            config.root = arg["--config-root=".len..];
            if (config.root.?.len == 0) {
                std.debug.print("utoo-lint: --config-root requires a path\n", .{});
                std.process.exit(2);
            }
        } else if (std.mem.startsWith(u8, arg, "--config-cwd=")) {
            config.cwd = arg["--config-cwd=".len..];
            if (config.cwd.?.len == 0) {
                std.debug.print("utoo-lint: --config-cwd requires a path\n", .{});
                std.process.exit(2);
            }
        }
    }
    return config;
}

fn findDefaultConfig(allocator: std.mem.Allocator, io: std.Io) !?[]u8 {
    const current = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(current);
    const start = try allocator.dupe(u8, current);
    return findDefaultConfigFrom(allocator, io, start);
}

fn findDefaultConfigFrom(allocator: std.mem.Allocator, io: std.Io, start: []u8) !?[]u8 {
    var current = start;
    defer allocator.free(current);

    while (true) {
        for (config_filenames) |filename| {
            const path = try std.fs.path.join(allocator, &.{ current, filename });
            errdefer allocator.free(path);
            if (isConfigFile(io, path)) return path;
            allocator.free(path);
        }

        const parent = std.fs.path.dirname(current) orelse break;
        if (std.mem.eql(u8, parent, current)) break;
        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }
    return null;
}

const config_filenames = [_][]const u8{
    "utlint.config.json",
    "utoo.json",
    "utoo-lint.json",
};

fn isConfigFile(io: std.Io, path: []const u8) bool {
    const directory_path = std.fs.path.dirname(path) orelse return false;
    const basename = std.fs.path.basename(path);
    var directory = std.Io.Dir.openDirAbsolute(io, directory_path, .{}) catch return false;
    defer directory.close(io);
    const stat = directory.statFile(io, basename, .{}) catch return false;
    return stat.kind == .file;
}

fn parseOutputFormat(value: []const u8) ?OutputFormat {
    if (std.mem.eql(u8, value, "text")) return .text;
    if (std.mem.eql(u8, value, "json")) return .json;
    return null;
}

fn loadConfigFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    config_root: ?[]const u8,
    config_cwd: ?[]const u8,
    explicit: bool,
    options: *lint.Options,
    rule_severities: *RuleSeverityMap,
) !?flat_config.FlatConfig {
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_config_file_size)) catch |err| {
        if (explicit) {
            std.debug.print("utoo-lint: unable to read config {s}: {s}\n", .{ path, @errorName(err) });
            std.process.exit(2);
        }
        return null;
    };
    defer allocator.free(source);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch |err| {
        std.debug.print("utoo-lint: invalid config {s}: {s}\n", .{ path, @errorName(err) });
        std.process.exit(2);
    };

    switch (parsed.value) {
        .object => |root| {
            defer parsed.deinit();
            try loadConfigObject(allocator, path, root, options, rule_severities);
            return null;
        },
        .array => {
            errdefer parsed.deinit();
            const current = try std.process.currentPathAlloc(io, allocator);
            defer allocator.free(current);
            const cwd = try flat_config.canonicalPathAlloc(allocator, io, current, config_cwd orelse current);
            errdefer allocator.free(cwd);
            const absolute_path = try flat_config.canonicalPathAlloc(allocator, io, cwd, path);
            defer allocator.free(absolute_path);
            const directory = try flat_config.canonicalPathAlloc(
                allocator,
                io,
                cwd,
                config_root orelse std.fs.path.dirname(absolute_path) orelse ".",
            );
            var loaded = flat_config.FlatConfig{
                .parsed = parsed,
                .io = io,
                .directory = directory,
                .cwd = cwd,
            };
            loaded.validateAndApplyAggregate(allocator, options, rule_severities) catch |err| {
                loaded.deinit(allocator);
                std.debug.print("utoo-lint: invalid flat config {s}: {s}\n", .{ path, @errorName(err) });
                std.process.exit(2);
            };
            return loaded;
        },
        else => {
            parsed.deinit();
            std.debug.print("utoo-lint: config {s} must be a JSON object or flat-config array\n", .{path});
            std.process.exit(2);
        },
    }
}

fn loadConfigObject(
    allocator: std.mem.Allocator,
    path: []const u8,
    root: std.json.ObjectMap,
    options: *lint.Options,
    rule_severities: *RuleSeverityMap,
) !void {
    options.* = lint.Options.allDisabled();
    if (root.get("settings")) |settings_value| {
        const settings = switch (settings_value) {
            .object => |object| object,
            else => {
                std.debug.print("utoo-lint: config {s} field \"settings\" must be an object\n", .{path});
                std.process.exit(2);
            },
        };
        if (settings.get("jest")) |jest_value| {
            const jest = switch (jest_value) {
                .object => |object| object,
                else => {
                    std.debug.print("utoo-lint: config {s} field \"settings.jest\" must be an object\n", .{path});
                    std.process.exit(2);
                },
            };
            if (jest.get("version")) |version| {
                options.setJestVersionFromConfig(version) catch |err| {
                    std.debug.print(
                        "utoo-lint: invalid config {s} setting settings.jest.version: {s}\n",
                        .{ path, @errorName(err) },
                    );
                    std.process.exit(2);
                };
            }
            if (jest.get("globalAliases")) |aliases| {
                options.setJestGlobalAliasesFromConfig(aliases) catch |err| {
                    std.debug.print(
                        "utoo-lint: invalid config {s} setting settings.jest.globalAliases: {s}\n",
                        .{ path, @errorName(err) },
                    );
                    std.process.exit(2);
                };
            }
        }
    }
    if (root.get("languageOptions")) |language_options_value| {
        const language_options = switch (language_options_value) {
            .object => |object| object,
            else => {
                std.debug.print("utoo-lint: config {s} field \"languageOptions\" must be an object\n", .{path});
                std.process.exit(2);
            },
        };
        if (language_options.get("globals")) |globals| {
            options.setConfiguredGlobalsFromConfig(globals) catch |err| {
                std.debug.print(
                    "utoo-lint: invalid config {s} field languageOptions.globals: {s}\n",
                    .{ path, @errorName(err) },
                );
                std.process.exit(2);
            };
        }
    }
    const rules_value = root.get("rules") orelse return;
    const rules = switch (rules_value) {
        .object => |object| object,
        else => {
            std.debug.print("utoo-lint: config {s} field \"rules\" must be an object\n", .{path});
            std.process.exit(2);
        },
    };

    var iter = rules.iterator();
    while (iter.next()) |entry| {
        options.setByRuleConfigValue(entry.key_ptr.*, entry.value_ptr.*) catch |err| {
            std.debug.print(
                "utoo-lint: invalid config {s} rule {s}: {s}\n",
                .{ path, entry.key_ptr.*, @errorName(err) },
            );
            std.process.exit(2);
        };
        const severity = lint.Options.severityFromRuleConfigValue(entry.value_ptr.*) catch |err| {
            std.debug.print(
                "utoo-lint: invalid config {s} rule {s}: {s}\n",
                .{ path, entry.key_ptr.*, @errorName(err) },
            );
            std.process.exit(2);
        };
        if (severity) |configured_severity| {
            const owned_rule = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(owned_rule);
            try rule_severities.put(owned_rule, configured_severity);
        }
    }
}

fn collectLintablePaths(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    files: *std.ArrayList([]const u8),
    stats: *Stats,
    json_diagnostics: ?*JsonDiagnosticList,
    config: ?*const flat_config.FlatConfig,
    default_targets: bool,
) !void {
    const cwd = std.Io.Dir.cwd();
    const stat = cwd.statFile(io, path, .{}) catch |err| {
        if (json_diagnostics) |diagnostics| {
            const message = try std.fmt.allocPrint(allocator, "unable to stat path: {s}", .{@errorName(err)});
            defer allocator.free(message);
            try appendJsonDiagnostic(allocator, diagnostics, path, 0, 0, null, "error", message, "io", "", &.{}, &.{}, null, &.{});
        } else {
            std.debug.print("{s}: unable to stat path: {s}\n", .{ path, @errorName(err) });
        }
        stats.errors += 1;
        stats.diagnostics += 1;
        return;
    };

    switch (stat.kind) {
        .file => {
            if (lint.isLintablePath(path) and try shouldLintCollectedPath(allocator, path, config, default_targets)) {
                try files.append(allocator, try allocator.dupe(u8, path));
            }
        },
        .directory => try collectLintableDirectory(allocator, io, path, files, stats, json_diagnostics, config, default_targets),
        else => {},
    }
}

fn shouldLintCollectedPath(
    allocator: std.mem.Allocator,
    path: []const u8,
    config: ?*const flat_config.FlatConfig,
    default_targets: bool,
) !bool {
    const loaded = config orelse return true;
    if (try loaded.isGloballyIgnored(allocator, path)) return false;
    return !default_targets or try loaded.selectsFile(allocator, path);
}

fn parseEnabledRules(
    allocator: std.mem.Allocator,
    value: []const u8,
    options: *lint.Options,
    rule_severities: *RuleSeverityMap,
) !void {
    if (value.len == 0) {
        std.debug.print("utoo-lint: --rules requires a comma-separated rule list\n", .{});
        std.process.exit(2);
    }

    var iter = std.mem.splitScalar(u8, value, ',');
    while (iter.next()) |raw_rule| {
        const rule = std.mem.trim(u8, raw_rule, " \t\r\n");
        if (rule.len == 0) {
            std.debug.print("utoo-lint: --rules contains an empty rule name\n", .{});
            std.process.exit(2);
        }
        options.setByRuleConfigValue(rule, .{ .string = "warn" }) catch |err| {
            if (err == error.UnknownRule) {
                std.debug.print("utoo-lint: unknown rule in --rules: {s}\n", .{rule});
            } else {
                std.debug.print("utoo-lint: invalid rule in --rules {s}: {s}\n", .{ rule, @errorName(err) });
            }
            std.process.exit(2);
        };
        const owned_rule = try allocator.dupe(u8, rule);
        errdefer allocator.free(owned_rule);
        const entry = try rule_severities.getOrPut(owned_rule);
        if (entry.found_existing) {
            allocator.free(owned_rule);
        } else {
            entry.value_ptr.* = .warning;
        }
    }
}

fn clearRuleSeverities(allocator: std.mem.Allocator, rule_severities: *RuleSeverityMap) void {
    var iter = rule_severities.keyIterator();
    while (iter.next()) |rule| allocator.free(rule.*);
    rule_severities.clearRetainingCapacity();
}

fn parseNoConsoleAllow(value: []const u8, options: *lint.Options) void {
    if (value.len == 0) {
        std.debug.print("utoo-lint: --no-console-allow requires a comma-separated method list\n", .{});
        std.process.exit(2);
    }

    var allow: @TypeOf(options.no_console_allow) = .{};
    var iter = std.mem.splitScalar(u8, value, ',');
    while (iter.next()) |raw_method| {
        const method = std.mem.trim(u8, raw_method, " \t\r\n");
        if (method.len == 0) {
            std.debug.print("utoo-lint: --no-console-allow contains an empty method name\n", .{});
            std.process.exit(2);
        }
        if (!allow.enable(method)) {
            std.debug.print("utoo-lint: --no-console-allow method is too long or too many methods were provided: {s}\n", .{method});
            std.process.exit(2);
        }
    }
    options.no_console_allow = allow;
}

fn parseNoMagicNumbersIgnore(value: []const u8, options: *lint.Options) void {
    if (value.len == 0) {
        std.debug.print("utoo-lint: --no-magic-numbers-ignore requires a comma-separated number list\n", .{});
        std.process.exit(2);
    }

    var ignored: @TypeOf(options.no_magic_numbers_ignore) = .{};
    var iter = std.mem.splitScalar(u8, value, ',');
    while (iter.next()) |raw_value| {
        const number = std.mem.trim(u8, raw_value, " \t\r\n");
        if (number.len == 0 or !ignored.appendCliValue(number)) {
            std.debug.print("utoo-lint: invalid or excessive --no-magic-numbers-ignore value: {s}\n", .{number});
            std.process.exit(2);
        }
    }
    options.no_magic_numbers = true;
    options.no_magic_numbers_ignore = ignored;
}

fn parseNoEmptyFunctionAllow(value: []const u8, options: *lint.Options) void {
    if (value.len == 0) {
        std.debug.print("utoo-lint: --no-empty-function-allow requires a comma-separated kind list\n", .{});
        std.process.exit(2);
    }

    var allow: @TypeOf(options.no_empty_function_allow) = .{};
    var iter = std.mem.splitScalar(u8, value, ',');
    while (iter.next()) |raw_kind| {
        const kind = std.mem.trim(u8, raw_kind, " \t\r\n");
        if (kind.len == 0) {
            std.debug.print("utoo-lint: --no-empty-function-allow contains an empty kind\n", .{});
            std.process.exit(2);
        }
        if (!allow.enable(kind)) {
            std.debug.print("utoo-lint: unsupported --no-empty-function-allow kind: {s}\n", .{kind});
            std.process.exit(2);
        }
    }
    options.no_empty_function_allow = allow;
}

fn parseNoParamReassignIgnorePropertyModificationsFor(value: []const u8, options: *lint.Options) void {
    if (value.len == 0) {
        std.debug.print("utoo-lint: --no-param-reassign-ignore-property-modifications-for requires a comma-separated name list\n", .{});
        std.process.exit(2);
    }

    var ignored: @TypeOf(options.no_param_reassign_ignore_property_modifications_for) = .{};
    var iter = std.mem.splitScalar(u8, value, ',');
    while (iter.next()) |raw_name| {
        const name = std.mem.trim(u8, raw_name, " \t\r\n");
        ignored.append(name) catch {
            std.debug.print("utoo-lint: invalid --no-param-reassign-ignore-property-modifications-for name: {s}\n", .{name});
            std.process.exit(2);
        };
    }
    options.no_param_reassign_ignore_property_modifications_for = ignored;
}

fn parseNoWarningCommentsTerms(value: []const u8, options: *lint.Options) void {
    if (value.len == 0) {
        std.debug.print("utoo-lint: --no-warning-comments-terms requires a comma-separated term list\n", .{});
        std.process.exit(2);
    }

    var terms: @TypeOf(options.no_warning_comments_terms) = .{};
    terms.custom = true;
    var iter = std.mem.splitScalar(u8, value, ',');
    while (iter.next()) |raw_term| {
        const term = std.mem.trim(u8, raw_term, " \t\r\n");
        terms.append(term) catch {
            std.debug.print("utoo-lint: invalid --no-warning-comments-terms term: {s}\n", .{term});
            std.process.exit(2);
        };
    }
    options.no_warning_comments_terms = terms;
}

fn appendCamelcaseAllow(value: []const u8, options: *lint.Options) void {
    options.camelcase_allow.append(value) catch {
        std.debug.print("utoo-lint: invalid --camelcase-allow value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.camelcase = true;
}

fn appendClassMethodsUseThisExceptMethod(value: []const u8, options: *lint.Options) void {
    options.class_methods_use_this_except_methods.append(value) catch {
        std.debug.print("utoo-lint: invalid --class-methods-use-this-except-method value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.class_methods_use_this = true;
}

fn parseClassMethodsUseThisIgnoreClassesWithImplements(value: []const u8, options: *lint.Options) void {
    if (std.mem.eql(u8, value, "all")) {
        options.class_methods_use_this_ignore_classes_with_implements = .all;
    } else if (std.mem.eql(u8, value, "public-fields")) {
        options.class_methods_use_this_ignore_classes_with_implements = .public_fields;
    } else if (std.mem.eql(u8, value, "none")) {
        options.class_methods_use_this_ignore_classes_with_implements = .none;
    } else {
        std.debug.print("utoo-lint: invalid --class-methods-use-this-ignore-classes-with-implements value: {s}\n", .{value});
        std.process.exit(2);
    }
    options.class_methods_use_this = true;
}

fn appendNoRestrictedExportName(value: []const u8, options: *lint.Options) void {
    options.no_restricted_exports_names.append(value) catch {
        std.debug.print("utoo-lint: invalid --no-restricted-exports-name value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.no_restricted_exports = true;
}

fn appendNoRestrictedGlobalName(value: []const u8, options: *lint.Options) void {
    if (!options.no_restricted_globals_entries.appendName(value)) {
        std.debug.print("utoo-lint: invalid --no-restricted-globals-name value: {s}\n", .{value});
        std.process.exit(2);
    }
    options.no_restricted_globals = true;
}

fn appendNoRestrictedImportName(value: []const u8, options: *lint.Options, kind: lint.NoRestrictedImportKind) void {
    var entry = lint.NoRestrictedImportEntry{ .kind = kind };
    if (!entry.setSource(value) or !options.no_restricted_imports_entries.append(entry)) {
        std.debug.print("utoo-lint: invalid no-restricted-imports value: {s}\n", .{value});
        std.process.exit(2);
    }
    options.no_restricted_imports = true;
}

fn appendNoRestrictedModuleName(value: []const u8, options: *lint.Options, kind: lint.NoRestrictedImportKind) void {
    var entry = lint.NoRestrictedImportEntry{ .kind = kind };
    if (!entry.setSource(value) or !options.no_restricted_modules_entries.append(entry)) {
        std.debug.print("utoo-lint: invalid no-restricted-modules value: {s}\n", .{value});
        std.process.exit(2);
    }
    options.no_restricted_modules = true;
}

fn appendNoRestrictedSyntaxSelector(value: []const u8, options: *lint.Options) void {
    var entry = lint.NoRestrictedSyntaxEntry{};
    if (!entry.setSelector(value) or !options.no_restricted_syntax_entries.append(entry)) {
        std.debug.print("utoo-lint: invalid --no-restricted-syntax-selector value: {s}\n", .{value});
        std.process.exit(2);
    }
    options.no_restricted_syntax = true;
}

fn parseNoMultipleEmptyLinesMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --no-multiple-empty-lines-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.no_multiple_empty_lines_max = max;
}

fn appendIdDenylistName(value: []const u8, options: *lint.Options) void {
    options.id_denylist_names.append(value) catch {
        std.debug.print("utoo-lint: invalid --id-denylist-name value: {s}\n", .{value});
        std.process.exit(2);
    };
}

fn parseIdLengthMin(value: []const u8, options: *lint.Options) void {
    const min = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --id-length-min value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.id_length_min = min;
    options.id_length = true;
}

fn parseIdLengthMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --id-length-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.id_length_max = max;
    options.id_length_has_max = true;
    options.id_length = true;
}

fn appendIdLengthException(value: []const u8, options: *lint.Options) void {
    options.id_length_exceptions.append(value) catch {
        std.debug.print("utoo-lint: invalid --id-length-exception value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.id_length = true;
}

fn appendIdLengthExceptionPattern(value: []const u8, options: *lint.Options) void {
    options.id_length_exception_patterns.append(value) catch {
        std.debug.print("utoo-lint: invalid --id-length-exception-pattern value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.id_length = true;
}

fn setIdMatchPattern(value: []const u8, options: *lint.Options) void {
    options.id_match_pattern.set(value) catch {
        std.debug.print("utoo-lint: invalid --id-match-pattern value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.id_match = true;
}

fn appendConsistentThisAlias(value: []const u8, options: *lint.Options) void {
    if (!options.consistent_this_aliases.custom) {
        options.consistent_this_aliases = .{ .custom = true };
    }
    options.consistent_this_aliases.append(value) catch {
        std.debug.print("utoo-lint: invalid --consistent-this-alias value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.consistent_this = true;
}

fn parseComplexityMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --complexity-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.complexity_max = max;
}

fn parseMaxClassesPerFileMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --max-classes-per-file-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    if (max < 1) {
        std.debug.print("utoo-lint: invalid --max-classes-per-file-max value: {s}\n", .{value});
        std.process.exit(2);
    }
    options.max_classes_per_file_max = max;
}

fn parseMaxDepthMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --max-depth-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.max_depth_max = max;
}

fn parseMaxLinesMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --max-lines-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.max_lines = true;
    options.max_lines_max = max;
}

fn parseMaxLinesPerFunctionMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --max-lines-per-function-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.max_lines_per_function = true;
    options.max_lines_per_function_max = max;
}

fn parseMaxNestedCallbacksMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --max-nested-callbacks-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.max_nested_callbacks_max = max;
}

fn parseMaxParamsMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --max-params-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.max_params_max = max;
}

fn parseSortKeysMinKeys(value: []const u8, options: *lint.Options) void {
    const min_keys = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --sort-keys-min-keys value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.sort_keys = true;
    options.sort_keys_min_keys = min_keys;
}

fn parseMaxStatementsMax(value: []const u8, options: *lint.Options) void {
    const max = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --max-statements-max value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.max_statements_max = max;
}

fn parseNoMultipleEmptyLinesMaxBof(value: []const u8, options: *lint.Options) void {
    const max_bof = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --no-multiple-empty-lines-max-bof value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.no_multiple_empty_lines_max_bof = max_bof;
}

fn parseNoMultipleEmptyLinesMaxEof(value: []const u8, options: *lint.Options) void {
    const max_eof = std.fmt.parseInt(usize, value, 10) catch {
        std.debug.print("utoo-lint: invalid --no-multiple-empty-lines-max-eof value: {s}\n", .{value});
        std.process.exit(2);
    };
    options.no_multiple_empty_lines_max_eof = max_eof;
}

fn collectLintableDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    files: *std.ArrayList([]const u8),
    stats: *Stats,
    json_diagnostics: ?*JsonDiagnosticList,
    config: ?*const flat_config.FlatConfig,
    default_targets: bool,
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (shouldSkipDirectoryEntry(entry.name)) continue;

        const child_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(child_path);

        switch (entry.kind) {
            .file => {
                if (lint.isLintablePath(child_path) and try shouldLintCollectedPath(allocator, child_path, config, default_targets)) {
                    try files.append(allocator, try allocator.dupe(u8, child_path));
                }
            },
            .directory => {
                if (config == null or try config.?.shouldTraverseDirectory(allocator, child_path)) {
                    try collectLintableDirectory(allocator, io, child_path, files, stats, json_diagnostics, config, default_targets);
                }
            },
            else => {},
        }
    }
}

fn lintFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    files: []const []const u8,
    options: lint.Options,
    rule_severities: *const RuleSeverityMap,
    config: ?*const flat_config.FlatConfig,
    fix_mode: FixMode,
    thread_count_override: ?usize,
    use_color: bool,
    stats: *Stats,
) !void {
    if (files.len == 0) return;

    const worker_count = @min(files.len, thread_count_override orelse (std.Thread.getCpuCount() catch 1));
    if (worker_count <= 1) {
        for (files) |file| {
            try lintFile(std.heap.smp_allocator, io, file, options, rule_severities, config, fix_mode, use_color, stats, null);
        }
        return;
    }

    var queue = WorkQueue{
        .io = io,
        .files = files,
        .options = options,
        .rule_severities = rule_severities,
        .config = config,
        .fix_mode = fix_mode,
        .use_color = use_color,
    };

    const threads = try allocator.alloc(std.Thread, worker_count);
    defer allocator.free(threads);

    const results = try allocator.alloc(WorkerResult, worker_count);
    defer allocator.free(results);
    for (results) |*result| {
        result.* = .{};
    }

    var spawned: usize = 0;
    errdefer {
        for (threads[0..spawned]) |thread| {
            thread.join();
        }
    }

    for (threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, lintWorker, .{ &queue, &results[index] });
        spawned += 1;
    }

    for (threads) |thread| {
        thread.join();
    }

    var worker_err: ?anyerror = null;
    for (results) |result| {
        stats.add(result.stats);
        if (worker_err == null) {
            worker_err = result.err;
        }
    }

    if (worker_err) |err| {
        return err;
    }
}

fn lintFilesJson(
    allocator: std.mem.Allocator,
    io: std.Io,
    files: []const []const u8,
    options: lint.Options,
    rule_severities: *const RuleSeverityMap,
    config: ?*const flat_config.FlatConfig,
    fix_mode: FixMode,
    stats: *Stats,
    json_diagnostics: *JsonDiagnosticList,
    json_suppressed_diagnostics: *JsonDiagnosticList,
    json_outputs: *JsonOutputList,
) !void {
    for (files) |file| {
        try lintFileJson(allocator, io, file, options, rule_severities, config, fix_mode, stats, json_diagnostics, json_suppressed_diagnostics, json_outputs);
    }
}

fn lintWorker(queue: *WorkQueue, result: *WorkerResult) void {
    while (true) {
        const index = queue.next_index.fetchAdd(1, .monotonic);
        if (index >= queue.files.len) return;

        lintFile(
            std.heap.smp_allocator,
            queue.io,
            queue.files[index],
            queue.options,
            queue.rule_severities,
            queue.config,
            queue.fix_mode,
            queue.use_color,
            &result.stats,
            &queue.print_mutex,
        ) catch |err| {
            result.err = err;
            return;
        };
    }
}

fn lintFileJson(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    options: lint.Options,
    rule_severities: *const RuleSeverityMap,
    config: ?*const flat_config.FlatConfig,
    fix_mode: FixMode,
    stats: *Stats,
    json_diagnostics: *JsonDiagnosticList,
    json_suppressed_diagnostics: *JsonDiagnosticList,
    json_outputs: *JsonOutputList,
) !void {
    var resolved_config = if (config) |loaded| try loaded.resolveForFile(allocator, path) else null;
    defer if (resolved_config) |*resolved| resolved.deinit(allocator);
    const effective_options = if (resolved_config) |*resolved| resolved.options else options;
    const effective_rule_severities = if (resolved_config) |*resolved| &resolved.rule_severities else rule_severities;

    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_file_size)) catch |err| {
        const message = try std.fmt.allocPrint(allocator, "unable to read file: {s}", .{@errorName(err)});
        defer allocator.free(message);
        try appendJsonDiagnostic(allocator, json_diagnostics, path, 0, 0, null, "error", message, "io", "", &.{}, &.{}, null, &.{});
        stats.errors += 1;
        stats.diagnostics += 1;
        return;
    };
    defer allocator.free(source);

    stats.files += 1;

    if (fix_mode == .none) {
        var result = try lint.lintSourceWithIo(allocator, io, source, path, effective_options);
        defer result.deinit(allocator);
        try appendJsonResultDiagnostics(allocator, json_diagnostics, path, source, result, effective_rule_severities, stats);
        return appendJsonResultSuppressedDiagnostics(allocator, json_suppressed_diagnostics, path, source, result, effective_rule_severities);
    }

    var fixed = try lint.lintSourceAndFixWithIo(allocator, io, source, path, effective_options);
    defer fixed.deinit(allocator);

    if (fixed.fixed) {
        stats.fixed += fixed.applied_diagnostics;
        if (fix_mode == .write) {
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = fixed.output });
        }
        try appendJsonOutput(allocator, json_outputs, path, fixed.output);
    }

    try appendJsonResultDiagnostics(allocator, json_diagnostics, path, fixed.output, fixed.result, effective_rule_severities, stats);
    try appendJsonResultSuppressedDiagnostics(allocator, json_suppressed_diagnostics, path, fixed.output, fixed.result, effective_rule_severities);
}

fn lintFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    options: lint.Options,
    rule_severities: *const RuleSeverityMap,
    config: ?*const flat_config.FlatConfig,
    fix_mode: FixMode,
    use_color: bool,
    stats: *Stats,
    print_mutex: ?*std.Io.Mutex,
) !void {
    var resolved_config = if (config) |loaded| try loaded.resolveForFile(allocator, path) else null;
    defer if (resolved_config) |*resolved| resolved.deinit(allocator);
    const effective_options = if (resolved_config) |*resolved| resolved.options else options;
    const effective_rule_severities = if (resolved_config) |*resolved| &resolved.rule_severities else rule_severities;

    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_file_size)) catch |err| {
        printLocked(io, print_mutex, "{s}: unable to read file: {s}\n", .{ path, @errorName(err) });
        stats.errors += 1;
        stats.diagnostics += 1;
        return;
    };
    defer allocator.free(source);

    stats.files += 1;

    if (fix_mode == .none) {
        var result = try lint.lintSourceWithIo(allocator, io, source, path, effective_options);
        defer result.deinit(allocator);
        return printResultDiagnostics(allocator, io, print_mutex, path, source, result, effective_rule_severities, use_color, stats);
    }

    var fixed = try lint.lintSourceAndFixWithIo(allocator, io, source, path, effective_options);
    defer fixed.deinit(allocator);

    if (fixed.fixed) {
        stats.fixed += fixed.applied_diagnostics;
        if (fix_mode == .write) {
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = fixed.output });
        }
    }

    try printResultDiagnostics(allocator, io, print_mutex, path, fixed.output, fixed.result, effective_rule_severities, use_color, stats);
}

fn printResultDiagnostics(
    allocator: std.mem.Allocator,
    io: std.Io,
    print_mutex: ?*std.Io.Mutex,
    path: []const u8,
    source: []const u8,
    result: lint.Result,
    rule_severities: *const RuleSeverityMap,
    use_color: bool,
    stats: *Stats,
) !void {
    if (result.diagnostics.len == 0) return;

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    try writeStyled(writer, use_color, "\x1b[1m", path);
    try writer.writeByte('\n');

    var location_width: usize = 0;
    for (result.diagnostics) |diagnostic| {
        const position = lint.offsetToLineColumn(source, diagnostic.span.start);
        location_width = @max(location_width, decimalDigits(position.line) + 1 + decimalDigits(position.column));
    }

    for (result.diagnostics) |diagnostic| {
        const severity = effectiveDiagnosticSeverity(rule_severities, diagnostic);
        const position = lint.offsetToLineColumn(source, diagnostic.span.start);
        const current_width = decimalDigits(position.line) + 1 + decimalDigits(position.column);
        try writer.writeAll("  ");
        try writer.splatByteAll(' ', location_width - current_width);
        if (use_color) try writer.writeAll("\x1b[2m");
        try writer.print("{d}:{d}", .{ position.line, position.column });
        if (use_color) try writer.writeAll("\x1b[0m");
        try writer.writeAll("  ");
        if (use_color) try writer.writeAll(if (severity == .@"error") "\x1b[31m" else "\x1b[33m");
        try writer.writeAll(severity.toString());
        if (use_color) try writer.writeAll("\x1b[0m");
        try writer.splatByteAll(' ', 9 - severity.toString().len);
        try writeSingleLine(writer, diagnostic.message);
        try writer.writeAll("  ");
        try writeStyled(writer, use_color, "\x1b[2m", diagnostic.rule_id);
        try writer.writeByte('\n');

        stats.diagnostics += 1;
        if (diagnostic.fixes.len > 0) stats.fixable += 1;
        if (severity == .@"error") {
            stats.errors += 1;
        }
    }
    try writer.writeByte('\n');

    printLocked(io, print_mutex, "{s}", .{output.writer.buffered()});
}

fn appendJsonDiagnostic(
    allocator: std.mem.Allocator,
    diagnostics: *JsonDiagnosticList,
    path: []const u8,
    line: usize,
    column: usize,
    end: ?lint.SourcePosition,
    severity: []const u8,
    message: []const u8,
    rule_id: []const u8,
    source: []const u8,
    fixes: []const lint.Fix,
    suggestions: []const lint.Suggestion,
    suppression: ?lint.Suppression,
    suppressions: []const lint.Suppression,
) !void {
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);

    const owned_message = try allocator.dupe(u8, message);
    errdefer allocator.free(owned_message);

    const owned_rule_id = try allocator.dupe(u8, rule_id);
    errdefer allocator.free(owned_rule_id);

    const owned_fixes = try dupeJsonFixes(allocator, source, fixes);
    errdefer freeOwnedJsonFixes(allocator, owned_fixes);

    const owned_suggestions = try dupeJsonSuggestions(allocator, source, suggestions);
    errdefer freeOwnedJsonSuggestions(allocator, owned_suggestions);

    const owned_suppressions = if (suppressions.len == 0)
        &.{}
    else suppressions: {
        const owned = try allocator.alloc(JsonSuppression, suppressions.len);
        var initialized: usize = 0;
        errdefer {
            for (owned[0..initialized]) |item| {
                allocator.free(item.kind);
                allocator.free(item.justification);
            }
            allocator.free(owned);
        }
        for (suppressions, 0..) |item, index| {
            const kind = try allocator.dupe(u8, "directive");
            errdefer allocator.free(kind);
            owned[index] = .{
                .kind = kind,
                .justification = try allocator.dupe(u8, item.justification),
            };
            initialized += 1;
        }
        break :suppressions owned;
    };
    errdefer {
        for (owned_suppressions) |item| {
            allocator.free(item.kind);
            allocator.free(item.justification);
        }
        if (owned_suppressions.len > 0) allocator.free(owned_suppressions);
    }
    const primary_suppression_index: ?usize = if (suppression) |primary| suppression_index: {
        for (suppressions, 0..) |item, index| {
            if (std.mem.eql(u8, item.justification, primary.justification)) break :suppression_index index;
        }
        break :suppression_index null;
    } else null;

    try diagnostics.append(allocator, .{
        .filePath = owned_path,
        .line = line,
        .column = column,
        .endLine = if (end) |position| position.line else null,
        .endColumn = if (end) |position| position.column else null,
        .severity = severity,
        .message = owned_message,
        .ruleId = owned_rule_id,
        .fixes = owned_fixes,
        .suggestions = owned_suggestions,
        .suppression = if (primary_suppression_index) |index|
            owned_suppressions[index]
        else if (owned_suppressions.len > 0)
            owned_suppressions[0]
        else
            null,
        .suppressions = owned_suppressions,
    });
}

fn diagnosticEndPosition(source: []const u8, diagnostic: lint.Diagnostic, start: lint.SourcePosition) lint.SourcePosition {
    if (diagnostic.span.end < diagnostic.span.start) return lint.offsetToUtf16LineColumn(source, diagnostic.span.end);
    const start_byte = @min(@as(usize, diagnostic.span.start), source.len);
    const end_byte = @min(@as(usize, diagnostic.span.end), source.len);
    // Reuse the start position instead of rescanning the entire file for every end.
    const relative_end = lint.offsetToUtf16LineColumn(source[start_byte..], @intCast(end_byte - start_byte));
    return .{
        .line = start.line + relative_end.line - 1,
        .column = if (relative_end.line == 1) start.column + relative_end.column - 1 else relative_end.column,
    };
}

fn appendJsonResultDiagnostics(
    allocator: std.mem.Allocator,
    json_diagnostics: *JsonDiagnosticList,
    path: []const u8,
    source: []const u8,
    result: lint.Result,
    rule_severities: *const RuleSeverityMap,
    stats: *Stats,
) !void {
    for (result.diagnostics) |diagnostic| {
        const severity = effectiveDiagnosticSeverity(rule_severities, diagnostic);
        const position = lint.offsetToUtf16LineColumn(source, diagnostic.span.start);
        try appendJsonDiagnostic(
            allocator,
            json_diagnostics,
            path,
            position.line,
            position.column,
            diagnosticEndPosition(source, diagnostic, position),
            severity.toString(),
            diagnostic.message,
            diagnostic.rule_id,
            source,
            diagnostic.fixes,
            diagnostic.suggestions,
            null,
            &.{},
        );

        stats.diagnostics += 1;
        if (severity == .@"error") stats.errors += 1;
    }
}

fn appendJsonResultSuppressedDiagnostics(
    allocator: std.mem.Allocator,
    json_diagnostics: *JsonDiagnosticList,
    path: []const u8,
    source: []const u8,
    result: lint.Result,
    rule_severities: *const RuleSeverityMap,
) !void {
    for (result.suppressed_diagnostics) |diagnostic| {
        const severity = effectiveDiagnosticSeverity(rule_severities, diagnostic);
        const position = lint.offsetToUtf16LineColumn(source, diagnostic.span.start);
        try appendJsonDiagnostic(
            allocator,
            json_diagnostics,
            path,
            position.line,
            position.column,
            diagnosticEndPosition(source, diagnostic, position),
            severity.toString(),
            diagnostic.message,
            diagnostic.rule_id,
            source,
            diagnostic.fixes,
            diagnostic.suggestions,
            diagnostic.suppression,
            if (diagnostic.suppressions.len > 0)
                diagnostic.suppressions
            else if (diagnostic.suppression) |suppression|
                &.{suppression}
            else
                &.{},
        );
    }
}

fn effectiveDiagnosticSeverity(rule_severities: *const RuleSeverityMap, diagnostic: lint.Diagnostic) lint.Severity {
    return rule_severities.get(diagnostic.rule_id) orelse diagnostic.severity;
}

fn dupeJsonFixes(allocator: std.mem.Allocator, source: []const u8, fixes: []const lint.Fix) ![]JsonFix {
    if (fixes.len == 0) return &.{};

    const owned = try allocator.alloc(JsonFix, fixes.len);
    var initialized: usize = 0;
    errdefer {
        freeJsonFixes(allocator, owned[0..initialized]);
        allocator.free(owned);
    }

    for (fixes, 0..) |fix, index| {
        owned[index] = .{
            .range = .{
                lint.offsetToUtf16Offset(source, fix.span.start),
                lint.offsetToUtf16Offset(source, fix.span.end),
            },
            .text = try allocator.dupe(u8, fix.replacement),
        };
        initialized += 1;
    }
    return owned;
}

fn freeJsonFixes(allocator: std.mem.Allocator, fixes: []const JsonFix) void {
    for (fixes) |fix| allocator.free(fix.text);
}

fn freeOwnedJsonFixes(allocator: std.mem.Allocator, fixes: []const JsonFix) void {
    freeJsonFixes(allocator, fixes);
    if (fixes.len > 0) allocator.free(fixes);
}

fn dupeJsonSuggestions(
    allocator: std.mem.Allocator,
    source: []const u8,
    suggestions: []const lint.Suggestion,
) ![]JsonSuggestion {
    if (suggestions.len == 0) return &.{};

    const owned = try allocator.alloc(JsonSuggestion, suggestions.len);
    var initialized: usize = 0;
    errdefer {
        freeJsonSuggestions(allocator, owned[0..initialized]);
        allocator.free(owned);
    }

    for (suggestions, 0..) |suggestion, index| {
        const desc = try allocator.dupe(u8, suggestion.message);
        errdefer allocator.free(desc);
        owned[index] = .{
            .desc = desc,
            .fix = try dupeJsonFixes(allocator, source, suggestion.fixes),
        };
        initialized += 1;
    }
    return owned;
}

fn freeJsonSuggestions(allocator: std.mem.Allocator, suggestions: []const JsonSuggestion) void {
    for (suggestions) |suggestion| {
        allocator.free(suggestion.desc);
        freeOwnedJsonFixes(allocator, suggestion.fix);
    }
}

fn freeOwnedJsonSuggestions(allocator: std.mem.Allocator, suggestions: []const JsonSuggestion) void {
    freeJsonSuggestions(allocator, suggestions);
    if (suggestions.len > 0) allocator.free(suggestions);
}

fn appendJsonOutput(allocator: std.mem.Allocator, outputs: *JsonOutputList, path: []const u8, output: []const u8) !void {
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    const owned_output = try allocator.dupe(u8, output);
    errdefer allocator.free(owned_output);

    try outputs.append(allocator, .{ .filePath = owned_path, .output = owned_output });
}

fn freeJsonDiagnostics(allocator: std.mem.Allocator, diagnostics: *JsonDiagnosticList) void {
    for (diagnostics.items) |diagnostic| {
        allocator.free(diagnostic.filePath);
        allocator.free(diagnostic.message);
        allocator.free(diagnostic.ruleId);
        freeOwnedJsonFixes(allocator, diagnostic.fixes);
        freeOwnedJsonSuggestions(allocator, diagnostic.suggestions);
        for (diagnostic.suppressions) |suppression| {
            allocator.free(suppression.kind);
            allocator.free(suppression.justification);
        }
        if (diagnostic.suppressions.len > 0) allocator.free(diagnostic.suppressions);
    }
    diagnostics.deinit(allocator);
}

fn freeJsonOutputs(allocator: std.mem.Allocator, outputs: *JsonOutputList) void {
    for (outputs.items) |output| {
        allocator.free(output.filePath);
        allocator.free(output.output);
    }
    outputs.deinit(allocator);
}

fn writeJsonReport(
    io: std.Io,
    stats: Stats,
    file_paths: []const []const u8,
    diagnostics: []const JsonDiagnostic,
    suppressed_diagnostics: []const JsonDiagnostic,
    outputs: []const JsonOutput,
) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try std.json.Stringify.value(JsonReport{
        .files = stats.files,
        .filePaths = file_paths,
        .diagnostics = diagnostics,
        .suppressedDiagnostics = suppressed_diagnostics,
        .outputs = outputs,
    }, .{ .emit_null_optional_fields = false }, stdout);
    try stdout.writeByte('\n');
    try stdout.flush();
}

fn detectColorSupport(io: std.Io, environ: std.process.Environ.Map) bool {
    if (environ.get("NO_COLOR") != null or environ.get("NODE_DISABLE_COLORS") != null) return false;
    if (nonZeroEnv(environ.get("FORCE_COLOR")) or nonZeroEnv(environ.get("CLICOLOR_FORCE"))) return true;
    std.Io.File.stderr().enableAnsiEscapeCodes(io) catch return false;
    return true;
}

fn nonZeroEnv(value: ?[]const u8) bool {
    const present = value orelse return false;
    return present.len > 0 and !std.mem.eql(u8, present, "0");
}

fn printTextSummary(stats: Stats, fix_mode: FixMode, use_color: bool) void {
    if (stats.diagnostics == 0) {
        if (use_color) std.debug.print("\x1b[32m", .{});
        std.debug.print("✓", .{});
        if (use_color) std.debug.print("\x1b[0m", .{});
        std.debug.print(" {d} file{s} checked, no problems found\n", .{ stats.files, pluralSuffix(stats.files) });
        if (stats.fixed > 0) {
            std.debug.print("  {d} problem{s} fixed.\n", .{ stats.fixed, pluralSuffix(stats.fixed) });
        }
        return;
    }

    if (use_color) std.debug.print("{s}", .{if (stats.errors > 0) "\x1b[31m" else "\x1b[33m"});
    std.debug.print("✖", .{});
    if (use_color) std.debug.print("\x1b[0m", .{});
    const warnings = stats.diagnostics - stats.errors;
    std.debug.print(" {d} problem{s} ({d} error{s}, {d} warning{s})\n", .{
        stats.diagnostics,
        pluralSuffix(stats.diagnostics),
        stats.errors,
        pluralSuffix(stats.errors),
        warnings,
        pluralSuffix(warnings),
    });
    if (stats.fixable > 0 and fix_mode == .none) {
        std.debug.print("  {d} problem{s} potentially fixable with the `--fix` option.\n", .{
            stats.fixable,
            pluralSuffix(stats.fixable),
        });
    }
    if (stats.fixed > 0) {
        std.debug.print("  {d} problem{s} fixed.\n", .{ stats.fixed, pluralSuffix(stats.fixed) });
    }
    std.debug.print("  {d} file{s} checked\n", .{ stats.files, pluralSuffix(stats.files) });
}

fn pluralSuffix(count: usize) []const u8 {
    return if (count == 1) "" else "s";
}

fn decimalDigits(value: usize) usize {
    var number = value;
    var digits: usize = 1;
    while (number >= 10) : (number /= 10) digits += 1;
    return digits;
}

fn writeStyled(writer: *std.Io.Writer, use_color: bool, style: []const u8, text_value: []const u8) !void {
    if (use_color) try writer.writeAll(style);
    try writer.writeAll(text_value);
    if (use_color) try writer.writeAll("\x1b[0m");
}

fn writeSingleLine(writer: *std.Io.Writer, message: []const u8) !void {
    var index: usize = 0;
    while (index < message.len) {
        const line_end = std.mem.indexOfAnyPos(u8, message, index, "\r\n") orelse {
            try writer.writeAll(message[index..]);
            return;
        };
        try writer.writeAll(message[index..line_end]);
        index = line_end;
        while (index < message.len and (message[index] == '\r' or message[index] == '\n' or message[index] == ' ' or message[index] == '\t')) : (index += 1) {}
        if (index < message.len and line_end > 0 and message[line_end - 1] != ' ') try writer.writeByte(' ');
    }
}

fn printLocked(
    io: std.Io,
    mutex: ?*std.Io.Mutex,
    comptime fmt: []const u8,
    args: anytype,
) void {
    if (mutex) |m| {
        m.lockUncancelable(io);
        defer m.unlock(io);
    }
    std.debug.print(fmt, args);
}

fn shouldSkipDirectoryEntry(name: []const u8) bool {
    return std.mem.eql(u8, name, ".git") or
        std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "node_modules") or
        std.mem.eql(u8, name, "vendor") or
        std.mem.eql(u8, name, "zig-out");
}

fn printHelp() void {
    std.debug.print(
        \\Usage:
        \\  utoo-lint [options] [file-or-directory ...]
        \\
        \\Options:
        \\  --config=PATH            Read configuration from PATH
        \\  --no-config              Do not read utlint.config.json (or legacy config names)
        \\  --format=text|json       Select diagnostic output format
        \\  --json                   Alias for --format=json
        \\  --color                  Force colors in text output
        \\  --no-color               Disable colors in text output
        \\  --fix                    Apply autofixes and write files to disk
        \\  --fix-dry-run            Apply autofixes without writing files
        \\  --threads=N              Number of worker threads to use
        \\  --rules=a,b,c            Enable only the comma-separated rule list
        \\  --accessor-pairs=off    Disable accessor-pairs
        \\  --accessor-pairs-get-without-set=on Enable accessor-pairs getWithoutSet
        \\  --accessor-pairs-set-without-get=off Disable accessor-pairs setWithoutGet
        \\  --array-callback-return=off Disable array-callback-return
        \\  --array-callback-return-allow-implicit=on Allow bare return statements in array callbacks
        \\  --array-callback-return-allow-implicit=off Require explicit values from array callbacks
        \\  --array-callback-return-check-for-each=on Check forEach callbacks for return values
        \\  --array-callback-return-allow-void=on Allow void returns in checked forEach callbacks
        \\  --arrow-body-style=off   Disable arrow-body-style
        \\  --arrow-body-style=on    Enable arrow-body-style
        \\  --arrow-body-style=always Require braces around arrow bodies
        \\  --arrow-body-style=as-needed Disallow unnecessary arrow body braces
        \\  --arrow-body-style=never Disallow arrow body braces when possible
        \\  --arrow-body-style-require-return-for-object-literal=on Keep braces for returned object literals
        \\  --block-scoped-var=off   Disable block-scoped-var
        \\  --camelcase=off          Disable camelcase
        \\  --camelcase=on           Enable camelcase
        \\  --camelcase-properties=never Ignore property names
        \\  --camelcase-ignore-destructuring=on Ignore destructured bindings
        \\  --camelcase-ignore-imports=on Ignore import bindings
        \\  --camelcase-allow=PATTERN Add an allowed camelcase name pattern
        \\  --capitalized-comments=off Disable capitalized-comments
        \\  --capitalized-comments=never Require lowercase comment starts
        \\  --capitalized-comments-ignore-inline-comments=on Ignore inline comments
        \\  --class-methods-use-this=on Enable class-methods-use-this
        \\  --class-methods-use-this=off Disable class-methods-use-this
        \\  --class-methods-use-this-enforce-for-class-fields=off Ignore function-valued class fields
        \\  --class-methods-use-this-except-method=NAME Ignore a class method name
        \\  --class-methods-use-this-ignore-override-methods=on Ignore TypeScript override methods
        \\  --class-methods-use-this-ignore-classes-with-implements=MODE Ignore all or public-fields in implementing classes
        \\  --complexity=off          Disable complexity
        \\  --complexity-max=N        Set complexity maximum
        \\  --complexity-variant=modified Use modified switch complexity
        \\  --consistent-return=off  Disable consistent-return
        \\  --consistent-this=off    Disable consistent-this
        \\  --consistent-this=on     Enable consistent-this with default alias
        \\  --consistent-this-alias=NAME Add a consistent-this alias
        \\  --constructor-super=off  Disable constructor-super
        \\  --curly=off              Disable curly
        \\  --dot-notation=off       Disable dot-notation
        \\  --default-case=off        Disable default-case
        \\  --default-case-last=off   Disable default-case-last
        \\  --default-param-last=off  Disable default-param-last
        \\  --eol-last=off            Disable eol-last
        \\  --eslint-comments-no-restricted-disable=off Disable eslint-comments/no-restricted-disable
        \\  --for-direction=off       Disable for-direction
        \\  --func-name-matching=off Disable func-name-matching
        \\  --func-name-matching=never Disallow matching function expression names
        \\  --func-names=off          Disable func-names
        \\  --func-names=as-needed    Allow inferable anonymous function names
        \\  --func-names=never        Disallow named function expressions
        \\  --func-style=off          Disable func-style
        \\  --func-style=expression   Require function expressions
        \\  --func-style=declaration  Require function declarations where possible
        \\  --func-style-allow-arrow-functions=on Allow arrow function expressions
        \\  --getter-return=off       Disable getter-return
        \\  --grouped-accessor-pairs=off Disable grouped-accessor-pairs
        \\  --grouped-accessor-pairs=get-before-set Require getters before setters
        \\  --grouped-accessor-pairs=set-before-get Require setters before getters
        \\  --guard-for-in=off        Disable guard-for-in
        \\  --init-declarations=always Require initialized variable declarations
        \\  --init-declarations=off   Disable init-declarations
        \\  --init-declarations=never Disallow initialized variable declarations
        \\  --init-declarations-ignore-for-loop-init=on Ignore for-loop initializers in never mode
        \\  --linebreak-style=off     Disable linebreak-style
        \\  --new-cap=off             Disable new-cap
        \\  --new-parens=off          Disable new-parens
        \\  --no-async-promise-executor=off Disable no-async-promise-executor
        \\  --no-array-constructor=off Disable no-array-constructor
        \\  --no-await-in-loop=off    Disable no-await-in-loop
        \\  --no-alert=off            Disable no-alert
        \\  --no-bitwise=off          Disable no-bitwise
        \\  --no-buffer-constructor=off Disable no-buffer-constructor
        \\  --no-caller=off           Disable no-caller
        \\  --no-case-declarations=off Disable no-case-declarations
        \\  --no-class-assign=off     Disable no-class-assign
        \\  --no-confusing-arrow=off  Disable no-confusing-arrow
        \\  --no-confusing-arrow-allow-parens=off Set no-confusing-arrow allowParens false
        \\  --no-cond-assign=off      Disable no-cond-assign
        \\  --no-compare-neg-zero=off Disable no-compare-neg-zero
        \\  --no-constant-binary-expression=off Disable no-constant-binary-expression
        \\  --no-constant-condition=off Disable no-constant-condition
        \\  --no-const-assign=off    Disable no-const-assign
        \\  --no-control-regex=off   Disable no-control-regex
        \\  --no-comma-operator=off   Disable no-comma-operator
        \\  --no-console=off          Disable no-console
        \\  --no-console-allow=warn,error Allow selected console methods
        \\  --no-continue=off         Disable no-continue
        \\  --no-constructor-return=off Disable no-constructor-return
        \\  --no-debugger=off         Disable no-debugger
        \\  --no-dupe-else-if=off     Disable no-dupe-else-if
        \\  --no-duplicate-case=off   Disable no-duplicate-case
        \\  --no-duplicate-imports=off Disable no-duplicate-imports
        \\  --no-dupe-args=off        Disable no-dupe-args
        \\  --no-dupe-class-members=off Disable no-dupe-class-members
        \\  --no-dupe-keys=off        Disable no-dupe-keys
        \\  --no-delete-var=off       Disable no-delete-var
        \\  --no-div-regex=off        Disable no-div-regex
        \\  --no-empty=off            Disable no-empty
        \\  --no-empty-allow-empty-catch=on Allow empty catch blocks
        \\  --no-empty-block-statements=off Disable no-empty-block-statements
        \\  --no-empty-character-class=off Disable no-empty-character-class
        \\  --no-empty-function=off Disable no-empty-function
        \\  --no-empty-function-allow=functions,arrowFunctions Allow selected empty function kinds
        \\      also supports asyncFunctions,generatorFunctions,methods,asyncMethods,generatorMethods,getters,setters,constructors
        \\  --no-empty-pattern=off  Disable no-empty-pattern
        \\  --no-empty-static-block=off Disable no-empty-static-block
        \\  --no-else-return=off    Disable no-else-return
        \\  --no-eq-null=off        Disable no-eq-null
        \\  --no-eval=off           Disable no-eval
        \\  --no-ex-assign=off      Disable no-ex-assign
        \\  --no-extend-native=off  Disable no-extend-native
        \\  --no-extra-bind=off     Disable no-extra-bind
        \\  --no-extra-label=off    Disable no-extra-label
        \\  --no-extra-semi=off      Disable no-extra-semi
        \\  --no-extra-boolean-cast=off Disable no-extra-boolean-cast
        \\  --no-floating-decimal=off Disable no-floating-decimal
        \\  --no-fallthrough=off      Disable no-fallthrough
        \\  --no-fallthrough-allow-empty-case=on Allow empty switch cases
        \\  --no-for-in=off           Disable no-for-in
        \\  --no-func-assign=off      Disable no-func-assign
        \\  --no-global-assign=off    Disable no-global-assign
        \\  --no-global-is-finite=off Disable no-global-is-finite
        \\  --no-global-is-nan=off    Disable no-global-is-nan
        \\  --no-implicit-coercion=off Disable no-implicit-coercion
        \\  --no-implicit-coercion-boolean=off Disable boolean coercion checks
        \\  --no-implicit-coercion-number=off Disable number coercion checks
        \\  --no-implicit-coercion-string=off Disable string coercion checks
        \\  --no-implicit-globals=off Disable no-implicit-globals
        \\  --no-implicit-globals=on Enable no-implicit-globals
        \\  --no-implicit-globals-lexical-bindings=on Check top-level lexical declarations
        \\  --no-implied-eval=off      Disable no-implied-eval
        \\  --no-import-assign=off     Disable no-import-assign
        \\  --alipay-ant-disallow-typos=off Disable @alipay/ant/disallow-typos
        \\  --alipay-ant-exhaustive-deps=off Disable @alipay/ant/exhaustive-deps
        \\  --alipay-ant-jsx-handler-names=off Disable @alipay/ant/jsx-handler-names
        \\  --alipay-ant-no-deprecated-dependence=off Disable @alipay/ant/no-deprecated-dependence
        \\  --alipay-ant-no-deprecated-variable=off Disable @alipay/ant/no-deprecated-variable
        \\  --alipay-ant-no-import-files-from-pages-in-common=off Disable @alipay/ant/no-import-files-from-pages-in-common
        \\  --alipay-ant-no-negative-conditionals=off Disable @alipay/ant/no-negative-conditionals
        \\  --alipay-ant-no-import-src=off Disable @alipay/ant/no-import-src
        \\  --alipay-ant-no-phantom-dependencies=off Disable @alipay/ant/no-phantom-dependencies
        \\  --alipay-ant-no-too-large-file=off Disable @alipay/ant/no-too-large-file
        \\  --alipay-ant-prefer-elseif-end-with-else=off Disable @alipay/ant/prefer-elseif-end-with-else
        \\  --alipay-ant-prefer-catch-unsafe-func-call=off Disable @alipay/ant/prefer-catch-unsafe-func-call
        \\  --alipay-ant-prefer-click-with-debounce=off Disable @alipay/ant/prefer-click-with-debounce
        \\  --alipay-ant-prefer-import-as-required=off Disable @alipay/ant/prefer-import-as-required
        \\  --alipay-ant-no-spread-params=off Disable @alipay/ant/no-spread-params
        \\  --alipay-ant-prefer-managed-resource=off Disable @alipay/ant/prefer-managed-resource
        \\  --alipay-ant-prefer-safe-image-renderer=off Disable @alipay/ant/prefer-safe-image-renderer
        \\  --alipay-ant-prefer-import-from-stdlib=off Disable @alipay/ant/prefer-import-from-stdlib
        \\  --alipay-spmlint-use-labeled-spm=off Disable @alipay/spmLint/use-labeled-spm
        \\  --alipay-spmlint-valid-manual-click=off Disable @alipay/spmLint/valid-manual-click
        \\  --alipay-spmlint-valid-manual-expo=off Disable @alipay/spmLint/valid-manual-expo
        \\  --alipay-spmlint-valid-manual-param=off Disable @alipay/spmLint/valid-manual-param
        \\  --alipay-spmlint-valid-manual-pv=off Disable @alipay/spmLint/valid-manual-pv
        \\  --import-default=off      Disable import/default
        \\  --import-export=off       Disable import/export
        \\  --import-first=off         Disable import/first
        \\  --import-named=off        Disable import/named
        \\  --import-namespace=off    Disable import/namespace
        \\  --import-newline-after-import=off Disable import/newline-after-import
        \\  --import-no-amd=off        Disable import/no-amd
        \\  --import-no-cycle=off      Disable import/no-cycle
        \\  --import-no-duplicates=off Disable import/no-duplicates
        \\  --import-no-named-as-default=off Disable import/no-named-as-default
        \\  --import-no-named-as-default-member=off Disable import/no-named-as-default-member
        \\  --import-no-unresolved=off Disable import/no-unresolved
        \\  --import-no-self-import=off Disable import/no-self-import
        \\  --jsx-a11y-alt-text=off   Disable jsx-a11y/alt-text
        \\  --jsx-a11y-anchor-has-content=off Disable jsx-a11y/anchor-has-content
        \\  --jsx-a11y-aria-props=off Disable jsx-a11y/aria-props
        \\  --jsx-a11y-aria-proptypes=off Disable jsx-a11y/aria-proptypes
        \\  --jsx-a11y-aria-role=off Disable jsx-a11y/aria-role
        \\  --jsx-a11y-aria-unsupported-elements=off Disable jsx-a11y/aria-unsupported-elements
        \\  --jsx-a11y-iframe-has-title=off Disable jsx-a11y/iframe-has-title
        \\  --jsx-a11y-img-redundant-alt=off Disable jsx-a11y/img-redundant-alt
        \\  --jsx-a11y-no-access-key=off Disable jsx-a11y/no-access-key
        \\  --jsx-a11y-no-distracting-elements=off Disable jsx-a11y/no-distracting-elements
        \\  --jsx-a11y-role-has-required-aria-props=off Disable jsx-a11y/role-has-required-aria-props
        \\  --jsx-a11y-role-supports-aria-props=off Disable jsx-a11y/role-supports-aria-props
        \\  --jsx-a11y-scope=off      Disable jsx-a11y/scope
        \\  --no-invalid-regexp=off    Disable no-invalid-regexp
        \\  --no-invalid-this=on       Enable no-invalid-this
        \\  --no-invalid-this=off      Disable no-invalid-this
        \\  --no-invalid-this-cap-is-constructor=off Do not treat capitalized functions as constructors
        \\  --no-irregular-whitespace=off Disable no-irregular-whitespace
        \\  --no-inline-comments=off   Disable no-inline-comments
        \\  --no-inner-declarations=off Disable no-inner-declarations
        \\  --no-iterator=off          Disable no-iterator
        \\  --no-label-var=off         Disable no-label-var
        \\  --no-labels=off           Disable no-labels
        \\  --no-lone-blocks=off      Disable no-lone-blocks
        \\  --no-lonely-if=off        Disable no-lonely-if
        \\  --id-length=on            Enable id-length
        \\  --id-length=off           Disable id-length
        \\  --id-length-min=N         Set id-length minimum
        \\  --id-length-max=N         Set id-length maximum
        \\  --id-length-properties=never Ignore property names
        \\  --id-length-exception=NAME Add an id-length exception
        \\  --id-length-exception-pattern=PATTERN Add an id-length exception pattern
        \\  --id-match=on             Enable id-match
        \\  --id-match=off            Disable id-match
        \\  --id-match-pattern=PATTERN Set id-match pattern
        \\  --id-match-properties=on  Check object and method property names
        \\  --id-match-class-fields=on Check class field names
        \\  --id-match-only-declarations=on Check declarations only
        \\  --id-match-ignore-destructuring=on Ignore destructured bindings
        \\  --id-denylist=off         Disable id-denylist
        \\  --id-denylist-name=NAME   Add a restricted identifier name
        \\  --logical-assignment-operators=off Disable logical-assignment-operators
        \\  --logical-assignment-operators=never Disallow logical assignment operators
        \\  --logical-assignment-operators-enforce-for-if-statements=on Enable logical-assignment-operators if-statement checks
        \\  --max-classes-per-file=off Disable max-classes-per-file
        \\  --max-classes-per-file-max=N Set max-classes-per-file maximum
        \\  --max-classes-per-file-ignore-expressions=on Ignore class expressions
        \\  --max-depth=off           Disable max-depth
        \\  --max-depth-max=N         Set max-depth maximum
        \\  --max-lines=on            Enable max-lines
        \\  --max-lines=off           Disable max-lines
        \\  --max-lines-max=N         Set max-lines maximum
        \\  --max-lines-skip-blank-lines=on Ignore blank lines for max-lines
        \\  --max-lines-skip-comments=on Ignore comment-only lines for max-lines
        \\  --max-lines-per-function=on Enable max-lines-per-function
        \\  --max-lines-per-function=off Disable max-lines-per-function
        \\  --max-lines-per-function-max=N Set max-lines-per-function maximum
        \\  --max-lines-per-function-skip-blank-lines=on Ignore blank lines in functions
        \\  --max-lines-per-function-skip-comments=on Ignore comment-only lines in functions
        \\  --max-lines-per-function-iifes=on Include IIFEs in max-lines-per-function
        \\  --max-nested-callbacks=off Disable max-nested-callbacks
        \\  --max-nested-callbacks-max=N Set max-nested-callbacks maximum
        \\  --max-params=off          Disable max-params
        \\  --max-params-max=N        Set max-params maximum
        \\  --max-statements=off      Disable max-statements
        \\  --max-statements-max=N    Set max-statements maximum
        \\  --max-statements-ignore-top-level-functions=on Ignore single top-level functions
        \\  --no-loop-func=off        Disable no-loop-func
        \\  --no-loss-of-precision=off Disable no-loss-of-precision
        \\  --no-magic-numbers=on     Enable no-magic-numbers
        \\  --no-magic-numbers=off    Disable no-magic-numbers
        \\  --no-magic-numbers-detect-objects=on Check object properties and member assignments
        \\  --no-magic-numbers-enforce-const=on Require const for direct numeric declarations
        \\  --no-magic-numbers-ignore=0,1,-1,100n Ignore selected Number or BigInt values
        \\  --no-magic-numbers-ignore-array-indexes=on Ignore valid array indexes
        \\  --no-magic-numbers-ignore-default-values=on Ignore default values
        \\  --no-magic-numbers-ignore-class-field-initial-values=on Ignore class field initial values
        \\  --no-magic-numbers-ignore-enums=on Ignore TypeScript enum values
        \\  --no-magic-numbers-ignore-numeric-literal-types=on Ignore numeric literal type aliases
        \\  --no-magic-numbers-ignore-readonly-class-properties=on Ignore readonly class properties
        \\  --no-magic-numbers-ignore-type-indexes=on Ignore TypeScript indexed access values
        \\  --no-multi-str=off        Disable no-multi-str
        \\  --no-multi-assign=off     Disable no-multi-assign
        \\  --no-multi-spaces=off     Disable no-multi-spaces
        \\  --no-multi-spaces-ignore-eol-comments=on Allow spacing before end-of-line comments
        \\  --no-mixed-spaces-and-tabs=off Disable no-mixed-spaces-and-tabs
        \\  --no-misleading-character-class=off Disable no-misleading-character-class
        \\  --no-multiple-empty-lines=off Disable no-multiple-empty-lines
        \\  --no-multiple-empty-lines-max=N Configure no-multiple-empty-lines max
        \\  --no-multiple-empty-lines-max-bof=N Configure no-multiple-empty-lines maxBOF
        \\  --no-multiple-empty-lines-max-eof=N Configure no-multiple-empty-lines maxEOF
        \\  --no-nonoctal-decimal-escape=off Disable no-nonoctal-decimal-escape
        \\  --no-new=off              Disable no-new
        \\  --no-nested-ternary=off   Disable no-nested-ternary
        \\  --no-negated-condition=off Disable no-negated-condition
        \\  --no-new-native-nonconstructor=off Disable no-new-native-nonconstructor
        \\  --no-new-func=off         Disable no-new-func
        \\  --no-new-require=off      Disable no-new-require
        \\  --no-obj-calls=off        Disable no-obj-calls
        \\  --no-new-object=off       Disable no-new-object
        \\  --no-new-symbol=off       Disable no-new-symbol
        \\  --no-new-wrappers=off     Disable no-new-wrappers
        \\  --no-octal=off            Disable no-octal
        \\  --no-octal-escape=off     Disable no-octal-escape
        \\  --no-object-constructor=off Disable no-object-constructor
        \\  --no-param-reassign=off   Disable no-param-reassign
        \\  --no-param-reassign-props=on Report parameter property writes
        \\  --no-param-reassign-ignore-property-modifications-for=req,res Allow listed parameter property writes
        \\  --no-path-concat=off      Disable no-path-concat
        \\  --no-plusplus=off         Disable no-plusplus
        \\  --no-plusplus-allow-for-loop-afterthoughts=on Allow ++/-- in for afterthoughts
        \\  --no-promise-executor-return=off Disable no-promise-executor-return
        \\  --no-proto=off            Disable no-proto
        \\  --no-process-env=off      Disable no-process-env
        \\  --no-process-exit=off     Disable no-process-exit
        \\  --no-prototype-builtins=off Disable no-prototype-builtins
        \\  --no-redeclare=off        Disable no-redeclare
        \\  --no-redeclare-builtin-globals=on Report redeclarations of built-in globals
        \\  --no-restricted-exports=off Disable no-restricted-exports
        \\  --no-restricted-exports=on Enable no-restricted-exports
        \\  --no-restricted-exports-name=NAME Restrict an exported name
        \\  --no-restricted-exports-default-direct=on Restrict direct default exports
        \\  --no-restricted-exports-default-named=on Restrict local named default exports
        \\  --no-restricted-exports-default-from=on Restrict re-exported default exports
        \\  --no-restricted-exports-named-from=on Restrict re-exported named defaults
        \\  --no-restricted-exports-namespace-from=on Restrict namespace default re-exports
        \\  --no-restricted-globals=off Disable no-restricted-globals
        \\  --no-restricted-globals=on Enable no-restricted-globals
        \\  --no-restricted-globals-name=NAME Restrict a global name
        \\  --no-restricted-imports=off Disable no-restricted-imports
        \\  --no-restricted-imports=on Enable no-restricted-imports
        \\  --no-restricted-imports-name=NAME Restrict an import source
        \\  --no-restricted-imports-pattern=PATTERN Restrict import sources matching a simple * pattern
        \\  --no-restricted-modules=off Disable no-restricted-modules
        \\  --no-restricted-modules=on Enable no-restricted-modules
        \\  --no-restricted-modules-name=NAME Restrict a require() source
        \\  --no-restricted-modules-pattern=PATTERN Restrict require() sources matching a simple * pattern
        \\  --no-restricted-properties=off Disable no-restricted-properties
        \\  --no-restricted-syntax=off Disable no-restricted-syntax
        \\  --no-restricted-syntax=on Enable no-restricted-syntax
        \\  --no-restricted-syntax-selector=SELECTOR Restrict a simple AST node selector
        \\  --no-regex-spaces=off     Disable no-regex-spaces
        \\  --no-return-await=off     Disable no-return-await
        \\  --no-return-assign=off    Disable no-return-assign
        \\  --no-return-assign=always Report all returned assignments, including parenthesized ones
        \\  --no-useless-return=off   Disable no-useless-return
        \\  --no-script-url=off       Disable no-script-url
        \\  --no-self-assign=off      Disable no-self-assign
        \\  --no-self-compare=off     Disable no-self-compare
        \\  --no-setter-return=off    Disable no-setter-return
        \\  --no-shadow=off           Disable no-shadow
        \\  --no-shadow-restricted-names=off Disable no-shadow-restricted-names
        \\  --no-sequences=off        Disable no-sequences
        \\  --no-sequences-allow-in-parentheses=off Report parenthesized sequence expressions
        \\  --no-sparse-arrays=off    Disable no-sparse-arrays
        \\  --no-ternary=off          Disable no-ternary
        \\  --no-template-curly-in-string=off Disable no-template-curly-in-string
        \\  --no-throw-literal=off    Disable no-throw-literal
        \\  --no-this-before-super=off Disable no-this-before-super
        \\  --no-tabs=off             Disable no-tabs
        \\  --no-trailing-spaces=off  Disable no-trailing-spaces
        \\  --no-unreachable=off      Disable no-unreachable
        \\  --no-unreachable-loop=off Disable no-unreachable-loop
        \\  --no-undef-init=off       Disable no-undef-init
        \\  --no-underscore-dangle=off Disable no-underscore-dangle
        \\  --no-underscore-dangle-allow-after-this=on Allow dangling underscores after this
        \\  --no-underscore-dangle-allow-after-super=on Allow dangling underscores after super
        \\  --no-underscore-dangle-allow-after-this-constructor=on Allow dangling underscores after this.constructor
        \\  --no-underscore-dangle-allow-function-params=off Report dangling underscores in function parameters
        \\  --no-underscore-dangle-allow-in-array-destructuring=off Report dangling underscores in array destructuring
        \\  --no-underscore-dangle-allow-in-object-destructuring=off Report dangling underscores in object destructuring
        \\  --no-underscore-dangle-enforce-in-method-names=on Report dangling underscores in method names
        \\  --no-underscore-dangle-enforce-in-class-fields=on Report dangling underscores in class fields
        \\  --no-undefined=off        Disable no-undefined
        \\  --unicode-bom=off         Disable unicode-bom
        \\  --no-unneeded-ternary=off Disable no-unneeded-ternary
        \\  --no-unexpected-multiline=off Disable no-unexpected-multiline
        \\  --no-unmodified-loop-condition=on Enable no-unmodified-loop-condition
        \\  --no-unmodified-loop-condition=off Disable no-unmodified-loop-condition
        \\  --no-unused-labels=off   Disable no-unused-labels
        \\  --no-unsafe-finally=off   Disable no-unsafe-finally
        \\  --no-unsafe-negation=off  Disable no-unsafe-negation
        \\  --no-unsafe-optional-chaining=off Disable no-unsafe-optional-chaining
        \\  --no-unsafe-optional-chaining-disallow-arithmetic-operators=on Report optional chains in arithmetic operators
        \\  --no-useless-computed-key=off Disable no-useless-computed-key
        \\  --no-useless-computed-key-enforce-for-class-members=off Disable class member checks
        \\  --no-useless-backreference=off Disable no-useless-backreference
        \\  --no-useless-call=off     Disable no-useless-call
        \\  --no-useless-concat=off   Disable no-useless-concat
        \\  --no-useless-constructor=off Disable no-useless-constructor
        \\  --no-useless-assignment=off Disable no-useless-assignment
        \\  --no-useless-catch=off    Disable no-useless-catch
        \\  --no-useless-escape=off   Disable no-useless-escape
        \\  --no-useless-rename=off   Disable no-useless-rename
        \\  --no-unused-private-class-members=off Disable no-unused-private-class-members
        \\  --no-unused-expressions=off Disable no-unused-expressions
        \\  --no-unused-expressions-allow-short-circuit=on Allow short-circuit expressions
        \\  --no-unused-expressions-allow-ternary=on Allow ternary expressions
        \\  --no-unused-expressions-allow-tagged-templates=on  Allow tagged template expressions
        \\  --no-warning-comments=off Disable no-warning-comments
        \\  --no-warning-comments-location=anywhere Report warning terms anywhere in comments
        \\  --no-warning-comments-decoration=asterisk Ignore leading * comment decorations
        \\  --no-warning-comments-decoration=slash Ignore leading / comment decorations
        \\  --no-warning-comments-decoration=slash-asterisk Ignore leading / and * comment decorations
        \\  --no-warning-comments-terms=todo,fixme Configure no-warning-comments terms
        \\  --no-void=off             Disable no-void
        \\  --no-void-allow-as-statement=on Allow void as expression statement
        \\  --no-with=off             Disable no-with
        \\  --no-var=off              Disable no-var
        \\  --one-var=off             Disable one-var
        \\  --object-shorthand=off    Disable object-shorthand
        \\  --operator-assignment=off Disable operator-assignment
        \\  --eqeqeq=off              Disable eqeqeq
        \\  --use-isnan=off           Disable use-isnan
        \\  --no-unused-vars=off      Disable no-unused-vars
        \\  --no-unassigned-vars=off Disable no-unassigned-vars
        \\  --no-use-before-define=off Disable no-use-before-define
        \\  --no-undef=off            Disable no-undef
        \\  --prefer-arrow-callback=off Disable prefer-arrow-callback
        \\  --prefer-arrow-callback=on Enable prefer-arrow-callback
        \\  --prefer-arrow-callback-allow-named-functions=on Allow named function callbacks
        \\  --prefer-arrow-callback-allow-unbound-this=off Report unbound this callbacks
        \\  --prefer-const=off        Disable prefer-const
        \\  --prefer-const-destructuring=all Require all destructured bindings to be const candidates
        \\  --prefer-exponentiation-operator=off Disable prefer-exponentiation-operator
        \\  --prefer-named-capture-group=on Enable prefer-named-capture-group
        \\  --prefer-named-capture-group=off Disable prefer-named-capture-group
        \\  --prefer-numeric-literals=off Disable prefer-numeric-literals
        \\  --prefer-promise-reject-errors=off Disable prefer-promise-reject-errors
        \\  --preserve-caught-error=off Disable preserve-caught-error
        \\  --preserve-caught-error-require-catch-parameter=on Require catch parameters
        \\  --prefer-destructuring=off Disable prefer-destructuring
        \\  --prefer-object-has-own=off Disable prefer-object-has-own
        \\  --prefer-object-spread=off Disable prefer-object-spread
        \\  --prefer-regex-literals=off Disable prefer-regex-literals
        \\  --prefer-rest-params=off  Disable prefer-rest-params
        \\  --prefer-spread=off       Disable prefer-spread
        \\  --prefer-template=off     Disable prefer-template
        \\  --react-default-props-match-prop-types=off Disable react/default-props-match-prop-types
        \\  --react-display-name=off Disable react/display-name
        \\  --react-jsx-boolean-value=off Disable react/jsx-boolean-value
        \\  --react-jsx-filename-extension=off Disable react/jsx-filename-extension
        \\  --react-jsx-no-duplicate-props=off Disable react/jsx-no-duplicate-props
        \\  --react-jsx-no-comment-textnodes=off Disable react/jsx-no-comment-textnodes
        \\  --react-jsx-no-bind=off Disable react/jsx-no-bind
        \\  --react-jsx-key=off Disable react/jsx-key
        \\  --react-button-has-type=off Disable react/button-has-type
        \\  --react-require-render-return=off Disable react/require-render-return
        \\  --react-jsx-no-target-blank=off Disable react/jsx-no-target-blank
        \\  --react-jsx-no-undef=off Disable react/jsx-no-undef
        \\  --react-jsx-pascal-case=off Disable react/jsx-pascal-case
        \\  --react-jsx-uses-react=off Disable react/jsx-uses-react
        \\  --react-jsx-uses-vars=off Accept legacy react/jsx-uses-vars configuration
        \\  --react-no-danger=off     Disable react/no-danger
        \\  --react-no-danger-with-children=off Disable react/no-danger-with-children
        \\  --react-no-access-state-in-setstate=off Disable react/no-access-state-in-setstate
        \\  --react-no-direct-mutation-state=off Disable react/no-direct-mutation-state
        \\  --react-no-deprecated=off Disable react/no-deprecated
        \\  --react-forbid-prop-types=off Disable react/forbid-prop-types
        \\  --react-no-array-index-key=off Disable react/no-array-index-key
        \\  --react-no-children-prop=off Disable react/no-children-prop
        \\  --react-no-find-dom-node=off Disable react/no-find-dom-node
        \\  --react-no-is-mounted=off Disable react/no-is-mounted
        \\  --react-no-multi-comp=off Disable react/no-multi-comp
        \\  --react-no-redundant-should-component-update=off Disable react/no-redundant-should-component-update
        \\  --react-no-render-return-value=off Disable react/no-render-return-value
        \\  --react-no-will-update-set-state=off Disable react/no-will-update-set-state
        \\  --react-no-this-in-sfc=off Disable react/no-this-in-sfc
        \\  --react-no-typos=off Disable react/no-typos
        \\  --react-no-unknown-property=off Disable react/no-unknown-property
        \\  --react-prop-types=off Disable react/prop-types
        \\  --react-no-unused-prop-types=off Disable react/no-unused-prop-types
        \\  --react-no-unused-state=off Disable react/no-unused-state
        \\  --react-no-string-refs=off Disable react/no-string-refs
        \\  --react-no-unescaped-entities=off Disable react/no-unescaped-entities
        \\  --react-prefer-es6-class=off Disable react/prefer-es6-class
        \\  --react-self-closing-comp=off Disable react/self-closing-comp
        \\  --react-style-prop-object=off Disable react/style-prop-object
        \\  --react-void-dom-elements-no-children=off Disable react/void-dom-elements-no-children
        \\  --react-hooks-rules-of-hooks=off Disable react-hooks/rules-of-hooks
        \\  --radix=off               Disable radix
        \\  --require-await=off      Disable require-await
        \\  --require-atomic-updates=off Disable require-atomic-updates
        \\  --require-unicode-regexp=off Disable require-unicode-regexp
        \\  --require-unicode-regexp-require-flag=u Require the u flag for regexps
        \\  --require-unicode-regexp-require-flag=v Require the v flag for regexps
        \\  --require-yield=off       Disable require-yield
        \\  --sort-imports=on         Enable sort-imports
        \\  --sort-imports=off        Disable sort-imports
        \\  --sort-imports-ignore-case=on Enable sort-imports and ignore case
        \\  --sort-imports-ignore-declaration-sort=on Ignore declaration order
        \\  --sort-imports-ignore-member-sort=on Ignore member order
        \\  --sort-imports-allow-separated-groups=on Allow blank-line separated import groups
        \\  --sort-keys=on            Enable sort-keys
        \\  --sort-keys=off           Disable sort-keys
        \\  --sort-keys=desc          Require descending object keys
        \\  --sort-keys-case-sensitive=off Compare object keys case-insensitively
        \\  --sort-keys-natural=on    Compare object keys with natural numeric order
        \\  --sort-keys-min-keys=N    Require sorting only when an object has at least N keys
        \\  --sort-keys-allow-line-separated-groups=on Allow blank-line separated key groups
        \\  --sort-vars=on            Enable sort-vars
        \\  --sort-vars=off           Disable sort-vars
        \\  --sort-vars-ignore-case=on Enable sort-vars and ignore case
        \\  --spaced-comment=off      Disable spaced-comment
        \\  --spaced-comment=never    Disallow spacing after comment markers
        \\  --strict=off              Disable strict
        \\  --strict=safe             Require strict mode using ESLint safe mode
        \\  --strict=global           Require global 'use strict'
        \\  --strict=function         Require function-level 'use strict'
        \\  --strict=never            Disallow 'use strict'
        \\  --symbol-description=off  Disable symbol-description
        \\  --typescript-eslint-adjacent-overload-signatures=off Disable @typescript-eslint/adjacent-overload-signatures
        \\  --typescript-eslint-array-type=off Disable @typescript-eslint/array-type
        \\  --typescript-eslint-class-literal-property-style=off Disable @typescript-eslint/class-literal-property-style
        \\  --typescript-eslint-consistent-type-assertions=off Disable @typescript-eslint/consistent-type-assertions
        \\  --typescript-eslint-consistent-type-definitions=off Disable @typescript-eslint/consistent-type-definitions
        \\  --typescript-eslint-dot-notation=off Disable @typescript-eslint/dot-notation
        \\  --typescript-eslint-no-array-constructor=off Disable @typescript-eslint/no-array-constructor
        \\  --typescript-eslint-ban-ts-comment=off Disable @typescript-eslint/ban-ts-comment
        \\  --typescript-eslint-ban-tslint-comment=off Disable @typescript-eslint/ban-tslint-comment
        \\  --typescript-eslint-explicit-member-accessibility=off Disable @typescript-eslint/explicit-member-accessibility
        \\  --typescript-eslint-member-ordering=off Disable @typescript-eslint/member-ordering
        \\  --typescript-eslint-method-signature-style=off Disable @typescript-eslint/method-signature-style
        \\  --typescript-eslint-no-confusing-non-null-assertion=off Disable @typescript-eslint/no-confusing-non-null-assertion
        \\  --typescript-eslint-no-dupe-class-members=off Disable @typescript-eslint/no-dupe-class-members
        \\  --typescript-eslint-no-empty-function=off Disable @typescript-eslint/no-empty-function
        \\  --typescript-eslint-no-empty-interface=off Disable @typescript-eslint/no-empty-interface
        \\  --typescript-eslint-no-extra-non-null-assertion=off Disable @typescript-eslint/no-extra-non-null-assertion
        \\  --typescript-eslint-no-duplicate-enum-values=off Disable @typescript-eslint/no-duplicate-enum-values
        \\  --typescript-eslint-no-inferrable-types=off Disable @typescript-eslint/no-inferrable-types
        \\  --typescript-eslint-no-invalid-void-type=off Disable @typescript-eslint/no-invalid-void-type
        \\  --typescript-eslint-no-namespace=off Disable @typescript-eslint/no-namespace
        \\  --typescript-eslint-no-non-null-asserted-optional-chain=off Disable @typescript-eslint/no-non-null-asserted-optional-chain
        \\  --typescript-eslint-no-redeclare=off Disable @typescript-eslint/no-redeclare
        \\  --typescript-eslint-no-require-imports=off Disable @typescript-eslint/no-require-imports
        \\  --typescript-eslint-no-loop-func=off Disable @typescript-eslint/no-loop-func
        \\  --typescript-eslint-no-shadow=off Disable @typescript-eslint/no-shadow
        \\  --typescript-eslint-no-this-alias=off Disable @typescript-eslint/no-this-alias
        \\  --typescript-eslint-no-unsafe-declaration-merging=off Disable @typescript-eslint/no-unsafe-declaration-merging
        \\  --typescript-eslint-triple-slash-reference=off Disable @typescript-eslint/triple-slash-reference
        \\  --typescript-eslint-typedef=off Disable @typescript-eslint/typedef
        \\  --typescript-eslint-unified-signatures=off Disable @typescript-eslint/unified-signatures
        \\  --typescript-eslint-no-unnecessary-parameter-property-assignment=off Disable @typescript-eslint/no-unnecessary-parameter-property-assignment
        \\  --typescript-eslint-no-unnecessary-type-constraint=off Disable @typescript-eslint/no-unnecessary-type-constraint
        \\  --typescript-eslint-no-useless-constructor=off Disable @typescript-eslint/no-useless-constructor
        \\  --typescript-eslint-no-useless-empty-export=off Disable @typescript-eslint/no-useless-empty-export
        \\  --typescript-eslint-no-unused-expressions=off Disable @typescript-eslint/no-unused-expressions
        \\  --typescript-eslint-no-unused-vars=off Disable @typescript-eslint/no-unused-vars
        \\  --typescript-eslint-no-use-before-define=off Disable @typescript-eslint/no-use-before-define
        \\  --typescript-eslint-no-wrapper-object-types=off Disable @typescript-eslint/no-wrapper-object-types
        \\  --typescript-eslint-prefer-as-const=off Disable @typescript-eslint/prefer-as-const
        \\  --typescript-eslint-prefer-namespace-keyword=off Disable @typescript-eslint/prefer-namespace-keyword
        \\  --typescript-eslint-restrict-plus-operands=off Disable @typescript-eslint/restrict-plus-operands
        \\  --valid-typeof=off        Disable valid-typeof
        \\  --vars-on-top=off         Disable vars-on-top
        \\  --wrap-iife=off|outside|inside|any Configure wrap-iife
        \\  --semantic-errors=off     Disable parser semantic errors
        \\  --yoda=off                Disable yoda
        \\  --yoda=always             Require yoda comparison style
        \\
    , .{});
}
