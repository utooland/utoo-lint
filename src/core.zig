const std = @import("std");
const parser = @import("parser");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const Severity = enum {
    @"error",
    warning,

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .@"error" => "error",
            .warning => "warning",
        };
    }
};

pub const EqeqeqStyle = enum {
    strict,
    allow_null,
    smart,
};

pub const max_consistent_this_aliases = 32;
pub const max_consistent_this_alias_len = 128;

pub const ConsistentThisAliasesError = error{
    EmptyConsistentThisAlias,
    TooManyConsistentThisAliases,
    ConsistentThisAliasTooLong,
};

pub const ConsistentThisAliases = struct {
    custom: bool = false,
    count: usize = 0,
    lengths: [max_consistent_this_aliases]usize = undefined,
    storage: [max_consistent_this_aliases][max_consistent_this_alias_len]u8 = undefined,

    pub fn contains(self: *const ConsistentThisAliases, name: []const u8) bool {
        if (!self.custom) return std.mem.eql(u8, name, "that");

        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const ConsistentThisAliases, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *ConsistentThisAliases, name: []const u8) ConsistentThisAliasesError!void {
        if (name.len == 0) return error.EmptyConsistentThisAlias;
        if (self.count >= max_consistent_this_aliases) return error.TooManyConsistentThisAliases;
        if (name.len > max_consistent_this_alias_len) return error.ConsistentThisAliasTooLong;
        if (self.contains(name)) return;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_class_methods_use_this_except_methods = 32;
pub const max_class_methods_use_this_except_method_len = 128;

pub const ClassMethodsUseThisExceptMethodsError = error{
    TooManyClassMethodsUseThisExceptMethods,
    ClassMethodsUseThisExceptMethodTooLong,
};

pub const ClassMethodsUseThisExceptMethods = struct {
    count: usize = 0,
    lengths: [max_class_methods_use_this_except_methods]usize = undefined,
    storage: [max_class_methods_use_this_except_methods][max_class_methods_use_this_except_method_len]u8 = undefined,

    pub fn contains(self: *const ClassMethodsUseThisExceptMethods, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const ClassMethodsUseThisExceptMethods, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *ClassMethodsUseThisExceptMethods, name: []const u8) ClassMethodsUseThisExceptMethodsError!void {
        if (self.count >= max_class_methods_use_this_except_methods) return error.TooManyClassMethodsUseThisExceptMethods;
        if (name.len > max_class_methods_use_this_except_method_len) return error.ClassMethodsUseThisExceptMethodTooLong;
        if (self.contains(name)) return;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const ClassMethodsUseThisIgnoreClassesWithImplements = enum {
    none,
    all,
    public_fields,
};

pub const NoInvalidThisCapIsConstructor = enum {
    yes,
    no,
};

pub const max_no_magic_numbers_ignore_values = 64;
pub const max_no_magic_numbers_bigint_len = 256;
pub const max_no_magic_numbers_bigint_storage = 2048;

pub const NoMagicNumbersIgnoreValues = struct {
    const Kind = enum { number, bigint };

    count: usize = 0,
    kinds: [max_no_magic_numbers_ignore_values]Kind = undefined,
    numbers: [max_no_magic_numbers_ignore_values]f64 = undefined,
    bigint_offsets: [max_no_magic_numbers_ignore_values]u16 = undefined,
    bigint_lengths: [max_no_magic_numbers_ignore_values]u16 = undefined,
    bigint_storage: [max_no_magic_numbers_bigint_storage]u8 = undefined,
    bigint_storage_len: usize = 0,

    pub fn containsNumber(self: *const NoMagicNumbersIgnoreValues, value: f64) bool {
        for (0..self.count) |index| {
            if (self.kinds[index] == .number and self.numbers[index] == value) return true;
        }
        return false;
    }

    pub fn containsBigInt(self: *const NoMagicNumbersIgnoreValues, canonical: []const u8) bool {
        for (0..self.count) |index| {
            if (self.kinds[index] != .bigint) continue;
            const start = self.bigint_offsets[index];
            const stored = self.bigint_storage[start .. start + self.bigint_lengths[index]];
            if (std.mem.eql(u8, stored, canonical)) return true;
        }
        return false;
    }

    pub fn appendNumber(self: *NoMagicNumbersIgnoreValues, value: f64) bool {
        if (self.containsNumber(value)) return true;
        if (self.count >= max_no_magic_numbers_ignore_values) return false;
        self.kinds[self.count] = .number;
        self.numbers[self.count] = value;
        self.count += 1;
        return true;
    }

    pub fn appendBigInt(self: *NoMagicNumbersIgnoreValues, value: []const u8) bool {
        var canonical_buffer: [max_no_magic_numbers_bigint_len]u8 = undefined;
        const canonical = canonicalBigIntConfigValue(value, &canonical_buffer) orelse return false;
        if (self.containsBigInt(canonical)) return true;
        if (self.count >= max_no_magic_numbers_ignore_values) return false;
        if (self.bigint_storage_len + canonical.len > self.bigint_storage.len) return false;
        self.kinds[self.count] = .bigint;
        @memcpy(self.bigint_storage[self.bigint_storage_len..][0..canonical.len], canonical);
        self.bigint_offsets[self.count] = @intCast(self.bigint_storage_len);
        self.bigint_lengths[self.count] = @intCast(canonical.len);
        self.bigint_storage_len += canonical.len;
        self.count += 1;
        return true;
    }

    pub fn appendCliValue(self: *NoMagicNumbersIgnoreValues, value: []const u8) bool {
        if (std.mem.endsWith(u8, value, "n")) return self.appendBigInt(value);
        const number = std.fmt.parseFloat(f64, value) catch return false;
        return self.appendNumber(number);
    }

    fn canonicalBigIntConfigValue(value: []const u8, buffer: []u8) ?[]const u8 {
        if (value.len < 2 or value[value.len - 1] != 'n') return null;
        var digits = value[0 .. value.len - 1];
        var negative = false;
        if (digits[0] == '+' or digits[0] == '-') {
            negative = digits[0] == '-';
            digits = digits[1..];
        }
        if (digits.len == 0) return null;
        for (digits) |digit| if (!std.ascii.isDigit(digit)) return null;

        digits = std.mem.trimStart(u8, digits, "0");
        if (digits.len == 0) digits = "0";
        const length = digits.len + @intFromBool(negative and !std.mem.eql(u8, digits, "0"));
        if (length > buffer.len) return null;

        var offset: usize = 0;
        if (negative and !std.mem.eql(u8, digits, "0")) {
            buffer[0] = '-';
            offset = 1;
        }
        @memcpy(buffer[offset..length], digits);
        return buffer[0..length];
    }
};

pub const CurlyStyle = enum {
    all,
    multi_line,
    multi,
    multi_or_nest,
};

pub const ObjectShorthandStyle = enum {
    always,
    methods,
    properties,
    never,
};

pub const ArrowBodyStyle = enum {
    always,
    as_needed,
    never,
};

pub const OperatorAssignmentStyle = enum {
    always,
    never,
};

pub const LinebreakStyle = enum {
    unix,
    windows,
};

pub const SortKeysOrder = enum {
    asc,
    desc,
};

pub const SortImportsMemberSyntax = enum {
    none,
    all,
    multiple,
    single,
};

pub const SortImportsMemberSyntaxOrder = struct {
    values: [4]SortImportsMemberSyntax = .{ .none, .all, .multiple, .single },

    pub fn rank(self: SortImportsMemberSyntaxOrder, syntax: SortImportsMemberSyntax) usize {
        for (self.values, 0..) |value, index| {
            if (value == syntax) return index;
        }
        return self.values.len;
    }
};

pub const ComplexityVariant = enum {
    classic,
    modified,
};

pub const InitDeclarationsMode = enum {
    always,
    never,
};

pub const StrictMode = enum {
    safe,
    global,
    function,
    never,
};

pub const EolLastStyle = enum {
    always,
    never,
};

pub const UnicodeBomStyle = enum {
    never,
    always,
};

pub const ReactJsxFilenameExtensionAllow = enum {
    always,
    as_needed,
};

pub const NoCondAssignStyle = enum {
    except_parens,
    always,
};

pub const NoLabelsAllowLoop = enum {
    yes,
    no,
};

pub const NoLabelsAllowSwitch = enum {
    yes,
    no,
};

pub const NoConfusingArrowAllowParens = enum {
    yes,
    no,
};

pub const max_no_console_allow_methods = 32;
pub const max_no_console_allow_method_len = 128;

pub const NoConsoleAllow = struct {
    count: usize = 0,
    lengths: [max_no_console_allow_methods]usize = undefined,
    storage: [max_no_console_allow_methods][max_no_console_allow_method_len]u8 = undefined,

    pub fn contains(self: NoConsoleAllow, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoConsoleAllow, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn enable(self: *NoConsoleAllow, name: []const u8) bool {
        if (name.len == 0 or name.len > max_no_console_allow_method_len) return false;
        if (self.contains(name)) return true;
        if (self.count >= max_no_console_allow_methods) return false;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const NoEmptyAllowEmptyCatch = enum {
    yes,
    no,
};

pub const NoEmptyFunctionAllow = struct {
    functions: bool = false,
    arrowFunctions: bool = false,
    generatorFunctions: bool = false,
    asyncFunctions: bool = false,
    methods: bool = false,
    generatorMethods: bool = false,
    asyncMethods: bool = false,
    getters: bool = false,
    setters: bool = false,
    constructors: bool = false,
    privateConstructors: bool = false,
    protectedConstructors: bool = false,
    decoratedFunctions: bool = false,
    overrideMethods: bool = false,

    pub fn contains(self: NoEmptyFunctionAllow, name: []const u8) bool {
        inline for (@typeInfo(NoEmptyFunctionAllow).@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, name)) return @field(self, field.name);
        }
        return false;
    }

    pub fn enable(self: *NoEmptyFunctionAllow, name: []const u8) bool {
        if (std.mem.eql(u8, name, "private-constructors")) {
            self.privateConstructors = true;
            return true;
        }
        if (std.mem.eql(u8, name, "protected-constructors")) {
            self.protectedConstructors = true;
            return true;
        }
        if (std.mem.eql(u8, name, "decoratedFunctions")) {
            self.decoratedFunctions = true;
            return true;
        }
        if (std.mem.eql(u8, name, "overrideMethods")) {
            self.overrideMethods = true;
            return true;
        }
        inline for (@typeInfo(NoEmptyFunctionAllow).@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                @field(self, field.name) = true;
                return true;
            }
        }
        return false;
    }
};

pub const NoFallthroughAllowEmptyCase = enum {
    yes,
    no,
};

pub const NoInvalidRegexpAllowConstructorFlags = struct {
    flags: [256]bool = [_]bool{false} ** 256,

    pub fn contains(self: NoInvalidRegexpAllowConstructorFlags, flag: u8) bool {
        return self.flags[flag];
    }

    pub fn enable(self: *NoInvalidRegexpAllowConstructorFlags, flag: []const u8) bool {
        if (flag.len != 1) return false;
        self.flags[flag[0]] = true;
        return true;
    }
};

pub const NoInnerDeclarationsMode = enum {
    functions,
    both,
};

pub const NoMultiSpacesIgnoreEOLComments = enum {
    yes,
    no,
};

pub const NoMultiSpacesExceptions = struct {
    property: bool = true,
    binary_expression: bool = false,
    variable_declarator: bool = false,
    import_declaration: bool = false,
};

pub const NoReturnAssignStyle = enum {
    except_parens,
    always,
};

pub const RadixStyle = enum {
    always,
    as_needed,
};

pub const MaxParamsCountThis = enum {
    always,
    never,
    except_void,
};

pub const RequireUnicodeRegexpRequireFlag = enum {
    any,
    u,
    v,
};

pub const NoSequencesAllowInParentheses = enum {
    yes,
    no,
};

pub const NoUnderscoreDangleAllowFunctionParams = enum {
    yes,
    no,
};

pub const NoUnderscoreDangleAllowDestructuring = enum {
    yes,
    no,
};

pub const NoWarningCommentsLocation = enum {
    start,
    anywhere,
};

pub const NoWarningCommentsDecoration = enum {
    none,
    asterisk,
    slash,
    slash_asterisk,
};

pub const no_warning_comments_default_terms = [_][]const u8{
    "todo",
    "fixme",
    "xxx",
};

pub const max_no_warning_comments_terms = 32;
pub const max_no_warning_comments_term_len = 128;

pub const NoWarningCommentsTermsError = error{
    EmptyNoWarningCommentsTerm,
    TooManyNoWarningCommentsTerms,
    NoWarningCommentsTermTooLong,
};

pub const NoWarningCommentsTerms = struct {
    custom: bool = false,
    count: usize = 0,
    lengths: [max_no_warning_comments_terms]usize = undefined,
    storage: [max_no_warning_comments_terms][max_no_warning_comments_term_len]u8 = undefined,

    pub fn len(self: *const NoWarningCommentsTerms) usize {
        return if (self.custom) self.count else no_warning_comments_default_terms.len;
    }

    pub fn at(self: *const NoWarningCommentsTerms, index: usize) []const u8 {
        if (!self.custom) return no_warning_comments_default_terms[index];
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn set(self: *NoWarningCommentsTerms, terms: []const []const u8) NoWarningCommentsTermsError!void {
        self.custom = true;
        self.count = 0;
        for (terms) |term| try self.append(term);
    }

    pub fn append(self: *NoWarningCommentsTerms, term: []const u8) NoWarningCommentsTermsError!void {
        if (term.len == 0) return error.EmptyNoWarningCommentsTerm;
        if (self.count >= max_no_warning_comments_terms) return error.TooManyNoWarningCommentsTerms;
        if (term.len > max_no_warning_comments_term_len) return error.NoWarningCommentsTermTooLong;

        self.custom = true;
        @memcpy(self.storage[self.count][0..term.len], term);
        self.lengths[self.count] = term.len;
        self.count += 1;
    }
};

pub const SpacedCommentStyle = enum {
    always,
    never,
};

pub const max_spaced_comment_markers = 32;
pub const max_spaced_comment_marker_len = 32;

pub const SpacedCommentMarkersError = error{
    EmptySpacedCommentMarker,
    TooManySpacedCommentMarkers,
    SpacedCommentMarkerTooLong,
};

pub const SpacedCommentMarkers = struct {
    count: usize = 0,
    lengths: [max_spaced_comment_markers]usize = undefined,
    storage: [max_spaced_comment_markers][max_spaced_comment_marker_len]u8 = undefined,

    pub fn matches(self: *const SpacedCommentMarkers, value: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.startsWith(u8, value, self.at(index))) return true;
        }
        return false;
    }

    pub fn at(self: *const SpacedCommentMarkers, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *SpacedCommentMarkers, marker: []const u8) SpacedCommentMarkersError!void {
        if (marker.len == 0) return error.EmptySpacedCommentMarker;
        if (self.count >= max_spaced_comment_markers) return error.TooManySpacedCommentMarkers;
        if (marker.len > max_spaced_comment_marker_len) return error.SpacedCommentMarkerTooLong;

        @memcpy(self.storage[self.count][0..marker.len], marker);
        self.lengths[self.count] = marker.len;
        self.count += 1;
    }
};

pub const NoVoidAllowAsStatement = enum {
    yes,
    no,
};

pub const NoImplicitCoercionBoolean = enum {
    yes,
    no,
};

pub const NoImplicitCoercionNumber = enum {
    yes,
    no,
};

pub const NoImplicitCoercionString = enum {
    yes,
    no,
};

pub const NoPlusplusAllowForLoopAfterthoughts = enum {
    yes,
    no,
};

pub const NoRedeclareBuiltinGlobals = enum {
    yes,
    no,
};

pub const NoUnusedExpressionsAllowShortCircuit = enum {
    yes,
    no,
};

pub const NoUnusedExpressionsAllowTernary = enum {
    yes,
    no,
};

pub const NoUnusedExpressionsAllowTaggedTemplates = enum {
    yes,
    no,
};

pub const NoUseBeforeDefineCheck = enum {
    yes,
    no,
};

pub const NoShadowHoist = enum {
    all,
    functions,
    functions_and_types,
    never,
    types,
};

pub const NoUnusedVarsVars = enum {
    all,
    local,
};

pub const NoUnusedVarsArgs = enum {
    none,
    after_used,
    all,
};

pub const NoUnusedVarsCaughtErrors = enum {
    none,
    all,
};

pub const NoParamReassignProps = enum {
    yes,
    no,
};

pub const max_import_no_unresolved_ignore_patterns = 32;
pub const max_import_no_unresolved_ignore_pattern_len = 256;

pub const ImportNoUnresolvedIgnorePatterns = struct {
    count: usize = 0,
    lengths: [max_import_no_unresolved_ignore_patterns]usize = undefined,
    storage: [max_import_no_unresolved_ignore_patterns][max_import_no_unresolved_ignore_pattern_len]u8 = undefined,

    pub fn at(self: *const ImportNoUnresolvedIgnorePatterns, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *ImportNoUnresolvedIgnorePatterns, pattern: []const u8) bool {
        if (pattern.len == 0) return false;
        if (self.count >= max_import_no_unresolved_ignore_patterns) return false;
        if (pattern.len > max_import_no_unresolved_ignore_pattern_len) return false;

        @memcpy(self.storage[self.count][0..pattern.len], pattern);
        self.lengths[self.count] = pattern.len;
        self.count += 1;
        return true;
    }
};

pub const max_typescript_eslint_no_require_imports_allow_patterns = 32;
pub const max_typescript_eslint_no_require_imports_allow_pattern_len = 256;

pub const TypescriptEslintNoRequireImportsAllowPatterns = struct {
    count: usize = 0,
    lengths: [max_typescript_eslint_no_require_imports_allow_patterns]usize = undefined,
    storage: [max_typescript_eslint_no_require_imports_allow_patterns][max_typescript_eslint_no_require_imports_allow_pattern_len]u8 = undefined,

    pub fn at(self: *const TypescriptEslintNoRequireImportsAllowPatterns, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *TypescriptEslintNoRequireImportsAllowPatterns, pattern: []const u8) bool {
        if (pattern.len == 0) return false;
        if (self.count >= max_typescript_eslint_no_require_imports_allow_patterns) return false;
        if (pattern.len > max_typescript_eslint_no_require_imports_allow_pattern_len) return false;

        @memcpy(self.storage[self.count][0..pattern.len], pattern);
        self.lengths[self.count] = pattern.len;
        self.count += 1;
        return true;
    }
};

pub const max_no_param_reassign_ignored_names = 32;
pub const max_no_param_reassign_ignored_name_len = 128;
pub const max_no_param_reassign_ignored_name_patterns = 32;
pub const max_no_param_reassign_ignored_name_pattern_len = 256;

pub const NoParamReassignIgnoredNamesError = error{
    EmptyNoParamReassignIgnoredName,
    TooManyNoParamReassignIgnoredNames,
    NoParamReassignIgnoredNameTooLong,
};

pub const NoParamReassignIgnoredNames = struct {
    count: usize = 0,
    lengths: [max_no_param_reassign_ignored_names]usize = undefined,
    storage: [max_no_param_reassign_ignored_names][max_no_param_reassign_ignored_name_len]u8 = undefined,

    pub fn contains(self: *const NoParamReassignIgnoredNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoParamReassignIgnoredNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoParamReassignIgnoredNames, name: []const u8) NoParamReassignIgnoredNamesError!void {
        if (name.len == 0) return error.EmptyNoParamReassignIgnoredName;
        if (self.count >= max_no_param_reassign_ignored_names) return error.TooManyNoParamReassignIgnoredNames;
        if (name.len > max_no_param_reassign_ignored_name_len) return error.NoParamReassignIgnoredNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const NoParamReassignIgnoredNamePatternsError = error{
    EmptyNoParamReassignIgnoredNamePattern,
    TooManyNoParamReassignIgnoredNamePatterns,
    NoParamReassignIgnoredNamePatternTooLong,
};

pub const NoParamReassignIgnoredNamePatterns = struct {
    count: usize = 0,
    lengths: [max_no_param_reassign_ignored_name_patterns]usize = undefined,
    storage: [max_no_param_reassign_ignored_name_patterns][max_no_param_reassign_ignored_name_pattern_len]u8 = undefined,

    pub fn at(self: *const NoParamReassignIgnoredNamePatterns, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoParamReassignIgnoredNamePatterns, pattern: []const u8) NoParamReassignIgnoredNamePatternsError!void {
        if (pattern.len == 0) return error.EmptyNoParamReassignIgnoredNamePattern;
        if (self.count >= max_no_param_reassign_ignored_name_patterns) return error.TooManyNoParamReassignIgnoredNamePatterns;
        if (pattern.len > max_no_param_reassign_ignored_name_pattern_len) return error.NoParamReassignIgnoredNamePatternTooLong;

        @memcpy(self.storage[self.count][0..pattern.len], pattern);
        self.lengths[self.count] = pattern.len;
        self.count += 1;
    }
};

pub const max_no_extend_native_exceptions = 32;
pub const max_no_extend_native_exception_len = 128;

pub const NoExtendNativeExceptionsError = error{
    EmptyNoExtendNativeException,
    TooManyNoExtendNativeExceptions,
    NoExtendNativeExceptionTooLong,
};

pub const NoExtendNativeExceptions = struct {
    count: usize = 0,
    lengths: [max_no_extend_native_exceptions]usize = undefined,
    storage: [max_no_extend_native_exceptions][max_no_extend_native_exception_len]u8 = undefined,

    pub fn contains(self: *const NoExtendNativeExceptions, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoExtendNativeExceptions, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoExtendNativeExceptions, name: []const u8) NoExtendNativeExceptionsError!void {
        if (name.len == 0) return error.EmptyNoExtendNativeException;
        if (self.count >= max_no_extend_native_exceptions) return error.TooManyNoExtendNativeExceptions;
        if (name.len > max_no_extend_native_exception_len) return error.NoExtendNativeExceptionTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_no_shadow_allow_names = 32;
pub const max_no_shadow_allow_name_len = 128;

pub const NoShadowAllowNamesError = error{
    EmptyNoShadowAllowName,
    TooManyNoShadowAllowNames,
    NoShadowAllowNameTooLong,
};

pub const NoShadowAllowNames = struct {
    count: usize = 0,
    lengths: [max_no_shadow_allow_names]usize = undefined,
    storage: [max_no_shadow_allow_names][max_no_shadow_allow_name_len]u8 = undefined,

    pub fn contains(self: *const NoShadowAllowNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoShadowAllowNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoShadowAllowNames, name: []const u8) NoShadowAllowNamesError!void {
        if (name.len == 0) return error.EmptyNoShadowAllowName;
        if (self.count >= max_no_shadow_allow_names) return error.TooManyNoShadowAllowNames;
        if (name.len > max_no_shadow_allow_name_len) return error.NoShadowAllowNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_no_restricted_properties = 32;
pub const max_no_restricted_property_name_len = 128;
pub const max_no_restricted_property_message_len = 256;
pub const max_no_restricted_property_allow_names = 16;
pub const max_no_restricted_globals = 64;
pub const max_no_restricted_global_name_len = 128;
pub const max_no_restricted_global_message_len = 256;
pub const max_no_restricted_global_objects = 16;
pub const max_no_restricted_syntax = 64;
pub const max_no_restricted_syntax_selector_len = 128;
pub const max_no_restricted_syntax_message_len = 256;
pub const max_no_restricted_export_names = 64;
pub const max_no_restricted_export_name_len = 128;
pub const max_no_restricted_imports = 16;
pub const max_no_restricted_import_source_len = 256;
pub const max_no_restricted_import_message_len = 256;
pub const max_no_restricted_import_names = 8;
pub const max_no_restricted_import_name_len = 128;
pub const max_id_denylist_names = 64;
pub const max_id_denylist_name_len = 128;
pub const max_id_length_exceptions = 64;
pub const max_id_length_exception_len = 128;
pub const max_id_length_exception_patterns = 64;
pub const max_id_length_exception_pattern_len = 256;
pub const max_id_match_pattern_len = 256;

pub const PromiseValidParamsExclusions = struct {
    resolve_method: bool = false,
    reject_method: bool = false,
    then_method: bool = false,
    catch_method: bool = false,
    finally_method: bool = false,
    race_method: bool = false,
    all_method: bool = false,
    all_settled_method: bool = false,
    any_method: bool = false,

    pub fn enable(self: *PromiseValidParamsExclusions, name: []const u8) void {
        if (std.mem.eql(u8, name, "resolve")) self.resolve_method = true;
        if (std.mem.eql(u8, name, "reject")) self.reject_method = true;
        if (std.mem.eql(u8, name, "then")) self.then_method = true;
        if (std.mem.eql(u8, name, "catch")) self.catch_method = true;
        if (std.mem.eql(u8, name, "finally")) self.finally_method = true;
        if (std.mem.eql(u8, name, "race")) self.race_method = true;
        if (std.mem.eql(u8, name, "all")) self.all_method = true;
        if (std.mem.eql(u8, name, "allSettled")) self.all_settled_method = true;
        if (std.mem.eql(u8, name, "any")) self.any_method = true;
    }

    pub fn contains(self: PromiseValidParamsExclusions, name: []const u8) bool {
        if (std.mem.eql(u8, name, "resolve")) return self.resolve_method;
        if (std.mem.eql(u8, name, "reject")) return self.reject_method;
        if (std.mem.eql(u8, name, "then")) return self.then_method;
        if (std.mem.eql(u8, name, "catch")) return self.catch_method;
        if (std.mem.eql(u8, name, "finally")) return self.finally_method;
        if (std.mem.eql(u8, name, "race")) return self.race_method;
        if (std.mem.eql(u8, name, "all")) return self.all_method;
        if (std.mem.eql(u8, name, "allSettled")) return self.all_settled_method;
        if (std.mem.eql(u8, name, "any")) return self.any_method;
        return false;
    }
};

pub const max_promise_param_name_pattern_len = 128;

pub const PromiseParamNamePattern = struct {
    const Default = enum { resolve, reject };

    default: Default = .resolve,
    custom: bool = false,
    length: usize = 0,
    storage: [max_promise_param_name_pattern_len]u8 = undefined,

    pub fn pattern(self: *const PromiseParamNamePattern) []const u8 {
        if (self.custom) return self.storage[0..self.length];
        return switch (self.default) {
            .resolve => "^_?resolve$",
            .reject => "^_?reject$",
        };
    }

    pub fn set(self: *PromiseParamNamePattern, value: []const u8) bool {
        if (value.len > max_promise_param_name_pattern_len) return false;
        @memcpy(self.storage[0..value.len], value);
        self.length = value.len;
        self.custom = true;
        return true;
    }

    pub fn matches(self: *const PromiseParamNamePattern, name: []const u8) bool {
        return simpleRegexMatches(self.pattern(), name);
    }

    fn simpleRegexMatches(pattern_text: []const u8, name: []const u8) bool {
        const anchored_start = pattern_text.len > 0 and pattern_text[0] == '^';
        const start = if (anchored_start) @as(usize, 1) else 0;
        const anchored_end = pattern_text.len > start and pattern_text[pattern_text.len - 1] == '$' and
            (pattern_text.len < 2 or pattern_text[pattern_text.len - 2] != '\\');
        const end = if (anchored_end) pattern_text.len - 1 else pattern_text.len;
        const regex_pattern = pattern_text[start..end];

        if (anchored_start) return matchHere(regex_pattern, 0, name, 0, anchored_end);
        for (0..name.len + 1) |offset| {
            if (matchHere(regex_pattern, 0, name, offset, anchored_end)) return true;
        }
        return false;
    }

    fn matchHere(regex_pattern: []const u8, pattern_index: usize, name: []const u8, name_index: usize, anchored_end: bool) bool {
        if (pattern_index >= regex_pattern.len) return !anchored_end or name_index == name.len;

        const atom_end = atomEnd(regex_pattern, pattern_index);
        const quantifier = if (atom_end < regex_pattern.len) regex_pattern[atom_end] else 0;
        const next_pattern = if (quantifier == '?' or quantifier == '*' or quantifier == '+') atom_end + 1 else atom_end;

        if (quantifier == '?') {
            if (name_index < name.len and atomMatches(regex_pattern[pattern_index..atom_end], name[name_index]) and
                matchHere(regex_pattern, next_pattern, name, name_index + 1, anchored_end)) return true;
            return matchHere(regex_pattern, next_pattern, name, name_index, anchored_end);
        }
        if (quantifier == '*' or quantifier == '+') {
            var consumed: usize = 0;
            while (name_index + consumed < name.len and atomMatches(regex_pattern[pattern_index..atom_end], name[name_index + consumed])) {
                consumed += 1;
            }
            const minimum: usize = if (quantifier == '+') 1 else 0;
            if (consumed < minimum) return false;
            var count = consumed + 1;
            while (count > minimum) {
                count -= 1;
                if (matchHere(regex_pattern, next_pattern, name, name_index + count, anchored_end)) return true;
            }
            return false;
        }

        return name_index < name.len and atomMatches(regex_pattern[pattern_index..atom_end], name[name_index]) and
            matchHere(regex_pattern, next_pattern, name, name_index + 1, anchored_end);
    }

    fn atomEnd(regex_pattern: []const u8, start: usize) usize {
        if (regex_pattern[start] == '\\' and start + 1 < regex_pattern.len) return start + 2;
        if (regex_pattern[start] == '[') {
            var index = start + 1;
            while (index < regex_pattern.len) : (index += 1) {
                if (regex_pattern[index] == ']' and index > start + 1) return index + 1;
            }
        }
        return start + 1;
    }

    fn atomMatches(atom: []const u8, character: u8) bool {
        if (atom.len == 1) return atom[0] == '.' or atom[0] == character;
        if (atom[0] == '\\') return atom.len == 2 and atom[1] == character;
        if (atom[0] != '[' or atom[atom.len - 1] != ']') return false;

        var index: usize = 1;
        const negated = index < atom.len - 1 and atom[index] == '^';
        if (negated) index += 1;
        var found = false;
        while (index < atom.len - 1) {
            if (index + 2 < atom.len - 1 and atom[index + 1] == '-') {
                found = found or (character >= atom[index] and character <= atom[index + 2]);
                index += 3;
            } else {
                found = found or character == atom[index];
                index += 1;
            }
        }
        return if (negated) !found else found;
    }
};
pub const max_camelcase_allow_patterns = 64;
pub const max_camelcase_allow_pattern_len = 256;

pub const NoRestrictedPropertyNameList = struct {
    count: usize = 0,
    lengths: [max_no_restricted_property_allow_names]usize = undefined,
    storage: [max_no_restricted_property_allow_names][max_no_restricted_property_name_len]u8 = undefined,

    pub fn contains(self: *const NoRestrictedPropertyNameList, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoRestrictedPropertyNameList, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoRestrictedPropertyNameList, name: []const u8) bool {
        if (name.len == 0) return false;
        if (self.count >= max_no_restricted_property_allow_names) return false;
        if (name.len > max_no_restricted_property_name_len) return false;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const NoRestrictedPropertyEntry = struct {
    has_object: bool = false,
    object_length: usize = 0,
    object_storage: [max_no_restricted_property_name_len]u8 = undefined,

    has_property: bool = false,
    property_length: usize = 0,
    property_storage: [max_no_restricted_property_name_len]u8 = undefined,

    has_message: bool = false,
    message_length: usize = 0,
    message_storage: [max_no_restricted_property_message_len]u8 = undefined,

    allow_objects: NoRestrictedPropertyNameList = .{},
    allow_properties: NoRestrictedPropertyNameList = .{},

    pub fn object(self: *const NoRestrictedPropertyEntry) ?[]const u8 {
        if (!self.has_object) return null;
        return self.object_storage[0..self.object_length];
    }

    pub fn property(self: *const NoRestrictedPropertyEntry) ?[]const u8 {
        if (!self.has_property) return null;
        return self.property_storage[0..self.property_length];
    }

    pub fn message(self: *const NoRestrictedPropertyEntry) ?[]const u8 {
        if (!self.has_message) return null;
        return self.message_storage[0..self.message_length];
    }

    pub fn setObject(self: *NoRestrictedPropertyEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_property_name_len) return false;
        @memcpy(self.object_storage[0..value.len], value);
        self.object_length = value.len;
        self.has_object = true;
        return true;
    }

    pub fn setProperty(self: *NoRestrictedPropertyEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_property_name_len) return false;
        @memcpy(self.property_storage[0..value.len], value);
        self.property_length = value.len;
        self.has_property = true;
        return true;
    }

    pub fn setMessage(self: *NoRestrictedPropertyEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_property_message_len) return false;
        @memcpy(self.message_storage[0..value.len], value);
        self.message_length = value.len;
        self.has_message = true;
        return true;
    }
};

pub const NoRestrictedProperties = struct {
    count: usize = 0,
    entries: [max_no_restricted_properties]NoRestrictedPropertyEntry = undefined,

    pub fn append(self: *NoRestrictedProperties, entry: NoRestrictedPropertyEntry) bool {
        if (self.count >= max_no_restricted_properties) return false;
        self.entries[self.count] = entry;
        self.count += 1;
        return true;
    }

    pub fn at(self: *const NoRestrictedProperties, index: usize) *const NoRestrictedPropertyEntry {
        return &self.entries[index];
    }
};

pub const NoRestrictedGlobalEntry = struct {
    name_length: usize = 0,
    name_storage: [max_no_restricted_global_name_len]u8 = undefined,

    has_message: bool = false,
    message_length: usize = 0,
    message_storage: [max_no_restricted_global_message_len]u8 = undefined,

    pub fn name(self: *const NoRestrictedGlobalEntry) []const u8 {
        return self.name_storage[0..self.name_length];
    }

    pub fn message(self: *const NoRestrictedGlobalEntry) ?[]const u8 {
        if (!self.has_message) return null;
        return self.message_storage[0..self.message_length];
    }

    pub fn setName(self: *NoRestrictedGlobalEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_global_name_len) return false;
        @memcpy(self.name_storage[0..value.len], value);
        self.name_length = value.len;
        return true;
    }

    pub fn setMessage(self: *NoRestrictedGlobalEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_global_message_len) return false;
        @memcpy(self.message_storage[0..value.len], value);
        self.message_length = value.len;
        self.has_message = true;
        return true;
    }
};

pub const NoRestrictedGlobalObjects = struct {
    count: usize = 0,
    lengths: [max_no_restricted_global_objects]usize = undefined,
    storage: [max_no_restricted_global_objects][max_no_restricted_global_name_len]u8 = undefined,

    pub fn contains(self: *const NoRestrictedGlobalObjects, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoRestrictedGlobalObjects, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoRestrictedGlobalObjects, name: []const u8) bool {
        if (name.len == 0 or name.len > max_no_restricted_global_name_len) return false;
        if (self.count >= max_no_restricted_global_objects) return false;
        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const NoRestrictedGlobals = struct {
    count: usize = 0,
    entries: [max_no_restricted_globals]NoRestrictedGlobalEntry = undefined,
    check_global_object: bool = false,
    global_objects: NoRestrictedGlobalObjects = .{},

    pub fn append(self: *NoRestrictedGlobals, entry: NoRestrictedGlobalEntry) bool {
        if (self.count >= max_no_restricted_globals) return false;
        self.entries[self.count] = entry;
        self.count += 1;
        return true;
    }

    pub fn appendName(self: *NoRestrictedGlobals, name: []const u8) bool {
        var entry = NoRestrictedGlobalEntry{};
        if (!entry.setName(name)) return false;
        return self.append(entry);
    }

    pub fn at(self: *const NoRestrictedGlobals, index: usize) *const NoRestrictedGlobalEntry {
        return &self.entries[index];
    }

    pub fn find(self: *const NoRestrictedGlobals, name: []const u8) ?*const NoRestrictedGlobalEntry {
        for (0..self.count) |index| {
            const entry = self.at(index);
            if (std.mem.eql(u8, entry.name(), name)) return entry;
        }
        return null;
    }
};

pub const NoRestrictedSyntaxEntry = struct {
    selector_length: usize = 0,
    selector_storage: [max_no_restricted_syntax_selector_len]u8 = undefined,

    has_message: bool = false,
    message_length: usize = 0,
    message_storage: [max_no_restricted_syntax_message_len]u8 = undefined,

    pub fn selector(self: *const NoRestrictedSyntaxEntry) []const u8 {
        return self.selector_storage[0..self.selector_length];
    }

    pub fn message(self: *const NoRestrictedSyntaxEntry) ?[]const u8 {
        if (!self.has_message) return null;
        return self.message_storage[0..self.message_length];
    }

    pub fn setSelector(self: *NoRestrictedSyntaxEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_syntax_selector_len) return false;
        @memcpy(self.selector_storage[0..value.len], value);
        self.selector_length = value.len;
        return true;
    }

    pub fn setMessage(self: *NoRestrictedSyntaxEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_syntax_message_len) return false;
        @memcpy(self.message_storage[0..value.len], value);
        self.message_length = value.len;
        self.has_message = true;
        return true;
    }
};

pub const NoRestrictedSyntax = struct {
    count: usize = 0,
    entries: [max_no_restricted_syntax]NoRestrictedSyntaxEntry = undefined,

    pub fn append(self: *NoRestrictedSyntax, entry: NoRestrictedSyntaxEntry) bool {
        if (self.count >= max_no_restricted_syntax) return false;
        self.entries[self.count] = entry;
        self.count += 1;
        return true;
    }

    pub fn at(self: *const NoRestrictedSyntax, index: usize) *const NoRestrictedSyntaxEntry {
        return &self.entries[index];
    }
};

pub const IdDenylistNamesError = error{
    EmptyIdDenylistName,
    TooManyIdDenylistNames,
    IdDenylistNameTooLong,
};

pub const IdDenylistNames = struct {
    count: usize = 0,
    lengths: [max_id_denylist_names]usize = undefined,
    storage: [max_id_denylist_names][max_id_denylist_name_len]u8 = undefined,

    pub fn contains(self: *const IdDenylistNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const IdDenylistNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *IdDenylistNames, name: []const u8) IdDenylistNamesError!void {
        if (name.len == 0) return error.EmptyIdDenylistName;
        if (self.count >= max_id_denylist_names) return error.TooManyIdDenylistNames;
        if (name.len > max_id_denylist_name_len) return error.IdDenylistNameTooLong;
        if (self.contains(name)) return;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const IdLengthProperties = enum {
    always,
    never,
};

pub const IdLengthExceptionsError = error{
    EmptyIdLengthException,
    TooManyIdLengthExceptions,
    IdLengthExceptionTooLong,
};

pub const IdLengthExceptions = struct {
    count: usize = 0,
    lengths: [max_id_length_exceptions]usize = undefined,
    storage: [max_id_length_exceptions][max_id_length_exception_len]u8 = undefined,

    pub fn contains(self: *const IdLengthExceptions, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const IdLengthExceptions, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *IdLengthExceptions, name: []const u8) IdLengthExceptionsError!void {
        if (name.len == 0) return error.EmptyIdLengthException;
        if (self.count >= max_id_length_exceptions) return error.TooManyIdLengthExceptions;
        if (name.len > max_id_length_exception_len) return error.IdLengthExceptionTooLong;
        if (self.contains(name)) return;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const IdLengthExceptionPatternsError = error{
    EmptyIdLengthExceptionPattern,
    TooManyIdLengthExceptionPatterns,
    IdLengthExceptionPatternTooLong,
};

pub const IdLengthExceptionPatterns = struct {
    count: usize = 0,
    lengths: [max_id_length_exception_patterns]usize = undefined,
    storage: [max_id_length_exception_patterns][max_id_length_exception_pattern_len]u8 = undefined,

    pub fn matches(self: *const IdLengthExceptionPatterns, name: []const u8) bool {
        for (0..self.count) |index| {
            if (simplePatternMatches(self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const IdLengthExceptionPatterns, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *IdLengthExceptionPatterns, pattern: []const u8) IdLengthExceptionPatternsError!void {
        if (pattern.len == 0) return error.EmptyIdLengthExceptionPattern;
        if (self.count >= max_id_length_exception_patterns) return error.TooManyIdLengthExceptionPatterns;
        if (pattern.len > max_id_length_exception_pattern_len) return error.IdLengthExceptionPatternTooLong;

        @memcpy(self.storage[self.count][0..pattern.len], pattern);
        self.lengths[self.count] = pattern.len;
        self.count += 1;
    }

    fn simplePatternMatches(pattern_text: []const u8, name: []const u8) bool {
        if (pattern_text.len >= 2 and pattern_text[0] == '^' and pattern_text[pattern_text.len - 1] == '$') {
            return std.mem.eql(u8, name, pattern_text[1 .. pattern_text.len - 1]);
        }
        if (pattern_text.len >= 1 and pattern_text[0] == '^') {
            return std.mem.startsWith(u8, name, pattern_text[1..]);
        }
        if (pattern_text.len >= 1 and pattern_text[pattern_text.len - 1] == '$') {
            return std.mem.endsWith(u8, name, pattern_text[0 .. pattern_text.len - 1]);
        }
        return std.mem.indexOf(u8, name, pattern_text) != null;
    }
};

pub const IdMatchPatternError = error{
    EmptyIdMatchPattern,
    IdMatchPatternTooLong,
};

pub const IdMatchPattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_id_match_pattern_len]u8 = undefined,

    pub fn pattern(self: *const IdMatchPattern) []const u8 {
        return self.storage[0..self.length];
    }

    pub fn set(self: *IdMatchPattern, value: []const u8) IdMatchPatternError!void {
        if (value.len == 0) return error.EmptyIdMatchPattern;
        if (value.len > max_id_match_pattern_len) return error.IdMatchPatternTooLong;
        @memcpy(self.storage[0..value.len], value);
        self.length = value.len;
        self.custom = true;
    }

    pub fn matches(self: *const IdMatchPattern, name: []const u8) bool {
        if (!self.custom) return true;
        return simplePatternMatches(self.pattern(), name);
    }

    fn simplePatternMatches(pattern_text: []const u8, name: []const u8) bool {
        if (pattern_text.len >= 2 and pattern_text[0] == '^' and pattern_text[pattern_text.len - 1] == '$') {
            return std.mem.eql(u8, name, pattern_text[1 .. pattern_text.len - 1]);
        }
        if (pattern_text.len >= 1 and pattern_text[0] == '^') {
            return std.mem.startsWith(u8, name, pattern_text[1..]);
        }
        if (pattern_text.len >= 1 and pattern_text[pattern_text.len - 1] == '$') {
            return std.mem.endsWith(u8, name, pattern_text[0 .. pattern_text.len - 1]);
        }
        return std.mem.indexOf(u8, name, pattern_text) != null;
    }
};

pub const CamelcaseProperties = enum {
    always,
    never,
};

pub const CamelcaseAllowPatternsError = error{
    EmptyCamelcaseAllowPattern,
    TooManyCamelcaseAllowPatterns,
    CamelcaseAllowPatternTooLong,
};

pub const CamelcaseAllowPatterns = struct {
    count: usize = 0,
    lengths: [max_camelcase_allow_patterns]usize = undefined,
    storage: [max_camelcase_allow_patterns][max_camelcase_allow_pattern_len]u8 = undefined,

    pub fn matches(self: *const CamelcaseAllowPatterns, name: []const u8) bool {
        for (0..self.count) |index| {
            if (simplePatternMatches(self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const CamelcaseAllowPatterns, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *CamelcaseAllowPatterns, pattern: []const u8) CamelcaseAllowPatternsError!void {
        if (pattern.len == 0) return error.EmptyCamelcaseAllowPattern;
        if (self.count >= max_camelcase_allow_patterns) return error.TooManyCamelcaseAllowPatterns;
        if (pattern.len > max_camelcase_allow_pattern_len) return error.CamelcaseAllowPatternTooLong;
        @memcpy(self.storage[self.count][0..pattern.len], pattern);
        self.lengths[self.count] = pattern.len;
        self.count += 1;
    }

    fn simplePatternMatches(pattern_text: []const u8, name: []const u8) bool {
        if (pattern_text.len >= 2 and pattern_text[0] == '^' and pattern_text[pattern_text.len - 1] == '$') {
            return std.mem.eql(u8, name, pattern_text[1 .. pattern_text.len - 1]);
        }
        if (pattern_text.len >= 1 and pattern_text[0] == '^') {
            return std.mem.startsWith(u8, name, pattern_text[1..]);
        }
        if (pattern_text.len >= 1 and pattern_text[pattern_text.len - 1] == '$') {
            return std.mem.endsWith(u8, name, pattern_text[0 .. pattern_text.len - 1]);
        }
        return std.mem.indexOf(u8, name, pattern_text) != null;
    }
};

pub const NoRestrictedExportNamesError = error{
    EmptyNoRestrictedExportName,
    TooManyNoRestrictedExportNames,
    NoRestrictedExportNameTooLong,
};

pub const NoRestrictedExportNames = struct {
    count: usize = 0,
    lengths: [max_no_restricted_export_names]usize = undefined,
    storage: [max_no_restricted_export_names][max_no_restricted_export_name_len]u8 = undefined,

    pub fn contains(self: *const NoRestrictedExportNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoRestrictedExportNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoRestrictedExportNames, name: []const u8) NoRestrictedExportNamesError!void {
        if (name.len == 0) return error.EmptyNoRestrictedExportName;
        if (self.count >= max_no_restricted_export_names) return error.TooManyNoRestrictedExportNames;
        if (name.len > max_no_restricted_export_name_len) return error.NoRestrictedExportNameTooLong;
        if (self.contains(name)) return;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const NoRestrictedExportsDefaultOptions = struct {
    direct: bool = false,
    named: bool = false,
    default_from: bool = false,
    named_from: bool = false,
    namespace_from: bool = false,
};

pub const NoRestrictedImportKind = enum {
    path,
    pattern,
};

pub const NoRestrictedImportNameList = struct {
    count: usize = 0,
    lengths: [max_no_restricted_import_names]usize = undefined,
    storage: [max_no_restricted_import_names][max_no_restricted_import_name_len]u8 = undefined,

    pub fn contains(self: *const NoRestrictedImportNameList, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoRestrictedImportNameList, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoRestrictedImportNameList, name: []const u8) bool {
        if (name.len == 0 or name.len > max_no_restricted_import_name_len) return false;
        if (self.count >= max_no_restricted_import_names) return false;
        if (self.contains(name)) return true;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const NoRestrictedImportEntry = struct {
    kind: NoRestrictedImportKind = .path,
    source_length: usize = 0,
    source_storage: [max_no_restricted_import_source_len]u8 = undefined,

    has_message: bool = false,
    message_length: usize = 0,
    message_storage: [max_no_restricted_import_message_len]u8 = undefined,

    import_names: NoRestrictedImportNameList = .{},
    allow_import_names: NoRestrictedImportNameList = .{},
    allow_type_imports: bool = false,

    pub fn source(self: *const NoRestrictedImportEntry) []const u8 {
        return self.source_storage[0..self.source_length];
    }

    pub fn message(self: *const NoRestrictedImportEntry) ?[]const u8 {
        if (!self.has_message) return null;
        return self.message_storage[0..self.message_length];
    }

    pub fn setSource(self: *NoRestrictedImportEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_import_source_len) return false;
        @memcpy(self.source_storage[0..value.len], value);
        self.source_length = value.len;
        return true;
    }

    pub fn setMessage(self: *NoRestrictedImportEntry, value: []const u8) bool {
        if (value.len == 0 or value.len > max_no_restricted_import_message_len) return false;
        @memcpy(self.message_storage[0..value.len], value);
        self.message_length = value.len;
        self.has_message = true;
        return true;
    }
};

pub const NoRestrictedImports = struct {
    count: usize = 0,
    entries: [max_no_restricted_imports]NoRestrictedImportEntry = undefined,

    pub fn append(self: *NoRestrictedImports, entry: NoRestrictedImportEntry) bool {
        if (self.count >= max_no_restricted_imports) return false;
        self.entries[self.count] = entry;
        self.count += 1;
        return true;
    }

    pub fn appendPath(self: *NoRestrictedImports, name: []const u8) bool {
        var entry = NoRestrictedImportEntry{};
        entry.kind = .path;
        if (!entry.setSource(name)) return false;
        return self.append(entry);
    }

    pub fn at(self: *const NoRestrictedImports, index: usize) *const NoRestrictedImportEntry {
        return &self.entries[index];
    }
};

pub const NoRestrictedModules = NoRestrictedImports;

pub const max_no_unused_vars_ignore_pattern_len = 256;

pub const NoUnusedVarsIgnorePatternError = error{
    NoUnusedVarsIgnorePatternTooLong,
};

pub const NoUnusedVarsIgnorePattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_no_unused_vars_ignore_pattern_len]u8 = undefined,

    pub fn pattern(self: *const NoUnusedVarsIgnorePattern) ?[]const u8 {
        if (!self.custom) return null;
        return self.storage[0..self.length];
    }

    pub fn set(self: *NoUnusedVarsIgnorePattern, pattern_value: []const u8) NoUnusedVarsIgnorePatternError!void {
        if (pattern_value.len > max_no_unused_vars_ignore_pattern_len) return error.NoUnusedVarsIgnorePatternTooLong;
        @memcpy(self.storage[0..pattern_value.len], pattern_value);
        self.custom = true;
        self.length = pattern_value.len;
    }
};

pub const max_react_hooks_additional_hooks_pattern_len = 256;

pub const ReactHooksAdditionalHooksPatternError = error{
    ReactHooksAdditionalHooksPatternTooLong,
};

pub const ReactHooksAdditionalHooksPattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_react_hooks_additional_hooks_pattern_len]u8 = undefined,

    pub fn pattern(self: *const ReactHooksAdditionalHooksPattern) ?[]const u8 {
        if (!self.custom) return null;
        return self.storage[0..self.length];
    }

    pub fn set(self: *ReactHooksAdditionalHooksPattern, pattern_value: []const u8) ReactHooksAdditionalHooksPatternError!void {
        if (pattern_value.len > max_react_hooks_additional_hooks_pattern_len) return error.ReactHooksAdditionalHooksPatternTooLong;
        @memcpy(self.storage[0..pattern_value.len], pattern_value);
        self.custom = true;
        self.length = pattern_value.len;
    }
};

pub const max_react_no_unstable_nested_components_prop_name_pattern_len = 256;

pub const ReactNoUnstableNestedComponentsPropNamePattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_react_no_unstable_nested_components_prop_name_pattern_len]u8 = undefined,

    pub fn pattern(self: *const ReactNoUnstableNestedComponentsPropNamePattern) []const u8 {
        if (!self.custom) return "render*";
        return self.storage[0..self.length];
    }

    pub fn set(self: *ReactNoUnstableNestedComponentsPropNamePattern, pattern_value: []const u8) bool {
        if (pattern_value.len > max_react_no_unstable_nested_components_prop_name_pattern_len) return false;
        @memcpy(self.storage[0..pattern_value.len], pattern_value);
        self.custom = true;
        self.length = pattern_value.len;
        return true;
    }
};

pub const max_no_useless_escape_allow_regex_characters = 32;

pub const NoUselessEscapeAllowRegexCharactersError = error{
    EmptyNoUselessEscapeAllowRegexCharacter,
    TooManyNoUselessEscapeAllowRegexCharacters,
    NoUselessEscapeAllowRegexCharacterTooLong,
};

pub const NoUselessEscapeAllowRegexCharacters = struct {
    count: usize = 0,
    characters: [max_no_useless_escape_allow_regex_characters]u8 = undefined,

    pub fn contains(self: *const NoUselessEscapeAllowRegexCharacters, character: u8) bool {
        for (0..self.count) |index| {
            if (self.characters[index] == character) return true;
        }
        return false;
    }

    pub fn append(self: *NoUselessEscapeAllowRegexCharacters, character: []const u8) NoUselessEscapeAllowRegexCharactersError!void {
        if (character.len == 0) return error.EmptyNoUselessEscapeAllowRegexCharacter;
        if (character.len > 1) return error.NoUselessEscapeAllowRegexCharacterTooLong;
        if (self.count >= max_no_useless_escape_allow_regex_characters) return error.TooManyNoUselessEscapeAllowRegexCharacters;

        self.characters[self.count] = character[0];
        self.count += 1;
    }
};

pub const max_no_this_alias_allowed_names = 32;
pub const max_no_this_alias_allowed_name_len = 128;

pub const NoThisAliasAllowedNamesError = error{
    EmptyNoThisAliasAllowedName,
    TooManyNoThisAliasAllowedNames,
    NoThisAliasAllowedNameTooLong,
};

pub const NoThisAliasAllowedNames = struct {
    custom: bool = false,
    count: usize = 0,
    lengths: [max_no_this_alias_allowed_names]usize = undefined,
    storage: [max_no_this_alias_allowed_names][max_no_this_alias_allowed_name_len]u8 = undefined,

    pub fn contains(self: *const NoThisAliasAllowedNames, name: []const u8) bool {
        if (!self.custom) return std.mem.eql(u8, name, "self");

        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NoThisAliasAllowedNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NoThisAliasAllowedNames, name: []const u8) NoThisAliasAllowedNamesError!void {
        if (name.len == 0) return error.EmptyNoThisAliasAllowedName;
        if (self.count >= max_no_this_alias_allowed_names) return error.TooManyNoThisAliasAllowedNames;
        if (name.len > max_no_this_alias_allowed_name_len) return error.NoThisAliasAllowedNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_typescript_eslint_no_invalid_void_type_allowed_generic_type_names = 32;
pub const max_typescript_eslint_no_invalid_void_type_allowed_generic_type_name_len = 128;

pub const TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNamesError = error{
    EmptyAllowedGenericTypeName,
    TooManyAllowedGenericTypeNames,
    AllowedGenericTypeNameTooLong,
};

pub const TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNames = struct {
    count: usize = 0,
    lengths: [max_typescript_eslint_no_invalid_void_type_allowed_generic_type_names]usize = undefined,
    storage: [max_typescript_eslint_no_invalid_void_type_allowed_generic_type_names][max_typescript_eslint_no_invalid_void_type_allowed_generic_type_name_len]u8 = undefined,

    pub fn contains(self: *const TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNames, name: []const u8) TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNamesError!void {
        if (name.len == 0) return error.EmptyAllowedGenericTypeName;
        if (self.count >= max_typescript_eslint_no_invalid_void_type_allowed_generic_type_names) return error.TooManyAllowedGenericTypeNames;
        if (name.len > max_typescript_eslint_no_invalid_void_type_allowed_generic_type_name_len) return error.AllowedGenericTypeNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_react_jsx_pascal_case_ignore_names = 32;
pub const max_react_jsx_pascal_case_ignore_name_len = 128;

pub const react_jsx_filename_extension_default_extensions = [_][]const u8{
    ".jsx",
    ".js",
    ".tsx",
    ".ts",
    ".vue",
};

pub const max_react_jsx_filename_extensions = 16;
pub const max_react_jsx_filename_extension_len = 32;

pub const ReactJsxFilenameExtensionsError = error{
    EmptyReactJsxFilenameExtension,
    TooManyReactJsxFilenameExtensions,
    ReactJsxFilenameExtensionTooLong,
};

pub const ReactJsxFilenameExtensions = struct {
    custom: bool = false,
    count: usize = 0,
    lengths: [max_react_jsx_filename_extensions]usize = undefined,
    storage: [max_react_jsx_filename_extensions][max_react_jsx_filename_extension_len]u8 = undefined,

    pub fn len(self: *const ReactJsxFilenameExtensions) usize {
        return if (self.custom) self.count else react_jsx_filename_extension_default_extensions.len;
    }

    pub fn at(self: *const ReactJsxFilenameExtensions, index: usize) []const u8 {
        if (!self.custom) return react_jsx_filename_extension_default_extensions[index];
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn containsFilePath(self: *const ReactJsxFilenameExtensions, file_path: []const u8) bool {
        for (0..self.len()) |index| {
            if (std.mem.endsWith(u8, file_path, self.at(index))) return true;
        }
        return false;
    }

    pub fn append(self: *ReactJsxFilenameExtensions, extension_name: []const u8) ReactJsxFilenameExtensionsError!void {
        if (extension_name.len == 0) return error.EmptyReactJsxFilenameExtension;
        if (self.count >= max_react_jsx_filename_extensions) return error.TooManyReactJsxFilenameExtensions;
        if (extension_name.len > max_react_jsx_filename_extension_len) return error.ReactJsxFilenameExtensionTooLong;

        self.custom = true;
        @memcpy(self.storage[self.count][0..extension_name.len], extension_name);
        self.lengths[self.count] = extension_name.len;
        self.count += 1;
    }
};

pub const ReactJsxPascalCaseIgnoreNamesError = error{
    EmptyReactJsxPascalCaseIgnoreName,
    TooManyReactJsxPascalCaseIgnoreNames,
    ReactJsxPascalCaseIgnoreNameTooLong,
};

pub const ReactJsxPascalCaseIgnoreNames = struct {
    count: usize = 0,
    lengths: [max_react_jsx_pascal_case_ignore_names]usize = undefined,
    storage: [max_react_jsx_pascal_case_ignore_names][max_react_jsx_pascal_case_ignore_name_len]u8 = undefined,

    pub fn contains(self: *const ReactJsxPascalCaseIgnoreNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const ReactJsxPascalCaseIgnoreNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *ReactJsxPascalCaseIgnoreNames, name: []const u8) ReactJsxPascalCaseIgnoreNamesError!void {
        if (name.len == 0) return error.EmptyReactJsxPascalCaseIgnoreName;
        if (self.count >= max_react_jsx_pascal_case_ignore_names) return error.TooManyReactJsxPascalCaseIgnoreNames;
        if (name.len > max_react_jsx_pascal_case_ignore_name_len) return error.ReactJsxPascalCaseIgnoreNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_react_no_unknown_property_ignore_names = 32;
pub const max_react_no_unknown_property_ignore_name_len = 128;

pub const ReactNoUnknownPropertyIgnoreNamesError = error{
    EmptyReactNoUnknownPropertyIgnoreName,
    TooManyReactNoUnknownPropertyIgnoreNames,
    ReactNoUnknownPropertyIgnoreNameTooLong,
};

pub const ReactNoUnknownPropertyIgnoreNames = struct {
    count: usize = 0,
    lengths: [max_react_no_unknown_property_ignore_names]usize = undefined,
    storage: [max_react_no_unknown_property_ignore_names][max_react_no_unknown_property_ignore_name_len]u8 = undefined,

    pub fn contains(self: *const ReactNoUnknownPropertyIgnoreNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const ReactNoUnknownPropertyIgnoreNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *ReactNoUnknownPropertyIgnoreNames, name: []const u8) ReactNoUnknownPropertyIgnoreNamesError!void {
        if (name.len == 0) return error.EmptyReactNoUnknownPropertyIgnoreName;
        if (self.count >= max_react_no_unknown_property_ignore_names) return error.TooManyReactNoUnknownPropertyIgnoreNames;
        if (name.len > max_react_no_unknown_property_ignore_name_len) return error.ReactNoUnknownPropertyIgnoreNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_react_prop_types_ignore_names = 32;
pub const max_react_prop_types_ignore_name_len = 128;

pub const ReactPropTypesIgnoreNamesError = error{
    EmptyReactPropTypesIgnoreName,
    TooManyReactPropTypesIgnoreNames,
    ReactPropTypesIgnoreNameTooLong,
};

pub const ReactPropTypesIgnoreNames = struct {
    count: usize = 0,
    lengths: [max_react_prop_types_ignore_names]usize = undefined,
    storage: [max_react_prop_types_ignore_names][max_react_prop_types_ignore_name_len]u8 = undefined,

    pub fn contains(self: *const ReactPropTypesIgnoreNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn ignoresPath(self: *const ReactPropTypesIgnoreNames, path: []const u8) bool {
        for (0..self.count) |index| {
            const name = self.at(index);
            if (std.mem.eql(u8, path, name)) return true;
            if (path.len > name.len and path[name.len] == '.' and std.mem.eql(u8, path[0..name.len], name)) return true;
        }
        return false;
    }

    pub fn at(self: *const ReactPropTypesIgnoreNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *ReactPropTypesIgnoreNames, name: []const u8) ReactPropTypesIgnoreNamesError!void {
        if (name.len == 0) return error.EmptyReactPropTypesIgnoreName;
        if (self.count >= max_react_prop_types_ignore_names) return error.TooManyReactPropTypesIgnoreNames;
        if (name.len > max_react_prop_types_ignore_name_len) return error.ReactPropTypesIgnoreNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_jsx_a11y_img_redundant_alt_names = 32;
pub const max_jsx_a11y_img_redundant_alt_name_len = 128;

pub const JsxA11yImgRedundantAltNamesError = error{
    EmptyJsxA11yImgRedundantAltName,
    TooManyJsxA11yImgRedundantAltNames,
    JsxA11yImgRedundantAltNameTooLong,
};

pub const JsxA11yImgRedundantAltNames = struct {
    count: usize = 0,
    lengths: [max_jsx_a11y_img_redundant_alt_names]usize = undefined,
    storage: [max_jsx_a11y_img_redundant_alt_names][max_jsx_a11y_img_redundant_alt_name_len]u8 = undefined,

    pub fn contains(self: *const JsxA11yImgRedundantAltNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn containsIgnoreCase(self: *const JsxA11yImgRedundantAltNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.ascii.eqlIgnoreCase(self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const JsxA11yImgRedundantAltNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *JsxA11yImgRedundantAltNames, name: []const u8) JsxA11yImgRedundantAltNamesError!void {
        if (name.len == 0) return error.EmptyJsxA11yImgRedundantAltName;
        if (self.count >= max_jsx_a11y_img_redundant_alt_names) return error.TooManyJsxA11yImgRedundantAltNames;
        if (name.len > max_jsx_a11y_img_redundant_alt_name_len) return error.JsxA11yImgRedundantAltNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_typescript_eslint_ban_type_entries = 32;
pub const max_typescript_eslint_ban_type_name_len = 128;
pub const max_typescript_eslint_ban_type_message_len = 512;

pub const TypescriptEslintBanTypesConfigError = error{
    EmptyBanTypeName,
    BanTypeNameTooLong,
    BanTypeMessageTooLong,
    TooManyBanTypes,
};

pub const TypescriptEslintBanTypeNames = struct {
    count: usize = 0,
    lengths: [max_typescript_eslint_ban_type_entries]usize = undefined,
    storage: [max_typescript_eslint_ban_type_entries][max_typescript_eslint_ban_type_name_len]u8 = undefined,

    pub fn contains(self: *const TypescriptEslintBanTypeNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const TypescriptEslintBanTypeNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *TypescriptEslintBanTypeNames, name: []const u8) TypescriptEslintBanTypesConfigError!void {
        if (name.len == 0) return error.EmptyBanTypeName;
        if (name.len > max_typescript_eslint_ban_type_name_len) return error.BanTypeNameTooLong;
        if (self.count >= max_typescript_eslint_ban_type_entries) return error.TooManyBanTypes;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const TypescriptEslintBanTypeEntries = struct {
    count: usize = 0,
    name_lengths: [max_typescript_eslint_ban_type_entries]usize = undefined,
    message_lengths: [max_typescript_eslint_ban_type_entries]usize = undefined,
    names: [max_typescript_eslint_ban_type_entries][max_typescript_eslint_ban_type_name_len]u8 = undefined,
    messages: [max_typescript_eslint_ban_type_entries][max_typescript_eslint_ban_type_message_len]u8 = undefined,

    pub fn messageFor(self: *const TypescriptEslintBanTypeEntries, name: []const u8) ?[]const u8 {
        var index = self.count;
        while (index > 0) {
            index -= 1;
            if (std.mem.eql(u8, self.nameAt(index), name)) return self.messageAt(index);
        }
        return null;
    }

    pub fn nameAt(self: *const TypescriptEslintBanTypeEntries, index: usize) []const u8 {
        return self.names[index][0..self.name_lengths[index]];
    }

    pub fn messageAt(self: *const TypescriptEslintBanTypeEntries, index: usize) []const u8 {
        return self.messages[index][0..self.message_lengths[index]];
    }

    pub fn append(
        self: *TypescriptEslintBanTypeEntries,
        name: []const u8,
        message: []const u8,
    ) TypescriptEslintBanTypesConfigError!void {
        if (name.len == 0) return error.EmptyBanTypeName;
        if (name.len > max_typescript_eslint_ban_type_name_len) return error.BanTypeNameTooLong;
        if (message.len > max_typescript_eslint_ban_type_message_len) return error.BanTypeMessageTooLong;
        if (self.count >= max_typescript_eslint_ban_type_entries) return error.TooManyBanTypes;

        @memcpy(self.names[self.count][0..name.len], name);
        @memcpy(self.messages[self.count][0..message.len], message);
        self.name_lengths[self.count] = name.len;
        self.message_lengths[self.count] = message.len;
        self.count += 1;
    }
};

pub const TypescriptEslintBanTypesConfig = struct {
    extend_defaults: bool = true,
    disabled: TypescriptEslintBanTypeNames = .{},
    custom: TypescriptEslintBanTypeEntries = .{},
};

pub const max_new_cap_exception_names = 32;
pub const max_new_cap_exception_name_len = 128;

pub const NewCapExceptionNamesError = error{
    EmptyNewCapExceptionName,
    TooManyNewCapExceptionNames,
    NewCapExceptionNameTooLong,
};

pub const NewCapExceptionNames = struct {
    count: usize = 0,
    lengths: [max_new_cap_exception_names]usize = undefined,
    storage: [max_new_cap_exception_names][max_new_cap_exception_name_len]u8 = undefined,

    pub fn contains(self: *const NewCapExceptionNames, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const NewCapExceptionNames, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *NewCapExceptionNames, name: []const u8) NewCapExceptionNamesError!void {
        if (name.len == 0) return error.EmptyNewCapExceptionName;
        if (self.count >= max_new_cap_exception_names) return error.TooManyNewCapExceptionNames;
        if (name.len > max_new_cap_exception_name_len) return error.NewCapExceptionNameTooLong;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
    }
};

pub const max_new_cap_exception_pattern_len = 256;

pub const NewCapExceptionPatternError = error{
    NewCapExceptionPatternTooLong,
};

pub const NewCapExceptionPattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_new_cap_exception_pattern_len]u8 = undefined,

    pub fn pattern(self: *const NewCapExceptionPattern) ?[]const u8 {
        if (!self.custom) return null;
        return self.storage[0..self.length];
    }

    pub fn set(self: *NewCapExceptionPattern, pattern_value: []const u8) NewCapExceptionPatternError!void {
        if (pattern_value.len > max_new_cap_exception_pattern_len) return error.NewCapExceptionPatternTooLong;
        @memcpy(self.storage[0..pattern_value.len], pattern_value);
        self.custom = true;
        self.length = pattern_value.len;
    }
};

pub const NoUselessComputedKeyEnforceForClassMembers = enum {
    yes,
    no,
};

pub const WrapIifeStyle = enum {
    outside,
    inside,
    any,
};

pub const AccessorPairsGetWithoutSet = enum {
    yes,
    no,
};

pub const AccessorPairsSetWithoutGet = enum {
    yes,
    no,
};

pub const AccessorPairsEnforceForClassMembers = enum {
    yes,
    no,
};

pub const GroupedAccessorPairsStyle = enum {
    any_order,
    get_before_set,
    set_before_get,
};

pub const LogicalAssignmentOperatorsEnforceForIfStatements = enum {
    yes,
    no,
};

pub const LogicalAssignmentOperatorsStyle = enum {
    always,
    never,
};

pub const ReactJsxBooleanValueStyle = enum {
    never,
    always,
};

pub const ReactPreferEs6ClassStyle = enum {
    always,
    never,
};

pub const FuncNamesStyle = enum {
    always,
    as_needed,
    never,
};

pub const FuncStyleStyle = enum {
    expression,
    declaration,
};

pub const FuncStyleNamedExports = enum {
    unset,
    expression,
    declaration,
    ignore,
};

pub const FuncNameMatchingStyle = enum {
    always,
    never,
};

pub const NoConstantConditionCheckLoops = enum {
    all,
    all_except_while_true,
    none,
};

pub const YodaStyle = enum {
    never,
    always,
};

pub const TypescriptEslintMethodSignatureStyle = enum {
    property,
    method,
};

pub const TypescriptEslintArrayTypeStyle = enum {
    array,
    array_simple,
    generic,
};

pub const TypescriptEslintBanTsCommentMode = enum {
    allow,
    ban,
    allow_with_description,
};

pub const TypescriptEslintConsistentTypeDefinitionsStyle = enum {
    interface,
    type,
};

pub const TypescriptEslintNoEmptyObjectTypeAllowInterfaces = enum {
    always,
    never,
    with_single_extends,
};

pub const TypescriptEslintNoEmptyObjectTypeAllowObjectTypes = enum {
    always,
    never,
};

pub const TypescriptEslintNoEmptyObjectTypeAllowWithName = NoUnusedVarsIgnorePattern;

pub const TypescriptEslintClassLiteralPropertyStyle = enum {
    fields,
    getters,
};

pub const TypescriptEslintConsistentTypeAssertionsStyle = enum {
    as,
    angle_bracket,
    never,
};

pub const TypescriptEslintLiteralTypeAssertions = enum {
    allow,
    allow_as_parameter,
    never,
};

pub const TypescriptEslintExplicitMemberAccessibility = enum {
    explicit,
    no_public,
    off,
};

pub const TypescriptEslintTripleSlashReferenceMode = enum {
    always,
    never,
};

pub const PreferConstDestructuring = enum {
    any,
    all,
};

pub const ArrayCallbackReturnAllowImplicit = enum {
    yes,
    no,
};

pub const ArrayCallbackReturnCheckForEach = enum {
    yes,
    no,
};

pub const ArrayCallbackReturnAllowVoid = enum {
    yes,
    no,
};

pub const CapitalizedCommentsMode = enum {
    always,
    never,
};

pub const CapitalizedCommentsIgnoreInlineComments = enum {
    yes,
    no,
};

pub const CapitalizedCommentsIgnoreConsecutiveComments = enum {
    yes,
    no,
};

pub const DotNotationAllowKeywords = enum {
    yes,
    no,
};

pub const max_no_inline_comments_ignore_pattern_len = 256;

pub const NoInlineCommentsIgnorePatternError = error{
    NoInlineCommentsIgnorePatternTooLong,
};

pub const NoInlineCommentsIgnorePattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_no_inline_comments_ignore_pattern_len]u8 = undefined,

    pub fn pattern(self: *const NoInlineCommentsIgnorePattern) ?[]const u8 {
        if (!self.custom) return null;
        return self.storage[0..self.length];
    }

    pub fn set(self: *NoInlineCommentsIgnorePattern, pattern_value: []const u8) NoInlineCommentsIgnorePatternError!void {
        if (pattern_value.len > max_no_inline_comments_ignore_pattern_len) return error.NoInlineCommentsIgnorePatternTooLong;
        @memcpy(self.storage[0..pattern_value.len], pattern_value);
        self.custom = true;
        self.length = pattern_value.len;
    }
};

pub const max_promise_always_return_ignore_assignment_variables = 32;
pub const max_promise_always_return_ignore_assignment_variable_len = 128;

pub const PromiseAlwaysReturnIgnoreAssignmentVariables = struct {
    custom: bool = false,
    count: usize = 0,
    lengths: [max_promise_always_return_ignore_assignment_variables]usize = undefined,
    storage: [max_promise_always_return_ignore_assignment_variables][max_promise_always_return_ignore_assignment_variable_len]u8 = undefined,

    pub fn contains(self: *const PromiseAlwaysReturnIgnoreAssignmentVariables, name: []const u8) bool {
        if (!self.custom) return std.mem.eql(u8, name, "globalThis");
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const PromiseAlwaysReturnIgnoreAssignmentVariables, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *PromiseAlwaysReturnIgnoreAssignmentVariables, name: []const u8) bool {
        if (name.len == 0) return false;
        if (self.count >= max_promise_always_return_ignore_assignment_variables) return false;
        if (name.len > max_promise_always_return_ignore_assignment_variable_len) return false;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const max_dot_notation_allow_pattern_len = 256;

pub const DotNotationAllowPatternError = error{
    DotNotationAllowPatternTooLong,
};

pub const DotNotationAllowPattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_dot_notation_allow_pattern_len]u8 = undefined,

    pub fn pattern(self: *const DotNotationAllowPattern) ?[]const u8 {
        if (!self.custom) return null;
        return self.storage[0..self.length];
    }

    pub fn set(self: *DotNotationAllowPattern, pattern_value: []const u8) DotNotationAllowPatternError!void {
        if (pattern_value.len > max_dot_notation_allow_pattern_len) return error.DotNotationAllowPatternTooLong;
        @memcpy(self.storage[0..pattern_value.len], pattern_value);
        self.custom = true;
        self.length = pattern_value.len;
    }
};

pub const max_default_case_comment_pattern_len = 256;

pub const DefaultCaseCommentPatternError = error{
    DefaultCaseCommentPatternTooLong,
};

pub const DefaultCaseCommentPattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_default_case_comment_pattern_len]u8 = undefined,

    pub fn pattern(self: *const DefaultCaseCommentPattern) ?[]const u8 {
        if (!self.custom) return null;
        return self.storage[0..self.length];
    }

    pub fn set(self: *DefaultCaseCommentPattern, pattern_value: []const u8) DefaultCaseCommentPatternError!void {
        if (pattern_value.len > max_default_case_comment_pattern_len) return error.DefaultCaseCommentPatternTooLong;
        @memcpy(self.storage[0..pattern_value.len], pattern_value);
        self.custom = true;
        self.length = pattern_value.len;
    }
};

pub const max_no_fallthrough_comment_pattern_len = 256;

pub const NoFallthroughCommentPatternError = error{
    NoFallthroughCommentPatternTooLong,
};

pub const NoFallthroughCommentPattern = struct {
    custom: bool = false,
    length: usize = 0,
    storage: [max_no_fallthrough_comment_pattern_len]u8 = undefined,

    pub fn pattern(self: *const NoFallthroughCommentPattern) ?[]const u8 {
        if (!self.custom) return null;
        return self.storage[0..self.length];
    }

    pub fn set(self: *NoFallthroughCommentPattern, pattern_value: []const u8) NoFallthroughCommentPatternError!void {
        if (pattern_value.len > max_no_fallthrough_comment_pattern_len) return error.NoFallthroughCommentPatternTooLong;
        @memcpy(self.storage[0..pattern_value.len], pattern_value);
        self.custom = true;
        self.length = pattern_value.len;
    }
};

pub const max_promise_no_callback_in_promise_exceptions = 32;
pub const max_promise_no_callback_in_promise_exception_len = 128;

pub const PromiseNoCallbackInPromiseExceptions = struct {
    count: usize = 0,
    lengths: [max_promise_no_callback_in_promise_exceptions]usize = undefined,
    storage: [max_promise_no_callback_in_promise_exceptions][max_promise_no_callback_in_promise_exception_len]u8 = undefined,

    pub fn contains(self: *const PromiseNoCallbackInPromiseExceptions, name: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const PromiseNoCallbackInPromiseExceptions, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *PromiseNoCallbackInPromiseExceptions, name: []const u8) bool {
        if (name.len == 0) return false;
        if (name.len > max_promise_no_callback_in_promise_exception_len) return false;
        if (self.count >= max_promise_no_callback_in_promise_exceptions) return false;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const max_promise_catch_or_return_termination_methods = 32;
pub const max_promise_catch_or_return_termination_method_len = 128;

pub const PromiseCatchOrReturnTerminationMethods = struct {
    custom: bool = false,
    count: usize = 0,
    lengths: [max_promise_catch_or_return_termination_methods]usize = undefined,
    storage: [max_promise_catch_or_return_termination_methods][max_promise_catch_or_return_termination_method_len]u8 = undefined,

    pub fn contains(self: *const PromiseCatchOrReturnTerminationMethods, name: []const u8) bool {
        if (!self.custom) return std.mem.eql(u8, name, "catch");
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const PromiseCatchOrReturnTerminationMethods, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *PromiseCatchOrReturnTerminationMethods, name: []const u8) bool {
        if (name.len > max_promise_catch_or_return_termination_method_len) return false;
        if (self.count >= max_promise_catch_or_return_termination_methods) return false;

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const Options = struct {
    accessor_pairs: bool = true,
    accessor_pairs_get_without_set: AccessorPairsGetWithoutSet = .no,
    accessor_pairs_set_without_get: AccessorPairsSetWithoutGet = .yes,
    accessor_pairs_enforce_for_class_members: AccessorPairsEnforceForClassMembers = .yes,
    array_callback_return: bool = true,
    array_callback_return_allow_implicit: ArrayCallbackReturnAllowImplicit = .no,
    array_callback_return_check_for_each: ArrayCallbackReturnCheckForEach = .no,
    array_callback_return_allow_void: ArrayCallbackReturnAllowVoid = .no,
    arrow_body_style: bool = false,
    arrow_body_style_style: ArrowBodyStyle = .as_needed,
    arrow_body_style_require_return_for_object_literal: bool = false,
    block_scoped_var: bool = true,
    camelcase: bool = false,
    camelcase_properties: CamelcaseProperties = .always,
    camelcase_ignore_destructuring: bool = false,
    camelcase_ignore_imports: bool = false,
    camelcase_ignore_globals: bool = false,
    camelcase_allow: CamelcaseAllowPatterns = .{},
    capitalized_comments: bool = true,
    capitalized_comments_mode: CapitalizedCommentsMode = .always,
    capitalized_comments_ignore_inline_comments: CapitalizedCommentsIgnoreInlineComments = .no,
    capitalized_comments_ignore_consecutive_comments: CapitalizedCommentsIgnoreConsecutiveComments = .no,
    class_methods_use_this: bool = false,
    class_methods_use_this_enforce_for_class_fields: bool = true,
    class_methods_use_this_except_methods: ClassMethodsUseThisExceptMethods = .{},
    class_methods_use_this_ignore_override_methods: bool = false,
    class_methods_use_this_ignore_classes_with_implements: ClassMethodsUseThisIgnoreClassesWithImplements = .none,
    complexity: bool = true,
    complexity_max: usize = 20,
    complexity_variant: ComplexityVariant = .classic,
    consistent_this: bool = false,
    consistent_this_aliases: ConsistentThisAliases = .{},
    consistent_return: bool = true,
    consistent_return_treat_undefined_as_unspecified: bool = false,
    constructor_super: bool = true,
    curly: bool = true,
    curly_style: CurlyStyle = .all,
    dot_notation: bool = true,
    dot_notation_allow_keywords: DotNotationAllowKeywords = .yes,
    dot_notation_allow_pattern: DotNotationAllowPattern = .{},
    typescript_eslint_dot_notation: bool = true,
    default_case: bool = true,
    default_case_comment_pattern: DefaultCaseCommentPattern = .{},
    default_case_last: bool = true,
    default_param_last: bool = true,
    eol_last: bool = true,
    eol_last_style: EolLastStyle = .always,
    eslint_comments_no_restricted_disable: bool = true,
    eslint_comments_no_restricted_disable_no_nested_ternary: bool = false,
    for_direction: bool = true,
    func_name_matching: bool = true,
    func_name_matching_style: FuncNameMatchingStyle = .always,
    func_name_matching_include_commonjs_module_exports: bool = false,
    func_name_matching_consider_property_descriptor: bool = false,
    func_names: bool = true,
    func_names_style: FuncNamesStyle = .always,
    func_names_has_generator_style: bool = false,
    func_names_generator_style: FuncNamesStyle = .always,
    func_style: bool = false,
    func_style_style: FuncStyleStyle = .expression,
    func_style_allow_arrow_functions: bool = false,
    func_style_allow_type_annotation: bool = false,
    func_style_named_exports: FuncStyleNamedExports = .unset,
    getter_return: bool = true,
    getter_return_allow_implicit: bool = false,
    grouped_accessor_pairs: bool = true,
    grouped_accessor_pairs_style: GroupedAccessorPairsStyle = .any_order,
    guard_for_in: bool = true,
    id_denylist: bool = true,
    id_denylist_names: IdDenylistNames = .{},
    id_length: bool = false,
    id_length_min: usize = 2,
    id_length_has_max: bool = false,
    id_length_max: usize = 0,
    id_length_properties: IdLengthProperties = .always,
    id_length_exceptions: IdLengthExceptions = .{},
    id_length_exception_patterns: IdLengthExceptionPatterns = .{},
    id_match: bool = false,
    id_match_pattern: IdMatchPattern = .{},
    id_match_properties: bool = false,
    id_match_class_fields: bool = false,
    id_match_only_declarations: bool = false,
    id_match_ignore_destructuring: bool = false,
    init_declarations: bool = false,
    init_declarations_mode: InitDeclarationsMode = .always,
    init_declarations_ignore_for_loop_init: bool = false,
    linebreak_style: bool = true,
    linebreak_style_style: LinebreakStyle = .unix,
    logical_assignment_operators: bool = true,
    logical_assignment_operators_style: LogicalAssignmentOperatorsStyle = .always,
    logical_assignment_operators_enforce_for_if_statements: LogicalAssignmentOperatorsEnforceForIfStatements = .no,
    max_classes_per_file: bool = true,
    max_classes_per_file_max: usize = 1,
    max_classes_per_file_ignore_expressions: bool = false,
    max_depth: bool = true,
    max_depth_max: usize = 4,
    max_lines: bool = false,
    max_lines_max: usize = 300,
    max_lines_skip_blank_lines: bool = false,
    max_lines_skip_comments: bool = false,
    max_lines_per_function: bool = false,
    max_lines_per_function_max: usize = 50,
    max_lines_per_function_skip_blank_lines: bool = false,
    max_lines_per_function_skip_comments: bool = false,
    max_lines_per_function_iifes: bool = false,
    max_nested_callbacks: bool = true,
    max_nested_callbacks_max: usize = 10,
    max_params: bool = true,
    max_params_max: usize = 3,
    max_params_count_this: MaxParamsCountThis = .except_void,
    max_statements: bool = true,
    max_statements_max: usize = 10,
    max_statements_ignore_top_level_functions: bool = false,
    new_cap: bool = true,
    new_cap_new_is_cap: bool = true,
    new_cap_cap_is_new: bool = true,
    new_cap_properties: bool = true,
    new_cap_new_is_cap_exceptions: NewCapExceptionNames = .{},
    new_cap_cap_is_new_exceptions: NewCapExceptionNames = .{},
    new_cap_new_is_cap_exception_pattern: NewCapExceptionPattern = .{},
    new_cap_cap_is_new_exception_pattern: NewCapExceptionPattern = .{},
    new_parens: bool = true,
    no_async_promise_executor: bool = true,
    no_array_constructor: bool = true,
    no_await_in_loop: bool = true,
    no_alert: bool = true,
    no_bitwise: bool = true,
    no_bitwise_allow_bitwise_and: bool = false,
    no_bitwise_allow_bitwise_or: bool = false,
    no_bitwise_allow_bitwise_xor: bool = false,
    no_bitwise_allow_bitwise_not: bool = false,
    no_bitwise_allow_left_shift: bool = false,
    no_bitwise_allow_right_shift: bool = false,
    no_bitwise_allow_unsigned_right_shift: bool = false,
    no_bitwise_int32_hint: bool = false,
    no_buffer_constructor: bool = true,
    no_caller: bool = true,
    no_case_declarations: bool = true,
    no_class_assign: bool = true,
    no_confusing_arrow: bool = true,
    no_confusing_arrow_allow_parens: NoConfusingArrowAllowParens = .yes,
    no_cond_assign: bool = true,
    no_cond_assign_style: NoCondAssignStyle = .except_parens,
    no_compare_neg_zero: bool = true,
    no_constant_binary_expression: bool = true,
    no_constant_condition: bool = true,
    no_constant_condition_check_loops: NoConstantConditionCheckLoops = .all_except_while_true,
    no_const_assign: bool = true,
    no_control_regex: bool = true,
    no_console: bool = true,
    no_console_allow: NoConsoleAllow = .{},
    no_comma_operator: bool = true,
    no_continue: bool = true,
    no_constructor_return: bool = true,
    no_debugger: bool = true,
    no_dupe_else_if: bool = true,
    no_duplicate_case: bool = true,
    no_dupe_args: bool = true,
    no_dupe_class_members: bool = true,
    typescript_eslint_no_dupe_class_members: bool = true,
    no_dupe_keys: bool = true,
    no_duplicate_imports: bool = true,
    no_duplicate_imports_allow_separate_type_imports: bool = false,
    no_duplicate_imports_include_exports: bool = false,
    no_delete_var: bool = true,
    no_div_regex: bool = true,
    no_empty: bool = true,
    no_empty_allow_empty_catch: NoEmptyAllowEmptyCatch = .no,
    no_empty_block_statements: bool = true,
    no_empty_character_class: bool = true,
    no_empty_function: bool = true,
    no_empty_function_allow: NoEmptyFunctionAllow = .{},
    no_empty_pattern: bool = true,
    no_empty_pattern_allow_object_patterns_as_parameters: bool = false,
    no_empty_static_block: bool = true,
    no_else_return: bool = true,
    no_else_return_allow_else_if: bool = true,
    no_eq_null: bool = true,
    no_eval: bool = true,
    no_eval_allow_indirect: bool = false,
    no_ex_assign: bool = true,
    no_extend_native: bool = true,
    no_extend_native_exceptions: NoExtendNativeExceptions = .{},
    no_extra_bind: bool = true,
    no_extra_label: bool = true,
    no_extra_semi: bool = true,
    no_extra_boolean_cast: bool = true,
    no_extra_boolean_cast_enforce_for_inner_expressions: bool = false,
    no_floating_decimal: bool = true,
    no_fallthrough: bool = true,
    no_fallthrough_allow_empty_case: NoFallthroughAllowEmptyCase = .no,
    no_fallthrough_comment_pattern: NoFallthroughCommentPattern = .{},
    no_fallthrough_report_unused_fallthrough_comment: bool = false,
    no_for_in: bool = true,
    no_func_assign: bool = true,
    no_global_assign: bool = true,
    no_global_assign_exceptions: NoShadowAllowNames = .{},
    no_global_is_finite: bool = true,
    no_global_is_nan: bool = true,
    no_implicit_coercion: bool = true,
    no_implicit_coercion_boolean: NoImplicitCoercionBoolean = .yes,
    no_implicit_coercion_number: NoImplicitCoercionNumber = .yes,
    no_implicit_coercion_string: NoImplicitCoercionString = .yes,
    no_implicit_coercion_allow_double_negation: bool = false,
    no_implicit_coercion_allow_bitwise_not: bool = false,
    no_implicit_coercion_allow_plus: bool = false,
    no_implicit_coercion_allow_multiply: bool = false,
    no_implicit_coercion_allow_subtract: bool = false,
    no_implicit_coercion_allow_double_negative: bool = false,
    no_implicit_coercion_disallow_template_shorthand: bool = false,
    no_implicit_globals: bool = false,
    no_implicit_globals_lexical_bindings: bool = false,
    no_implied_eval: bool = true,
    no_import_assign: bool = true,
    alipay_ant_disallow_typos: bool = true,
    alipay_ant_exhaustive_deps: bool = true,
    alipay_ant_jsx_handler_names: bool = true,
    alipay_ant_no_deprecated_dependence: bool = true,
    alipay_ant_no_deprecated_dependence_profile: DeprecatedDependenceProfile = .default,
    alipay_ant_no_deprecated_variable: bool = true,
    alipay_ant_no_import_files_from_pages_in_common: bool = true,
    alipay_ant_no_negative_conditionals: bool = true,
    alipay_ant_no_import_src: bool = true,
    alipay_ant_no_phantom_dependencies: bool = true,
    alipay_ant_no_too_large_file: bool = true,
    alipay_ant_prefer_elseif_end_with_else: bool = true,
    alipay_ant_prefer_catch_unsafe_func_call: bool = true,
    alipay_ant_prefer_click_with_debounce: bool = true,
    alipay_ant_prefer_import_as_required: bool = true,
    alipay_ant_no_spread_params: bool = true,
    alipay_ant_prefer_managed_resource: bool = true,
    alipay_ant_prefer_safe_image_renderer: bool = true,
    alipay_ant_prefer_import_from_stdlib: bool = true,
    alipay_spmlint_use_labeled_spm: bool = true,
    alipay_spmlint_valid_manual_click: bool = true,
    alipay_spmlint_valid_manual_expo: bool = true,
    alipay_spmlint_valid_manual_param: bool = true,
    alipay_spmlint_valid_manual_pv: bool = true,
    import_default: bool = true,
    import_export: bool = true,
    import_first: bool = true,
    import_named: bool = true,
    import_namespace: bool = true,
    import_newline_after_import: bool = true,
    import_newline_after_import_count: usize = 1,
    import_newline_after_import_exact_count: bool = false,
    import_newline_after_import_consider_comments: bool = false,
    import_no_amd: bool = true,
    import_no_cycle: bool = true,
    import_no_cycle_amd: bool = false,
    import_no_cycle_commonjs: bool = false,
    import_no_cycle_max_depth: usize = 1024,
    import_no_duplicates: bool = true,
    import_no_duplicates_consider_query_string: bool = false,
    import_no_named_as_default: bool = true,
    import_no_named_as_default_member: bool = true,
    import_no_unresolved: bool = true,
    import_no_unresolved_amd: bool = false,
    import_no_unresolved_commonjs: bool = false,
    import_no_unresolved_ignore: ImportNoUnresolvedIgnorePatterns = .{},
    import_no_self_import: bool = true,
    jest_no_conditional_expect: bool = true,
    jest_no_deprecated_functions: bool = true,
    jest_no_export: bool = true,
    jest_no_focused_tests: bool = true,
    jest_no_identical_title: bool = true,
    jest_no_interpolation_in_snapshots: bool = true,
    jest_no_jasmine_globals: bool = true,
    jest_no_mocks_import: bool = true,
    jest_no_standalone_expect: bool = true,
    jest_no_standalone_expect_additional_test_block_functions: JestAdditionalTestBlockFunctions = .{},
    jest_valid_describe_callback: bool = true,
    jest_valid_expect_in_promise: bool = true,
    jest_valid_expect: bool = true,
    jest_valid_expect_always_await: bool = false,
    jest_valid_expect_async_matchers: JestValidExpectAsyncMatchers = .{},
    jest_valid_expect_min_args: f64 = 1,
    jest_valid_expect_max_args: f64 = 1,
    jest_valid_title: bool = true,
    jest_valid_title_ignore_spaces: bool = false,
    jest_valid_title_ignore_type_of_describe_name: bool = false,
    jest_valid_title_ignore_type_of_test_name: bool = false,
    jest_valid_title_disallowed_words: JestValidTitleDisallowedWords = .{},
    jest_valid_title_must_not_match: JestValidTitleMatchers = .{},
    jest_valid_title_must_match: JestValidTitleMatchers = .{},
    jest_global_aliases: JestGlobalAliases = .{},
    jest_version: u32 = 0,
    jsx_a11y_alt_text: bool = true,
    jsx_a11y_alt_text_img: bool = true,
    jsx_a11y_alt_text_object: bool = true,
    jsx_a11y_alt_text_area: bool = true,
    jsx_a11y_alt_text_input_image: bool = true,
    jsx_a11y_alt_text_img_components: JsxA11yImgRedundantAltNames = .{},
    jsx_a11y_alt_text_object_components: JsxA11yImgRedundantAltNames = .{},
    jsx_a11y_alt_text_area_components: JsxA11yImgRedundantAltNames = .{},
    jsx_a11y_alt_text_input_image_components: JsxA11yImgRedundantAltNames = .{},
    jsx_a11y_anchor_has_content: bool = true,
    jsx_a11y_anchor_has_content_components: JsxA11yImgRedundantAltNames = .{},
    jsx_a11y_aria_props: bool = true,
    jsx_a11y_aria_proptypes: bool = true,
    jsx_a11y_aria_role: bool = true,
    jsx_a11y_aria_role_allowed_invalid_roles: JsxA11yImgRedundantAltNames = .{},
    jsx_a11y_aria_role_ignore_non_dom: bool = true,
    jsx_a11y_aria_unsupported_elements: bool = true,
    jsx_a11y_iframe_has_title: bool = true,
    jsx_a11y_img_redundant_alt: bool = true,
    jsx_a11y_img_redundant_alt_components: JsxA11yImgRedundantAltNames = .{},
    jsx_a11y_img_redundant_alt_words: JsxA11yImgRedundantAltNames = .{},
    jsx_a11y_no_access_key: bool = true,
    jsx_a11y_no_distracting_elements: bool = true,
    jsx_a11y_no_distracting_elements_marquee: bool = true,
    jsx_a11y_no_distracting_elements_blink: bool = true,
    jsx_a11y_role_has_required_aria_props: bool = true,
    jsx_a11y_role_supports_aria_props: bool = true,
    jsx_a11y_scope: bool = true,
    no_invalid_regexp: bool = true,
    no_invalid_regexp_allow_constructor_flags: NoInvalidRegexpAllowConstructorFlags = .{},
    no_invalid_this: bool = false,
    no_invalid_this_cap_is_constructor: NoInvalidThisCapIsConstructor = .yes,
    no_irregular_whitespace: bool = true,
    no_irregular_whitespace_skip_strings: bool = true,
    no_irregular_whitespace_skip_comments: bool = false,
    no_irregular_whitespace_skip_reg_exps: bool = false,
    no_irregular_whitespace_skip_templates: bool = false,
    no_irregular_whitespace_skip_jsx_text: bool = false,
    no_inline_comments: bool = true,
    no_inline_comments_ignore_pattern: NoInlineCommentsIgnorePattern = .{},
    no_inner_declarations: bool = true,
    no_inner_declarations_mode: NoInnerDeclarationsMode = .functions,
    no_iterator: bool = true,
    no_label_var: bool = true,
    no_labels: bool = true,
    no_labels_allow_loop: NoLabelsAllowLoop = .no,
    no_labels_allow_switch: NoLabelsAllowSwitch = .no,
    no_lone_blocks: bool = true,
    no_lonely_if: bool = true,
    no_loop_func: bool = true,
    no_loss_of_precision: bool = true,
    no_magic_numbers: bool = false,
    no_magic_numbers_detect_objects: bool = false,
    no_magic_numbers_enforce_const: bool = false,
    no_magic_numbers_ignore: NoMagicNumbersIgnoreValues = .{},
    no_magic_numbers_ignore_array_indexes: bool = false,
    no_magic_numbers_ignore_default_values: bool = false,
    no_magic_numbers_ignore_class_field_initial_values: bool = false,
    no_magic_numbers_ignore_enums: bool = false,
    no_magic_numbers_ignore_numeric_literal_types: bool = false,
    no_magic_numbers_ignore_readonly_class_properties: bool = false,
    no_magic_numbers_ignore_type_indexes: bool = false,
    no_multi_str: bool = true,
    no_multi_assign: bool = true,
    no_multi_assign_ignore_non_declaration: bool = false,
    no_multi_spaces: bool = true,
    no_multi_spaces_ignore_eol_comments: NoMultiSpacesIgnoreEOLComments = .no,
    no_multi_spaces_exceptions: NoMultiSpacesExceptions = .{},
    no_mixed_spaces_and_tabs: bool = true,
    no_mixed_spaces_and_tabs_smart_tabs: bool = false,
    no_misleading_character_class: bool = true,
    no_multiple_empty_lines: bool = true,
    no_multiple_empty_lines_max: usize = 2,
    no_multiple_empty_lines_max_bof: ?usize = null,
    no_multiple_empty_lines_max_eof: ?usize = null,
    no_nonoctal_decimal_escape: bool = true,
    no_new: bool = true,
    no_nested_ternary: bool = true,
    no_negated_condition: bool = true,
    no_new_native_nonconstructor: bool = true,
    no_new_func: bool = true,
    no_new_require: bool = true,
    no_obj_calls: bool = true,
    no_new_object: bool = true,
    no_new_symbol: bool = true,
    no_new_wrappers: bool = true,
    no_octal: bool = true,
    no_octal_escape: bool = true,
    no_object_constructor: bool = true,
    no_param_reassign: bool = true,
    no_param_reassign_props: NoParamReassignProps = .no,
    no_param_reassign_ignore_property_modifications_for: NoParamReassignIgnoredNames = .{},
    no_param_reassign_ignore_property_modifications_for_regex: NoParamReassignIgnoredNamePatterns = .{},
    no_path_concat: bool = true,
    no_plusplus: bool = true,
    no_plusplus_allow_for_loop_afterthoughts: NoPlusplusAllowForLoopAfterthoughts = .no,
    no_promise_executor_return: bool = true,
    no_promise_executor_return_allow_void: bool = false,
    no_proto: bool = true,
    no_process_env: bool = true,
    no_process_exit: bool = true,
    no_prototype_builtins: bool = true,
    no_redeclare: bool = true,
    no_redeclare_builtin_globals: NoRedeclareBuiltinGlobals = .no,
    no_restricted_exports: bool = false,
    no_restricted_exports_names: NoRestrictedExportNames = .{},
    no_restricted_exports_default: NoRestrictedExportsDefaultOptions = .{},
    no_restricted_globals: bool = false,
    no_restricted_globals_entries: NoRestrictedGlobals = .{},
    no_restricted_imports: bool = false,
    no_restricted_imports_entries: NoRestrictedImports = .{},
    no_restricted_modules: bool = false,
    no_restricted_modules_entries: NoRestrictedModules = .{},
    no_restricted_properties: bool = true,
    no_restricted_properties_entries: NoRestrictedProperties = .{},
    no_restricted_syntax: bool = false,
    no_restricted_syntax_entries: NoRestrictedSyntax = .{},
    no_regex_spaces: bool = true,
    no_return_await: bool = true,
    no_return_assign: bool = true,
    no_return_assign_style: NoReturnAssignStyle = .except_parens,
    no_useless_return: bool = true,
    no_script_url: bool = true,
    no_self_assign: bool = true,
    no_self_assign_props: bool = true,
    no_self_compare: bool = true,
    no_setter_return: bool = true,
    no_shadow: bool = true,
    no_shadow_allow: NoShadowAllowNames = .{},
    no_shadow_builtin_globals: bool = false,
    no_shadow_hoist: NoShadowHoist = .functions,
    no_shadow_ignore_on_initialization: bool = false,
    no_shadow_restricted_names: bool = true,
    no_sequences: bool = true,
    no_sequences_allow_in_parentheses: NoSequencesAllowInParentheses = .yes,
    no_sparse_arrays: bool = true,
    no_ternary: bool = true,
    no_template_curly_in_string: bool = true,
    no_throw_literal: bool = true,
    no_this_before_super: bool = true,
    no_tabs: bool = true,
    no_tabs_allow_indentation_tabs: bool = false,
    no_trailing_spaces: bool = true,
    no_trailing_spaces_skip_blank_lines: bool = false,
    no_trailing_spaces_ignore_comments: bool = false,
    no_unreachable: bool = true,
    no_undef_init: bool = true,
    no_unassigned_vars: bool = true,
    no_underscore_dangle: bool = true,
    no_underscore_dangle_allow_after_this: bool = false,
    no_underscore_dangle_allow_after_super: bool = false,
    no_underscore_dangle_allow_after_this_constructor: bool = false,
    no_underscore_dangle_allow_function_params: NoUnderscoreDangleAllowFunctionParams = .yes,
    no_underscore_dangle_allow_in_array_destructuring: NoUnderscoreDangleAllowDestructuring = .yes,
    no_underscore_dangle_allow_in_object_destructuring: NoUnderscoreDangleAllowDestructuring = .yes,
    no_underscore_dangle_enforce_in_method_names: bool = false,
    no_underscore_dangle_enforce_in_class_fields: bool = false,
    no_underscore_dangle_allow: NoShadowAllowNames = .{},
    no_undefined: bool = true,
    unicode_bom: bool = true,
    no_unneeded_ternary: bool = true,
    no_unneeded_ternary_default_assignment: bool = true,
    no_unexpected_multiline: bool = true,
    no_unmodified_loop_condition: bool = false,
    no_unused_labels: bool = true,
    no_unreachable_loop: bool = true,
    no_unreachable_loop_ignore_while: bool = false,
    no_unreachable_loop_ignore_do_while: bool = false,
    no_unreachable_loop_ignore_for: bool = false,
    no_unreachable_loop_ignore_for_in: bool = false,
    no_unreachable_loop_ignore_for_of: bool = false,
    no_unsafe_finally: bool = true,
    no_unsafe_negation: bool = true,
    no_unsafe_negation_enforce_for_ordering_relations: bool = false,
    no_unsafe_optional_chaining: bool = true,
    no_unsafe_optional_chaining_disallow_arithmetic_operators: bool = false,
    no_useless_computed_key: bool = true,
    no_useless_computed_key_enforce_for_class_members: NoUselessComputedKeyEnforceForClassMembers = .yes,
    no_useless_backreference: bool = true,
    no_useless_call: bool = true,
    no_useless_concat: bool = true,
    no_useless_constructor: bool = true,
    no_useless_assignment: bool = true,
    no_useless_catch: bool = true,
    no_useless_escape: bool = true,
    no_useless_escape_allow_regex_characters: NoUselessEscapeAllowRegexCharacters = .{},
    no_useless_rename: bool = true,
    no_useless_rename_ignore_destructuring: bool = false,
    no_useless_rename_ignore_import: bool = false,
    no_useless_rename_ignore_export: bool = false,
    no_unused_private_class_members: bool = true,
    no_unused_expressions: bool = true,
    no_unused_expressions_allow_short_circuit: NoUnusedExpressionsAllowShortCircuit = .no,
    no_unused_expressions_allow_ternary: NoUnusedExpressionsAllowTernary = .no,
    no_unused_expressions_allow_tagged_templates: NoUnusedExpressionsAllowTaggedTemplates = .no,
    typescript_eslint_no_unused_expressions: bool = true,
    typescript_eslint_no_unused_expressions_allow_short_circuit: NoUnusedExpressionsAllowShortCircuit = .yes,
    typescript_eslint_no_unused_expressions_allow_ternary: NoUnusedExpressionsAllowTernary = .yes,
    typescript_eslint_no_unused_expressions_allow_tagged_templates: NoUnusedExpressionsAllowTaggedTemplates = .yes,
    no_warning_comments: bool = true,
    no_warning_comments_location: NoWarningCommentsLocation = .start,
    no_warning_comments_decoration: NoWarningCommentsDecoration = .none,
    no_warning_comments_terms: NoWarningCommentsTerms = .{},
    no_void: bool = true,
    no_void_allow_as_statement: NoVoidAllowAsStatement = .no,
    no_with: bool = true,
    no_var: bool = true,
    unicode_bom_style: UnicodeBomStyle = .never,
    object_shorthand: bool = true,
    object_shorthand_style: ObjectShorthandStyle = .always,
    object_shorthand_avoid_quotes: bool = false,
    object_shorthand_ignore_constructors: bool = false,
    object_shorthand_avoid_explicit_return_arrows: bool = false,
    one_var: bool = true,
    one_var_check_var: bool = true,
    one_var_check_let: bool = true,
    one_var_check_const: bool = true,
    operator_assignment: bool = true,
    operator_assignment_style: OperatorAssignmentStyle = .always,
    eqeqeq: bool = true,
    eqeqeq_style: EqeqeqStyle = .strict,
    use_isnan: bool = true,
    use_isnan_enforce_for_index_of: bool = false,
    use_isnan_enforce_for_switch_case: bool = true,
    no_unused_vars: bool = true,
    no_unused_vars_vars: NoUnusedVarsVars = .all,
    no_unused_vars_args: NoUnusedVarsArgs = .none,
    no_unused_vars_caught_errors: NoUnusedVarsCaughtErrors = .none,
    no_unused_vars_ignore_rest_siblings: bool = false,
    no_unused_vars_ignore_class_with_static_init_block: bool = false,
    no_unused_vars_ignore_using_declarations: bool = false,
    no_unused_vars_args_ignore_pattern: NoUnusedVarsIgnorePattern = .{},
    no_unused_vars_caught_errors_ignore_pattern: NoUnusedVarsIgnorePattern = .{},
    no_unused_vars_destructured_array_ignore_pattern: NoUnusedVarsIgnorePattern = .{},
    no_unused_vars_report_used_ignore_pattern: bool = false,
    no_unused_vars_vars_ignore_pattern: NoUnusedVarsIgnorePattern = .{},
    no_use_before_define: bool = true,
    no_use_before_define_check_functions: NoUseBeforeDefineCheck = .yes,
    no_use_before_define_check_classes: NoUseBeforeDefineCheck = .yes,
    no_use_before_define_check_variables: NoUseBeforeDefineCheck = .yes,
    no_use_before_define_allow_named_exports: bool = false,
    no_undef: bool = true,
    no_undef_typeof: bool = false,
    prefer_arrow_callback: bool = false,
    prefer_arrow_callback_allow_named_functions: bool = false,
    prefer_arrow_callback_allow_unbound_this: bool = true,
    prefer_const: bool = true,
    prefer_const_destructuring: PreferConstDestructuring = .any,
    prefer_const_ignore_read_before_assign: bool = true,
    prefer_exponentiation_operator: bool = true,
    prefer_named_capture_group: bool = false,
    prefer_numeric_literals: bool = true,
    prefer_object_has_own: bool = true,
    prefer_promise_reject_errors: bool = true,
    prefer_promise_reject_errors_allow_empty_reject: bool = false,
    preserve_caught_error: bool = true,
    preserve_caught_error_require_catch_parameter: bool = false,
    promise_no_promise_in_callback: bool = true,
    promise_no_promise_in_callback_exempt_declarations: bool = false,
    promise_no_return_in_finally: bool = true,
    promise_no_return_wrap: bool = true,
    promise_no_return_wrap_allow_reject: bool = false,
    promise_param_names: bool = true,
    promise_param_names_resolve_pattern: PromiseParamNamePattern = .{},
    promise_param_names_reject_pattern: PromiseParamNamePattern = .{ .default = .reject },
    promise_valid_params: bool = true,
    promise_valid_params_exclude: PromiseValidParamsExclusions = .{},
    prefer_destructuring: bool = true,
    prefer_destructuring_variable_declarator_array: bool = true,
    prefer_destructuring_variable_declarator_object: bool = true,
    prefer_destructuring_assignment_expression_array: bool = true,
    prefer_destructuring_assignment_expression_object: bool = true,
    prefer_destructuring_enforce_for_renamed_properties: bool = false,
    prefer_regex_literals: bool = true,
    prefer_regex_literals_disallow_redundant_wrapping: bool = false,
    prefer_rest_params: bool = true,
    prefer_object_spread: bool = true,
    prefer_spread: bool = true,
    prefer_template: bool = true,
    react_default_props_match_prop_types: bool = true,
    react_default_props_match_prop_types_allow_required_defaults: bool = false,
    react_display_name: bool = true,
    react_display_name_check_context_objects: bool = false,
    react_display_name_ignore_transpiler_name: bool = false,
    react_jsx_boolean_value: bool = true,
    react_jsx_boolean_value_style: ReactJsxBooleanValueStyle = .never,
    react_jsx_filename_extension: bool = true,
    react_jsx_filename_extension_extensions: ReactJsxFilenameExtensions = .{},
    react_jsx_filename_extension_allow: ReactJsxFilenameExtensionAllow = .always,
    react_jsx_no_duplicate_props: bool = true,
    react_jsx_no_duplicate_props_ignore_case: bool = true,
    react_jsx_no_comment_textnodes: bool = true,
    react_jsx_no_bind: bool = true,
    react_jsx_no_bind_allow_arrow_functions: bool = false,
    react_jsx_no_bind_allow_functions: bool = false,
    react_jsx_no_bind_allow_bind: bool = false,
    react_jsx_no_bind_ignore_refs: bool = false,
    react_jsx_no_bind_ignore_dom_components: bool = false,
    react_jsx_key: bool = true,
    react_jsx_key_check_key_must_before_spread: bool = false,
    react_jsx_key_check_fragment_shorthand: bool = false,
    react_jsx_key_warn_on_duplicates: bool = false,
    react_button_has_type: bool = true,
    react_button_has_type_button: bool = true,
    react_button_has_type_submit: bool = true,
    react_button_has_type_reset: bool = true,
    react_require_render_return: bool = true,
    react_jsx_no_target_blank: bool = true,
    react_jsx_no_target_blank_allow_referrer: bool = false,
    react_jsx_no_target_blank_enforce_dynamic_links: bool = true,
    react_jsx_no_target_blank_warn_on_spread_attributes: bool = false,
    react_jsx_no_target_blank_links: bool = true,
    react_jsx_no_target_blank_forms: bool = false,
    react_jsx_no_undef: bool = true,
    react_jsx_pascal_case: bool = true,
    react_jsx_pascal_case_allow_all_caps: bool = true,
    react_jsx_pascal_case_allow_leading_underscore: bool = false,
    react_jsx_pascal_case_allow_namespace: bool = false,
    react_jsx_pascal_case_ignore: ReactJsxPascalCaseIgnoreNames = .{},
    react_jsx_uses_react: bool = true,
    react_jsx_uses_vars: bool = true,
    react_no_danger: bool = true,
    react_no_danger_with_children: bool = true,
    react_no_access_state_in_setstate: bool = true,
    react_no_direct_mutation_state: bool = true,
    react_no_deprecated: bool = true,
    react_forbid_prop_types: bool = true,
    react_forbid_prop_types_forbid_any: bool = true,
    react_forbid_prop_types_forbid_array: bool = true,
    react_forbid_prop_types_forbid_object: bool = true,
    react_forbid_prop_types_check_context_types: bool = false,
    react_forbid_prop_types_check_child_context_types: bool = false,
    react_no_array_index_key: bool = true,
    react_no_children_prop: bool = true,
    react_no_children_prop_allow_functions: bool = false,
    react_no_find_dom_node: bool = true,
    react_no_forward_ref: bool = false,
    react_no_is_mounted: bool = true,
    react_no_multi_comp: bool = true,
    react_no_multi_comp_ignore_stateless: bool = true,
    react_no_unstable_nested_components: bool = false,
    react_no_unstable_nested_components_allow_as_props: bool = false,
    react_no_unstable_nested_components_prop_name_pattern: ReactNoUnstableNestedComponentsPropNamePattern = .{},
    react_no_redundant_should_component_update: bool = true,
    react_no_render_return_value: bool = true,
    react_no_will_update_set_state: bool = true,
    react_no_this_in_sfc: bool = true,
    react_no_typos: bool = true,
    react_no_unknown_property: bool = true,
    react_no_unknown_property_ignore: ReactNoUnknownPropertyIgnoreNames = .{},
    react_no_unknown_property_require_data_lowercase: bool = false,
    react_prop_types: bool = true,
    react_prop_types_skip_undeclared: bool = false,
    react_prop_types_ignore: ReactPropTypesIgnoreNames = .{},
    react_prop_types_custom_validators: ReactPropTypesIgnoreNames = .{},
    react_no_unused_prop_types: bool = true,
    react_no_unused_prop_types_skip_shape_props: bool = true,
    react_no_unused_prop_types_ignore: ReactPropTypesIgnoreNames = .{},
    react_no_unused_prop_types_custom_validators: ReactPropTypesIgnoreNames = .{},
    react_no_unused_state: bool = true,
    react_no_string_refs: bool = true,
    react_no_string_refs_no_template_literals: bool = false,
    react_no_unescaped_entities: bool = true,
    react_no_unescaped_entities_forbid_gt: bool = true,
    react_no_unescaped_entities_forbid_double_quote: bool = true,
    react_no_unescaped_entities_forbid_single_quote: bool = true,
    react_no_unescaped_entities_forbid_closing_brace: bool = true,
    react_prefer_es6_class: bool = true,
    react_prefer_es6_class_style: ReactPreferEs6ClassStyle = .always,
    react_self_closing_comp: bool = true,
    react_self_closing_comp_component: bool = true,
    react_self_closing_comp_html: bool = true,
    react_style_prop_object: bool = true,
    react_void_dom_elements_no_children: bool = true,
    react_hooks_exhaustive_deps: bool = true,
    react_hooks_exhaustive_deps_additional_hooks: ReactHooksAdditionalHooksPattern = .{},
    react_hooks_rules_of_hooks: bool = true,
    react_hooks_use_memo: bool = false,
    react_hooks_void_use_memo: bool = false,
    react_hooks_set_state_in_render: bool = false,
    react_hooks_purity: bool = false,
    unused_imports_no_unused_imports: bool = false,
    radix: bool = true,
    radix_style: RadixStyle = .always,
    require_await: bool = true,
    require_atomic_updates: bool = true,
    require_atomic_updates_allow_properties: bool = false,
    require_unicode_regexp: bool = true,
    require_unicode_regexp_require_flag: RequireUnicodeRegexpRequireFlag = .any,
    require_yield: bool = true,
    sort_vars: bool = false,
    sort_vars_ignore_case: bool = false,
    sort_imports: bool = false,
    sort_imports_ignore_case: bool = false,
    sort_imports_ignore_declaration_sort: bool = false,
    sort_imports_ignore_member_sort: bool = false,
    sort_imports_allow_separated_groups: bool = false,
    sort_imports_member_syntax_order: SortImportsMemberSyntaxOrder = .{},
    sort_keys: bool = false,
    sort_keys_order: SortKeysOrder = .asc,
    sort_keys_case_sensitive: bool = true,
    sort_keys_natural: bool = false,
    sort_keys_min_keys: usize = 2,
    sort_keys_allow_line_separated_groups: bool = false,
    spaced_comment: bool = true,
    spaced_comment_style: SpacedCommentStyle = .always,
    spaced_comment_markers: SpacedCommentMarkers = .{},
    spaced_comment_exceptions: SpacedCommentMarkers = .{},
    strict: bool = false,
    strict_mode: StrictMode = .safe,
    symbol_description: bool = true,
    typescript_eslint_adjacent_overload_signatures: bool = true,
    typescript_eslint_array_type: bool = true,
    typescript_eslint_array_type_style: TypescriptEslintArrayTypeStyle = .array_simple,
    typescript_eslint_class_literal_property_style: bool = true,
    typescript_eslint_class_literal_property_style_style: TypescriptEslintClassLiteralPropertyStyle = .fields,
    typescript_eslint_consistent_type_assertions: bool = true,
    typescript_eslint_consistent_type_definitions: bool = true,
    typescript_eslint_consistent_type_definitions_style: TypescriptEslintConsistentTypeDefinitionsStyle = .interface,
    typescript_eslint_no_array_constructor: bool = true,
    typescript_eslint_ban_types: bool = true,
    typescript_eslint_ban_types_config: TypescriptEslintBanTypesConfig = .{},
    typescript_eslint_ban_ts_comment: bool = true,
    typescript_eslint_ban_ts_comment_ts_expect_error: TypescriptEslintBanTsCommentMode = .allow_with_description,
    typescript_eslint_ban_ts_comment_ts_ignore: TypescriptEslintBanTsCommentMode = .allow_with_description,
    typescript_eslint_ban_ts_comment_ts_nocheck: TypescriptEslintBanTsCommentMode = .allow_with_description,
    typescript_eslint_ban_ts_comment_ts_check: TypescriptEslintBanTsCommentMode = .allow_with_description,
    typescript_eslint_ban_ts_comment_minimum_description_length: usize = 3,
    typescript_eslint_ban_tslint_comment: bool = true,
    typescript_eslint_explicit_member_accessibility: bool = false,
    typescript_eslint_explicit_member_accessibility_accessibility: TypescriptEslintExplicitMemberAccessibility = .no_public,
    typescript_eslint_consistent_type_assertions_assertion_style: TypescriptEslintConsistentTypeAssertionsStyle = .as,
    typescript_eslint_consistent_type_assertions_object_literal_type_assertions: TypescriptEslintLiteralTypeAssertions = .never,
    typescript_eslint_consistent_type_assertions_array_literal_type_assertions: TypescriptEslintLiteralTypeAssertions = .allow,
    typescript_eslint_member_ordering: bool = true,
    typescript_eslint_method_signature_style: bool = true,
    typescript_eslint_method_signature_style_style: TypescriptEslintMethodSignatureStyle = .property,
    typescript_eslint_no_confusing_non_null_assertion: bool = true,
    typescript_eslint_no_empty_function: bool = true,
    typescript_eslint_no_empty_function_allow: NoEmptyFunctionAllow = .{},
    typescript_eslint_no_empty_object_type: bool = false,
    typescript_eslint_no_empty_object_type_allow_interfaces: TypescriptEslintNoEmptyObjectTypeAllowInterfaces = .never,
    typescript_eslint_no_empty_object_type_allow_object_types: TypescriptEslintNoEmptyObjectTypeAllowObjectTypes = .never,
    typescript_eslint_no_empty_object_type_allow_with_name: TypescriptEslintNoEmptyObjectTypeAllowWithName = .{},
    typescript_eslint_no_empty_interface: bool = true,
    typescript_eslint_no_empty_interface_allow_single_extends: bool = false,
    typescript_eslint_no_extra_semi: bool = true,
    typescript_eslint_no_extra_non_null_assertion: bool = true,
    typescript_eslint_no_duplicate_enum_values: bool = true,
    // Opt-in: adding support must not enable a new check in existing projects.
    typescript_eslint_no_explicit_any: bool = false,
    typescript_eslint_no_explicit_any_fix_to_unknown: bool = false,
    typescript_eslint_no_explicit_any_ignore_rest_args: bool = false,
    typescript_eslint_no_inferrable_types: bool = true,
    typescript_eslint_no_inferrable_types_ignore_parameters: bool = false,
    typescript_eslint_no_inferrable_types_ignore_properties: bool = false,
    typescript_eslint_no_invalid_void_type: bool = true,
    typescript_eslint_no_invalid_void_type_allow_as_this_parameter: bool = false,
    typescript_eslint_no_invalid_void_type_allow_in_generic_type_arguments: bool = true,
    typescript_eslint_no_invalid_void_type_allowed_generic_type_names: TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNames = .{},
    typescript_eslint_no_loss_of_precision: bool = true,
    typescript_eslint_no_loop_func: bool = true,
    typescript_eslint_no_misused_new: bool = true,
    typescript_eslint_no_non_null_asserted_optional_chain: bool = true,
    typescript_eslint_no_namespace: bool = true,
    typescript_eslint_no_namespace_allow_declarations: bool = true,
    typescript_eslint_no_namespace_allow_definition_files: bool = true,
    typescript_eslint_no_redeclare: bool = true,
    typescript_eslint_no_redeclare_builtin_globals: bool = false,
    typescript_eslint_no_redeclare_ignore_declaration_merge: bool = true,
    typescript_eslint_no_require_imports: bool = true,
    typescript_eslint_no_require_imports_allow_as_import: bool = false,
    typescript_eslint_no_require_imports_allow: TypescriptEslintNoRequireImportsAllowPatterns = .{},
    typescript_eslint_no_shadow: bool = true,
    typescript_eslint_no_shadow_allow: NoShadowAllowNames = .{},
    typescript_eslint_no_shadow_builtin_globals: bool = false,
    typescript_eslint_no_shadow_hoist: NoShadowHoist = .functions_and_types,
    typescript_eslint_no_shadow_ignore_on_initialization: bool = false,
    typescript_eslint_no_shadow_ignore_type_value_shadow: bool = false,
    typescript_eslint_no_shadow_ignore_function_type_parameter_name_value_shadow: bool = true,
    typescript_eslint_no_this_alias: bool = true,
    typescript_eslint_no_this_alias_allowed_names: NoThisAliasAllowedNames = .{},
    typescript_eslint_no_this_alias_allow_destructuring: bool = true,
    typescript_eslint_no_unsafe_declaration_merging: bool = true,
    typescript_eslint_no_unsafe_function_type: bool = false,
    typescript_eslint_triple_slash_reference: bool = true,
    typescript_eslint_triple_slash_reference_path: TypescriptEslintTripleSlashReferenceMode = .never,
    typescript_eslint_triple_slash_reference_types: TypescriptEslintTripleSlashReferenceMode = .always,
    typescript_eslint_triple_slash_reference_lib: TypescriptEslintTripleSlashReferenceMode = .always,
    typescript_eslint_typedef: bool = true,
    typescript_eslint_typedef_property_declaration: bool = true,
    typescript_eslint_typedef_member_variable_declaration: bool = false,
    typescript_eslint_typedef_parameter: bool = false,
    typescript_eslint_typedef_arrow_parameter: bool = false,
    typescript_eslint_typedef_array_destructuring: bool = false,
    typescript_eslint_typedef_object_destructuring: bool = false,
    typescript_eslint_typedef_variable_declaration: bool = false,
    typescript_eslint_typedef_variable_declaration_ignore_function: bool = false,
    typescript_eslint_unified_signatures: bool = true,
    typescript_eslint_no_unnecessary_parameter_property_assignment: bool = true,
    typescript_eslint_no_unnecessary_type_constraint: bool = true,
    typescript_eslint_no_useless_constructor: bool = true,
    typescript_eslint_no_useless_empty_export: bool = true,
    typescript_eslint_no_unused_vars: bool = true,
    typescript_eslint_no_unused_vars_vars: NoUnusedVarsVars = .all,
    typescript_eslint_no_unused_vars_args: NoUnusedVarsArgs = .after_used,
    typescript_eslint_no_unused_vars_caught_errors: NoUnusedVarsCaughtErrors = .none,
    typescript_eslint_no_unused_vars_ignore_rest_siblings: bool = true,
    typescript_eslint_no_unused_vars_ignore_class_with_static_init_block: bool = false,
    typescript_eslint_no_unused_vars_ignore_using_declarations: bool = false,
    typescript_eslint_no_unused_vars_args_ignore_pattern: NoUnusedVarsIgnorePattern = .{},
    typescript_eslint_no_unused_vars_caught_errors_ignore_pattern: NoUnusedVarsIgnorePattern = .{},
    typescript_eslint_no_unused_vars_destructured_array_ignore_pattern: NoUnusedVarsIgnorePattern = .{},
    typescript_eslint_no_unused_vars_report_used_ignore_pattern: bool = false,
    typescript_eslint_no_unused_vars_vars_ignore_pattern: NoUnusedVarsIgnorePattern = .{},
    typescript_eslint_no_use_before_define: bool = true,
    typescript_eslint_no_use_before_define_check_functions: NoUseBeforeDefineCheck = .no,
    typescript_eslint_no_use_before_define_check_classes: NoUseBeforeDefineCheck = .yes,
    typescript_eslint_no_use_before_define_check_variables: NoUseBeforeDefineCheck = .yes,
    typescript_eslint_no_use_before_define_check_typedefs: NoUseBeforeDefineCheck = .yes,
    typescript_eslint_no_use_before_define_check_enums: NoUseBeforeDefineCheck = .yes,
    typescript_eslint_no_use_before_define_allow_named_exports: bool = false,
    typescript_eslint_no_use_before_define_ignore_type_references: bool = true,
    typescript_eslint_no_var_requires: bool = true,
    typescript_eslint_no_wrapper_object_types: bool = true,
    typescript_eslint_prefer_as_const: bool = true,
    typescript_eslint_prefer_namespace_keyword: bool = true,
    typescript_eslint_restrict_plus_operands: bool = true,
    typescript_eslint_restrict_plus_operands_allow_number_and_string: bool = false,
    promise_always_return: bool = true,
    promise_always_return_ignore_last_callback: bool = false,
    promise_always_return_ignore_assignment_variables: PromiseAlwaysReturnIgnoreAssignmentVariables = .{},
    promise_catch_or_return: bool = true,
    promise_catch_or_return_allow_finally: bool = false,
    promise_catch_or_return_allow_then: bool = false,
    promise_catch_or_return_allow_then_strict: bool = false,
    promise_catch_or_return_termination_methods: PromiseCatchOrReturnTerminationMethods = .{},
    promise_no_callback_in_promise: bool = true,
    promise_no_callback_in_promise_exceptions: PromiseNoCallbackInPromiseExceptions = .{},
    promise_no_callback_in_promise_timeouts_err: bool = false,
    promise_no_nesting: bool = true,
    promise_no_new_statics: bool = true,
    parser_semantic_errors: bool = true,
    valid_typeof: bool = true,
    valid_typeof_require_string_literals: bool = false,
    vars_on_top: bool = true,
    wrap_iife: bool = true,
    wrap_iife_style: WrapIifeStyle = .outside,
    yoda: bool = true,
    yoda_style: YodaStyle = .never,
    yoda_only_equality: bool = false,
    yoda_except_range: bool = false,

    pub fn allDisabled() Options {
        var options = Options{};
        inline for (@typeInfo(Options).@"struct".fields) |field| {
            if (field.type == bool) {
                @field(options, field.name) = false;
            }
        }
        return options;
    }

    pub fn setByCliName(self: *Options, cli_name: []const u8, value: bool) bool {
        @setEvalBranchQuota(10000);

        if (std.mem.eql(u8, cli_name, "semantic-errors")) {
            self.parser_semantic_errors = value;
            return true;
        }

        if (std.mem.eql(u8, cli_name, "prettier/prettier")) {
            return true;
        }

        if (std.mem.startsWith(u8, cli_name, "@typescript-eslint/")) {
            const typescript_rule_name = cli_name["@typescript-eslint/".len..];
            inline for (@typeInfo(Options).@"struct".fields) |field| {
                if (field.type == bool) {
                    if (comptime fieldNameStartsWith(field.name, "typescript_eslint_")) {
                        if (cliNameMatchesFieldName(field.name["typescript_eslint_".len..], typescript_rule_name)) {
                            @field(self, field.name) = value;
                            return true;
                        }
                    }
                }
            }
            return false;
        }

        if (std.mem.startsWith(u8, cli_name, "import/")) {
            return self.setByPrefixedRuleName("import_", cli_name["import/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "jest/")) {
            return self.setByPrefixedRuleName("jest_", cli_name["jest/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "promise/")) {
            return self.setByPrefixedRuleName("promise_", cli_name["promise/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "eslint-comments/")) {
            return self.setByPrefixedRuleName("eslint_comments_", cli_name["eslint-comments/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "@alipay/ant/")) {
            return self.setByPrefixedRuleName("alipay_ant_", cli_name["@alipay/ant/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "@alipay/spmLint/")) {
            return self.setByPrefixedRuleName("alipay_spmlint_", cli_name["@alipay/spmLint/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "jsx-a11y/")) {
            return self.setByPrefixedRuleName("jsx_a11y_", cli_name["jsx-a11y/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "react/")) {
            return self.setByPrefixedRuleName("react_", cli_name["react/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "react-hooks/")) {
            return self.setByPrefixedRuleName("react_hooks_", cli_name["react-hooks/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "promise/")) {
            return self.setByPrefixedRuleName("promise_", cli_name["promise/".len..], value);
        }

        if (std.mem.startsWith(u8, cli_name, "unused-imports/")) {
            return self.setByPrefixedRuleName("unused_imports_", cli_name["unused-imports/".len..], value);
        }

        inline for (@typeInfo(Options).@"struct".fields) |field| {
            if (field.type == bool and cliNameMatchesFieldName(field.name, cli_name)) {
                @field(self, field.name) = value;
                return true;
            }
        }
        return false;
    }

    pub fn setByRuleConfigValue(self: *Options, cli_name: []const u8, value: std.json.Value) RuleConfigError!void {
        const enabled = try ruleConfigValueToBool(value);
        if (!self.setByCliName(cli_name, enabled)) return error.UnknownRule;
        if (std.mem.eql(u8, cli_name, "@alipay/ant/no-deprecated-dependence")) {
            self.alipay_ant_no_deprecated_dependence_profile = deprecatedDependenceProfileFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "accessor-pairs")) {
            self.accessor_pairs_get_without_set = try accessorPairsGetWithoutSetFromConfig(value);
            self.accessor_pairs_set_without_get = try accessorPairsSetWithoutGetFromConfig(value);
            self.accessor_pairs_enforce_for_class_members = try accessorPairsEnforceForClassMembersFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "array-callback-return")) {
            self.array_callback_return_allow_implicit = try arrayCallbackReturnAllowImplicitFromConfig(value);
            self.array_callback_return_check_for_each = try arrayCallbackReturnCheckForEachFromConfig(value);
            self.array_callback_return_allow_void = try arrayCallbackReturnAllowVoidFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "arrow-body-style")) {
            const config = try arrowBodyStyleFromConfig(value);
            self.arrow_body_style_style = config.style;
            self.arrow_body_style_require_return_for_object_literal = config.require_return_for_object_literal;
        }
        if (std.mem.eql(u8, cli_name, "camelcase")) {
            const config = try camelcaseFromConfig(value);
            self.camelcase_properties = config.properties;
            self.camelcase_ignore_destructuring = config.ignore_destructuring;
            self.camelcase_ignore_imports = config.ignore_imports;
            self.camelcase_ignore_globals = config.ignore_globals;
            self.camelcase_allow = config.allow;
        }
        if (std.mem.eql(u8, cli_name, "capitalized-comments")) {
            self.capitalized_comments_mode = try capitalizedCommentsModeFromConfig(value);
            self.capitalized_comments_ignore_inline_comments = try capitalizedCommentsIgnoreInlineCommentsFromConfig(value);
            self.capitalized_comments_ignore_consecutive_comments = try capitalizedCommentsIgnoreConsecutiveCommentsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "class-methods-use-this")) {
            const config = try classMethodsUseThisFromConfig(value);
            self.class_methods_use_this_enforce_for_class_fields = config.enforce_for_class_fields;
            self.class_methods_use_this_except_methods = config.except_methods;
            self.class_methods_use_this_ignore_override_methods = config.ignore_override_methods;
            self.class_methods_use_this_ignore_classes_with_implements = config.ignore_classes_with_implements;
        }
        if (std.mem.eql(u8, cli_name, "complexity")) {
            self.complexity_max = try complexityMaxFromConfig(value);
            self.complexity_variant = try complexityVariantFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "consistent-return")) {
            self.consistent_return_treat_undefined_as_unspecified = try consistentReturnTreatUndefinedAsUnspecifiedFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "consistent-this")) {
            self.consistent_this_aliases = try consistentThisAliasesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "curly")) {
            self.curly_style = try curlyStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "default-case")) {
            self.default_case_comment_pattern = try defaultCaseCommentPatternFromConfig(value);
        }
        if (enabled and (std.mem.eql(u8, cli_name, "dot-notation") or std.mem.eql(u8, cli_name, "@typescript-eslint/dot-notation"))) {
            self.dot_notation_allow_keywords = try dotNotationAllowKeywordsFromConfig(value);
            self.dot_notation_allow_pattern = try dotNotationAllowPatternFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "eol-last")) {
            self.eol_last_style = try eolLastStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "eslint-comments/no-restricted-disable")) {
            self.eslint_comments_no_restricted_disable_no_nested_ternary = noRestrictedDisableRestrictsNoNestedTernary(value);
        }
        if (std.mem.eql(u8, cli_name, "import/no-unresolved")) {
            self.import_no_unresolved_amd = try importNoUnresolvedBoolOptionFromConfig(value, "amd", false);
            self.import_no_unresolved_commonjs = try importNoUnresolvedBoolOptionFromConfig(value, "commonjs", false);
            self.import_no_unresolved_ignore = try importNoUnresolvedIgnorePatternsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "jest/no-standalone-expect")) {
            self.jest_no_standalone_expect_additional_test_block_functions = try jestAdditionalTestBlockFunctionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "jest/valid-expect")) {
            const config = try jestValidExpectFromConfig(value);
            self.jest_valid_expect_always_await = config.always_await;
            self.jest_valid_expect_async_matchers = config.async_matchers;
            self.jest_valid_expect_min_args = config.min_args;
            self.jest_valid_expect_max_args = config.max_args;
        }
        if (std.mem.eql(u8, cli_name, "jest/valid-title")) {
            const config = try jestValidTitleFromConfig(value);
            self.jest_valid_title_ignore_spaces = config.ignore_spaces;
            self.jest_valid_title_ignore_type_of_describe_name = config.ignore_type_of_describe_name;
            self.jest_valid_title_ignore_type_of_test_name = config.ignore_type_of_test_name;
            self.jest_valid_title_disallowed_words = config.disallowed_words;
            self.jest_valid_title_must_not_match = config.must_not_match;
            self.jest_valid_title_must_match = config.must_match;
        }
        if (std.mem.eql(u8, cli_name, "func-name-matching")) {
            self.func_name_matching_style = try funcNameMatchingStyleFromConfig(value);
            self.func_name_matching_include_commonjs_module_exports = try funcNameMatchingBoolOptionFromConfig(value, "includeCommonJSModuleExports");
            self.func_name_matching_consider_property_descriptor = try funcNameMatchingBoolOptionFromConfig(value, "considerPropertyDescriptor");
        }
        if (std.mem.eql(u8, cli_name, "func-names")) {
            self.func_names_style = try funcNamesStyleFromConfig(value);
            const generator_style = try funcNamesGeneratorStyleFromConfig(value);
            self.func_names_has_generator_style = generator_style != null;
            self.func_names_generator_style = generator_style orelse self.func_names_style;
        }
        if (std.mem.eql(u8, cli_name, "func-style")) {
            const config = try funcStyleFromConfig(value);
            self.func_style_style = config.style;
            self.func_style_allow_arrow_functions = config.allow_arrow_functions;
            self.func_style_allow_type_annotation = config.allow_type_annotation;
            self.func_style_named_exports = config.named_exports;
        }
        if (std.mem.eql(u8, cli_name, "getter-return")) {
            self.getter_return_allow_implicit = try getterReturnAllowImplicitFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "grouped-accessor-pairs")) {
            self.grouped_accessor_pairs_style = try groupedAccessorPairsStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "id-denylist")) {
            self.id_denylist_names = try idDenylistNamesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "id-length")) {
            const config = try idLengthFromConfig(value);
            self.id_length_min = config.min;
            self.id_length_has_max = config.has_max;
            self.id_length_max = config.max;
            self.id_length_properties = config.properties;
            self.id_length_exceptions = config.exceptions;
            self.id_length_exception_patterns = config.exception_patterns;
        }
        if (std.mem.eql(u8, cli_name, "id-match")) {
            const config = try idMatchFromConfig(value);
            self.id_match_pattern = config.pattern;
            self.id_match_properties = config.properties;
            self.id_match_class_fields = config.class_fields;
            self.id_match_only_declarations = config.only_declarations;
            self.id_match_ignore_destructuring = config.ignore_destructuring;
        }
        if (std.mem.eql(u8, cli_name, "init-declarations")) {
            self.init_declarations_mode = try initDeclarationsModeFromConfig(value);
            self.init_declarations_ignore_for_loop_init = try initDeclarationsIgnoreForLoopInitFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "eqeqeq")) {
            self.eqeqeq_style = try eqeqeqStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "linebreak-style")) {
            self.linebreak_style_style = try linebreakStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "use-isnan")) {
            self.use_isnan_enforce_for_index_of = try useIsnanBoolOptionFromConfig(value, "enforceForIndexOf", false);
            self.use_isnan_enforce_for_switch_case = try useIsnanBoolOptionFromConfig(value, "enforceForSwitchCase", true);
        }
        if (std.mem.eql(u8, cli_name, "logical-assignment-operators")) {
            self.logical_assignment_operators_style = try logicalAssignmentOperatorsStyleFromConfig(value);
            self.logical_assignment_operators_enforce_for_if_statements = try logicalAssignmentOperatorsEnforceForIfStatementsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "max-classes-per-file")) {
            self.max_classes_per_file_max = try maxClassesPerFileMaxFromConfig(value);
            self.max_classes_per_file_ignore_expressions = try maxClassesPerFileIgnoreExpressionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "max-depth")) {
            self.max_depth_max = try maxDepthMaxFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "max-lines")) {
            self.max_lines_max = try maxLinesMaxFromConfig(value, 300);
            self.max_lines_skip_blank_lines = try maxLinesBoolOptionFromConfig(value, "skipBlankLines");
            self.max_lines_skip_comments = try maxLinesBoolOptionFromConfig(value, "skipComments");
        }
        if (std.mem.eql(u8, cli_name, "max-lines-per-function")) {
            self.max_lines_per_function_max = try maxLinesMaxFromConfig(value, 50);
            self.max_lines_per_function_skip_blank_lines = try maxLinesBoolOptionFromConfig(value, "skipBlankLines");
            self.max_lines_per_function_skip_comments = try maxLinesBoolOptionFromConfig(value, "skipComments");
            self.max_lines_per_function_iifes = try maxLinesBoolOptionFromConfig(value, "IIFEs");
        }
        if (std.mem.eql(u8, cli_name, "max-nested-callbacks")) {
            self.max_nested_callbacks_max = try maxNestedCallbacksMaxFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "max-params")) {
            self.max_params_max = try maxParamsMaxFromConfig(value);
            self.max_params_count_this = try maxParamsCountThisFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "max-statements")) {
            self.max_statements_max = try maxStatementsMaxFromConfig(value);
            self.max_statements_ignore_top_level_functions = try maxStatementsIgnoreTopLevelFunctionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "promise/valid-params")) {
            self.promise_valid_params_exclude = try promiseValidParamsExclusionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "promise/param-names")) {
            self.promise_param_names_resolve_pattern = try promiseParamNamePatternFromConfig(value, "resolvePattern", .resolve);
            self.promise_param_names_reject_pattern = try promiseParamNamePatternFromConfig(value, "rejectPattern", .reject);
        }
        if (std.mem.eql(u8, cli_name, "promise/no-return-wrap")) {
            self.promise_no_return_wrap_allow_reject = try promiseNoReturnWrapAllowRejectFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "promise/no-promise-in-callback")) {
            self.promise_no_promise_in_callback_exempt_declarations = try promiseNoPromiseInCallbackExemptDeclarationsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "import/no-cycle")) {
            self.import_no_cycle_amd = try importNoCycleBoolOptionFromConfig(value, "amd", false);
            self.import_no_cycle_commonjs = try importNoCycleBoolOptionFromConfig(value, "commonjs", false);
            self.import_no_cycle_max_depth = try importNoCycleMaxDepthFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "import/no-duplicates")) {
            self.import_no_duplicates_consider_query_string = try importNoDuplicatesBoolOptionFromConfig(value, "considerQueryString", false);
        }
        if (std.mem.eql(u8, cli_name, "import/newline-after-import")) {
            self.import_newline_after_import_count = try importNewlineAfterImportCountFromConfig(value);
            self.import_newline_after_import_exact_count = try importNewlineAfterImportExactCountFromConfig(value);
            self.import_newline_after_import_consider_comments = try importNewlineAfterImportConsiderCommentsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "jsx-a11y/anchor-has-content")) {
            self.jsx_a11y_anchor_has_content_components = try jsxA11yNamesFromConfig(value, "components");
        }
        if (std.mem.eql(u8, cli_name, "jsx-a11y/aria-role")) {
            self.jsx_a11y_aria_role_allowed_invalid_roles = try jsxA11yNamesFromConfig(value, "allowedInvalidRoles");
            self.jsx_a11y_aria_role_ignore_non_dom = try jsxA11yBoolOptionFromConfig(value, "ignoreNonDOM", true);
        }
        if (std.mem.eql(u8, cli_name, "jsx-a11y/alt-text")) {
            const elements = try jsxA11yAltTextElementsFromConfig(value);
            self.jsx_a11y_alt_text_img = elements.img;
            self.jsx_a11y_alt_text_object = elements.object;
            self.jsx_a11y_alt_text_area = elements.area;
            self.jsx_a11y_alt_text_input_image = elements.input_image;
            self.jsx_a11y_alt_text_img_components = try jsxA11yNamesFromConfig(value, "img");
            self.jsx_a11y_alt_text_object_components = try jsxA11yNamesFromConfig(value, "object");
            self.jsx_a11y_alt_text_area_components = try jsxA11yNamesFromConfig(value, "area");
            self.jsx_a11y_alt_text_input_image_components = try jsxA11yNamesFromConfig(value, "input[type=\"image\"]");
        }
        if (std.mem.eql(u8, cli_name, "jsx-a11y/img-redundant-alt")) {
            self.jsx_a11y_img_redundant_alt_components = try jsxA11yNamesFromConfig(value, "components");
            self.jsx_a11y_img_redundant_alt_words = try jsxA11yNamesFromConfig(value, "words");
        }
        if (std.mem.eql(u8, cli_name, "jsx-a11y/no-distracting-elements")) {
            const elements = try jsxA11yNoDistractingElementsFromConfig(value);
            self.jsx_a11y_no_distracting_elements_marquee = elements.marquee;
            self.jsx_a11y_no_distracting_elements_blink = elements.blink;
        }
        if (std.mem.eql(u8, cli_name, "new-cap")) {
            self.new_cap_new_is_cap = try newCapBoolOptionFromConfig(value, "newIsCap", true);
            self.new_cap_cap_is_new = try newCapBoolOptionFromConfig(value, "capIsNew", true);
            self.new_cap_properties = try newCapBoolOptionFromConfig(value, "properties", true);
            self.new_cap_new_is_cap_exceptions = try newCapExceptionNamesFromConfig(value, "newIsCapExceptions");
            self.new_cap_cap_is_new_exceptions = try newCapExceptionNamesFromConfig(value, "capIsNewExceptions");
            self.new_cap_new_is_cap_exception_pattern = try newCapExceptionPatternFromConfig(value, "newIsCapExceptionPattern");
            self.new_cap_cap_is_new_exception_pattern = try newCapExceptionPatternFromConfig(value, "capIsNewExceptionPattern");
        }
        if (std.mem.eql(u8, cli_name, "no-bitwise")) {
            self.no_bitwise_allow_bitwise_and = try noBitwiseAllowFromConfig(value, "&");
            self.no_bitwise_allow_bitwise_or = try noBitwiseAllowFromConfig(value, "|");
            self.no_bitwise_allow_bitwise_xor = try noBitwiseAllowFromConfig(value, "^");
            self.no_bitwise_allow_bitwise_not = try noBitwiseAllowFromConfig(value, "~");
            self.no_bitwise_allow_left_shift = try noBitwiseAllowFromConfig(value, "<<");
            self.no_bitwise_allow_right_shift = try noBitwiseAllowFromConfig(value, ">>");
            self.no_bitwise_allow_unsigned_right_shift = try noBitwiseAllowFromConfig(value, ">>>");
            self.no_bitwise_int32_hint = try noBitwiseInt32HintFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-console")) {
            self.no_console_allow = try noConsoleAllowFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-duplicate-imports")) {
            self.no_duplicate_imports_allow_separate_type_imports = try noDuplicateImportsBoolOptionFromConfig(value, "allowSeparateTypeImports", false);
            self.no_duplicate_imports_include_exports = try noDuplicateImportsBoolOptionFromConfig(value, "includeExports", false);
        }
        if (std.mem.eql(u8, cli_name, "no-cond-assign")) {
            self.no_cond_assign_style = try noCondAssignStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-constant-condition")) {
            self.no_constant_condition_check_loops = try noConstantConditionCheckLoopsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-confusing-arrow")) {
            self.no_confusing_arrow_allow_parens = try noConfusingArrowAllowParensFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-empty")) {
            self.no_empty_allow_empty_catch = try noEmptyAllowEmptyCatchFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-empty-function")) {
            self.no_empty_function_allow = try noEmptyFunctionAllowFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-eval")) {
            self.no_eval_allow_indirect = try noEvalAllowIndirectFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-extend-native")) {
            self.no_extend_native_exceptions = try noExtendNativeExceptionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-global-assign")) {
            self.no_global_assign_exceptions = try noGlobalAssignExceptionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-empty-function")) {
            self.typescript_eslint_no_empty_function_allow = try noEmptyFunctionAllowFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-empty-pattern")) {
            self.no_empty_pattern_allow_object_patterns_as_parameters = try noEmptyPatternAllowObjectPatternsAsParametersFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-else-return")) {
            self.no_else_return_allow_else_if = try noElseReturnAllowElseIfFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-extra-boolean-cast")) {
            self.no_extra_boolean_cast_enforce_for_inner_expressions = try noExtraBooleanCastEnforceForInnerExpressionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-fallthrough")) {
            self.no_fallthrough_allow_empty_case = try noFallthroughAllowEmptyCaseFromConfig(value);
            self.no_fallthrough_comment_pattern = try noFallthroughCommentPatternFromConfig(value);
            self.no_fallthrough_report_unused_fallthrough_comment = try noFallthroughReportUnusedFallthroughCommentFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-implicit-coercion")) {
            self.no_implicit_coercion_boolean = try noImplicitCoercionBooleanFromConfig(value);
            self.no_implicit_coercion_number = try noImplicitCoercionNumberFromConfig(value);
            self.no_implicit_coercion_string = try noImplicitCoercionStringFromConfig(value);
            self.no_implicit_coercion_allow_double_negation = try noImplicitCoercionAllowFromConfig(value, "!!");
            self.no_implicit_coercion_allow_bitwise_not = try noImplicitCoercionAllowFromConfig(value, "~");
            self.no_implicit_coercion_allow_plus = try noImplicitCoercionAllowFromConfig(value, "+");
            self.no_implicit_coercion_allow_multiply = try noImplicitCoercionAllowFromConfig(value, "*");
            self.no_implicit_coercion_allow_subtract = try noImplicitCoercionAllowFromConfig(value, "-");
            self.no_implicit_coercion_allow_double_negative = try noImplicitCoercionAllowFromConfig(value, "- -");
            self.no_implicit_coercion_disallow_template_shorthand = try noImplicitCoercionDisallowTemplateShorthandFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-implicit-globals")) {
            self.no_implicit_globals_lexical_bindings = try noImplicitGlobalsLexicalBindingsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-inner-declarations")) {
            self.no_inner_declarations_mode = try noInnerDeclarationsModeFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-invalid-regexp")) {
            self.no_invalid_regexp_allow_constructor_flags = try noInvalidRegexpAllowConstructorFlagsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-invalid-this")) {
            self.no_invalid_this_cap_is_constructor = if (try boolRuleObjectOption(value, "capIsConstructor", true)) .yes else .no;
        }
        if (std.mem.eql(u8, cli_name, "no-irregular-whitespace")) {
            self.no_irregular_whitespace_skip_strings = try noIrregularWhitespaceBoolOptionFromConfig(value, "skipStrings", true);
            self.no_irregular_whitespace_skip_comments = try noIrregularWhitespaceBoolOptionFromConfig(value, "skipComments", false);
            self.no_irregular_whitespace_skip_reg_exps = try noIrregularWhitespaceBoolOptionFromConfig(value, "skipRegExps", false);
            self.no_irregular_whitespace_skip_templates = try noIrregularWhitespaceBoolOptionFromConfig(value, "skipTemplates", false);
            self.no_irregular_whitespace_skip_jsx_text = try noIrregularWhitespaceBoolOptionFromConfig(value, "skipJSXText", false);
        }
        if (std.mem.eql(u8, cli_name, "no-inline-comments")) {
            self.no_inline_comments_ignore_pattern = try noInlineCommentsIgnorePatternFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-labels")) {
            self.no_labels_allow_loop = try noLabelsAllowLoopFromConfig(value);
            self.no_labels_allow_switch = try noLabelsAllowSwitchFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-magic-numbers")) {
            self.no_magic_numbers_detect_objects = try boolRuleObjectOption(value, "detectObjects", false);
            self.no_magic_numbers_enforce_const = try boolRuleObjectOption(value, "enforceConst", false);
            self.no_magic_numbers_ignore = try noMagicNumbersIgnoreFromConfig(value);
            self.no_magic_numbers_ignore_array_indexes = try boolRuleObjectOption(value, "ignoreArrayIndexes", false);
            self.no_magic_numbers_ignore_default_values = try boolRuleObjectOption(value, "ignoreDefaultValues", false);
            self.no_magic_numbers_ignore_class_field_initial_values = try boolRuleObjectOption(value, "ignoreClassFieldInitialValues", false);
            self.no_magic_numbers_ignore_enums = try boolRuleObjectOption(value, "ignoreEnums", false);
            self.no_magic_numbers_ignore_numeric_literal_types = try boolRuleObjectOption(value, "ignoreNumericLiteralTypes", false);
            self.no_magic_numbers_ignore_readonly_class_properties = try boolRuleObjectOption(value, "ignoreReadonlyClassProperties", false);
            self.no_magic_numbers_ignore_type_indexes = try boolRuleObjectOption(value, "ignoreTypeIndexes", false);
        }
        if (std.mem.eql(u8, cli_name, "no-mixed-spaces-and-tabs")) {
            self.no_mixed_spaces_and_tabs_smart_tabs = try noMixedSpacesAndTabsSmartTabsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-multi-assign")) {
            self.no_multi_assign_ignore_non_declaration = try noMultiAssignBoolOptionFromConfig(value, "ignoreNonDeclaration", false);
        }
        if (std.mem.eql(u8, cli_name, "no-multi-spaces")) {
            self.no_multi_spaces_ignore_eol_comments = try noMultiSpacesIgnoreEOLCommentsFromConfig(value);
            self.no_multi_spaces_exceptions = try noMultiSpacesExceptionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-multiple-empty-lines")) {
            self.no_multiple_empty_lines_max = try noMultipleEmptyLinesMaxFromConfig(value);
            self.no_multiple_empty_lines_max_bof = try noMultipleEmptyLinesMaxBofFromConfig(value);
            self.no_multiple_empty_lines_max_eof = try noMultipleEmptyLinesMaxEofFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-param-reassign")) {
            self.no_param_reassign_props = try noParamReassignPropsFromConfig(value);
            self.no_param_reassign_ignore_property_modifications_for = try noParamReassignIgnoredNamesFromConfig(value);
            self.no_param_reassign_ignore_property_modifications_for_regex = try noParamReassignIgnoredNamePatternsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-redeclare")) {
            self.no_redeclare_builtin_globals = try noRedeclareBuiltinGlobalsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-restricted-exports")) {
            self.no_restricted_exports_names = try noRestrictedExportNamesFromConfig(value);
            self.no_restricted_exports_default = try noRestrictedExportsDefaultOptionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-restricted-globals")) {
            self.no_restricted_globals_entries = try noRestrictedGlobalsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-restricted-imports")) {
            self.no_restricted_imports_entries = try noRestrictedImportsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-restricted-modules")) {
            self.no_restricted_modules_entries = try noRestrictedModulesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-restricted-properties")) {
            self.no_restricted_properties_entries = try noRestrictedPropertiesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-restricted-syntax")) {
            self.no_restricted_syntax_entries = try noRestrictedSyntaxFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-self-assign")) {
            self.no_self_assign_props = try noSelfAssignPropsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-trailing-spaces")) {
            self.no_trailing_spaces_skip_blank_lines = try noTrailingSpacesBoolOptionFromConfig(value, "skipBlankLines");
            self.no_trailing_spaces_ignore_comments = try noTrailingSpacesBoolOptionFromConfig(value, "ignoreComments");
        }
        if (std.mem.eql(u8, cli_name, "no-unreachable-loop")) {
            const ignore = try noUnreachableLoopIgnoreFromConfig(value);
            self.no_unreachable_loop_ignore_while = ignore.while_statement;
            self.no_unreachable_loop_ignore_do_while = ignore.do_while_statement;
            self.no_unreachable_loop_ignore_for = ignore.for_statement;
            self.no_unreachable_loop_ignore_for_in = ignore.for_in_statement;
            self.no_unreachable_loop_ignore_for_of = ignore.for_of_statement;
        }
        if (std.mem.eql(u8, cli_name, "no-unsafe-negation")) {
            self.no_unsafe_negation_enforce_for_ordering_relations = try noUnsafeNegationBoolOptionFromConfig(value, "enforceForOrderingRelations", false);
        }
        if (std.mem.eql(u8, cli_name, "no-unsafe-optional-chaining")) {
            self.no_unsafe_optional_chaining_disallow_arithmetic_operators = try noUnsafeOptionalChainingBoolOptionFromConfig(value, "disallowArithmeticOperators", false);
        }
        if (std.mem.eql(u8, cli_name, "no-useless-rename")) {
            self.no_useless_rename_ignore_destructuring = try noUselessRenameBoolOptionFromConfig(value, "ignoreDestructuring");
            self.no_useless_rename_ignore_import = try noUselessRenameBoolOptionFromConfig(value, "ignoreImport");
            self.no_useless_rename_ignore_export = try noUselessRenameBoolOptionFromConfig(value, "ignoreExport");
        }
        if (std.mem.eql(u8, cli_name, "no-useless-escape")) {
            self.no_useless_escape_allow_regex_characters = try noUselessEscapeAllowRegexCharactersFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "unicode-bom")) {
            self.unicode_bom_style = try unicodeBomStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-shadow")) {
            self.no_shadow_allow = try noShadowAllowFromConfig(value);
            self.no_shadow_builtin_globals = try noShadowBuiltinGlobalsFromConfig(value);
            self.no_shadow_hoist = try noShadowHoistFromConfig(value, .functions);
            self.no_shadow_ignore_on_initialization = try noShadowBoolOptionFromConfig(value, "ignoreOnInitialization", false);
        }
        if (std.mem.eql(u8, cli_name, "no-underscore-dangle")) {
            self.no_underscore_dangle_allow_after_this = try noUnderscoreDangleBoolOptionFromConfig(value, "allowAfterThis", false);
            self.no_underscore_dangle_allow_after_super = try noUnderscoreDangleBoolOptionFromConfig(value, "allowAfterSuper", false);
            self.no_underscore_dangle_allow_after_this_constructor = try noUnderscoreDangleBoolOptionFromConfig(value, "allowAfterThisConstructor", false);
            self.no_underscore_dangle_allow_function_params = if (try noUnderscoreDangleBoolOptionFromConfig(value, "allowFunctionParams", true)) .yes else .no;
            self.no_underscore_dangle_allow_in_array_destructuring = if (try noUnderscoreDangleBoolOptionFromConfig(value, "allowInArrayDestructuring", true)) .yes else .no;
            self.no_underscore_dangle_allow_in_object_destructuring = if (try noUnderscoreDangleBoolOptionFromConfig(value, "allowInObjectDestructuring", true)) .yes else .no;
            self.no_underscore_dangle_enforce_in_method_names = try noUnderscoreDangleBoolOptionFromConfig(value, "enforceInMethodNames", false);
            self.no_underscore_dangle_enforce_in_class_fields = try noUnderscoreDangleBoolOptionFromConfig(value, "enforceInClassFields", false);
            self.no_underscore_dangle_allow = try noUnderscoreDangleAllowFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-plusplus")) {
            self.no_plusplus_allow_for_loop_afterthoughts = try noPlusplusAllowForLoopAfterthoughtsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-promise-executor-return")) {
            self.no_promise_executor_return_allow_void = try noPromiseExecutorReturnAllowVoidFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "prefer-arrow-callback")) {
            self.prefer_arrow_callback_allow_named_functions = try preferArrowCallbackBoolOptionFromConfig(value, "allowNamedFunctions", false);
            self.prefer_arrow_callback_allow_unbound_this = try preferArrowCallbackBoolOptionFromConfig(value, "allowUnboundThis", true);
        }
        if (std.mem.eql(u8, cli_name, "prefer-const")) {
            self.prefer_const_destructuring = try preferConstDestructuringFromConfig(value);
            self.prefer_const_ignore_read_before_assign = try preferConstBoolOptionFromConfig(value, "ignoreReadBeforeAssign", true);
        }
        if (std.mem.eql(u8, cli_name, "prefer-destructuring")) {
            self.prefer_destructuring_variable_declarator_array = try preferDestructuringOptionFromConfig(value, "VariableDeclarator", "array", true);
            self.prefer_destructuring_variable_declarator_object = try preferDestructuringOptionFromConfig(value, "VariableDeclarator", "object", true);
            self.prefer_destructuring_assignment_expression_array = try preferDestructuringOptionFromConfig(value, "AssignmentExpression", "array", true);
            self.prefer_destructuring_assignment_expression_object = try preferDestructuringOptionFromConfig(value, "AssignmentExpression", "object", true);
            self.prefer_destructuring_enforce_for_renamed_properties = try preferDestructuringEnforceForRenamedPropertiesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "prefer-promise-reject-errors")) {
            self.prefer_promise_reject_errors_allow_empty_reject = try preferPromiseRejectErrorsAllowEmptyRejectFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "preserve-caught-error")) {
            self.preserve_caught_error_require_catch_parameter = try preserveCaughtErrorRequireCatchParameterFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "prefer-regex-literals")) {
            self.prefer_regex_literals_disallow_redundant_wrapping = try preferRegexLiteralsDisallowRedundantWrappingFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "radix")) {
            self.radix_style = try radixStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "require-atomic-updates")) {
            self.require_atomic_updates_allow_properties = try requireAtomicUpdatesBoolOptionFromConfig(value, "allowProperties", false);
        }
        if (std.mem.eql(u8, cli_name, "require-unicode-regexp")) {
            self.require_unicode_regexp_require_flag = try requireUnicodeRegexpRequireFlagFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "sort-vars")) {
            self.sort_vars_ignore_case = try sortVarsIgnoreCaseFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "sort-imports")) {
            self.sort_imports_ignore_case = try sortImportsBoolOptionFromConfig(value, "ignoreCase", false);
            self.sort_imports_ignore_declaration_sort = try sortImportsBoolOptionFromConfig(value, "ignoreDeclarationSort", false);
            self.sort_imports_ignore_member_sort = try sortImportsBoolOptionFromConfig(value, "ignoreMemberSort", false);
            self.sort_imports_allow_separated_groups = try sortImportsBoolOptionFromConfig(value, "allowSeparatedGroups", false);
            self.sort_imports_member_syntax_order = try sortImportsMemberSyntaxOrderFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "sort-keys")) {
            self.sort_keys_order = try sortKeysOrderFromConfig(value);
            self.sort_keys_case_sensitive = try sortKeysBoolOptionFromConfig(value, "caseSensitive", true);
            self.sort_keys_natural = try sortKeysBoolOptionFromConfig(value, "natural", false);
            self.sort_keys_min_keys = try sortKeysMinKeysFromConfig(value);
            self.sort_keys_allow_line_separated_groups = try sortKeysBoolOptionFromConfig(value, "allowLineSeparatedGroups", false);
        }
        if (std.mem.eql(u8, cli_name, "strict")) {
            self.strict_mode = try strictModeFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-return-assign")) {
            self.no_return_assign_style = try noReturnAssignStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-sequences")) {
            self.no_sequences_allow_in_parentheses = try noSequencesAllowInParenthesesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-useless-computed-key")) {
            self.no_useless_computed_key_enforce_for_class_members = try noUselessComputedKeyEnforceForClassMembersFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-unused-expressions")) {
            self.no_unused_expressions_allow_short_circuit = try noUnusedExpressionsAllowShortCircuitFromConfig(value);
            self.no_unused_expressions_allow_ternary = try noUnusedExpressionsAllowTernaryFromConfig(value);
            self.no_unused_expressions_allow_tagged_templates = try noUnusedExpressionsAllowTaggedTemplatesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-unused-expressions")) {
            self.typescript_eslint_no_unused_expressions_allow_short_circuit = try noUnusedExpressionsAllowShortCircuitFromConfig(value);
            self.typescript_eslint_no_unused_expressions_allow_ternary = try noUnusedExpressionsAllowTernaryFromConfig(value);
            self.typescript_eslint_no_unused_expressions_allow_tagged_templates = try noUnusedExpressionsAllowTaggedTemplatesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-unused-vars")) {
            self.no_unused_vars_vars = try noUnusedVarsVarsFromConfig(value, .all);
            self.no_unused_vars_args = try noUnusedVarsArgsFromConfig(value, .none);
            self.no_unused_vars_caught_errors = try noUnusedVarsCaughtErrorsFromConfig(value, .none);
            self.no_unused_vars_ignore_rest_siblings = try noUnusedVarsIgnoreRestSiblingsFromConfig(value, false);
            self.no_unused_vars_ignore_class_with_static_init_block = try noUnusedVarsBoolOptionFromConfig(value, "ignoreClassWithStaticInitBlock", false);
            self.no_unused_vars_ignore_using_declarations = try noUnusedVarsBoolOptionFromConfig(value, "ignoreUsingDeclarations", false);
            self.no_unused_vars_args_ignore_pattern = try noUnusedVarsIgnorePatternFromConfig(value, "argsIgnorePattern");
            self.no_unused_vars_caught_errors_ignore_pattern = try noUnusedVarsIgnorePatternFromConfig(value, "caughtErrorsIgnorePattern");
            self.no_unused_vars_destructured_array_ignore_pattern = try noUnusedVarsIgnorePatternFromConfig(value, "destructuredArrayIgnorePattern");
            self.no_unused_vars_report_used_ignore_pattern = try noUnusedVarsReportUsedIgnorePatternFromConfig(value, false);
            self.no_unused_vars_vars_ignore_pattern = try noUnusedVarsIgnorePatternFromConfig(value, "varsIgnorePattern");
        }
        if (std.mem.eql(u8, cli_name, "no-use-before-define")) {
            self.no_use_before_define_check_functions = try noUseBeforeDefineCheckFromConfig(value, "functions", true);
            self.no_use_before_define_check_classes = try noUseBeforeDefineCheckFromConfig(value, "classes", true);
            self.no_use_before_define_check_variables = try noUseBeforeDefineCheckFromConfig(value, "variables", true);
            self.no_use_before_define_allow_named_exports = try noUseBeforeDefineAllowNamedExportsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "object-shorthand")) {
            self.object_shorthand_style = try objectShorthandStyleFromConfig(value);
            self.object_shorthand_avoid_quotes = try objectShorthandAvoidQuotesFromConfig(value);
            self.object_shorthand_ignore_constructors = try objectShorthandIgnoreConstructorsFromConfig(value);
            self.object_shorthand_avoid_explicit_return_arrows = try objectShorthandAvoidExplicitReturnArrowsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "one-var")) {
            const config = try oneVarNeverConfigFromConfig(value);
            self.one_var_check_var = config.@"var";
            self.one_var_check_let = config.let;
            self.one_var_check_const = config.@"const";
        }
        if (std.mem.eql(u8, cli_name, "operator-assignment")) {
            self.operator_assignment_style = try operatorAssignmentStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/default-props-match-prop-types")) {
            self.react_default_props_match_prop_types_allow_required_defaults = try reactDefaultPropsMatchPropTypesAllowRequiredDefaultsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/display-name")) {
            self.react_display_name_check_context_objects = try reactDisplayNameBoolOptionFromConfig(value, "checkContextObjects", false);
            self.react_display_name_ignore_transpiler_name = try reactDisplayNameBoolOptionFromConfig(value, "ignoreTranspilerName", false);
        }
        if (std.mem.eql(u8, cli_name, "react/button-has-type")) {
            self.react_button_has_type_button = try reactButtonHasTypeBoolOptionFromConfig(value, "button", true);
            self.react_button_has_type_submit = try reactButtonHasTypeBoolOptionFromConfig(value, "submit", true);
            self.react_button_has_type_reset = try reactButtonHasTypeBoolOptionFromConfig(value, "reset", true);
        }
        if (std.mem.eql(u8, cli_name, "react/forbid-prop-types")) {
            const forbid = try reactForbidPropTypesForbidFromConfig(value);
            self.react_forbid_prop_types_forbid_any = forbid.any;
            self.react_forbid_prop_types_forbid_array = forbid.array;
            self.react_forbid_prop_types_forbid_object = forbid.object;
            self.react_forbid_prop_types_check_context_types = try reactForbidPropTypesBoolOptionFromConfig(value, "checkContextTypes", false);
            self.react_forbid_prop_types_check_child_context_types = try reactForbidPropTypesBoolOptionFromConfig(value, "checkChildContextTypes", false);
        }
        if (std.mem.eql(u8, cli_name, "react/jsx-filename-extension")) {
            self.react_jsx_filename_extension_extensions = try reactJsxFilenameExtensionsFromConfig(value);
            self.react_jsx_filename_extension_allow = try reactJsxFilenameExtensionAllowFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/jsx-boolean-value")) {
            self.react_jsx_boolean_value_style = try reactJsxBooleanValueStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/jsx-no-bind")) {
            self.react_jsx_no_bind_allow_arrow_functions = try reactJsxNoBindBoolOptionFromConfig(value, "allowArrowFunctions", false);
            self.react_jsx_no_bind_allow_functions = try reactJsxNoBindBoolOptionFromConfig(value, "allowFunctions", false);
            self.react_jsx_no_bind_allow_bind = try reactJsxNoBindBoolOptionFromConfig(value, "allowBind", false);
            self.react_jsx_no_bind_ignore_refs = try reactJsxNoBindBoolOptionFromConfig(value, "ignoreRefs", false);
            self.react_jsx_no_bind_ignore_dom_components = try reactJsxNoBindBoolOptionFromConfig(value, "ignoreDOMComponents", false);
        }
        if (std.mem.eql(u8, cli_name, "react/jsx-no-duplicate-props")) {
            self.react_jsx_no_duplicate_props_ignore_case = try reactJsxNoDuplicatePropsIgnoreCaseFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/jsx-key")) {
            self.react_jsx_key_check_key_must_before_spread = try reactJsxKeyBoolOptionFromConfig(value, "checkKeyMustBeforeSpread", false);
            self.react_jsx_key_check_fragment_shorthand = try reactJsxKeyBoolOptionFromConfig(value, "checkFragmentShorthand", false);
            self.react_jsx_key_warn_on_duplicates = try reactJsxKeyBoolOptionFromConfig(value, "warnOnDuplicates", false);
        }
        if (std.mem.eql(u8, cli_name, "react/jsx-no-target-blank")) {
            self.react_jsx_no_target_blank_allow_referrer = try reactJsxNoTargetBlankAllowReferrerFromConfig(value);
            self.react_jsx_no_target_blank_enforce_dynamic_links = try reactJsxNoTargetBlankEnforceDynamicLinksFromConfig(value);
            self.react_jsx_no_target_blank_warn_on_spread_attributes = try reactJsxNoTargetBlankWarnOnSpreadAttributesFromConfig(value);
            self.react_jsx_no_target_blank_links = try reactJsxNoTargetBlankBoolOptionFromConfig(value, "links", true);
            self.react_jsx_no_target_blank_forms = try reactJsxNoTargetBlankBoolOptionFromConfig(value, "forms", false);
        }
        if (std.mem.eql(u8, cli_name, "react/jsx-pascal-case")) {
            self.react_jsx_pascal_case_allow_all_caps = try reactJsxPascalCaseAllowAllCapsFromConfig(value);
            self.react_jsx_pascal_case_allow_leading_underscore = try reactJsxPascalCaseAllowLeadingUnderscoreFromConfig(value);
            self.react_jsx_pascal_case_allow_namespace = try reactJsxPascalCaseAllowNamespaceFromConfig(value);
            self.react_jsx_pascal_case_ignore = try reactJsxPascalCaseIgnoreFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/prop-types")) {
            self.react_prop_types_skip_undeclared = try reactPropTypesSkipUndeclaredFromConfig(value);
            self.react_prop_types_ignore = try reactPropTypesIgnoreFromConfig(value);
            self.react_prop_types_custom_validators = try reactPropTypesCustomValidatorsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/no-unused-prop-types")) {
            self.react_no_unused_prop_types_skip_shape_props = try reactNoUnusedPropTypesSkipShapePropsFromConfig(value);
            self.react_no_unused_prop_types_ignore = try reactPropTypesIgnoreFromConfig(value);
            self.react_no_unused_prop_types_custom_validators = try reactPropTypesCustomValidatorsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/no-string-refs")) {
            self.react_no_string_refs_no_template_literals = try reactNoStringRefsNoTemplateLiteralsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/no-multi-comp")) {
            self.react_no_multi_comp_ignore_stateless = try reactNoMultiCompIgnoreStatelessFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/no-unstable-nested-components")) {
            self.react_no_unstable_nested_components_allow_as_props = try reactNoUnstableNestedComponentsAllowAsPropsFromConfig(value);
            self.react_no_unstable_nested_components_prop_name_pattern = try reactNoUnstableNestedComponentsPropNamePatternFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/no-children-prop")) {
            self.react_no_children_prop_allow_functions = try reactNoChildrenPropAllowFunctionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/no-unknown-property")) {
            self.react_no_unknown_property_ignore = try reactNoUnknownPropertyIgnoreFromConfig(value);
            self.react_no_unknown_property_require_data_lowercase = try reactNoUnknownPropertyRequireDataLowercaseFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/no-unescaped-entities")) {
            const forbid = try reactNoUnescapedEntitiesForbidFromConfig(value);
            self.react_no_unescaped_entities_forbid_gt = forbid.gt;
            self.react_no_unescaped_entities_forbid_double_quote = forbid.double_quote;
            self.react_no_unescaped_entities_forbid_single_quote = forbid.single_quote;
            self.react_no_unescaped_entities_forbid_closing_brace = forbid.closing_brace;
        }
        if (std.mem.eql(u8, cli_name, "react/prefer-es6-class")) {
            self.react_prefer_es6_class_style = try reactPreferEs6ClassStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react/self-closing-comp")) {
            self.react_self_closing_comp_component = try reactSelfClosingCompBoolOptionFromConfig(value, "component", true);
            self.react_self_closing_comp_html = try reactSelfClosingCompBoolOptionFromConfig(value, "html", true);
        }
        if (std.mem.eql(u8, cli_name, "promise/no-callback-in-promise")) {
            self.promise_no_callback_in_promise_exceptions = try promiseNoCallbackInPromiseExceptionsFromConfig(value);
            self.promise_no_callback_in_promise_timeouts_err = try promiseNoCallbackInPromiseTimeoutsErrFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "promise/catch-or-return")) {
            self.promise_catch_or_return_allow_finally = try promiseCatchOrReturnBoolOptionFromConfig(value, "allowFinally");
            self.promise_catch_or_return_allow_then = try promiseCatchOrReturnBoolOptionFromConfig(value, "allowThen");
            self.promise_catch_or_return_allow_then_strict = try promiseCatchOrReturnBoolOptionFromConfig(value, "allowThenStrict");
            self.promise_catch_or_return_termination_methods = try promiseCatchOrReturnTerminationMethodsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "promise/always-return")) {
            self.promise_always_return_ignore_last_callback = try promiseAlwaysReturnBoolOptionFromConfig(value, "ignoreLastCallback", false);
            self.promise_always_return_ignore_assignment_variables = try promiseAlwaysReturnIgnoreAssignmentVariablesFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "react-hooks/exhaustive-deps")) {
            self.react_hooks_exhaustive_deps_additional_hooks = try reactHooksAdditionalHooksFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/array-type")) {
            self.typescript_eslint_array_type_style = try typescriptEslintArrayTypeStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/ban-types")) {
            self.typescript_eslint_ban_types_config = try typescriptEslintBanTypesConfigFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/ban-ts-comment")) {
            self.typescript_eslint_ban_ts_comment_ts_expect_error = try typescriptEslintBanTsCommentModeFromConfig(value, "ts-expect-error", .allow_with_description);
            self.typescript_eslint_ban_ts_comment_ts_ignore = try typescriptEslintBanTsCommentModeFromConfig(value, "ts-ignore", .allow_with_description);
            self.typescript_eslint_ban_ts_comment_ts_nocheck = try typescriptEslintBanTsCommentModeFromConfig(value, "ts-nocheck", .allow_with_description);
            self.typescript_eslint_ban_ts_comment_ts_check = try typescriptEslintBanTsCommentModeFromConfig(value, "ts-check", .allow_with_description);
            self.typescript_eslint_ban_ts_comment_minimum_description_length = try typescriptEslintBanTsCommentMinimumDescriptionLengthFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/class-literal-property-style")) {
            self.typescript_eslint_class_literal_property_style_style = try typescriptEslintClassLiteralPropertyStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/consistent-type-definitions")) {
            self.typescript_eslint_consistent_type_definitions_style = try typescriptEslintConsistentTypeDefinitionsStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/consistent-type-assertions")) {
            self.typescript_eslint_consistent_type_assertions_assertion_style = try typescriptEslintConsistentTypeAssertionsStyleFromConfig(value);
            self.typescript_eslint_consistent_type_assertions_object_literal_type_assertions = try typescriptEslintLiteralTypeAssertionsFromConfig(value, "objectLiteralTypeAssertions", .never);
            self.typescript_eslint_consistent_type_assertions_array_literal_type_assertions = try typescriptEslintLiteralTypeAssertionsFromConfig(value, "arrayLiteralTypeAssertions", .allow);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/explicit-member-accessibility")) {
            self.typescript_eslint_explicit_member_accessibility_accessibility = try typescriptEslintExplicitMemberAccessibilityFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-empty-interface")) {
            self.typescript_eslint_no_empty_interface_allow_single_extends = try typescriptEslintNoEmptyInterfaceAllowSingleExtendsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-empty-object-type")) {
            self.typescript_eslint_no_empty_object_type_allow_interfaces = try typescriptEslintNoEmptyObjectTypeAllowInterfacesFromConfig(value);
            self.typescript_eslint_no_empty_object_type_allow_object_types = try typescriptEslintNoEmptyObjectTypeAllowObjectTypesFromConfig(value);
            self.typescript_eslint_no_empty_object_type_allow_with_name = try typescriptEslintNoEmptyObjectTypeAllowWithNameFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-explicit-any")) {
            self.typescript_eslint_no_explicit_any_fix_to_unknown = try typescriptEslintNoExplicitAnyBoolOptionFromConfig(value, "fixToUnknown");
            self.typescript_eslint_no_explicit_any_ignore_rest_args = try typescriptEslintNoExplicitAnyBoolOptionFromConfig(value, "ignoreRestArgs");
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-inferrable-types")) {
            self.typescript_eslint_no_inferrable_types_ignore_parameters = try typescriptEslintNoInferrableTypesBoolOptionFromConfig(value, "ignoreParameters", false);
            self.typescript_eslint_no_inferrable_types_ignore_properties = try typescriptEslintNoInferrableTypesBoolOptionFromConfig(value, "ignoreProperties", false);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-invalid-void-type")) {
            self.typescript_eslint_no_invalid_void_type_allow_as_this_parameter = try typescriptEslintNoInvalidVoidTypeBoolOptionFromConfig(value, "allowAsThisParameter", false);
            const allow_in_generic_type_arguments = try typescriptEslintNoInvalidVoidTypeGenericTypeArgumentsFromConfig(value);
            self.typescript_eslint_no_invalid_void_type_allow_in_generic_type_arguments = allow_in_generic_type_arguments.allow_any;
            self.typescript_eslint_no_invalid_void_type_allowed_generic_type_names = allow_in_generic_type_arguments.allowed_names;
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-shadow")) {
            self.typescript_eslint_no_shadow_allow = try noShadowAllowFromConfig(value);
            self.typescript_eslint_no_shadow_builtin_globals = try noShadowBuiltinGlobalsFromConfig(value);
            self.typescript_eslint_no_shadow_hoist = try noShadowHoistFromConfig(value, .functions_and_types);
            self.typescript_eslint_no_shadow_ignore_on_initialization = try noShadowBoolOptionFromConfig(value, "ignoreOnInitialization", false);
            self.typescript_eslint_no_shadow_ignore_type_value_shadow = try noShadowBoolOptionFromConfig(value, "ignoreTypeValueShadow", false);
            self.typescript_eslint_no_shadow_ignore_function_type_parameter_name_value_shadow = try noShadowBoolOptionFromConfig(value, "ignoreFunctionTypeParameterNameValueShadow", true);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/method-signature-style")) {
            self.typescript_eslint_method_signature_style_style = try typescriptEslintMethodSignatureStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-namespace")) {
            self.typescript_eslint_no_namespace_allow_declarations = try typescriptEslintNoNamespaceBoolOptionFromConfig(value, "allowDeclarations", true);
            self.typescript_eslint_no_namespace_allow_definition_files = try typescriptEslintNoNamespaceBoolOptionFromConfig(value, "allowDefinitionFiles", true);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-redeclare")) {
            self.typescript_eslint_no_redeclare_builtin_globals = try typescriptEslintNoRedeclareBuiltinGlobalsFromConfig(value);
            self.typescript_eslint_no_redeclare_ignore_declaration_merge = try typescriptEslintNoRedeclareIgnoreDeclarationMergeFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-require-imports")) {
            self.typescript_eslint_no_require_imports_allow_as_import = try typescriptEslintNoRequireImportsBoolOptionFromConfig(value, "allowAsImport", false);
            self.typescript_eslint_no_require_imports_allow = try typescriptEslintNoRequireImportsAllowFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-this-alias")) {
            self.typescript_eslint_no_this_alias_allowed_names = try typescriptEslintNoThisAliasAllowedNamesFromConfig(value);
            self.typescript_eslint_no_this_alias_allow_destructuring = try typescriptEslintNoThisAliasAllowDestructuringFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-unused-vars")) {
            self.typescript_eslint_no_unused_vars_vars = try noUnusedVarsVarsFromConfig(value, .all);
            self.typescript_eslint_no_unused_vars_args = try noUnusedVarsArgsFromConfig(value, .after_used);
            self.typescript_eslint_no_unused_vars_caught_errors = try noUnusedVarsCaughtErrorsFromConfig(value, .none);
            self.typescript_eslint_no_unused_vars_ignore_rest_siblings = try noUnusedVarsIgnoreRestSiblingsFromConfig(value, true);
            self.typescript_eslint_no_unused_vars_ignore_class_with_static_init_block = try noUnusedVarsBoolOptionFromConfig(value, "ignoreClassWithStaticInitBlock", false);
            self.typescript_eslint_no_unused_vars_ignore_using_declarations = try noUnusedVarsBoolOptionFromConfig(value, "ignoreUsingDeclarations", false);
            self.typescript_eslint_no_unused_vars_args_ignore_pattern = try noUnusedVarsIgnorePatternFromConfig(value, "argsIgnorePattern");
            self.typescript_eslint_no_unused_vars_caught_errors_ignore_pattern = try noUnusedVarsIgnorePatternFromConfig(value, "caughtErrorsIgnorePattern");
            self.typescript_eslint_no_unused_vars_destructured_array_ignore_pattern = try noUnusedVarsIgnorePatternFromConfig(value, "destructuredArrayIgnorePattern");
            self.typescript_eslint_no_unused_vars_report_used_ignore_pattern = try noUnusedVarsReportUsedIgnorePatternFromConfig(value, false);
            self.typescript_eslint_no_unused_vars_vars_ignore_pattern = try noUnusedVarsIgnorePatternFromConfig(value, "varsIgnorePattern");
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/triple-slash-reference")) {
            self.typescript_eslint_triple_slash_reference_path = try typescriptEslintTripleSlashReferenceModeFromConfig(value, "path", .never);
            self.typescript_eslint_triple_slash_reference_types = try typescriptEslintTripleSlashReferenceModeFromConfig(value, "types", .always);
            self.typescript_eslint_triple_slash_reference_lib = try typescriptEslintTripleSlashReferenceModeFromConfig(value, "lib", .always);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/typedef")) {
            self.typescript_eslint_typedef_property_declaration = try typescriptEslintTypedefBoolOptionFromConfig(value, "propertyDeclaration", true);
            self.typescript_eslint_typedef_member_variable_declaration = try typescriptEslintTypedefBoolOptionFromConfig(value, "memberVariableDeclaration", false);
            self.typescript_eslint_typedef_parameter = try typescriptEslintTypedefBoolOptionFromConfig(value, "parameter", false);
            self.typescript_eslint_typedef_arrow_parameter = try typescriptEslintTypedefBoolOptionFromConfig(value, "arrowParameter", false);
            self.typescript_eslint_typedef_array_destructuring = try typescriptEslintTypedefBoolOptionFromConfig(value, "arrayDestructuring", false);
            self.typescript_eslint_typedef_object_destructuring = try typescriptEslintTypedefBoolOptionFromConfig(value, "objectDestructuring", false);
            self.typescript_eslint_typedef_variable_declaration = try typescriptEslintTypedefBoolOptionFromConfig(value, "variableDeclaration", false);
            self.typescript_eslint_typedef_variable_declaration_ignore_function = try typescriptEslintTypedefBoolOptionFromConfig(value, "variableDeclarationIgnoreFunction", false);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/restrict-plus-operands")) {
            self.typescript_eslint_restrict_plus_operands_allow_number_and_string = try typescriptEslintRestrictPlusOperandsBoolOptionFromConfig(value, "allowNumberAndString", false);
        }
        if (std.mem.eql(u8, cli_name, "no-undef")) {
            self.no_undef_typeof = try noUndefTypeofFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-tabs")) {
            self.no_tabs_allow_indentation_tabs = try noTabsAllowIndentationTabsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-unneeded-ternary")) {
            self.no_unneeded_ternary_default_assignment = try noUnneededTernaryDefaultAssignmentFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "@typescript-eslint/no-use-before-define")) {
            self.typescript_eslint_no_use_before_define_check_functions = try noUseBeforeDefineCheckFromConfig(value, "functions", false);
            self.typescript_eslint_no_use_before_define_check_classes = try noUseBeforeDefineCheckFromConfig(value, "classes", true);
            self.typescript_eslint_no_use_before_define_check_variables = try noUseBeforeDefineCheckFromConfig(value, "variables", true);
            self.typescript_eslint_no_use_before_define_check_typedefs = try noUseBeforeDefineCheckFromConfig(value, "typedefs", true);
            self.typescript_eslint_no_use_before_define_check_enums = try noUseBeforeDefineCheckFromConfig(value, "enums", true);
            self.typescript_eslint_no_use_before_define_allow_named_exports = try noUseBeforeDefineAllowNamedExportsFromConfig(value);
            self.typescript_eslint_no_use_before_define_ignore_type_references = try noUseBeforeDefineBoolOptionFromConfig(value, "ignoreTypeReferences", true);
        }
        if (std.mem.eql(u8, cli_name, "no-void")) {
            self.no_void_allow_as_statement = try noVoidAllowAsStatementFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "no-warning-comments")) {
            self.no_warning_comments_location = try noWarningCommentsLocationFromConfig(value);
            self.no_warning_comments_decoration = try noWarningCommentsDecorationFromConfig(value);
            self.no_warning_comments_terms = try noWarningCommentsTermsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "valid-typeof")) {
            self.valid_typeof_require_string_literals = try validTypeofRequireStringLiteralsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "spaced-comment")) {
            self.spaced_comment_style = try spacedCommentStyleFromConfig(value);
            self.spaced_comment_markers = try spacedCommentMarkersFromConfig(value);
            self.spaced_comment_exceptions = try spacedCommentExceptionsFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "wrap-iife")) {
            self.wrap_iife_style = try wrapIifeStyleFromConfig(value);
        }
        if (std.mem.eql(u8, cli_name, "yoda")) {
            self.yoda_style = try yodaStyleFromConfig(value);
            self.yoda_only_equality = try yodaOnlyEqualityFromConfig(value);
            self.yoda_except_range = try yodaExceptRangeFromConfig(value);
        }
    }

    pub fn setJestVersionFromConfig(self: *Options, value: std.json.Value) RuleConfigError!void {
        self.jest_version = switch (value) {
            .integer => |version| if (version > 0 and version <= std.math.maxInt(u32))
                @intCast(version)
            else
                return error.InvalidJestVersion,
            .string => |version| blk: {
                const separator = std.mem.indexOfScalar(u8, version, '.') orelse version.len;
                const major = version[0..separator];
                if (major.len == 0) return error.InvalidJestVersion;
                for (major) |char| {
                    if (!std.ascii.isDigit(char)) return error.InvalidJestVersion;
                }
                const parsed = std.fmt.parseUnsigned(u32, major, 10) catch return error.InvalidJestVersion;
                if (parsed == 0) return error.InvalidJestVersion;
                break :blk parsed;
            },
            else => return error.InvalidJestVersion,
        };
    }

    pub fn setJestGlobalAliasesFromConfig(self: *Options, value: std.json.Value) RuleConfigError!void {
        const aliases = switch (value) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };

        self.jest_global_aliases = .{};
        var iterator = aliases.iterator();
        while (iterator.next()) |entry| {
            const values = switch (entry.value_ptr.*) {
                .array => |array| array.items,
                else => return error.UnsupportedRuleConfigValue,
            };
            for (values) |item| {
                const alias = switch (item) {
                    .string => |string| string,
                    else => return error.UnsupportedRuleConfigValue,
                };
                if (!self.jest_global_aliases.append(entry.key_ptr.*, alias)) {
                    return error.UnsupportedRuleConfigValue;
                }
            }
        }
    }

    pub fn severityFromRuleConfigValue(value: std.json.Value) RuleConfigError!?Severity {
        return switch (value) {
            .bool => |enabled| if (enabled) .@"error" else null,
            .integer => |severity| switch (severity) {
                0 => null,
                1 => .warning,
                2 => .@"error",
                else => error.UnsupportedRuleConfigValue,
            },
            .string => |severity| {
                if (std.ascii.eqlIgnoreCase(severity, "off") or std.mem.eql(u8, severity, "0")) return null;
                if (std.ascii.eqlIgnoreCase(severity, "warn") or
                    std.ascii.eqlIgnoreCase(severity, "warning") or
                    std.ascii.eqlIgnoreCase(severity, "on") or
                    std.mem.eql(u8, severity, "1"))
                {
                    return .warning;
                }
                if (std.ascii.eqlIgnoreCase(severity, "error") or std.mem.eql(u8, severity, "2")) {
                    return .@"error";
                }
                return error.UnsupportedRuleConfigValue;
            },
            .array => |items| {
                if (items.items.len == 0) return error.EmptyRuleConfigArray;
                return severityFromRuleConfigValue(items.items[0]);
            },
            else => error.UnsupportedRuleConfigValue,
        };
    }

    pub const RuleConfigError = error{
        EmptyRuleConfigArray,
        InvalidJestVersion,
        UnknownRule,
        UnsupportedRuleConfigValue,
    };

    fn ruleConfigValueToBool(value: std.json.Value) RuleConfigError!bool {
        return switch (value) {
            .bool => |enabled| enabled,
            .integer => |severity| switch (severity) {
                0 => false,
                1, 2 => true,
                else => error.UnsupportedRuleConfigValue,
            },
            .string => |severity| ruleSeverityStringToBool(severity) orelse error.UnsupportedRuleConfigValue,
            .array => |items| {
                if (items.items.len == 0) return error.EmptyRuleConfigArray;
                return ruleConfigValueToBool(items.items[0]);
            },
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn ruleSeverityStringToBool(severity: []const u8) ?bool {
        if (std.ascii.eqlIgnoreCase(severity, "off") or std.mem.eql(u8, severity, "0")) return false;
        if (std.ascii.eqlIgnoreCase(severity, "warn") or
            std.ascii.eqlIgnoreCase(severity, "warning") or
            std.ascii.eqlIgnoreCase(severity, "error") or
            std.ascii.eqlIgnoreCase(severity, "on") or
            std.mem.eql(u8, severity, "1") or
            std.mem.eql(u8, severity, "2"))
        {
            return true;
        }
        return null;
    }

    fn curlyStyleFromConfig(value: std.json.Value) RuleConfigError!CurlyStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .all,
        };
        if (items.len < 2) return .all;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "all")) return .all;
        if (std.mem.eql(u8, style, "multi-line")) return .multi_line;
        if (std.mem.eql(u8, style, "multi")) return .multi;
        if (std.mem.eql(u8, style, "multi-or-nest")) return .multi_or_nest;
        return error.UnsupportedRuleConfigValue;
    }

    fn eolLastStyleFromConfig(value: std.json.Value) RuleConfigError!EolLastStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always") or std.mem.eql(u8, style, "unix") or std.mem.eql(u8, style, "windows")) return .always;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn eqeqeqStyleFromConfig(value: std.json.Value) RuleConfigError!EqeqeqStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .strict,
        };
        if (items.len < 2) return .strict;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .strict;
        if (std.mem.eql(u8, style, "allow-null")) return .allow_null;
        if (std.mem.eql(u8, style, "smart")) return .smart;
        return error.UnsupportedRuleConfigValue;
    }

    fn linebreakStyleFromConfig(value: std.json.Value) RuleConfigError!LinebreakStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .unix,
        };
        if (items.len < 2) return .unix;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "unix")) return .unix;
        if (std.mem.eql(u8, style, "windows")) return .windows;
        return error.UnsupportedRuleConfigValue;
    }

    fn initDeclarationsModeFromConfig(value: std.json.Value) RuleConfigError!InitDeclarationsMode {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const mode = switch (items[1]) {
            .string => |mode| mode,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, mode, "always")) return .always;
        if (std.mem.eql(u8, mode, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn initDeclarationsIgnoreForLoopInitFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 3) return false;

        const config = switch (items[2]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("ignoreForLoopInit") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn consistentReturnTreatUndefinedAsUnspecifiedFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("treatUndefinedAsUnspecified") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn consistentThisAliasesFromConfig(value: std.json.Value) RuleConfigError!ConsistentThisAliases {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        var aliases = ConsistentThisAliases{ .custom = true };
        for (items[1..]) |item| {
            const alias = switch (item) {
                .string => |alias| alias,
                else => return error.UnsupportedRuleConfigValue,
            };
            aliases.append(alias) catch return error.UnsupportedRuleConfigValue;
        }
        return aliases;
    }

    fn accessorPairsGetWithoutSetFromConfig(value: std.json.Value) RuleConfigError!AccessorPairsGetWithoutSet {
        const enabled = try accessorPairsOptionFromConfig(value, "getWithoutSet", false);
        return if (enabled) .yes else .no;
    }

    fn accessorPairsSetWithoutGetFromConfig(value: std.json.Value) RuleConfigError!AccessorPairsSetWithoutGet {
        const enabled = try accessorPairsOptionFromConfig(value, "setWithoutGet", true);
        return if (enabled) .yes else .no;
    }

    fn accessorPairsEnforceForClassMembersFromConfig(value: std.json.Value) RuleConfigError!AccessorPairsEnforceForClassMembers {
        const enabled = try accessorPairsOptionFromConfig(value, "enforceForClassMembers", true);
        return if (enabled) .yes else .no;
    }

    fn accessorPairsOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn arrayCallbackReturnAllowImplicitFromConfig(value: std.json.Value) RuleConfigError!ArrayCallbackReturnAllowImplicit {
        const enabled = try arrayCallbackReturnOptionFromConfig(value, "allowImplicit", false);
        return if (enabled) .yes else .no;
    }

    fn arrayCallbackReturnCheckForEachFromConfig(value: std.json.Value) RuleConfigError!ArrayCallbackReturnCheckForEach {
        const enabled = try arrayCallbackReturnOptionFromConfig(value, "checkForEach", false);
        return if (enabled) .yes else .no;
    }

    fn arrayCallbackReturnAllowVoidFromConfig(value: std.json.Value) RuleConfigError!ArrayCallbackReturnAllowVoid {
        const enabled = try arrayCallbackReturnOptionFromConfig(value, "allowVoid", false);
        return if (enabled) .yes else .no;
    }

    fn arrayCallbackReturnOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    const ArrowBodyStyleConfig = struct {
        style: ArrowBodyStyle = .as_needed,
        require_return_for_object_literal: bool = false,
    };

    fn arrowBodyStyleFromConfig(value: std.json.Value) RuleConfigError!ArrowBodyStyleConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const style_value = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = ArrowBodyStyleConfig{};
        if (std.mem.eql(u8, style_value, "always")) {
            result.style = .always;
        } else if (std.mem.eql(u8, style_value, "as-needed")) {
            result.style = .as_needed;
        } else if (std.mem.eql(u8, style_value, "never")) {
            result.style = .never;
        } else {
            return error.UnsupportedRuleConfigValue;
        }

        if (items.len < 3) return result;
        const config = switch (items[2]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        result.require_return_for_object_literal = try boolObjectOption(config, "requireReturnForObjectLiteral", false);
        return result;
    }

    const CamelcaseConfig = struct {
        properties: CamelcaseProperties = .always,
        ignore_destructuring: bool = false,
        ignore_imports: bool = false,
        ignore_globals: bool = false,
        allow: CamelcaseAllowPatterns = .{},
    };

    fn camelcaseFromConfig(value: std.json.Value) RuleConfigError!CamelcaseConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = CamelcaseConfig{};
        if (config.get("properties")) |properties_value| {
            const properties = switch (properties_value) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, properties, "always")) {
                result.properties = .always;
            } else if (std.mem.eql(u8, properties, "never")) {
                result.properties = .never;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }

        result.ignore_destructuring = try boolObjectOption(config, "ignoreDestructuring", false);
        result.ignore_imports = try boolObjectOption(config, "ignoreImports", false);
        result.ignore_globals = try boolObjectOption(config, "ignoreGlobals", false);

        if (config.get("allow")) |allow_value| {
            const allow_items = switch (allow_value) {
                .array => |array| array.items,
                else => return error.UnsupportedRuleConfigValue,
            };
            for (allow_items) |allow_item| {
                const pattern = switch (allow_item) {
                    .string => |string| string,
                    else => return error.UnsupportedRuleConfigValue,
                };
                result.allow.append(pattern) catch return error.UnsupportedRuleConfigValue;
            }
        }

        return result;
    }

    const ClassMethodsUseThisConfig = struct {
        enforce_for_class_fields: bool = true,
        except_methods: ClassMethodsUseThisExceptMethods = .{},
        ignore_override_methods: bool = false,
        ignore_classes_with_implements: ClassMethodsUseThisIgnoreClassesWithImplements = .none,
    };

    fn classMethodsUseThisFromConfig(value: std.json.Value) RuleConfigError!ClassMethodsUseThisConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = ClassMethodsUseThisConfig{};
        result.enforce_for_class_fields = try boolObjectOption(config, "enforceForClassFields", true);
        result.ignore_override_methods = try boolObjectOption(config, "ignoreOverrideMethods", false);

        if (config.get("exceptMethods")) |except_methods_value| {
            const except_methods = switch (except_methods_value) {
                .array => |array| array.items,
                else => return error.UnsupportedRuleConfigValue,
            };
            for (except_methods) |except_method_value| {
                const except_method = switch (except_method_value) {
                    .string => |name| name,
                    else => return error.UnsupportedRuleConfigValue,
                };
                result.except_methods.append(except_method) catch return error.UnsupportedRuleConfigValue;
            }
        }

        if (config.get("ignoreClassesWithImplements")) |ignore_value| {
            const ignore = switch (ignore_value) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, ignore, "all")) {
                result.ignore_classes_with_implements = .all;
            } else if (std.mem.eql(u8, ignore, "public-fields")) {
                result.ignore_classes_with_implements = .public_fields;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }

        return result;
    }

    fn capitalizedCommentsModeFromConfig(value: std.json.Value) RuleConfigError!CapitalizedCommentsMode {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const mode = switch (items[1]) {
            .string => |mode| mode,
            .object => return .always,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, mode, "always")) return .always;
        if (std.mem.eql(u8, mode, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn capitalizedCommentsIgnoreInlineCommentsFromConfig(value: std.json.Value) RuleConfigError!CapitalizedCommentsIgnoreInlineComments {
        const ignore = try capitalizedCommentsBoolOptionFromConfig(value, "ignoreInlineComments", false);
        return if (ignore) .yes else .no;
    }

    fn capitalizedCommentsIgnoreConsecutiveCommentsFromConfig(value: std.json.Value) RuleConfigError!CapitalizedCommentsIgnoreConsecutiveComments {
        const ignore = try capitalizedCommentsBoolOptionFromConfig(value, "ignoreConsecutiveComments", false);
        return if (ignore) .yes else .no;
    }

    fn capitalizedCommentsBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config_value = switch (items[1]) {
            .object => items[1],
            .string => if (items.len >= 3) items[2] else return default,
            else => return error.UnsupportedRuleConfigValue,
        };
        const config = switch (config_value) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn complexityMaxFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 20,
        };
        if (items.len < 2) return 20;

        switch (items[1]) {
            .integer => |max| return nonNegativeIntegerToUsize(max),
            .object => |object| {
                if (object.get("maximum")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                if (object.get("max")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                return 20;
            },
            else => return error.UnsupportedRuleConfigValue,
        }
    }

    fn complexityVariantFromConfig(value: std.json.Value) RuleConfigError!ComplexityVariant {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .classic,
        };
        if (items.len < 2) return .classic;

        const object = switch (items[1]) {
            .object => |object| object,
            else => return .classic,
        };
        const variant = switch (object.get("variant") orelse return .classic) {
            .string => |variant| variant,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, variant, "classic")) return .classic;
        if (std.mem.eql(u8, variant, "modified")) return .modified;
        return error.UnsupportedRuleConfigValue;
    }

    fn deprecatedDependenceProfileFromConfig(value: std.json.Value) DeprecatedDependenceProfile {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .default,
        };
        if (items.len < 2) return .default;
        const config = switch (items[1]) {
            .object => |object| object,
            else => return .default,
        };
        const external_packages = switch (config.get("externalPackages") orelse return .default) {
            .object => |object| object,
            else => return .default,
        };

        if (external_packages.get("@example/share-react") != null or
            external_packages.get("@example/monitor-web") != null or
            external_packages.get("moment") != null)
        {
            return .profile_a;
        }
        if (external_packages.get("@example/bridge") != null or
            external_packages.get("@example/rpc-client") != null or
            external_packages.get("statekit") != null)
        {
            return .profile_b;
        }
        return .default;
    }

    fn dotNotationAllowKeywordsFromConfig(value: std.json.Value) RuleConfigError!DotNotationAllowKeywords {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .yes,
        };
        if (items.len < 2) return .yes;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowKeywords") orelse return .yes) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn dotNotationAllowPatternFromConfig(value: std.json.Value) RuleConfigError!DotNotationAllowPattern {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const pattern_value = switch (config.get("allowPattern") orelse return .{}) {
            .string => |pattern_value| pattern_value,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (pattern_value.len == 0) return .{};

        var pattern = DotNotationAllowPattern{};
        pattern.set(pattern_value) catch return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn noRestrictedDisableRestrictsNoNestedTernary(value: std.json.Value) bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;
        for (items[1..]) |item| {
            const rule = switch (item) {
                .string => |rule| rule,
                else => continue,
            };
            if (std.mem.eql(u8, rule, "no-nested-ternary")) return true;
        }
        return false;
    }

    fn importNoUnresolvedIgnorePatternsFromConfig(value: std.json.Value) RuleConfigError!ImportNoUnresolvedIgnorePatterns {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ignores = switch (config.get("ignore") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var patterns = ImportNoUnresolvedIgnorePatterns{};
        for (ignores) |ignore| {
            const pattern = switch (ignore) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!patterns.append(pattern)) return error.UnsupportedRuleConfigValue;
        }
        return patterns;
    }

    fn importNoUnresolvedBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn funcNameMatchingStyleFromConfig(value: std.json.Value) RuleConfigError!FuncNameMatchingStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            .object => return .always,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn funcNameMatchingBoolOptionFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config_value = switch (items[1]) {
            .object => items[1],
            .string => if (items.len >= 3) items[2] else return false,
            else => return error.UnsupportedRuleConfigValue,
        };
        const config = switch (config_value) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn getterReturnAllowImplicitFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowImplicit") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn funcNamesStyleFromConfig(value: std.json.Value) RuleConfigError!FuncNamesStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "as-needed")) return .as_needed;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn funcNamesGeneratorStyleFromConfig(value: std.json.Value) RuleConfigError!?FuncNamesStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return null,
        };
        if (items.len < 3) return null;

        const config = switch (items[2]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const style = switch (config.get("generators") orelse return null) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "as-needed")) return .as_needed;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    const FuncStyleConfig = struct {
        style: FuncStyleStyle = .expression,
        allow_arrow_functions: bool = false,
        allow_type_annotation: bool = false,
        named_exports: FuncStyleNamedExports = .unset,
    };

    fn funcStyleFromConfig(value: std.json.Value) RuleConfigError!FuncStyleConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };

        var config = FuncStyleConfig{};
        if (items.len >= 2) {
            const style = switch (items[1]) {
                .string => |style| style,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, style, "expression")) {
                config.style = .expression;
            } else if (std.mem.eql(u8, style, "declaration")) {
                config.style = .declaration;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }

        if (items.len >= 3) {
            const object = switch (items[2]) {
                .object => |object| object,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (object.get("allowArrowFunctions")) |entry| {
                config.allow_arrow_functions = switch (entry) {
                    .bool => |enabled| enabled,
                    else => return error.UnsupportedRuleConfigValue,
                };
            }
            if (object.get("allowTypeAnnotation")) |entry| {
                config.allow_type_annotation = switch (entry) {
                    .bool => |enabled| enabled,
                    else => return error.UnsupportedRuleConfigValue,
                };
            }
            if (object.get("overrides")) |entry| {
                const overrides = switch (entry) {
                    .object => |overrides| overrides,
                    else => return error.UnsupportedRuleConfigValue,
                };
                if (overrides.get("namedExports")) |named_exports| {
                    const mode = switch (named_exports) {
                        .string => |mode| mode,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    if (std.mem.eql(u8, mode, "expression")) {
                        config.named_exports = .expression;
                    } else if (std.mem.eql(u8, mode, "declaration")) {
                        config.named_exports = .declaration;
                    } else if (std.mem.eql(u8, mode, "ignore")) {
                        config.named_exports = .ignore;
                    } else {
                        return error.UnsupportedRuleConfigValue;
                    }
                }
            }
        }

        return config;
    }

    fn groupedAccessorPairsStyleFromConfig(value: std.json.Value) RuleConfigError!GroupedAccessorPairsStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .any_order,
        };
        if (items.len < 2) return .any_order;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "anyOrder")) return .any_order;
        if (std.mem.eql(u8, style, "getBeforeSet")) return .get_before_set;
        if (std.mem.eql(u8, style, "setBeforeGet")) return .set_before_get;
        return error.UnsupportedRuleConfigValue;
    }

    fn idDenylistNamesFromConfig(value: std.json.Value) RuleConfigError!IdDenylistNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };

        var names = IdDenylistNames{};
        if (items.len < 2) return names;

        for (items[1..]) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            names.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return names;
    }

    fn jestAdditionalTestBlockFunctionsFromConfig(value: std.json.Value) RuleConfigError!JestAdditionalTestBlockFunctions {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const configured = config.get("additionalTestBlockFunctions") orelse return .{};
        const functions = switch (configured) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = JestAdditionalTestBlockFunctions{};
        for (functions) |function_value| {
            const function_name = switch (function_value) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!result.append(function_name)) return error.UnsupportedRuleConfigValue;
        }
        return result;
    }

    const JestValidExpectConfig = struct {
        always_await: bool = false,
        async_matchers: JestValidExpectAsyncMatchers = .{},
        min_args: f64 = 1,
        max_args: f64 = 1,
    };

    fn jestValidExpectFromConfig(value: std.json.Value) RuleConfigError!JestValidExpectConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const object = switch (items[1]) {
            .object => |config| config,
            else => return error.UnsupportedRuleConfigValue,
        };
        var result = JestValidExpectConfig{};

        if (object.get("alwaysAwait")) |configured| {
            result.always_await = switch (configured) {
                .bool => |enabled| enabled,
                else => return error.UnsupportedRuleConfigValue,
            };
        }
        if (object.get("asyncMatchers")) |configured| {
            const matchers = switch (configured) {
                .array => |array| array.items,
                else => return error.UnsupportedRuleConfigValue,
            };
            result.async_matchers.custom = true;
            for (matchers) |matcher_value| {
                const matcher = switch (matcher_value) {
                    .string => |name| name,
                    else => return error.UnsupportedRuleConfigValue,
                };
                if (!result.async_matchers.append(matcher)) return error.UnsupportedRuleConfigValue;
            }
        }
        if (object.get("minArgs")) |configured| {
            result.min_args = try jestValidExpectNumberOption(configured, 0);
        }
        if (object.get("maxArgs")) |configured| {
            result.max_args = try jestValidExpectNumberOption(configured, 1);
        }
        return result;
    }

    fn jestValidExpectNumberOption(value: std.json.Value, minimum: f64) RuleConfigError!f64 {
        const number: f64 = switch (value) {
            .integer => |integer| @floatFromInt(integer),
            .float => |float| float,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (!std.math.isFinite(number) or number < minimum) return error.UnsupportedRuleConfigValue;
        return number;
    }

    const JestValidTitleConfig = struct {
        ignore_spaces: bool = false,
        ignore_type_of_describe_name: bool = false,
        ignore_type_of_test_name: bool = false,
        disallowed_words: JestValidTitleDisallowedWords = .{},
        must_not_match: JestValidTitleMatchers = .{},
        must_match: JestValidTitleMatchers = .{},
    };

    fn jestValidTitleFromConfig(value: std.json.Value) RuleConfigError!JestValidTitleConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const object = switch (items[1]) {
            .object => |config| config,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = JestValidTitleConfig{};
        result.ignore_spaces = try optionalBoolObjectValue(object, "ignoreSpaces", false);
        result.ignore_type_of_describe_name = try optionalBoolObjectValue(object, "ignoreTypeOfDescribeName", false);
        result.ignore_type_of_test_name = try optionalBoolObjectValue(object, "ignoreTypeOfTestName", false);

        if (object.get("disallowedWords")) |configured| {
            const words = switch (configured) {
                .array => |array| array.items,
                .null => &.{},
                else => return error.UnsupportedRuleConfigValue,
            };
            for (words) |word_value| {
                const word = switch (word_value) {
                    .string => |text| text,
                    else => return error.UnsupportedRuleConfigValue,
                };
                if (!result.disallowed_words.append(word)) return error.UnsupportedRuleConfigValue;
            }
        }

        if (object.get("mustNotMatch")) |configured| {
            result.must_not_match = try jestValidTitleMatchersFromValue(configured);
        }
        if (object.get("mustMatch")) |configured| {
            result.must_match = try jestValidTitleMatchersFromValue(configured);
        }
        return result;
    }

    fn optionalBoolObjectValue(object: std.json.ObjectMap, key: []const u8, default: bool) RuleConfigError!bool {
        return switch (object.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn jestValidTitleMatchersFromValue(value: std.json.Value) RuleConfigError!JestValidTitleMatchers {
        var result = JestValidTitleMatchers{};
        switch (value) {
            .string, .array => {
                const matcher = try jestValidTitleMatcherFromValue(value);
                result.applyToAll(matcher);
            },
            .object => |object| {
                if (object.get("describe")) |configured| {
                    result.describe = try jestValidTitleMatcherFromValue(configured);
                }
                if (object.get("test")) |configured| {
                    result.test_case = try jestValidTitleMatcherFromValue(configured);
                }
                if (object.get("it")) |configured| {
                    result.it = try jestValidTitleMatcherFromValue(configured);
                }
            },
            else => return error.UnsupportedRuleConfigValue,
        }
        return result;
    }

    fn jestValidTitleMatcherFromValue(value: std.json.Value) RuleConfigError!JestValidTitleMatcher {
        var matcher = JestValidTitleMatcher{};
        switch (value) {
            .string => |pattern| {
                if (!matcher.set(pattern, null)) return error.UnsupportedRuleConfigValue;
            },
            .array => |array| {
                if (array.items.len < 1 or array.items.len > 2) return error.UnsupportedRuleConfigValue;
                const pattern = switch (array.items[0]) {
                    .string => |text| text,
                    else => return error.UnsupportedRuleConfigValue,
                };
                const message = if (array.items.len == 2) switch (array.items[1]) {
                    .string => |text| text,
                    else => return error.UnsupportedRuleConfigValue,
                } else null;
                if (!matcher.set(pattern, message)) return error.UnsupportedRuleConfigValue;
            },
            else => return error.UnsupportedRuleConfigValue,
        }
        return matcher;
    }

    const IdLengthConfig = struct {
        min: usize = 2,
        has_max: bool = false,
        max: usize = 0,
        properties: IdLengthProperties = .always,
        exceptions: IdLengthExceptions = .{},
        exception_patterns: IdLengthExceptionPatterns = .{},
    };

    fn idLengthFromConfig(value: std.json.Value) RuleConfigError!IdLengthConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = IdLengthConfig{};
        if (config.get("min")) |min_value| {
            result.min = try jsonNonNegativeIntegerToUsize(min_value);
        }
        if (config.get("max")) |max_value| {
            result.max = try jsonNonNegativeIntegerToUsize(max_value);
            result.has_max = true;
        }
        if (config.get("properties")) |properties_value| {
            const properties = switch (properties_value) {
                .string => |properties| properties,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, properties, "always")) {
                result.properties = .always;
            } else if (std.mem.eql(u8, properties, "never")) {
                result.properties = .never;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }
        if (config.get("exceptions")) |exceptions_value| {
            result.exceptions = try idLengthExceptionsFromValue(exceptions_value);
        }
        if (config.get("exceptionPatterns")) |patterns_value| {
            result.exception_patterns = try idLengthExceptionPatternsFromValue(patterns_value);
        }
        return result;
    }

    fn idLengthExceptionsFromValue(value: std.json.Value) RuleConfigError!IdLengthExceptions {
        const items = switch (value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var exceptions = IdLengthExceptions{};
        for (items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            exceptions.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return exceptions;
    }

    fn idLengthExceptionPatternsFromValue(value: std.json.Value) RuleConfigError!IdLengthExceptionPatterns {
        const items = switch (value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var patterns = IdLengthExceptionPatterns{};
        for (items) |item| {
            const pattern = switch (item) {
                .string => |pattern| pattern,
                else => return error.UnsupportedRuleConfigValue,
            };
            patterns.append(pattern) catch return error.UnsupportedRuleConfigValue;
        }
        return patterns;
    }

    const IdMatchConfig = struct {
        pattern: IdMatchPattern = .{},
        properties: bool = false,
        class_fields: bool = false,
        only_declarations: bool = false,
        ignore_destructuring: bool = false,
    };

    fn idMatchFromConfig(value: std.json.Value) RuleConfigError!IdMatchConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const pattern_value = switch (items[1]) {
            .string => |pattern| pattern,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = IdMatchConfig{};
        result.pattern.set(pattern_value) catch return error.UnsupportedRuleConfigValue;
        if (items.len < 3) return result;

        const config = switch (items[2]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        result.properties = try boolObjectOption(config, "properties", false);
        result.class_fields = try boolObjectOption(config, "classFields", false);
        result.only_declarations = try boolObjectOption(config, "onlyDeclarations", false);
        result.ignore_destructuring = try boolObjectOption(config, "ignoreDestructuring", false);
        return result;
    }

    fn jsonNonNegativeIntegerToUsize(value: std.json.Value) RuleConfigError!usize {
        const integer = switch (value) {
            .integer => |integer| integer,
            else => return error.UnsupportedRuleConfigValue,
        };
        return nonNegativeIntegerToUsize(integer);
    }

    fn noRestrictedExportNamesFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedExportNames {
        const config = noRestrictedExportsObjectFromConfig(value) orelse return .{};
        const entries = switch (config.get("restrictedNamedExports") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var names = NoRestrictedExportNames{};
        for (entries) |entry| {
            const name = switch (entry) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            names.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return names;
    }

    fn noRestrictedExportsDefaultOptionsFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedExportsDefaultOptions {
        const config = noRestrictedExportsObjectFromConfig(value) orelse return .{};
        const default_config = switch (config.get("restrictDefaultExports") orelse return .{}) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };

        return .{
            .direct = try boolObjectOption(default_config, "direct", false),
            .named = try boolObjectOption(default_config, "named", false),
            .default_from = try boolObjectOption(default_config, "defaultFrom", false),
            .named_from = try boolObjectOption(default_config, "namedFrom", false),
            .namespace_from = try boolObjectOption(default_config, "namespaceFrom", false),
        };
    }

    fn noRestrictedExportsObjectFromConfig(value: std.json.Value) ?std.json.ObjectMap {
        const items = switch (value) {
            .array => |array| array.items,
            else => return null,
        };
        if (items.len < 2) return null;

        return switch (items[1]) {
            .object => |object| object,
            else => null,
        };
    }

    fn noRestrictedImportsFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedImports {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };

        var result = NoRestrictedImports{};
        if (items.len < 2) return result;

        for (items[1..]) |item| {
            switch (item) {
                .string => |source| {
                    if (!result.appendPath(source)) return error.UnsupportedRuleConfigValue;
                },
                .object => |object| {
                    if (object.get("paths") != null or object.get("patterns") != null) {
                        if (object.get("paths")) |paths_value| {
                            try appendNoRestrictedImportConfigItems(&result, paths_value, .path);
                        }
                        if (object.get("patterns")) |patterns_value| {
                            try appendNoRestrictedImportPatternItems(&result, patterns_value);
                        }
                    } else {
                        try appendNoRestrictedImportObject(&result, object, .path);
                    }
                },
                else => return error.UnsupportedRuleConfigValue,
            }
        }

        return result;
    }

    fn noRestrictedModulesFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedModules {
        return try noRestrictedImportsFromConfig(value);
    }

    fn appendNoRestrictedImportConfigItems(
        result: *NoRestrictedImports,
        value: std.json.Value,
        kind: NoRestrictedImportKind,
    ) RuleConfigError!void {
        const items = switch (value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        for (items) |item| {
            switch (item) {
                .string => |source| {
                    var entry = NoRestrictedImportEntry{ .kind = kind };
                    if (!entry.setSource(source)) return error.UnsupportedRuleConfigValue;
                    if (!result.append(entry)) return error.UnsupportedRuleConfigValue;
                },
                .object => |object| try appendNoRestrictedImportObject(result, object, kind),
                else => return error.UnsupportedRuleConfigValue,
            }
        }
    }

    fn appendNoRestrictedImportPatternItems(result: *NoRestrictedImports, value: std.json.Value) RuleConfigError!void {
        switch (value) {
            .array => try appendNoRestrictedImportConfigItems(result, value, .pattern),
            .object => |object| try appendNoRestrictedImportPatternObject(result, object),
            else => return error.UnsupportedRuleConfigValue,
        }
    }

    fn appendNoRestrictedImportPatternObject(result: *NoRestrictedImports, object: std.json.ObjectMap) RuleConfigError!void {
        if (object.get("group")) |group_value| {
            const groups = switch (group_value) {
                .array => |array| array.items,
                else => return error.UnsupportedRuleConfigValue,
            };
            for (groups) |group_item| {
                const source = switch (group_item) {
                    .string => |source| source,
                    else => return error.UnsupportedRuleConfigValue,
                };
                var entry = try noRestrictedImportEntryFromObject(object, .pattern);
                if (!entry.setSource(source)) return error.UnsupportedRuleConfigValue;
                if (!result.append(entry)) return error.UnsupportedRuleConfigValue;
            }
            return;
        }

        try appendNoRestrictedImportObject(result, object, .pattern);
    }

    fn appendNoRestrictedImportObject(
        result: *NoRestrictedImports,
        object: std.json.ObjectMap,
        kind: NoRestrictedImportKind,
    ) RuleConfigError!void {
        var entry = try noRestrictedImportEntryFromObject(object, kind);
        if (entry.source_length == 0) {
            const source = switch (object.get("name") orelse return error.UnsupportedRuleConfigValue) {
                .string => |source| source,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!entry.setSource(source)) return error.UnsupportedRuleConfigValue;
        }
        if (!result.append(entry)) return error.UnsupportedRuleConfigValue;
    }

    fn noRestrictedImportEntryFromObject(
        object: std.json.ObjectMap,
        kind: NoRestrictedImportKind,
    ) RuleConfigError!NoRestrictedImportEntry {
        var entry = NoRestrictedImportEntry{ .kind = kind };

        if (object.get("name")) |name_value| {
            const source = switch (name_value) {
                .string => |source| source,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!entry.setSource(source)) return error.UnsupportedRuleConfigValue;
        }
        if (object.get("message")) |message_value| {
            const message = switch (message_value) {
                .string => |message| message,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!entry.setMessage(message)) return error.UnsupportedRuleConfigValue;
        }
        if (object.get("importNames")) |names_value| {
            try appendNoRestrictedImportNames(&entry.import_names, names_value);
        }
        if (object.get("allowImportNames")) |names_value| {
            try appendNoRestrictedImportNames(&entry.allow_import_names, names_value);
        }
        if (object.get("allowTypeImports")) |allow_type_imports_value| {
            entry.allow_type_imports = switch (allow_type_imports_value) {
                .bool => |enabled| enabled,
                else => return error.UnsupportedRuleConfigValue,
            };
        }

        return entry;
    }

    fn appendNoRestrictedImportNames(
        names: *NoRestrictedImportNameList,
        value: std.json.Value,
    ) RuleConfigError!void {
        const items = switch (value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        for (items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!names.append(name)) return error.UnsupportedRuleConfigValue;
        }
    }

    fn boolObjectOption(object: std.json.ObjectMap, key: []const u8, default: bool) RuleConfigError!bool {
        return switch (object.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn boolRuleObjectOption(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;
        const object = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return boolObjectOption(object, key, default);
    }

    fn noMagicNumbersIgnoreFromConfig(value: std.json.Value) RuleConfigError!NoMagicNumbersIgnoreValues {
        var result: NoMagicNumbersIgnoreValues = .{};
        const items = switch (value) {
            .array => |array| array.items,
            else => return result,
        };
        if (items.len < 2) return result;
        const object = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ignore_value = object.get("ignore") orelse return result;
        const ignored = switch (ignore_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        for (ignored) |item| {
            const appended = switch (item) {
                .integer => |number| result.appendNumber(@floatFromInt(number)),
                .float => |number| result.appendNumber(number),
                .number_string => |raw| result.appendNumber(std.fmt.parseFloat(f64, raw) catch return error.UnsupportedRuleConfigValue),
                .string => |bigint| result.appendBigInt(bigint),
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!appended) return error.UnsupportedRuleConfigValue;
        }
        return result;
    }

    fn reactNoUnusedPropTypesSkipShapePropsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("skipShapeProps") orelse return true) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn reactPropTypesSkipUndeclaredFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("skipUndeclared") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn reactPropTypesIgnoreFromConfig(value: std.json.Value) RuleConfigError!ReactPropTypesIgnoreNames {
        return reactPropTypesNamesFromConfig(value, "ignore");
    }

    fn reactPropTypesCustomValidatorsFromConfig(value: std.json.Value) RuleConfigError!ReactPropTypesIgnoreNames {
        return reactPropTypesNamesFromConfig(value, "customValidators");
    }

    fn reactPropTypesNamesFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!ReactPropTypesIgnoreNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const name_items = switch (config.get(key) orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var names = ReactPropTypesIgnoreNames{};
        for (name_items) |item| {
            const name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            names.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return names;
    }

    fn jsxA11yNamesFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!JsxA11yImgRedundantAltNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const name_items = switch (config.get(key) orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var names = JsxA11yImgRedundantAltNames{};
        for (name_items) |item| {
            const name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            names.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return names;
    }

    fn jsxA11yBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    const JsxA11yAltTextElementsConfig = struct {
        img: bool = true,
        object: bool = true,
        area: bool = true,
        input_image: bool = true,
    };

    fn jsxA11yAltTextElementsFromConfig(value: std.json.Value) RuleConfigError!JsxA11yAltTextElementsConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const element_items = switch (config.get("elements") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = JsxA11yAltTextElementsConfig{
            .img = false,
            .object = false,
            .area = false,
            .input_image = false,
        };
        for (element_items) |item| {
            const element = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, element, "img")) {
                result.img = true;
            } else if (std.mem.eql(u8, element, "object")) {
                result.object = true;
            } else if (std.mem.eql(u8, element, "area")) {
                result.area = true;
            } else if (std.mem.eql(u8, element, "input[type=\"image\"]")) {
                result.input_image = true;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }
        return result;
    }

    const JsxA11yNoDistractingElementsConfig = struct {
        marquee: bool = true,
        blink: bool = true,
    };

    fn jsxA11yNoDistractingElementsFromConfig(value: std.json.Value) RuleConfigError!JsxA11yNoDistractingElementsConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const element_items = switch (config.get("elements") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = JsxA11yNoDistractingElementsConfig{
            .marquee = false,
            .blink = false,
        };
        for (element_items) |item| {
            const element = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, element, "marquee")) {
                result.marquee = true;
            } else if (std.mem.eql(u8, element, "blink")) {
                result.blink = true;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }
        return result;
    }

    fn reactJsxNoTargetBlankAllowReferrerFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowReferrer") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn reactJsxNoTargetBlankEnforceDynamicLinksFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const mode = switch (config.get("enforceDynamicLinks") orelse return true) {
            .string => |mode| mode,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, mode, "always")) return true;
        if (std.mem.eql(u8, mode, "never")) return false;
        return error.UnsupportedRuleConfigValue;
    }

    fn reactJsxNoTargetBlankWarnOnSpreadAttributesFromConfig(value: std.json.Value) RuleConfigError!bool {
        return reactJsxNoTargetBlankBoolOptionFromConfig(value, "warnOnSpreadAttributes", false);
    }

    fn reactJsxNoTargetBlankBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    const ReactNoUnescapedEntitiesForbid = struct {
        gt: bool = true,
        double_quote: bool = true,
        single_quote: bool = true,
        closing_brace: bool = true,
    };

    fn reactNoUnescapedEntitiesForbidFromConfig(value: std.json.Value) RuleConfigError!ReactNoUnescapedEntitiesForbid {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const forbid = switch (config.get("forbid") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = ReactNoUnescapedEntitiesForbid{
            .gt = false,
            .double_quote = false,
            .single_quote = false,
            .closing_brace = false,
        };
        for (forbid) |entry| {
            const char = switch (entry) {
                .string => |string| string,
                .object => |object| switch (object.get("char") orelse return error.UnsupportedRuleConfigValue) {
                    .string => |string| string,
                    else => return error.UnsupportedRuleConfigValue,
                },
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, char, ">")) {
                result.gt = true;
            } else if (std.mem.eql(u8, char, "\"")) {
                result.double_quote = true;
            } else if (std.mem.eql(u8, char, "'")) {
                result.single_quote = true;
            } else if (std.mem.eql(u8, char, "}")) {
                result.closing_brace = true;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }
        return result;
    }

    fn reactNoChildrenPropAllowFunctionsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowFunctions") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintBanTypesConfigFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintBanTypesConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config_object = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };

        var config = TypescriptEslintBanTypesConfig{};
        config.extend_defaults = if (config_object.get("extendDefaults")) |extend_defaults| switch (extend_defaults) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        } else true;

        const types_value = config_object.get("types") orelse return config;
        const types = switch (types_value) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };

        var iter = types.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            switch (entry.value_ptr.*) {
                .bool => |enabled| {
                    if (enabled) {
                        try appendBanTypeConfig(&config.custom, name, defaultBanTypeMessage(name));
                    } else {
                        try appendDisabledBanType(&config.disabled, name);
                    }
                },
                .string => |message| try appendBanTypeConfig(&config.custom, name, message),
                .object => |object| {
                    const message = if (object.get("message")) |message_value| switch (message_value) {
                        .string => |message| message,
                        else => return error.UnsupportedRuleConfigValue,
                    } else defaultBanTypeMessage(name);
                    try appendBanTypeConfig(&config.custom, name, message);
                },
                else => return error.UnsupportedRuleConfigValue,
            }
        }

        return config;
    }

    fn appendDisabledBanType(
        disabled: *TypescriptEslintBanTypeNames,
        name: []const u8,
    ) RuleConfigError!void {
        disabled.append(name) catch return error.UnsupportedRuleConfigValue;
    }

    fn appendBanTypeConfig(
        entries: *TypescriptEslintBanTypeEntries,
        name: []const u8,
        message: []const u8,
    ) RuleConfigError!void {
        entries.append(name, message) catch return error.UnsupportedRuleConfigValue;
    }

    fn defaultBanTypeMessage(name: []const u8) []const u8 {
        if (std.mem.eql(u8, name, "String")) return "Use string instead";
        if (std.mem.eql(u8, name, "Boolean")) return "Use boolean instead";
        if (std.mem.eql(u8, name, "Number")) return "Use number instead";
        if (std.mem.eql(u8, name, "Symbol")) return "Use symbol instead";
        if (std.mem.eql(u8, name, "BigInt")) return "Use bigint instead";
        if (std.mem.eql(u8, name, "Function")) return "The `Function` type accepts any function-like value.";
        if (std.mem.eql(u8, name, "Object")) return "Use object instead";
        if (std.mem.eql(u8, name, "object")) return "Use a more specific object type instead";
        if (std.mem.eql(u8, name, "{}")) return "Use a more specific object type instead";
        return "This type is banned.";
    }

    fn typescriptEslintConsistentTypeAssertionsStyleFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintConsistentTypeAssertionsStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .as,
        };
        if (items.len < 2) return .as;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const style = switch (config.get("assertionStyle") orelse return .as) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "as")) return .as;
        if (std.mem.eql(u8, style, "angle-bracket")) return .angle_bracket;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintLiteralTypeAssertionsFromConfig(
        value: std.json.Value,
        key: []const u8,
        default: TypescriptEslintLiteralTypeAssertions,
    ) RuleConfigError!TypescriptEslintLiteralTypeAssertions {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const style = switch (config.get(key) orelse return default) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "allow")) return .allow;
        if (std.mem.eql(u8, style, "allow-as-parameter")) return .allow_as_parameter;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintExplicitMemberAccessibilityFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintExplicitMemberAccessibility {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no_public,
        };
        if (items.len < 2) return .no_public;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const accessibility = switch (config.get("accessibility") orelse return .no_public) {
            .string => |accessibility| accessibility,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, accessibility, "explicit")) return .explicit;
        if (std.mem.eql(u8, accessibility, "no-public")) return .no_public;
        if (std.mem.eql(u8, accessibility, "off")) return .off;
        return error.UnsupportedRuleConfigValue;
    }

    fn logicalAssignmentOperatorsStyleFromConfig(value: std.json.Value) RuleConfigError!LogicalAssignmentOperatorsStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            .object => return .always,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn logicalAssignmentOperatorsEnforceForIfStatementsFromConfig(value: std.json.Value) RuleConfigError!LogicalAssignmentOperatorsEnforceForIfStatements {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config_value = switch (items[1]) {
            .object => items[1],
            .string => if (items.len >= 3) items[2] else return .no,
            else => return error.UnsupportedRuleConfigValue,
        };
        const config = switch (config_value) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const enforce = switch (config.get("enforceForIfStatements") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (enforce) .yes else .no;
    }

    fn maxParamsMaxFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 3,
        };
        if (items.len < 2) return 3;

        switch (items[1]) {
            .integer => |max| return nonNegativeIntegerToUsize(max),
            .object => |object| {
                if (object.get("max")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                if (object.get("maximum")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                return 3;
            },
            else => return error.UnsupportedRuleConfigValue,
        }
    }

    fn maxDepthMaxFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 4,
        };
        if (items.len < 2) return 4;

        switch (items[1]) {
            .integer => |max| return nonNegativeIntegerToUsize(max),
            .object => |object| {
                if (object.get("max")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                if (object.get("maximum")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                return 4;
            },
            else => return error.UnsupportedRuleConfigValue,
        }
    }

    fn maxLinesMaxFromConfig(value: std.json.Value, default: usize) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        switch (items[1]) {
            .integer => |max| return nonNegativeIntegerToUsize(max),
            .object => |object| {
                if (object.get("max")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                return default;
            },
            else => return error.UnsupportedRuleConfigValue,
        }
    }

    fn maxLinesBoolOptionFromConfig(value: std.json.Value, option_name: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const object = switch (items[1]) {
            .object => |object| object,
            else => return false,
        };
        return switch (object.get(option_name) orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn maxClassesPerFileMaxFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 1,
        };
        if (items.len < 2) return 1;

        const max = switch (items[1]) {
            .integer => |max| max,
            .object => |object| switch (object.get("max") orelse return 1) {
                .integer => |max| max,
                else => return error.UnsupportedRuleConfigValue,
            },
            else => return error.UnsupportedRuleConfigValue,
        };

        if (max < 1) return error.UnsupportedRuleConfigValue;
        return @intCast(max);
    }

    fn maxClassesPerFileIgnoreExpressionsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        return switch (items[1]) {
            .object => |object| switch (object.get("ignoreExpressions") orelse return false) {
                .bool => |enabled| enabled,
                else => return error.UnsupportedRuleConfigValue,
            },
            .integer => false,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn maxNestedCallbacksMaxFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 10,
        };
        if (items.len < 2) return 10;

        switch (items[1]) {
            .integer => |max| return nonNegativeIntegerToUsize(max),
            .object => |object| {
                if (object.get("maximum")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                if (object.get("max")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                return 10;
            },
            else => return error.UnsupportedRuleConfigValue,
        }
    }

    fn nonNegativeIntegerToUsize(value: i64) RuleConfigError!usize {
        if (value < 0) return error.UnsupportedRuleConfigValue;
        return @intCast(value);
    }

    fn maxParamsCountThisFromConfig(value: std.json.Value) RuleConfigError!MaxParamsCountThis {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .except_void,
        };
        if (items.len < 2) return .except_void;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return .except_void,
        };
        if (config.get("countThis")) |count_this_value| {
            const count_this = switch (count_this_value) {
                .string => |count_this| count_this,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, count_this, "always")) return .always;
            if (std.mem.eql(u8, count_this, "never")) return .never;
            if (std.mem.eql(u8, count_this, "except-void")) return .except_void;
            return error.UnsupportedRuleConfigValue;
        }
        if (config.get("countVoidThis")) |count_void_this_value| {
            const count_void_this = switch (count_void_this_value) {
                .bool => |enabled| enabled,
                else => return error.UnsupportedRuleConfigValue,
            };
            return if (count_void_this) .always else .except_void;
        }
        return .except_void;
    }

    fn maxStatementsMaxFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 10,
        };
        if (items.len < 2) return 10;

        switch (items[1]) {
            .integer => |max| return nonNegativeIntegerToUsize(max),
            .object => |object| {
                if (object.get("maximum")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                if (object.get("max")) |max_value| {
                    const max = switch (max_value) {
                        .integer => |max| max,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    return nonNegativeIntegerToUsize(max);
                }
                return 10;
            },
            else => return error.UnsupportedRuleConfigValue,
        }
    }

    fn maxStatementsIgnoreTopLevelFunctionsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 3) return false;

        return switch (items[2]) {
            .object => |object| switch (object.get("ignoreTopLevelFunctions") orelse return false) {
                .bool => |enabled| enabled,
                else => error.UnsupportedRuleConfigValue,
            },
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn newCapBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn newCapExceptionNamesFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!NewCapExceptionNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const exception_value = config.get(key) orelse return .{};
        const exception_items = switch (exception_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var exceptions = NewCapExceptionNames{};
        for (exception_items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            exceptions.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return exceptions;
    }

    fn newCapExceptionPatternFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!NewCapExceptionPattern {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const pattern_value = switch (config.get(key) orelse return .{}) {
            .string => |pattern_value| pattern_value,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (pattern_value.len == 0) return .{};

        var pattern = NewCapExceptionPattern{};
        pattern.set(pattern_value) catch return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn defaultCaseCommentPatternFromConfig(value: std.json.Value) RuleConfigError!DefaultCaseCommentPattern {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const pattern_value = switch (config.get("commentPattern") orelse return .{}) {
            .string => |pattern_value| pattern_value,
            else => return error.UnsupportedRuleConfigValue,
        };

        var pattern = DefaultCaseCommentPattern{};
        pattern.set(pattern_value) catch return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn noBitwiseAllowFromConfig(value: std.json.Value, expected: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow_value = config.get("allow") orelse return false;
        const allow_items = switch (allow_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        for (allow_items) |item| {
            const operator = switch (item) {
                .string => |operator| operator,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!isNoBitwiseOperatorToken(operator)) return error.UnsupportedRuleConfigValue;
            if (std.mem.eql(u8, operator, expected)) return true;
        }

        return false;
    }

    fn noBitwiseInt32HintFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("int32Hint") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noUselessEscapeAllowRegexCharactersFromConfig(value: std.json.Value) RuleConfigError!NoUselessEscapeAllowRegexCharacters {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow_value = config.get("allowRegexCharacters") orelse return .{};
        const allow_items = switch (allow_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var allow = NoUselessEscapeAllowRegexCharacters{};
        for (allow_items) |item| {
            const character = switch (item) {
                .string => |character| character,
                else => return error.UnsupportedRuleConfigValue,
            };
            allow.append(character) catch return error.UnsupportedRuleConfigValue;
        }
        return allow;
    }

    fn noInvalidRegexpAllowConstructorFlagsFromConfig(value: std.json.Value) RuleConfigError!NoInvalidRegexpAllowConstructorFlags {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow_value = config.get("allowConstructorFlags") orelse return .{};
        const allow_items = switch (allow_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var allow: NoInvalidRegexpAllowConstructorFlags = .{};
        for (allow_items) |item| {
            const flag = switch (item) {
                .string => |flag| flag,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!allow.enable(flag)) return error.UnsupportedRuleConfigValue;
        }
        return allow;
    }

    fn isNoBitwiseOperatorToken(operator: []const u8) bool {
        inline for (.{ "&", "|", "^", "~", "<<", ">>", ">>>" }) |allowed| {
            if (std.mem.eql(u8, operator, allowed)) return true;
        }
        return false;
    }

    fn noConsoleAllowFromConfig(value: std.json.Value) RuleConfigError!NoConsoleAllow {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow_value = config.get("allow") orelse return .{};
        const allow_items = switch (allow_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var allow: NoConsoleAllow = .{};
        for (allow_items) |item| {
            const method = switch (item) {
                .string => |method| method,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!allow.enable(method)) return error.UnsupportedRuleConfigValue;
        }
        return allow;
    }

    fn noCondAssignStyleFromConfig(value: std.json.Value) RuleConfigError!NoCondAssignStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .except_parens,
        };
        if (items.len < 2) return .except_parens;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "except-parens")) return .except_parens;
        if (std.mem.eql(u8, style, "always")) return .always;
        return error.UnsupportedRuleConfigValue;
    }

    fn noConstantConditionCheckLoopsFromConfig(value: std.json.Value) RuleConfigError!NoConstantConditionCheckLoops {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .all_except_while_true,
        };
        if (items.len < 2) return .all_except_while_true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const check_loops = config.get("checkLoops") orelse return .all_except_while_true;
        return switch (check_loops) {
            .bool => |enabled| if (enabled) .all else .none,
            .string => |style| {
                if (std.mem.eql(u8, style, "all")) return .all;
                if (std.mem.eql(u8, style, "allExceptWhileTrue")) return .all_except_while_true;
                if (std.mem.eql(u8, style, "none")) return .none;
                return error.UnsupportedRuleConfigValue;
            },
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noConfusingArrowAllowParensFromConfig(value: std.json.Value) RuleConfigError!NoConfusingArrowAllowParens {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .yes,
        };
        if (items.len < 2) return .yes;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowParens") orelse return .yes) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn noEmptyAllowEmptyCatchFromConfig(value: std.json.Value) RuleConfigError!NoEmptyAllowEmptyCatch {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowEmptyCatch") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn noEmptyFunctionAllowFromConfig(value: std.json.Value) RuleConfigError!NoEmptyFunctionAllow {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow_value = config.get("allow") orelse return .{};
        const allow_items = switch (allow_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var allow: NoEmptyFunctionAllow = .{};
        for (allow_items) |item| {
            const kind = switch (item) {
                .string => |kind| kind,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!allow.enable(kind)) return error.UnsupportedRuleConfigValue;
        }
        return allow;
    }

    fn noElseReturnAllowElseIfFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowElseIf") orelse return true) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noEmptyPatternAllowObjectPatternsAsParametersFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowObjectPatternsAsParameters") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noExtraBooleanCastEnforceForInnerExpressionsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const option = config.get("enforceForInnerExpressions") orelse config.get("enforceForLogicalOperands") orelse return false;
        return switch (option) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noFallthroughAllowEmptyCaseFromConfig(value: std.json.Value) RuleConfigError!NoFallthroughAllowEmptyCase {
        const allow = try noFallthroughBoolOptionFromConfig(value, "allowEmptyCase", false);
        return if (allow) .yes else .no;
    }

    fn noFallthroughReportUnusedFallthroughCommentFromConfig(value: std.json.Value) RuleConfigError!bool {
        return noFallthroughBoolOptionFromConfig(value, "reportUnusedFallthroughComment", false);
    }

    fn noImplicitGlobalsLexicalBindingsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return try boolObjectOption(config, "lexicalBindings", false);
    }

    fn noFallthroughCommentPatternFromConfig(value: std.json.Value) RuleConfigError!NoFallthroughCommentPattern {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const pattern_value = switch (config.get("commentPattern") orelse return .{}) {
            .string => |pattern_value| pattern_value,
            else => return error.UnsupportedRuleConfigValue,
        };

        var pattern = NoFallthroughCommentPattern{};
        pattern.set(pattern_value) catch return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn noFallthroughBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn importNoCycleMaxDepthFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 1024,
        };
        if (items.len < 2) return 1024;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const max_depth = switch (config.get("maxDepth") orelse return 1024) {
            .integer => |max_depth| max_depth,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (max_depth < 1) return error.UnsupportedRuleConfigValue;
        return @intCast(max_depth);
    }

    fn importNoCycleBoolOptionFromConfig(value: std.json.Value, name: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(name) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn importNoDuplicatesBoolOptionFromConfig(value: std.json.Value, name: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(name) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn importNewlineAfterImportCountFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 1,
        };
        if (items.len < 2) return 1;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const count = switch (config.get("count") orelse return 1) {
            .integer => |count| count,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (count < 0) return error.UnsupportedRuleConfigValue;
        return @intCast(count);
    }

    fn importNewlineAfterImportExactCountFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("exactCount") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn importNewlineAfterImportConsiderCommentsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("considerComments") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noImplicitCoercionBooleanFromConfig(value: std.json.Value) RuleConfigError!NoImplicitCoercionBoolean {
        const enabled = try noImplicitCoercionOptionFromConfig(value, "boolean");
        return if (enabled) .yes else .no;
    }

    fn noImplicitCoercionNumberFromConfig(value: std.json.Value) RuleConfigError!NoImplicitCoercionNumber {
        const enabled = try noImplicitCoercionOptionFromConfig(value, "number");
        return if (enabled) .yes else .no;
    }

    fn noImplicitCoercionStringFromConfig(value: std.json.Value) RuleConfigError!NoImplicitCoercionString {
        const enabled = try noImplicitCoercionOptionFromConfig(value, "string");
        return if (enabled) .yes else .no;
    }

    fn noImplicitCoercionDisallowTemplateShorthandFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("disallowTemplateShorthand") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noImplicitCoercionOptionFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return true) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noImplicitCoercionAllowFromConfig(value: std.json.Value, expected: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow_value = config.get("allow") orelse return false;
        const allow_items = switch (allow_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var found = false;
        for (allow_items) |item| {
            const allow = switch (item) {
                .string => |allow| allow,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!isNoImplicitCoercionAllowToken(allow)) return error.UnsupportedRuleConfigValue;
            if (std.mem.eql(u8, allow, expected)) found = true;
        }
        return found;
    }

    fn isNoImplicitCoercionAllowToken(value: []const u8) bool {
        return std.mem.eql(u8, value, "!!") or
            std.mem.eql(u8, value, "~") or
            std.mem.eql(u8, value, "+") or
            std.mem.eql(u8, value, "*") or
            std.mem.eql(u8, value, "-") or
            std.mem.eql(u8, value, "- -");
    }

    fn noInnerDeclarationsModeFromConfig(value: std.json.Value) RuleConfigError!NoInnerDeclarationsMode {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .functions,
        };
        if (items.len < 2) return .functions;

        const mode = switch (items[1]) {
            .string => |mode| mode,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, mode, "functions")) return .functions;
        if (std.mem.eql(u8, mode, "both")) return .both;
        return error.UnsupportedRuleConfigValue;
    }

    fn noLabelsAllowLoopFromConfig(value: std.json.Value) RuleConfigError!NoLabelsAllowLoop {
        const enabled = try noLabelsBoolOptionFromConfig(value, "allowLoop", false);
        return if (enabled) .yes else .no;
    }

    fn noLabelsAllowSwitchFromConfig(value: std.json.Value) RuleConfigError!NoLabelsAllowSwitch {
        const enabled = try noLabelsBoolOptionFromConfig(value, "allowSwitch", false);
        return if (enabled) .yes else .no;
    }

    fn noLabelsBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noDuplicateImportsBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noMixedSpacesAndTabsSmartTabsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "smart-tabs")) return true;
        return error.UnsupportedRuleConfigValue;
    }

    fn noMultiSpacesIgnoreEOLCommentsFromConfig(value: std.json.Value) RuleConfigError!NoMultiSpacesIgnoreEOLComments {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ignore = switch (config.get("ignoreEOLComments") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (ignore) .yes else .no;
    }

    fn noMultiSpacesExceptionsFromConfig(value: std.json.Value) RuleConfigError!NoMultiSpacesExceptions {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const exceptions = switch (config.get("exceptions") orelse return .{}) {
            .object => |exceptions| exceptions,
            else => return error.UnsupportedRuleConfigValue,
        };

        var options = NoMultiSpacesExceptions{};
        if (exceptions.get("Property")) |entry| options.property = try noMultiSpacesExceptionEnabled(entry);
        if (exceptions.get("BinaryExpression")) |entry| options.binary_expression = try noMultiSpacesExceptionEnabled(entry);
        if (exceptions.get("VariableDeclarator")) |entry| options.variable_declarator = try noMultiSpacesExceptionEnabled(entry);
        if (exceptions.get("ImportDeclaration")) |entry| options.import_declaration = try noMultiSpacesExceptionEnabled(entry);
        return options;
    }

    fn noMultiSpacesExceptionEnabled(value: std.json.Value) RuleConfigError!bool {
        return switch (value) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noMultipleEmptyLinesMaxFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 2,
        };
        if (items.len < 2) return 2;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const max = switch (config.get("max") orelse return 2) {
            .integer => |max| max,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (max < 0) return error.UnsupportedRuleConfigValue;
        return @intCast(max);
    }

    fn noMultipleEmptyLinesMaxBofFromConfig(value: std.json.Value) RuleConfigError!?usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return null,
        };
        if (items.len < 2) return null;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const max = switch (config.get("maxBOF") orelse return null) {
            .integer => |max| max,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (max < 0) return error.UnsupportedRuleConfigValue;
        return @intCast(max);
    }

    fn noMultipleEmptyLinesMaxEofFromConfig(value: std.json.Value) RuleConfigError!?usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return null,
        };
        if (items.len < 2) return null;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const max = switch (config.get("maxEOF") orelse return null) {
            .integer => |max| max,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (max < 0) return error.UnsupportedRuleConfigValue;
        return @intCast(max);
    }

    fn noParamReassignPropsFromConfig(value: std.json.Value) RuleConfigError!NoParamReassignProps {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const props = switch (config.get("props") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (props) .yes else .no;
    }

    fn noParamReassignIgnoredNamesFromConfig(value: std.json.Value) RuleConfigError!NoParamReassignIgnoredNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ignored_value = config.get("ignorePropertyModificationsFor") orelse return .{};
        const ignored_items = switch (ignored_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var ignored = NoParamReassignIgnoredNames{};
        for (ignored_items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            ignored.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return ignored;
    }

    fn noParamReassignIgnoredNamePatternsFromConfig(value: std.json.Value) RuleConfigError!NoParamReassignIgnoredNamePatterns {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ignored_value = config.get("ignorePropertyModificationsForRegex") orelse return .{};
        const ignored_items = switch (ignored_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var ignored = NoParamReassignIgnoredNamePatterns{};
        for (ignored_items) |item| {
            const pattern = switch (item) {
                .string => |pattern| pattern,
                else => return error.UnsupportedRuleConfigValue,
            };
            ignored.append(pattern) catch return error.UnsupportedRuleConfigValue;
        }
        return ignored;
    }

    fn noShadowAllowFromConfig(value: std.json.Value) RuleConfigError!NoShadowAllowNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow_value = config.get("allow") orelse return .{};
        const allow_items = switch (allow_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var allow = NoShadowAllowNames{};
        for (allow_items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            allow.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return allow;
    }

    fn noShadowBuiltinGlobalsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("builtinGlobals") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noShadowHoistFromConfig(value: std.json.Value, default: NoShadowHoist) RuleConfigError!NoShadowHoist {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const hoist = switch (config.get("hoist") orelse return default) {
            .string => |hoist| hoist,
            else => return error.UnsupportedRuleConfigValue,
        };

        if (std.mem.eql(u8, hoist, "all")) return .all;
        if (std.mem.eql(u8, hoist, "functions")) return .functions;
        if (std.mem.eql(u8, hoist, "functions-and-types")) return .functions_and_types;
        if (std.mem.eql(u8, hoist, "never")) return .never;
        if (std.mem.eql(u8, hoist, "types")) return .types;
        return error.UnsupportedRuleConfigValue;
    }

    fn noShadowBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noUnderscoreDangleBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noUnderscoreDangleAllowFromConfig(value: std.json.Value) RuleConfigError!NoShadowAllowNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow_value = config.get("allow") orelse return .{};
        const allow_items = switch (allow_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var allow = NoShadowAllowNames{};
        for (allow_items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            allow.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return allow;
    }

    fn noPlusplusAllowForLoopAfterthoughtsFromConfig(value: std.json.Value) RuleConfigError!NoPlusplusAllowForLoopAfterthoughts {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowForLoopAfterthoughts") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn noRedeclareBuiltinGlobalsFromConfig(value: std.json.Value) RuleConfigError!NoRedeclareBuiltinGlobals {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const enabled = switch (config.get("builtinGlobals") orelse return .no) {
            .bool => |bool_value| bool_value,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (enabled) .yes else .no;
    }

    fn noRestrictedPropertiesFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedProperties {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        var restrictions = NoRestrictedProperties{};
        for (items[1..]) |item| {
            const config = switch (item) {
                .object => |object| object,
                else => return error.UnsupportedRuleConfigValue,
            };

            var entry = NoRestrictedPropertyEntry{};
            const has_object = try noRestrictedPropertyOptionalString(config, "object", &entry, .object);
            const has_property = try noRestrictedPropertyOptionalString(config, "property", &entry, .property);
            _ = try noRestrictedPropertyOptionalString(config, "message", &entry, .message);
            const has_allow_objects = try noRestrictedPropertyNameListFromConfig(config, "allowObjects", &entry.allow_objects);
            const has_allow_properties = try noRestrictedPropertyNameListFromConfig(config, "allowProperties", &entry.allow_properties);

            if (has_object and has_allow_objects) return error.UnsupportedRuleConfigValue;
            if (has_property and has_allow_properties) return error.UnsupportedRuleConfigValue;
            if (!has_object and !has_property) return error.UnsupportedRuleConfigValue;
            if (has_allow_objects and !has_property) return error.UnsupportedRuleConfigValue;
            if (has_allow_properties and !has_object) return error.UnsupportedRuleConfigValue;
            if (!restrictions.append(entry)) return error.UnsupportedRuleConfigValue;
        }
        return restrictions;
    }

    fn noRestrictedGlobalsFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedGlobals {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        switch (items[1]) {
            .object => |object| {
                if (object.get("globals") != null) {
                    return noRestrictedGlobalsFromObjectConfig(object);
                }
            },
            else => {},
        }

        var restrictions = NoRestrictedGlobals{};
        for (items[1..]) |item| {
            const entry = try noRestrictedGlobalEntryFromConfig(item);
            if (!restrictions.append(entry)) return error.UnsupportedRuleConfigValue;
        }
        return restrictions;
    }

    fn noRestrictedGlobalsFromObjectConfig(config: std.json.ObjectMap) RuleConfigError!NoRestrictedGlobals {
        var restrictions = NoRestrictedGlobals{};

        const globals_value = config.get("globals") orelse return error.UnsupportedRuleConfigValue;
        const globals = switch (globals_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };
        for (globals) |item| {
            const entry = try noRestrictedGlobalEntryFromConfig(item);
            if (!restrictions.append(entry)) return error.UnsupportedRuleConfigValue;
        }

        if (config.get("checkGlobalObject")) |value| {
            restrictions.check_global_object = switch (value) {
                .bool => |enabled| enabled,
                else => return error.UnsupportedRuleConfigValue,
            };
        }

        if (config.get("globalObjects")) |value| {
            const objects = switch (value) {
                .array => |array| array.items,
                else => return error.UnsupportedRuleConfigValue,
            };
            for (objects) |item| {
                const name = switch (item) {
                    .string => |string| string,
                    else => return error.UnsupportedRuleConfigValue,
                };
                if (!restrictions.global_objects.append(name)) return error.UnsupportedRuleConfigValue;
            }
        }

        return restrictions;
    }

    fn noRestrictedGlobalEntryFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedGlobalEntry {
        var entry = NoRestrictedGlobalEntry{};
        switch (value) {
            .string => |name| {
                if (!entry.setName(name)) return error.UnsupportedRuleConfigValue;
            },
            .object => |object| {
                const name_value = object.get("name") orelse return error.UnsupportedRuleConfigValue;
                const name = switch (name_value) {
                    .string => |string| string,
                    else => return error.UnsupportedRuleConfigValue,
                };
                if (!entry.setName(name)) return error.UnsupportedRuleConfigValue;
                if (object.get("message")) |message_value| {
                    const message = switch (message_value) {
                        .string => |string| string,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    if (!entry.setMessage(message)) return error.UnsupportedRuleConfigValue;
                }
            },
            else => return error.UnsupportedRuleConfigValue,
        }
        return entry;
    }

    fn noRestrictedSyntaxFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedSyntax {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        var restrictions = NoRestrictedSyntax{};
        for (items[1..]) |item| {
            const entry = try noRestrictedSyntaxEntryFromConfig(item);
            if (!restrictions.append(entry)) return error.UnsupportedRuleConfigValue;
        }
        return restrictions;
    }

    fn noRestrictedSyntaxEntryFromConfig(value: std.json.Value) RuleConfigError!NoRestrictedSyntaxEntry {
        var entry = NoRestrictedSyntaxEntry{};
        switch (value) {
            .string => |selector| {
                if (!entry.setSelector(selector)) return error.UnsupportedRuleConfigValue;
            },
            .object => |object| {
                const selector_value = object.get("selector") orelse return error.UnsupportedRuleConfigValue;
                const selector = switch (selector_value) {
                    .string => |string| string,
                    else => return error.UnsupportedRuleConfigValue,
                };
                if (!entry.setSelector(selector)) return error.UnsupportedRuleConfigValue;

                if (object.get("message")) |message_value| {
                    const message = switch (message_value) {
                        .string => |string| string,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    if (!entry.setMessage(message)) return error.UnsupportedRuleConfigValue;
                }
            },
            else => return error.UnsupportedRuleConfigValue,
        }
        return entry;
    }

    const NoRestrictedPropertyStringTarget = enum {
        object,
        property,
        message,
    };

    fn noRestrictedPropertyOptionalString(
        config: std.json.ObjectMap,
        key: []const u8,
        entry: *NoRestrictedPropertyEntry,
        target: NoRestrictedPropertyStringTarget,
    ) RuleConfigError!bool {
        const value = config.get(key) orelse return false;
        const string = switch (value) {
            .string => |string| string,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ok = switch (target) {
            .object => entry.setObject(string),
            .property => entry.setProperty(string),
            .message => entry.setMessage(string),
        };
        if (!ok) return error.UnsupportedRuleConfigValue;
        return true;
    }

    fn noRestrictedPropertyNameListFromConfig(
        config: std.json.ObjectMap,
        key: []const u8,
        names: *NoRestrictedPropertyNameList,
    ) RuleConfigError!bool {
        const value = config.get(key) orelse return false;
        const items = switch (value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        for (items) |item| {
            const name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!names.append(name)) return error.UnsupportedRuleConfigValue;
        }
        return true;
    }

    fn preferConstDestructuringFromConfig(value: std.json.Value) RuleConfigError!PreferConstDestructuring {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .any,
        };
        if (items.len < 2) return .any;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const destructuring = switch (config.get("destructuring") orelse return .any) {
            .string => |destructuring| destructuring,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, destructuring, "any")) return .any;
        if (std.mem.eql(u8, destructuring, "all")) return .all;
        return error.UnsupportedRuleConfigValue;
    }

    fn preferConstBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const option = config.get(key) orelse return default;
        return switch (option) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn preferArrowCallbackBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const option = config.get(key) orelse return default;
        return switch (option) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn requireAtomicUpdatesBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn preferDestructuringOptionFromConfig(
        value: std.json.Value,
        node_key: []const u8,
        kind_key: []const u8,
        default: bool,
    ) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (config.get(node_key)) |node_config_value| {
            const node_config = switch (node_config_value) {
                .object => |object| object,
                else => return error.UnsupportedRuleConfigValue,
            };
            return switch (node_config.get(kind_key) orelse return default) {
                .bool => |enabled| enabled,
                else => error.UnsupportedRuleConfigValue,
            };
        }
        return switch (config.get(kind_key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn preferDestructuringEnforceForRenamedPropertiesFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 3) return false;

        const config = switch (items[2]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("enforceForRenamedProperties") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn preferPromiseRejectErrorsAllowEmptyRejectFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowEmptyReject") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn promiseValidParamsExclusionsFromConfig(value: std.json.Value) RuleConfigError!PromiseValidParamsExclusions {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};
        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const excluded = switch (config.get("exclude") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var result = PromiseValidParamsExclusions{};
        for (excluded) |entry| {
            const name = switch (entry) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            result.enable(name);
        }
        return result;
    }

    fn promiseParamNamePatternFromConfig(
        value: std.json.Value,
        key: []const u8,
        default: PromiseParamNamePattern.Default,
    ) RuleConfigError!PromiseParamNamePattern {
        var result = PromiseParamNamePattern{ .default = default };
        const items = switch (value) {
            .array => |array| array.items,
            else => return result,
        };
        if (items.len < 2) return result;
        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const pattern = switch (config.get(key) orelse return result) {
            .string => |pattern| pattern,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (!result.set(pattern)) return error.UnsupportedRuleConfigValue;
        return result;
    }

    fn promiseNoReturnWrapAllowRejectFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;
        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowReject") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn promiseNoPromiseInCallbackExemptDeclarationsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("exemptDeclarations") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn preserveCaughtErrorRequireCatchParameterFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("requireCatchParameter") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noPromiseExecutorReturnAllowVoidFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowVoid") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn preferRegexLiteralsDisallowRedundantWrappingFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("disallowRedundantWrapping") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noReturnAssignStyleFromConfig(value: std.json.Value) RuleConfigError!NoReturnAssignStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .except_parens,
        };
        if (items.len < 2) return .except_parens;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "except-parens")) return .except_parens;
        if (std.mem.eql(u8, style, "always")) return .always;
        return error.UnsupportedRuleConfigValue;
    }

    fn radixStyleFromConfig(value: std.json.Value) RuleConfigError!RadixStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "as-needed")) return .as_needed;
        return error.UnsupportedRuleConfigValue;
    }

    fn requireUnicodeRegexpRequireFlagFromConfig(value: std.json.Value) RuleConfigError!RequireUnicodeRegexpRequireFlag {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .any,
        };
        if (items.len < 2) return .any;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const require_flag = switch (config.get("requireFlag") orelse return .any) {
            .string => |flag| flag,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, require_flag, "u")) return .u;
        if (std.mem.eql(u8, require_flag, "v")) return .v;
        return error.UnsupportedRuleConfigValue;
    }

    fn sortVarsIgnoreCaseFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("ignoreCase") orelse return false) {
            .bool => |ignore_case| ignore_case,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn sortImportsBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const config = sortImportsConfigObject(value) orelse return default;
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn sortImportsMemberSyntaxOrderFromConfig(value: std.json.Value) RuleConfigError!SortImportsMemberSyntaxOrder {
        const config = sortImportsConfigObject(value) orelse return .{};
        const entries = switch (config.get("memberSyntaxSortOrder") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (entries.len != 4) return error.UnsupportedRuleConfigValue;

        var result = SortImportsMemberSyntaxOrder{};
        var seen = [_]bool{false} ** 4;
        for (entries, 0..) |entry, index| {
            const syntax_name = switch (entry) {
                .string => |syntax_name| syntax_name,
                else => return error.UnsupportedRuleConfigValue,
            };
            const syntax = try sortImportsMemberSyntaxFromString(syntax_name);
            const rank_index = @intFromEnum(syntax);
            if (seen[rank_index]) return error.UnsupportedRuleConfigValue;
            seen[rank_index] = true;
            result.values[index] = syntax;
        }
        return result;
    }

    fn sortImportsMemberSyntaxFromString(value: []const u8) RuleConfigError!SortImportsMemberSyntax {
        if (std.mem.eql(u8, value, "none")) return .none;
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "multiple")) return .multiple;
        if (std.mem.eql(u8, value, "single")) return .single;
        return error.UnsupportedRuleConfigValue;
    }

    fn sortImportsConfigObject(value: std.json.Value) ?std.json.ObjectMap {
        const items = switch (value) {
            .array => |array| array.items,
            else => return null,
        };
        if (items.len < 2) return null;

        return switch (items[1]) {
            .object => |object| object,
            else => null,
        };
    }

    fn sortKeysOrderFromConfig(value: std.json.Value) RuleConfigError!SortKeysOrder {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .asc,
        };
        if (items.len < 2) return .asc;

        const order = switch (items[1]) {
            .string => |order| order,
            .object => return .asc,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, order, "asc")) return .asc;
        if (std.mem.eql(u8, order, "desc")) return .desc;
        return error.UnsupportedRuleConfigValue;
    }

    fn sortKeysBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const config = sortKeysConfigObject(value) orelse return default;
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn sortKeysMinKeysFromConfig(value: std.json.Value) RuleConfigError!usize {
        const config = sortKeysConfigObject(value) orelse return 2;
        return switch (config.get("minKeys") orelse return 2) {
            .integer => |min_keys| nonNegativeIntegerToUsize(min_keys),
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn sortKeysConfigObject(value: std.json.Value) ?std.json.ObjectMap {
        const items = switch (value) {
            .array => |array| array.items,
            else => return null,
        };
        if (items.len < 2) return null;
        const index: usize = switch (items[1]) {
            .object => 1,
            .string => if (items.len >= 3) 2 else return null,
            else => return null,
        };
        return switch (items[index]) {
            .object => |object| object,
            else => null,
        };
    }

    fn strictModeFromConfig(value: std.json.Value) RuleConfigError!StrictMode {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .safe,
        };
        if (items.len < 2) return .safe;

        const mode = switch (items[1]) {
            .string => |mode| mode,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, mode, "safe")) return .safe;
        if (std.mem.eql(u8, mode, "global")) return .global;
        if (std.mem.eql(u8, mode, "function")) return .function;
        if (std.mem.eql(u8, mode, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn noSequencesAllowInParenthesesFromConfig(value: std.json.Value) RuleConfigError!NoSequencesAllowInParentheses {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .yes,
        };
        if (items.len < 2) return .yes;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowInParentheses") orelse return .yes) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn noUselessComputedKeyEnforceForClassMembersFromConfig(value: std.json.Value) RuleConfigError!NoUselessComputedKeyEnforceForClassMembers {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .yes,
        };
        if (items.len < 2) return .yes;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const enforce = switch (config.get("enforceForClassMembers") orelse return .yes) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (enforce) .yes else .no;
    }

    fn noUnusedExpressionsAllowShortCircuitFromConfig(value: std.json.Value) RuleConfigError!NoUnusedExpressionsAllowShortCircuit {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowShortCircuit") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn noUnusedExpressionsAllowTernaryFromConfig(value: std.json.Value) RuleConfigError!NoUnusedExpressionsAllowTernary {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowTernary") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn noUnusedExpressionsAllowTaggedTemplatesFromConfig(value: std.json.Value) RuleConfigError!NoUnusedExpressionsAllowTaggedTemplates {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowTaggedTemplates") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn noUnusedVarsArgsFromConfig(value: std.json.Value, default: NoUnusedVarsArgs) RuleConfigError!NoUnusedVarsArgs {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const args = switch (config.get("args") orelse return default) {
            .string => |args| args,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, args, "none")) return .none;
        if (std.mem.eql(u8, args, "after-used")) return .after_used;
        if (std.mem.eql(u8, args, "all")) return .all;
        return error.UnsupportedRuleConfigValue;
    }

    fn noUnusedVarsVarsFromConfig(value: std.json.Value, default: NoUnusedVarsVars) RuleConfigError!NoUnusedVarsVars {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const vars = switch (config.get("vars") orelse return default) {
            .string => |vars| vars,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, vars, "all")) return .all;
        if (std.mem.eql(u8, vars, "local")) return .local;
        return error.UnsupportedRuleConfigValue;
    }

    fn noUnusedVarsCaughtErrorsFromConfig(value: std.json.Value, default: NoUnusedVarsCaughtErrors) RuleConfigError!NoUnusedVarsCaughtErrors {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const caught_errors = switch (config.get("caughtErrors") orelse return default) {
            .string => |caught_errors| caught_errors,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, caught_errors, "none")) return .none;
        if (std.mem.eql(u8, caught_errors, "all")) return .all;
        return error.UnsupportedRuleConfigValue;
    }

    fn noUnusedVarsIgnoreRestSiblingsFromConfig(value: std.json.Value, default: bool) RuleConfigError!bool {
        return noUnusedVarsBoolOptionFromConfig(value, "ignoreRestSiblings", default);
    }

    fn noUnusedVarsReportUsedIgnorePatternFromConfig(value: std.json.Value, default: bool) RuleConfigError!bool {
        return noUnusedVarsBoolOptionFromConfig(value, "reportUsedIgnorePattern", default);
    }

    fn noUnusedVarsBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noUnusedVarsIgnorePatternFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!NoUnusedVarsIgnorePattern {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const pattern_value = switch (config.get(key) orelse return .{}) {
            .string => |pattern_value| pattern_value,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (pattern_value.len == 0) return .{};

        var pattern = NoUnusedVarsIgnorePattern{};
        pattern.set(pattern_value) catch return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn noUseBeforeDefineCheckFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!NoUseBeforeDefineCheck {
        const items = switch (value) {
            .array => |array| array.items,
            else => return if (default) .yes else .no,
        };
        if (items.len < 2) return if (default) .yes else .no;

        const config = switch (items[1]) {
            .string => |style| {
                if (std.mem.eql(u8, style, "nofunc")) {
                    return if (std.mem.eql(u8, key, "functions")) .no else if (default) .yes else .no;
                }
                return error.UnsupportedRuleConfigValue;
            },
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const enabled = switch (config.get(key) orelse return if (default) .yes else .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (enabled) .yes else .no;
    }

    fn noUseBeforeDefineAllowNamedExportsFromConfig(value: std.json.Value) RuleConfigError!bool {
        return noUseBeforeDefineBoolOptionFromConfig(value, "allowNamedExports", false);
    }

    fn noUseBeforeDefineBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            .string => return default,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn objectShorthandStyleFromConfig(value: std.json.Value) RuleConfigError!ObjectShorthandStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            .object => return .always,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "methods")) return .methods;
        if (std.mem.eql(u8, style, "properties")) return .properties;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn objectShorthandAvoidQuotesFromConfig(value: std.json.Value) RuleConfigError!bool {
        return objectShorthandBoolOptionFromConfig(value, "avoidQuotes");
    }

    fn objectShorthandIgnoreConstructorsFromConfig(value: std.json.Value) RuleConfigError!bool {
        return objectShorthandBoolOptionFromConfig(value, "ignoreConstructors");
    }

    fn objectShorthandAvoidExplicitReturnArrowsFromConfig(value: std.json.Value) RuleConfigError!bool {
        return objectShorthandBoolOptionFromConfig(value, "avoidExplicitReturnArrows");
    }

    fn objectShorthandBoolOptionFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config_value = switch (items[1]) {
            .object => items[1],
            .string => if (items.len >= 3) items[2] else return false,
            else => return error.UnsupportedRuleConfigValue,
        };
        const config = switch (config_value) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    const OneVarNeverConfig = struct {
        @"var": bool = true,
        let: bool = true,
        @"const": bool = true,
    };

    fn oneVarNeverConfigFromConfig(value: std.json.Value) RuleConfigError!OneVarNeverConfig {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        return switch (items[1]) {
            .string => |style| {
                if (!std.mem.eql(u8, style, "never")) return error.UnsupportedRuleConfigValue;
                return .{};
            },
            .object => |object| oneVarNeverObjectConfig(object),
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn oneVarNeverObjectConfig(object: std.json.ObjectMap) RuleConfigError!OneVarNeverConfig {
        var config = OneVarNeverConfig{
            .@"var" = false,
            .let = false,
            .@"const" = false,
        };
        var matched = false;

        if (object.get("var")) |value| {
            config.@"var" = try oneVarNeverOption(value);
            matched = true;
        }
        if (object.get("let")) |value| {
            config.let = try oneVarNeverOption(value);
            matched = true;
        }
        if (object.get("const")) |value| {
            config.@"const" = try oneVarNeverOption(value);
            matched = true;
        }

        if (!matched) return error.UnsupportedRuleConfigValue;
        return config;
    }

    fn oneVarNeverOption(value: std.json.Value) RuleConfigError!bool {
        const style = switch (value) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (!std.mem.eql(u8, style, "never")) return error.UnsupportedRuleConfigValue;
        return true;
    }

    fn operatorAssignmentStyleFromConfig(value: std.json.Value) RuleConfigError!OperatorAssignmentStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn noUndefTypeofFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("typeof") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noTabsAllowIndentationTabsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowIndentationTabs") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn useIsnanBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noTrailingSpacesBoolOptionFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    const NoUnreachableLoopIgnore = struct {
        while_statement: bool = false,
        do_while_statement: bool = false,
        for_statement: bool = false,
        for_in_statement: bool = false,
        for_of_statement: bool = false,
    };

    fn noUnreachableLoopIgnoreFromConfig(value: std.json.Value) RuleConfigError!NoUnreachableLoopIgnore {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ignore_value = config.get("ignore") orelse return .{};
        const ignore_items = switch (ignore_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var ignore = NoUnreachableLoopIgnore{};
        for (ignore_items) |item| {
            const name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, name, "WhileStatement")) {
                ignore.while_statement = true;
            } else if (std.mem.eql(u8, name, "DoWhileStatement")) {
                ignore.do_while_statement = true;
            } else if (std.mem.eql(u8, name, "ForStatement")) {
                ignore.for_statement = true;
            } else if (std.mem.eql(u8, name, "ForInStatement")) {
                ignore.for_in_statement = true;
            } else if (std.mem.eql(u8, name, "ForOfStatement")) {
                ignore.for_of_statement = true;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }
        return ignore;
    }

    fn noUnsafeNegationBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noUnsafeOptionalChainingBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        return noUnsafeNegationBoolOptionFromConfig(value, key, default);
    }

    fn noIrregularWhitespaceBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noInlineCommentsIgnorePatternFromConfig(value: std.json.Value) RuleConfigError!NoInlineCommentsIgnorePattern {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const pattern_value = switch (config.get("ignorePattern") orelse return .{}) {
            .string => |pattern_value| pattern_value,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (pattern_value.len == 0) return .{};

        var pattern = NoInlineCommentsIgnorePattern{};
        pattern.set(pattern_value) catch return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn noMultiAssignBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noEvalAllowIndirectFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowIndirect") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noExtendNativeExceptionsFromConfig(value: std.json.Value) RuleConfigError!NoExtendNativeExceptions {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const exceptions_value = config.get("exceptions") orelse return .{};
        const exceptions_items = switch (exceptions_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var exceptions = NoExtendNativeExceptions{};
        for (exceptions_items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            exceptions.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return exceptions;
    }

    fn noGlobalAssignExceptionsFromConfig(value: std.json.Value) RuleConfigError!NoShadowAllowNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const exceptions_value = config.get("exceptions") orelse return .{};
        const exception_items = switch (exceptions_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var exceptions = NoShadowAllowNames{};
        for (exception_items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            exceptions.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return exceptions;
    }

    fn noUselessRenameBoolOptionFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn noSelfAssignPropsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("props") orelse return true) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn unicodeBomStyleFromConfig(value: std.json.Value) RuleConfigError!UnicodeBomStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .never,
        };
        if (items.len < 2) return .never;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "never")) return .never;
        if (std.mem.eql(u8, style, "always")) return .always;
        return error.UnsupportedRuleConfigValue;
    }

    fn noUnneededTernaryDefaultAssignmentFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("defaultAssignment") orelse return true) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn noVoidAllowAsStatementFromConfig(value: std.json.Value) RuleConfigError!NoVoidAllowAsStatement {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .no,
        };
        if (items.len < 2) return .no;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allowAsStatement") orelse return .no) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
        return if (allow) .yes else .no;
    }

    fn noWarningCommentsLocationFromConfig(value: std.json.Value) RuleConfigError!NoWarningCommentsLocation {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .start,
        };
        if (items.len < 2) return .start;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const location = switch (config.get("location") orelse return .start) {
            .string => |location| location,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, location, "start")) return .start;
        if (std.mem.eql(u8, location, "anywhere")) return .anywhere;
        return error.UnsupportedRuleConfigValue;
    }

    fn noWarningCommentsDecorationFromConfig(value: std.json.Value) RuleConfigError!NoWarningCommentsDecoration {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .none,
        };
        if (items.len < 2) return .none;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const decoration_value = config.get("decoration") orelse return .none;
        const decoration_items = switch (decoration_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var has_asterisk = false;
        var has_slash = false;
        for (decoration_items) |item| {
            const char = switch (item) {
                .string => |char| char,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, char, "*")) {
                has_asterisk = true;
            } else if (std.mem.eql(u8, char, "/")) {
                has_slash = true;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }

        if (has_asterisk and has_slash) return .slash_asterisk;
        if (has_asterisk) return .asterisk;
        if (has_slash) return .slash;
        return .none;
    }

    fn noWarningCommentsTermsFromConfig(value: std.json.Value) RuleConfigError!NoWarningCommentsTerms {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const terms_value = config.get("terms") orelse return .{};
        const term_items = switch (terms_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var terms = NoWarningCommentsTerms{};
        terms.custom = true;
        for (term_items) |item| {
            const term = switch (item) {
                .string => |term| term,
                else => return error.UnsupportedRuleConfigValue,
            };
            terms.append(term) catch return error.UnsupportedRuleConfigValue;
        }
        return terms;
    }

    fn spacedCommentStyleFromConfig(value: std.json.Value) RuleConfigError!SpacedCommentStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn validTypeofRequireStringLiteralsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("requireStringLiterals") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn spacedCommentMarkersFromConfig(value: std.json.Value) RuleConfigError!SpacedCommentMarkers {
        return spacedCommentPatternsFromConfig(value, "markers");
    }

    fn spacedCommentExceptionsFromConfig(value: std.json.Value) RuleConfigError!SpacedCommentMarkers {
        return spacedCommentPatternsFromConfig(value, "exceptions");
    }

    fn spacedCommentPatternsFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!SpacedCommentMarkers {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 3) return .{};

        const config = switch (items[2]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const patterns_value = config.get(key) orelse return .{};
        const pattern_items = switch (patterns_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var patterns = SpacedCommentMarkers{};
        for (pattern_items) |item| {
            const pattern = switch (item) {
                .string => |pattern| pattern,
                else => return error.UnsupportedRuleConfigValue,
            };
            patterns.append(pattern) catch return error.UnsupportedRuleConfigValue;
        }
        return patterns;
    }

    fn reactButtonHasTypeBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    const ReactForbidPropTypesForbid = struct {
        any: bool = true,
        array: bool = true,
        object: bool = true,
    };

    fn reactForbidPropTypesForbidFromConfig(value: std.json.Value) RuleConfigError!ReactForbidPropTypesForbid {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const forbid_items = switch (config.get("forbid") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var forbid = ReactForbidPropTypesForbid{
            .any = false,
            .array = false,
            .object = false,
        };
        for (forbid_items) |item| {
            const name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (std.mem.eql(u8, name, "any")) {
                forbid.any = true;
            } else if (std.mem.eql(u8, name, "array")) {
                forbid.array = true;
            } else if (std.mem.eql(u8, name, "object")) {
                forbid.object = true;
            } else {
                return error.UnsupportedRuleConfigValue;
            }
        }
        return forbid;
    }

    fn reactForbidPropTypesBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn reactJsxFilenameExtensionsFromConfig(value: std.json.Value) RuleConfigError!ReactJsxFilenameExtensions {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const extension_items = switch (config.get("extensions") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var extensions = ReactJsxFilenameExtensions{};
        for (extension_items) |item| {
            const extension_name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            extensions.append(extension_name) catch return error.UnsupportedRuleConfigValue;
        }
        return extensions;
    }

    fn reactJsxFilenameExtensionAllowFromConfig(value: std.json.Value) RuleConfigError!ReactJsxFilenameExtensionAllow {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allow") orelse return .always) {
            .string => |string| string,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, allow, "always")) return .always;
        if (std.mem.eql(u8, allow, "as-needed")) return .as_needed;
        return error.UnsupportedRuleConfigValue;
    }

    fn reactJsxBooleanValueStyleFromConfig(value: std.json.Value) RuleConfigError!ReactJsxBooleanValueStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .never,
        };
        if (items.len < 2) return .never;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "never")) return .never;
        if (std.mem.eql(u8, style, "always")) return .always;
        return error.UnsupportedRuleConfigValue;
    }

    fn reactPreferEs6ClassStyleFromConfig(value: std.json.Value) RuleConfigError!ReactPreferEs6ClassStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .always,
        };
        if (items.len < 2) return .always;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "always")) return .always;
        if (std.mem.eql(u8, style, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn reactDefaultPropsMatchPropTypesAllowRequiredDefaultsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowRequiredDefaults") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactDisplayNameBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactJsxNoBindBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactJsxNoDuplicatePropsIgnoreCaseFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("ignoreCase") orelse return true) {
            .bool => |ignore_case| ignore_case,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactJsxKeyBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactNoStringRefsNoTemplateLiteralsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("noTemplateLiterals") orelse return false) {
            .bool => |no_template_literals| no_template_literals,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactNoMultiCompIgnoreStatelessFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("ignoreStateless") orelse return true) {
            .bool => |ignore_stateless| ignore_stateless,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactNoUnstableNestedComponentsAllowAsPropsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const config = reactNoUnstableNestedComponentsConfigObject(value) orelse return false;
        return switch (config.get("allowAsProps") orelse return false) {
            .bool => |allow_as_props| allow_as_props,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactNoUnstableNestedComponentsPropNamePatternFromConfig(value: std.json.Value) RuleConfigError!ReactNoUnstableNestedComponentsPropNamePattern {
        const config = reactNoUnstableNestedComponentsConfigObject(value) orelse return .{};
        const pattern_value = switch (config.get("propNamePattern") orelse return .{}) {
            .string => |pattern| pattern,
            else => return error.UnsupportedRuleConfigValue,
        };
        var pattern = ReactNoUnstableNestedComponentsPropNamePattern{};
        if (!pattern.set(pattern_value)) return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn reactNoUnstableNestedComponentsConfigObject(value: std.json.Value) ?std.json.ObjectMap {
        const items = switch (value) {
            .array => |array| array.items,
            else => return null,
        };
        if (items.len < 2) return null;
        return switch (items[1]) {
            .object => |object| object,
            else => null,
        };
    }

    fn reactNoUnknownPropertyIgnoreFromConfig(value: std.json.Value) RuleConfigError!ReactNoUnknownPropertyIgnoreNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ignore_items = switch (config.get("ignore") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var ignore = ReactNoUnknownPropertyIgnoreNames{};
        for (ignore_items) |item| {
            const name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            ignore.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return ignore;
    }

    fn reactNoUnknownPropertyRequireDataLowercaseFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("requireDataLowercase") orelse return false) {
            .bool => |require_data_lowercase| require_data_lowercase,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactSelfClosingCompBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactHooksAdditionalHooksFromConfig(value: std.json.Value) RuleConfigError!ReactHooksAdditionalHooksPattern {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const pattern_value = switch (config.get("additionalHooks") orelse return .{}) {
            .string => |pattern_value| pattern_value,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (pattern_value.len == 0) return .{};

        var pattern = ReactHooksAdditionalHooksPattern{};
        pattern.set(pattern_value) catch return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn reactJsxPascalCaseAllowAllCapsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowAllCaps") orelse return true) {
            .bool => |allow_all_caps| allow_all_caps,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactJsxPascalCaseAllowLeadingUnderscoreFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowLeadingUnderscore") orelse return false) {
            .bool => |allow_leading_underscore| allow_leading_underscore,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactJsxPascalCaseAllowNamespaceFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowNamespace") orelse return false) {
            .bool => |allow_namespace| allow_namespace,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn reactJsxPascalCaseIgnoreFromConfig(value: std.json.Value) RuleConfigError!ReactJsxPascalCaseIgnoreNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const ignore_items = switch (config.get("ignore") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var ignore = ReactJsxPascalCaseIgnoreNames{};
        for (ignore_items) |item| {
            const name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            ignore.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return ignore;
    }

    fn wrapIifeStyleFromConfig(value: std.json.Value) RuleConfigError!WrapIifeStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .outside,
        };
        if (items.len < 2) return .outside;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "outside")) return .outside;
        if (std.mem.eql(u8, style, "inside")) return .inside;
        if (std.mem.eql(u8, style, "any")) return .any;
        return error.UnsupportedRuleConfigValue;
    }

    fn yodaStyleFromConfig(value: std.json.Value) RuleConfigError!YodaStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .never,
        };
        if (items.len < 2) return .never;

        const style = switch (items[1]) {
            .string => |style| style,
            .object => return .never,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "never")) return .never;
        if (std.mem.eql(u8, style, "always")) return .always;
        return error.UnsupportedRuleConfigValue;
    }

    fn yodaOnlyEqualityFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config_value = switch (items[1]) {
            .object => items[1],
            .string => if (items.len >= 3) items[2] else return false,
            else => return error.UnsupportedRuleConfigValue,
        };
        const config = switch (config_value) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("onlyEquality") orelse return false) {
            .bool => |enabled| enabled,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn yodaExceptRangeFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 3) return false;

        const config = switch (items[2]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("exceptRange") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintMethodSignatureStyleFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintMethodSignatureStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .property,
        };
        if (items.len < 2) return .property;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "property")) return .property;
        if (std.mem.eql(u8, style, "method")) return .method;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintArrayTypeStyleFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintArrayTypeStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .array_simple,
        };
        if (items.len < 2) return .array_simple;

        const config_value = switch (items[1]) {
            .object => items[1],
            else => return error.UnsupportedRuleConfigValue,
        };
        const config = switch (config_value) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const style = switch (config.get("default") orelse return .array_simple) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "array")) return .array;
        if (std.mem.eql(u8, style, "array-simple")) return .array_simple;
        if (std.mem.eql(u8, style, "generic")) return .generic;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintBanTsCommentModeFromConfig(value: std.json.Value, key: []const u8, default: TypescriptEslintBanTsCommentMode) RuleConfigError!TypescriptEslintBanTsCommentMode {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| if (enabled) .ban else .allow,
            .string => |mode| if (std.mem.eql(u8, mode, "allow-with-description"))
                .allow_with_description
            else
                error.UnsupportedRuleConfigValue,
            else => error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintBanTsCommentMinimumDescriptionLengthFromConfig(value: std.json.Value) RuleConfigError!usize {
        const items = switch (value) {
            .array => |array| array.items,
            else => return 3,
        };
        if (items.len < 2) return 3;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const length = switch (config.get("minimumDescriptionLength") orelse return 3) {
            .integer => |length| length,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (length < 0) return error.UnsupportedRuleConfigValue;
        return @intCast(length);
    }

    fn typescriptEslintConsistentTypeDefinitionsStyleFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintConsistentTypeDefinitionsStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .interface,
        };
        if (items.len < 2) return .interface;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "interface")) return .interface;
        if (std.mem.eql(u8, style, "type")) return .type;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintClassLiteralPropertyStyleFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintClassLiteralPropertyStyle {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .fields,
        };
        if (items.len < 2) return .fields;

        const style = switch (items[1]) {
            .string => |style| style,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, style, "fields")) return .fields;
        if (std.mem.eql(u8, style, "getters")) return .getters;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintTripleSlashReferenceModeFromConfig(value: std.json.Value, key: []const u8, default: TypescriptEslintTripleSlashReferenceMode) RuleConfigError!TypescriptEslintTripleSlashReferenceMode {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const mode = switch (config.get(key) orelse return default) {
            .string => |mode| mode,
            else => return error.UnsupportedRuleConfigValue,
        };
        if (std.mem.eql(u8, mode, "always")) return .always;
        if (std.mem.eql(u8, mode, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintNoNamespaceBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintNoRedeclareIgnoreDeclarationMergeFromConfig(value: std.json.Value) RuleConfigError!bool {
        return typescriptEslintNoNamespaceBoolOptionFromConfig(value, "ignoreDeclarationMerge", true);
    }

    fn typescriptEslintNoRedeclareBuiltinGlobalsFromConfig(value: std.json.Value) RuleConfigError!bool {
        return noShadowBuiltinGlobalsFromConfig(value);
    }

    fn typescriptEslintNoRequireImportsBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        return typescriptEslintNoNamespaceBoolOptionFromConfig(value, key, default);
    }

    fn typescriptEslintNoRequireImportsAllowFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintNoRequireImportsAllowPatterns {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allow = switch (config.get("allow") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var patterns: TypescriptEslintNoRequireImportsAllowPatterns = .{};
        for (allow) |entry| {
            const pattern = switch (entry) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!patterns.append(pattern)) return error.UnsupportedRuleConfigValue;
        }
        return patterns;
    }

    fn typescriptEslintNoThisAliasAllowedNamesFromConfig(value: std.json.Value) RuleConfigError!NoThisAliasAllowedNames {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const allowed_names_value = config.get("allowedNames") orelse return .{};
        const allowed_names = switch (allowed_names_value) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var names = NoThisAliasAllowedNames{ .custom = true };
        for (allowed_names) |name_value| {
            const name = switch (name_value) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            names.append(name) catch return error.UnsupportedRuleConfigValue;
        }
        return names;
    }

    fn typescriptEslintNoThisAliasAllowDestructuringFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return true,
        };
        if (items.len < 2) return true;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowDestructuring") orelse return true) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintNoExplicitAnyBoolOptionFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;
        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintNoInferrableTypesBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintNoInvalidVoidTypeBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    const TypescriptEslintNoInvalidVoidTypeGenericTypeArguments = struct {
        allow_any: bool = true,
        allowed_names: TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNames = .{},
    };

    fn typescriptEslintNoInvalidVoidTypeGenericTypeArgumentsFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintNoInvalidVoidTypeGenericTypeArguments {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };

        return switch (config.get("allowInGenericTypeArguments") orelse return .{}) {
            .bool => |enabled| .{ .allow_any = enabled },
            .array => |array| blk: {
                var names = TypescriptEslintNoInvalidVoidTypeAllowedGenericTypeNames{};
                for (array.items) |item| {
                    const name = switch (item) {
                        .string => |name| name,
                        else => return error.UnsupportedRuleConfigValue,
                    };
                    names.append(name) catch return error.UnsupportedRuleConfigValue;
                }
                break :blk .{
                    .allow_any = false,
                    .allowed_names = names,
                };
            },
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintNoEmptyInterfaceAllowSingleExtendsFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("allowSingleExtends") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintNoEmptyObjectTypeAllowInterfacesFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintNoEmptyObjectTypeAllowInterfaces {
        const option = try typescriptEslintNoEmptyObjectTypeStringOption(value, "allowInterfaces") orelse return .never;
        if (std.mem.eql(u8, option, "always")) return .always;
        if (std.mem.eql(u8, option, "never")) return .never;
        if (std.mem.eql(u8, option, "with-single-extends")) return .with_single_extends;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintNoEmptyObjectTypeAllowObjectTypesFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintNoEmptyObjectTypeAllowObjectTypes {
        const option = try typescriptEslintNoEmptyObjectTypeStringOption(value, "allowObjectTypes") orelse return .never;
        if (std.mem.eql(u8, option, "always")) return .always;
        if (std.mem.eql(u8, option, "never")) return .never;
        return error.UnsupportedRuleConfigValue;
    }

    fn typescriptEslintNoEmptyObjectTypeAllowWithNameFromConfig(value: std.json.Value) RuleConfigError!TypescriptEslintNoEmptyObjectTypeAllowWithName {
        const option = try typescriptEslintNoEmptyObjectTypeStringOption(value, "allowWithName") orelse return .{};
        var pattern: TypescriptEslintNoEmptyObjectTypeAllowWithName = .{};
        pattern.set(option) catch return error.UnsupportedRuleConfigValue;
        return pattern;
    }

    fn typescriptEslintNoEmptyObjectTypeStringOption(value: std.json.Value, key: []const u8) RuleConfigError!?[]const u8 {
        const items = switch (value) {
            .array => |array| array.items,
            else => return null,
        };
        if (items.len < 2) return null;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return null) {
            .string => |option| option,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintTypedefBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn typescriptEslintRestrictPlusOperandsBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn promiseNoCallbackInPromiseExceptionsFromConfig(value: std.json.Value) RuleConfigError!PromiseNoCallbackInPromiseExceptions {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const exception_items = switch (config.get("exceptions") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var exceptions = PromiseNoCallbackInPromiseExceptions{};
        for (exception_items) |item| {
            const name = switch (item) {
                .string => |name| name,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!exceptions.append(name)) return error.UnsupportedRuleConfigValue;
        }
        return exceptions;
    }

    fn promiseNoCallbackInPromiseTimeoutsErrFromConfig(value: std.json.Value) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get("timeoutsErr") orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn promiseCatchOrReturnBoolOptionFromConfig(value: std.json.Value, key: []const u8) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return false,
        };
        if (items.len < 2) return false;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return false) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn promiseAlwaysReturnBoolOptionFromConfig(value: std.json.Value, key: []const u8, default: bool) RuleConfigError!bool {
        const items = switch (value) {
            .array => |array| array.items,
            else => return default,
        };
        if (items.len < 2) return default;

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        return switch (config.get(key) orelse return default) {
            .bool => |enabled| enabled,
            else => return error.UnsupportedRuleConfigValue,
        };
    }

    fn promiseCatchOrReturnTerminationMethodsFromConfig(value: std.json.Value) RuleConfigError!PromiseCatchOrReturnTerminationMethods {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const method_value = config.get("terminationMethod") orelse return .{};

        var methods = PromiseCatchOrReturnTerminationMethods{ .custom = true };
        switch (method_value) {
            .string => |method| if (!methods.append(method)) return error.UnsupportedRuleConfigValue,
            .array => |array| for (array.items) |item| {
                const method = switch (item) {
                    .string => |method| method,
                    else => return error.UnsupportedRuleConfigValue,
                };
                if (!methods.append(method)) return error.UnsupportedRuleConfigValue;
            },
            else => return error.UnsupportedRuleConfigValue,
        }
        return methods;
    }

    fn promiseAlwaysReturnIgnoreAssignmentVariablesFromConfig(value: std.json.Value) RuleConfigError!PromiseAlwaysReturnIgnoreAssignmentVariables {
        const items = switch (value) {
            .array => |array| array.items,
            else => return .{},
        };
        if (items.len < 2) return .{};

        const config = switch (items[1]) {
            .object => |object| object,
            else => return error.UnsupportedRuleConfigValue,
        };
        const name_items = switch (config.get("ignoreAssignmentVariable") orelse return .{}) {
            .array => |array| array.items,
            else => return error.UnsupportedRuleConfigValue,
        };

        var names = PromiseAlwaysReturnIgnoreAssignmentVariables{ .custom = true };
        for (name_items) |item| {
            const name = switch (item) {
                .string => |string| string,
                else => return error.UnsupportedRuleConfigValue,
            };
            if (!names.append(name)) return error.UnsupportedRuleConfigValue;
        }
        return names;
    }

    fn setByPrefixedRuleName(self: *Options, comptime field_prefix: []const u8, rule_name: []const u8, value: bool) bool {
        inline for (@typeInfo(Options).@"struct".fields) |field| {
            if (field.type == bool) {
                if (comptime fieldNameStartsWith(field.name, field_prefix)) {
                    if (cliNameMatchesFieldName(field.name[field_prefix.len..], rule_name)) {
                        @field(self, field.name) = value;
                        return true;
                    }
                }
            }
        }
        return false;
    }

    fn cliNameMatchesFieldName(comptime field_name: []const u8, cli_name: []const u8) bool {
        if (cli_name.len != field_name.len) return false;

        comptime var index: usize = 0;
        inline while (index < field_name.len) : (index += 1) {
            const expected = if (field_name[index] == '_') '-' else field_name[index];
            if (cli_name[index] != expected) return false;
        }
        return true;
    }

    fn fieldNameStartsWith(comptime field_name: []const u8, comptime prefix: []const u8) bool {
        @setEvalBranchQuota(10_000);
        if (field_name.len < prefix.len) return false;

        comptime var index: usize = 0;
        inline while (index < prefix.len) : (index += 1) {
            if (field_name[index] != prefix[index]) return false;
        }
        return true;
    }
};

pub const DeprecatedDependenceProfile = enum {
    default,
    profile_a,
    profile_b,
};

pub const max_jest_valid_expect_async_matchers = 64;
pub const max_jest_valid_expect_async_matcher_len = 128;

pub const JestValidExpectAsyncMatchers = struct {
    custom: bool = false,
    count: usize = 0,
    lengths: [max_jest_valid_expect_async_matchers]usize = undefined,
    storage: [max_jest_valid_expect_async_matchers][max_jest_valid_expect_async_matcher_len]u8 = undefined,

    pub fn contains(self: *const JestValidExpectAsyncMatchers, name: []const u8) bool {
        if (!self.custom) {
            return std.mem.eql(u8, name, "toResolve") or std.mem.eql(u8, name, "toReject");
        }
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }
        return false;
    }

    pub fn at(self: *const JestValidExpectAsyncMatchers, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *JestValidExpectAsyncMatchers, name: []const u8) bool {
        if (name.len > max_jest_valid_expect_async_matcher_len) return false;
        if (self.count >= max_jest_valid_expect_async_matchers) return false;
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const max_jest_additional_test_block_functions = 64;
pub const max_jest_additional_test_block_function_len = 128;

pub const JestAdditionalTestBlockFunctions = struct {
    count: usize = 0,
    lengths: [max_jest_additional_test_block_functions]usize = undefined,
    storage: [max_jest_additional_test_block_functions][max_jest_additional_test_block_function_len]u8 = undefined,

    pub fn at(self: *const JestAdditionalTestBlockFunctions, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *JestAdditionalTestBlockFunctions, name: []const u8) bool {
        if (name.len > max_jest_additional_test_block_function_len) return false;
        if (self.count >= max_jest_additional_test_block_functions) return false;
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.at(index), name)) return true;
        }

        @memcpy(self.storage[self.count][0..name.len], name);
        self.lengths[self.count] = name.len;
        self.count += 1;
        return true;
    }
};

pub const max_jest_valid_title_disallowed_words = 64;
pub const max_jest_valid_title_disallowed_word_len = 128;

pub const JestValidTitleDisallowedWords = struct {
    count: usize = 0,
    lengths: [max_jest_valid_title_disallowed_words]usize = undefined,
    storage: [max_jest_valid_title_disallowed_words][max_jest_valid_title_disallowed_word_len]u8 = undefined,

    pub fn at(self: *const JestValidTitleDisallowedWords, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }

    pub fn append(self: *JestValidTitleDisallowedWords, word: []const u8) bool {
        if (word.len > max_jest_valid_title_disallowed_word_len) return false;
        if (self.count >= max_jest_valid_title_disallowed_words) return false;

        @memcpy(self.storage[self.count][0..word.len], word);
        self.lengths[self.count] = word.len;
        self.count += 1;
        return true;
    }
};

pub const max_jest_valid_title_pattern_len = 512;
pub const max_jest_valid_title_matcher_message_len = 512;

pub const JestValidTitleMatcher = struct {
    active: bool = false,
    pattern_length: usize = 0,
    message_length: usize = 0,
    pattern_storage: [max_jest_valid_title_pattern_len]u8 = undefined,
    message_storage: [max_jest_valid_title_matcher_message_len]u8 = undefined,

    pub fn pattern(self: *const JestValidTitleMatcher) ?[]const u8 {
        if (!self.active) return null;
        return self.pattern_storage[0..self.pattern_length];
    }

    pub fn message(self: *const JestValidTitleMatcher) ?[]const u8 {
        if (self.message_length == 0) return null;
        return self.message_storage[0..self.message_length];
    }

    pub fn set(self: *JestValidTitleMatcher, pattern_value: []const u8, message_value: ?[]const u8) bool {
        if (pattern_value.len > max_jest_valid_title_pattern_len) return false;
        const custom_message = message_value orelse "";
        if (custom_message.len > max_jest_valid_title_matcher_message_len) return false;

        @memcpy(self.pattern_storage[0..pattern_value.len], pattern_value);
        @memcpy(self.message_storage[0..custom_message.len], custom_message);
        self.active = true;
        self.pattern_length = pattern_value.len;
        self.message_length = custom_message.len;
        return true;
    }
};

pub const JestValidTitleMatchers = struct {
    describe: JestValidTitleMatcher = .{},
    test_case: JestValidTitleMatcher = .{},
    it: JestValidTitleMatcher = .{},

    pub fn applyToAll(self: *JestValidTitleMatchers, matcher: JestValidTitleMatcher) void {
        self.describe = matcher;
        self.test_case = matcher;
        self.it = matcher;
    }
};

pub const max_jest_global_aliases = 32;
pub const max_jest_global_alias_len = 128;

pub const JestGlobalAliases = struct {
    count: usize = 0,
    canonical_lengths: [max_jest_global_aliases]usize = undefined,
    alias_lengths: [max_jest_global_aliases]usize = undefined,
    canonical_storage: [max_jest_global_aliases][max_jest_global_alias_len]u8 = undefined,
    alias_storage: [max_jest_global_aliases][max_jest_global_alias_len]u8 = undefined,

    pub fn canonicalAt(self: *const JestGlobalAliases, index: usize) []const u8 {
        return self.canonical_storage[index][0..self.canonical_lengths[index]];
    }

    pub fn aliasAt(self: *const JestGlobalAliases, index: usize) []const u8 {
        return self.alias_storage[index][0..self.alias_lengths[index]];
    }

    pub fn canonicalFor(self: *const JestGlobalAliases, alias: []const u8) ?[]const u8 {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.aliasAt(index), alias)) return self.canonicalAt(index);
        }
        return null;
    }

    pub fn append(self: *JestGlobalAliases, canonical: []const u8, alias: []const u8) bool {
        if (canonical.len == 0 or alias.len == 0) return false;
        if (canonical.len > max_jest_global_alias_len or alias.len > max_jest_global_alias_len) return false;
        if (self.count >= max_jest_global_aliases) return false;
        if (self.canonicalFor(alias) != null) return true;

        @memcpy(self.canonical_storage[self.count][0..canonical.len], canonical);
        @memcpy(self.alias_storage[self.count][0..alias.len], alias);
        self.canonical_lengths[self.count] = canonical.len;
        self.alias_lengths[self.count] = alias.len;
        self.count += 1;
        return true;
    }
};

pub const Diagnostic = struct {
    rule_id: []const u8,
    message: []const u8,
    span: ast.Span,
    severity: Severity,
    fixes: []Fix,
    suggestions: []Suggestion = &.{},
    suppression: ?Suppression = null,
    suppressions: []Suppression = &.{},
};

pub const Suppression = struct {
    justification: []const u8,
};

pub const Fix = struct {
    span: ast.Span,
    replacement: []const u8,
};

pub const Suggestion = struct {
    message: []const u8,
    fixes: []const Fix,
};

pub const Result = struct {
    diagnostics: []Diagnostic,
    suppressed_diagnostics: []Diagnostic = &.{},

    pub fn deinit(self: *Result, allocator: Allocator) void {
        freeDiagnosticSlice(allocator, self.diagnostics);
        freeDiagnosticSlice(allocator, self.suppressed_diagnostics);
    }

    pub fn hasDiagnostics(self: Result) bool {
        return self.diagnostics.len > 0;
    }

    pub fn hasErrors(self: Result) bool {
        for (self.diagnostics) |diagnostic| {
            if (diagnostic.severity == .@"error") return true;
        }
        return false;
    }
};

pub const SourcePosition = struct {
    line: usize,
    column: usize,
};

pub const DiagnosticList = std.ArrayList(Diagnostic);

pub fn addDiagnostic(
    allocator: Allocator,
    diagnostics: *DiagnosticList,
    severity: Severity,
    rule_id: []const u8,
    message: []const u8,
    span: ast.Span,
) Allocator.Error!void {
    return addDiagnosticWithFixes(
        allocator,
        diagnostics,
        severity,
        rule_id,
        message,
        span,
        &.{},
    );
}

pub fn addDiagnosticWithFix(
    allocator: Allocator,
    diagnostics: *DiagnosticList,
    severity: Severity,
    rule_id: []const u8,
    message: []const u8,
    span: ast.Span,
    fix: Fix,
) Allocator.Error!void {
    return addDiagnosticWithFixes(
        allocator,
        diagnostics,
        severity,
        rule_id,
        message,
        span,
        &.{fix},
    );
}

pub fn addDiagnosticWithFixes(
    allocator: Allocator,
    diagnostics: *DiagnosticList,
    severity: Severity,
    rule_id: []const u8,
    message: []const u8,
    span: ast.Span,
    fixes: []const Fix,
) Allocator.Error!void {
    return addDiagnosticWithFixesAndSuggestions(
        allocator,
        diagnostics,
        severity,
        rule_id,
        message,
        span,
        fixes,
        &.{},
    );
}

pub fn addDiagnosticWithSuggestions(
    allocator: Allocator,
    diagnostics: *DiagnosticList,
    severity: Severity,
    rule_id: []const u8,
    message: []const u8,
    span: ast.Span,
    suggestions: []const Suggestion,
) Allocator.Error!void {
    return addDiagnosticWithFixesAndSuggestions(
        allocator,
        diagnostics,
        severity,
        rule_id,
        message,
        span,
        &.{},
        suggestions,
    );
}

pub fn addDiagnosticWithFixesAndSuggestions(
    allocator: Allocator,
    diagnostics: *DiagnosticList,
    severity: Severity,
    rule_id: []const u8,
    message: []const u8,
    span: ast.Span,
    fixes: []const Fix,
    suggestions: []const Suggestion,
) Allocator.Error!void {
    const owned_message = try allocator.dupe(u8, message);
    errdefer allocator.free(owned_message);

    const owned_fixes = try dupeFixes(allocator, fixes);
    errdefer freeFixes(allocator, owned_fixes);

    const owned_suggestions = try dupeSuggestions(allocator, suggestions);
    errdefer freeSuggestions(allocator, owned_suggestions);

    try diagnostics.append(allocator, .{
        .rule_id = rule_id,
        .message = owned_message,
        .span = span,
        .severity = severity,
        .fixes = owned_fixes,
        .suggestions = owned_suggestions,
    });
}

pub fn addDiagnosticFmt(
    allocator: Allocator,
    diagnostics: *DiagnosticList,
    severity: Severity,
    rule_id: []const u8,
    span: ast.Span,
    comptime fmt: []const u8,
    args: anytype,
) Allocator.Error!void {
    const owned_message = try std.fmt.allocPrint(allocator, fmt, args);
    errdefer allocator.free(owned_message);

    try diagnostics.append(allocator, .{
        .rule_id = rule_id,
        .message = owned_message,
        .span = span,
        .severity = severity,
        .fixes = &.{},
    });
}

pub fn freeDiagnostics(allocator: Allocator, diagnostics: *DiagnosticList) void {
    for (diagnostics.items) |diagnostic| {
        freeDiagnostic(allocator, diagnostic);
    }
    diagnostics.deinit(allocator);
}

fn dupeFixes(allocator: Allocator, fixes: []const Fix) Allocator.Error![]Fix {
    if (fixes.len == 0) return &.{};

    const owned = try allocator.alloc(Fix, fixes.len);
    var initialized: usize = 0;
    errdefer {
        for (owned[0..initialized]) |fix| allocator.free(fix.replacement);
        allocator.free(owned);
    }

    for (fixes, 0..) |fix, index| {
        owned[index] = .{
            .span = fix.span,
            .replacement = try allocator.dupe(u8, fix.replacement),
        };
        initialized += 1;
    }
    return owned;
}

fn dupeSuggestions(allocator: Allocator, suggestions: []const Suggestion) Allocator.Error![]Suggestion {
    if (suggestions.len == 0) return &.{};

    const owned = try allocator.alloc(Suggestion, suggestions.len);
    var initialized: usize = 0;
    errdefer {
        for (owned[0..initialized]) |suggestion| {
            allocator.free(suggestion.message);
            freeFixes(allocator, suggestion.fixes);
        }
        allocator.free(owned);
    }

    for (suggestions, 0..) |suggestion, index| {
        const owned_message = try allocator.dupe(u8, suggestion.message);
        errdefer allocator.free(owned_message);
        owned[index] = .{
            .message = owned_message,
            .fixes = try dupeFixes(allocator, suggestion.fixes),
        };
        initialized += 1;
    }
    return owned;
}

fn freeSuggestions(allocator: Allocator, suggestions: []Suggestion) void {
    for (suggestions) |suggestion| {
        allocator.free(suggestion.message);
        freeFixes(allocator, suggestion.fixes);
    }
    if (suggestions.len > 0) allocator.free(suggestions);
}

pub fn freeDiagnostic(allocator: Allocator, diagnostic: Diagnostic) void {
    allocator.free(diagnostic.message);
    freeFixes(allocator, diagnostic.fixes);
    freeSuggestions(allocator, diagnostic.suggestions);
    if (diagnostic.suppressions.len > 0) {
        for (diagnostic.suppressions) |suppression| allocator.free(suppression.justification);
        allocator.free(diagnostic.suppressions);
    } else if (diagnostic.suppression) |suppression| {
        allocator.free(suppression.justification);
    }
}

pub fn freeDiagnosticSlice(allocator: Allocator, diagnostics: []Diagnostic) void {
    for (diagnostics) |diagnostic| freeDiagnostic(allocator, diagnostic);
    if (diagnostics.len > 0) allocator.free(diagnostics);
}

fn freeFixes(allocator: Allocator, fixes: []const Fix) void {
    for (fixes) |fix| allocator.free(fix.replacement);
    if (fixes.len > 0) allocator.free(fixes);
}

pub fn isKnownGlobal(name: []const u8) bool {
    const globals = [_][]const u8{
        "alert",
        "Array",
        "BigInt",
        "Boolean",
        "Buffer",
        "confirm",
        "Date",
        "Error",
        "Headers",
        "Infinity",
        "Intl",
        "isFinite",
        "isNaN",
        "JSON",
        "Map",
        "Math",
        "NaN",
        "Number",
        "Object",
        "Promise",
        "RegExp",
        "Request",
        "Response",
        "Set",
        "String",
        "Symbol",
        "URL",
        "URLSearchParams",
        "WeakMap",
        "WeakSet",
        "__dirname",
        "__filename",
        "clearInterval",
        "clearTimeout",
        "console",
        "document",
        "exports",
        "fetch",
        "global",
        "globalThis",
        "module",
        "process",
        "prompt",
        "queueMicrotask",
        "require",
        "setInterval",
        "setTimeout",
        "undefined",
        "window",
    };

    for (globals) |global| {
        if (std.mem.eql(u8, name, global)) return true;
    }

    return false;
}

test "Options can enable rules by CLI name" {
    var options = Options.allDisabled();

    try std.testing.expect(!options.no_debugger);
    try std.testing.expect(options.setByCliName("no-debugger", true));
    try std.testing.expect(options.no_debugger);

    try std.testing.expect(!options.typescript_eslint_no_unused_vars);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-unused-vars", true));
    try std.testing.expect(options.typescript_eslint_no_unused_vars);
    try std.testing.expect(!options.no_unused_vars);

    try std.testing.expect(!options.typescript_eslint_no_inferrable_types);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-inferrable-types", true));
    try std.testing.expect(options.typescript_eslint_no_inferrable_types);
    try std.testing.expect(!options.typescript_eslint_no_inferrable_types_ignore_parameters);
    try std.testing.expect(!options.typescript_eslint_no_inferrable_types_ignore_properties);

    try std.testing.expect(!options.typescript_eslint_no_empty_interface);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-empty-interface", true));
    try std.testing.expect(options.typescript_eslint_no_empty_interface);
    try std.testing.expect(!options.typescript_eslint_no_empty_interface_allow_single_extends);

    try std.testing.expect(!options.typescript_eslint_no_empty_object_type);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-empty-object-type", true));
    try std.testing.expect(options.typescript_eslint_no_empty_object_type);
    try std.testing.expectEqual(TypescriptEslintNoEmptyObjectTypeAllowInterfaces.never, options.typescript_eslint_no_empty_object_type_allow_interfaces);
    try std.testing.expectEqual(TypescriptEslintNoEmptyObjectTypeAllowObjectTypes.never, options.typescript_eslint_no_empty_object_type_allow_object_types);

    try std.testing.expect(!options.typescript_eslint_restrict_plus_operands);
    try std.testing.expect(options.setByCliName("@typescript-eslint/restrict-plus-operands", true));
    try std.testing.expect(options.typescript_eslint_restrict_plus_operands);
    try std.testing.expect(!options.typescript_eslint_restrict_plus_operands_allow_number_and_string);

    try std.testing.expect(!options.typescript_eslint_no_duplicate_enum_values);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-duplicate-enum-values", true));
    try std.testing.expect(options.typescript_eslint_no_duplicate_enum_values);

    try std.testing.expect(!options.typescript_eslint_no_useless_empty_export);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-useless-empty-export", true));
    try std.testing.expect(options.typescript_eslint_no_useless_empty_export);

    try std.testing.expect(!options.typescript_eslint_no_wrapper_object_types);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-wrapper-object-types", true));
    try std.testing.expect(options.typescript_eslint_no_wrapper_object_types);

    try std.testing.expect(!options.typescript_eslint_no_unnecessary_parameter_property_assignment);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-unnecessary-parameter-property-assignment", true));
    try std.testing.expect(options.typescript_eslint_no_unnecessary_parameter_property_assignment);

    try std.testing.expect(!options.typescript_eslint_no_require_imports);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-require-imports", true));
    try std.testing.expect(options.typescript_eslint_no_require_imports);
    try std.testing.expect(!options.typescript_eslint_no_require_imports_allow_as_import);
    try std.testing.expectEqual(@as(usize, 0), options.typescript_eslint_no_require_imports_allow.count);

    try std.testing.expect(!options.typescript_eslint_no_unsafe_declaration_merging);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-unsafe-declaration-merging", true));
    try std.testing.expect(options.typescript_eslint_no_unsafe_declaration_merging);

    try std.testing.expect(!options.promise_valid_params);
    try std.testing.expect(options.setByCliName("promise/valid-params", true));
    try std.testing.expect(options.promise_valid_params);

    try std.testing.expect(!options.promise_param_names);
    try std.testing.expect(options.setByCliName("promise/param-names", true));
    try std.testing.expect(options.promise_param_names);

    try std.testing.expect(!options.promise_no_return_wrap);
    try std.testing.expect(options.setByCliName("promise/no-return-wrap", true));
    try std.testing.expect(options.promise_no_return_wrap);

    try std.testing.expect(!options.promise_no_return_in_finally);
    try std.testing.expect(options.setByCliName("promise/no-return-in-finally", true));
    try std.testing.expect(options.promise_no_return_in_finally);

    try std.testing.expect(!options.promise_no_promise_in_callback);
    try std.testing.expect(options.setByCliName("promise/no-promise-in-callback", true));
    try std.testing.expect(options.promise_no_promise_in_callback);

    try std.testing.expect(!options.promise_no_new_statics);
    try std.testing.expect(options.setByCliName("promise/no-new-statics", true));
    try std.testing.expect(options.promise_no_new_statics);

    try std.testing.expect(!options.promise_no_nesting);
    try std.testing.expect(options.setByCliName("promise/no-nesting", true));
    try std.testing.expect(options.promise_no_nesting);

    try std.testing.expect(!options.promise_no_callback_in_promise);
    try std.testing.expect(options.setByCliName("promise/no-callback-in-promise", true));
    try std.testing.expect(options.promise_no_callback_in_promise);

    try std.testing.expect(!options.promise_catch_or_return);
    try std.testing.expect(options.setByCliName("promise/catch-or-return", true));
    try std.testing.expect(options.promise_catch_or_return);

    try std.testing.expect(!options.promise_always_return);
    try std.testing.expect(options.setByCliName("promise/always-return", true));
    try std.testing.expect(options.promise_always_return);

    try std.testing.expect(!options.typescript_eslint_no_unsafe_function_type);
    try std.testing.expect(options.setByCliName("@typescript-eslint/no-unsafe-function-type", true));
    try std.testing.expect(options.typescript_eslint_no_unsafe_function_type);

    try std.testing.expect(!options.jsx_a11y_aria_props);
    try std.testing.expect(options.setByCliName("jsx-a11y/aria-props", true));
    try std.testing.expect(options.jsx_a11y_aria_props);

    try std.testing.expect(!options.react_jsx_no_target_blank);
    try std.testing.expect(options.setByCliName("react/jsx-no-target-blank", true));
    try std.testing.expect(options.react_jsx_no_target_blank);
    try std.testing.expect(!options.react_jsx_no_target_blank_allow_referrer);
    try std.testing.expect(options.react_jsx_no_target_blank_enforce_dynamic_links);
    try std.testing.expect(options.react_jsx_no_target_blank_links);
    try std.testing.expect(!options.react_jsx_no_target_blank_forms);

    try std.testing.expect(!options.import_no_duplicates);
    try std.testing.expect(options.setByCliName("import/no-duplicates", true));
    try std.testing.expect(options.import_no_duplicates);
    try std.testing.expect(!options.import_no_duplicates_consider_query_string);

    try std.testing.expect(!options.alipay_ant_no_import_src);
    try std.testing.expect(options.setByCliName("@alipay/ant/no-import-src", true));
    try std.testing.expect(options.alipay_ant_no_import_src);

    try std.testing.expect(!options.alipay_ant_no_phantom_dependencies);
    try std.testing.expect(options.setByCliName("@alipay/ant/no-phantom-dependencies", true));
    try std.testing.expect(options.alipay_ant_no_phantom_dependencies);

    try std.testing.expect(!options.alipay_ant_disallow_typos);
    try std.testing.expect(options.setByCliName("@alipay/ant/disallow-typos", true));
    try std.testing.expect(options.alipay_ant_disallow_typos);

    try std.testing.expect(!options.alipay_spmlint_use_labeled_spm);
    try std.testing.expect(options.setByCliName("@alipay/spmLint/use-labeled-spm", true));
    try std.testing.expect(options.alipay_spmlint_use_labeled_spm);

    try std.testing.expect(!options.alipay_spmlint_valid_manual_click);
    try std.testing.expect(options.setByCliName("@alipay/spmLint/valid-manual-click", true));
    try std.testing.expect(options.alipay_spmlint_valid_manual_click);

    try std.testing.expect(!options.alipay_spmlint_valid_manual_expo);
    try std.testing.expect(options.setByCliName("@alipay/spmLint/valid-manual-expo", true));
    try std.testing.expect(options.alipay_spmlint_valid_manual_expo);

    try std.testing.expect(!options.alipay_spmlint_valid_manual_param);
    try std.testing.expect(options.setByCliName("@alipay/spmLint/valid-manual-param", true));
    try std.testing.expect(options.alipay_spmlint_valid_manual_param);

    try std.testing.expect(!options.alipay_spmlint_valid_manual_pv);
    try std.testing.expect(options.setByCliName("@alipay/spmLint/valid-manual-pv", true));
    try std.testing.expect(options.alipay_spmlint_valid_manual_pv);

    try std.testing.expect(!options.import_default);
    try std.testing.expect(options.setByCliName("import/default", true));
    try std.testing.expect(options.import_default);

    try std.testing.expect(!options.import_export);
    try std.testing.expect(options.setByCliName("import/export", true));
    try std.testing.expect(options.import_export);

    try std.testing.expect(!options.import_named);
    try std.testing.expect(options.setByCliName("import/named", true));
    try std.testing.expect(options.import_named);

    try std.testing.expect(!options.import_namespace);
    try std.testing.expect(options.setByCliName("import/namespace", true));
    try std.testing.expect(options.import_namespace);

    try std.testing.expect(!options.import_no_cycle);
    try std.testing.expect(options.setByCliName("import/no-cycle", true));
    try std.testing.expect(options.import_no_cycle);
    try std.testing.expect(!options.import_no_cycle_amd);
    try std.testing.expect(!options.import_no_cycle_commonjs);
    try std.testing.expectEqual(@as(usize, 1024), options.import_no_cycle_max_depth);

    try std.testing.expect(!options.import_no_named_as_default);
    try std.testing.expect(options.setByCliName("import/no-named-as-default", true));
    try std.testing.expect(options.import_no_named_as_default);

    try std.testing.expect(!options.import_no_named_as_default_member);
    try std.testing.expect(options.setByCliName("import/no-named-as-default-member", true));
    try std.testing.expect(options.import_no_named_as_default_member);

    try std.testing.expect(!options.import_no_unresolved);
    try std.testing.expect(options.setByCliName("import/no-unresolved", true));
    try std.testing.expect(options.import_no_unresolved);
    try std.testing.expect(!options.import_no_unresolved_amd);
    try std.testing.expect(!options.import_no_unresolved_commonjs);
    try std.testing.expectEqual(@as(usize, 0), options.import_no_unresolved_ignore.count);

    try std.testing.expect(!options.react_default_props_match_prop_types);
    try std.testing.expect(options.setByCliName("react/default-props-match-prop-types", true));
    try std.testing.expect(options.react_default_props_match_prop_types);

    try std.testing.expect(!options.react_button_has_type);
    try std.testing.expect(options.setByCliName("react/button-has-type", true));
    try std.testing.expect(options.react_button_has_type);
    try std.testing.expect(options.react_button_has_type_button);
    try std.testing.expect(options.react_button_has_type_submit);
    try std.testing.expect(options.react_button_has_type_reset);

    try std.testing.expect(!options.react_forbid_prop_types);
    try std.testing.expect(options.setByCliName("react/forbid-prop-types", true));
    try std.testing.expect(options.react_forbid_prop_types);
    try std.testing.expect(options.react_forbid_prop_types_forbid_any);
    try std.testing.expect(options.react_forbid_prop_types_forbid_array);
    try std.testing.expect(options.react_forbid_prop_types_forbid_object);

    try std.testing.expect(!options.react_jsx_filename_extension);
    try std.testing.expect(options.setByCliName("react/jsx-filename-extension", true));
    try std.testing.expect(options.react_jsx_filename_extension);
    try std.testing.expectEqual(react_jsx_filename_extension_default_extensions.len, options.react_jsx_filename_extension_extensions.len());

    try std.testing.expect(!options.react_jsx_no_bind);
    try std.testing.expect(options.setByCliName("react/jsx-no-bind", true));
    try std.testing.expect(options.react_jsx_no_bind);
    try std.testing.expect(!options.react_jsx_no_bind_allow_arrow_functions);
    try std.testing.expect(!options.react_jsx_no_bind_allow_functions);
    try std.testing.expect(!options.react_jsx_no_bind_allow_bind);
    try std.testing.expect(!options.react_jsx_no_bind_ignore_refs);
    try std.testing.expect(!options.react_jsx_no_bind_ignore_dom_components);

    try std.testing.expect(!options.react_jsx_key);
    try std.testing.expect(options.setByCliName("react/jsx-key", true));
    try std.testing.expect(options.react_jsx_key);
    try std.testing.expect(!options.react_jsx_key_check_key_must_before_spread);
    try std.testing.expect(!options.react_jsx_key_warn_on_duplicates);

    try std.testing.expect(!options.react_prop_types);
    try std.testing.expect(options.setByCliName("react/prop-types", true));
    try std.testing.expect(options.react_prop_types);
    try std.testing.expect(!options.react_prop_types_skip_undeclared);

    try std.testing.expect(!options.react_no_unused_prop_types);
    try std.testing.expect(options.setByCliName("react/no-unused-prop-types", true));
    try std.testing.expect(options.react_no_unused_prop_types);
    try std.testing.expect(options.react_no_unused_prop_types_skip_shape_props);
    try std.testing.expectEqual(@as(usize, 0), options.react_jsx_pascal_case_ignore.count);

    try std.testing.expect(!options.react_no_string_refs);
    try std.testing.expect(options.setByCliName("react/no-string-refs", true));
    try std.testing.expect(options.react_no_string_refs);
    try std.testing.expect(!options.react_no_string_refs_no_template_literals);

    try std.testing.expect(!options.react_no_multi_comp);
    try std.testing.expect(options.setByCliName("react/no-multi-comp", true));
    try std.testing.expect(options.react_no_multi_comp);
    try std.testing.expect(options.react_no_multi_comp_ignore_stateless);

    try std.testing.expect(!options.react_no_unknown_property);
    try std.testing.expect(options.setByCliName("react/no-unknown-property", true));
    try std.testing.expect(options.react_no_unknown_property);
    try std.testing.expectEqual(@as(usize, 0), options.react_no_unknown_property_ignore.count);
    try std.testing.expect(!options.react_no_unknown_property_require_data_lowercase);

    try std.testing.expect(!options.react_self_closing_comp);
    try std.testing.expect(options.setByCliName("react/self-closing-comp", true));
    try std.testing.expect(options.react_self_closing_comp);
    try std.testing.expect(options.react_self_closing_comp_component);
    try std.testing.expect(options.react_self_closing_comp_html);

    try std.testing.expect(!options.react_no_unescaped_entities);
    try std.testing.expect(options.setByCliName("react/no-unescaped-entities", true));
    try std.testing.expect(options.react_no_unescaped_entities);
    try std.testing.expect(options.react_no_unescaped_entities_forbid_gt);
    try std.testing.expect(options.react_no_unescaped_entities_forbid_double_quote);
    try std.testing.expect(options.react_no_unescaped_entities_forbid_single_quote);
    try std.testing.expect(options.react_no_unescaped_entities_forbid_closing_brace);

    try std.testing.expect(!options.react_hooks_rules_of_hooks);
    try std.testing.expect(options.setByCliName("react-hooks/rules-of-hooks", true));
    try std.testing.expect(options.react_hooks_rules_of_hooks);

    try std.testing.expect(!options.jest_no_conditional_expect);
    try std.testing.expect(options.setByCliName("jest/no-conditional-expect", true));
    try std.testing.expect(options.jest_no_conditional_expect);

    try std.testing.expect(!options.jest_no_deprecated_functions);
    try std.testing.expect(options.setByCliName("jest/no-deprecated-functions", true));
    try std.testing.expect(options.jest_no_deprecated_functions);

    try std.testing.expect(!options.jest_no_export);
    try std.testing.expect(options.setByCliName("jest/no-export", true));
    try std.testing.expect(options.jest_no_export);

    try std.testing.expect(!options.jest_no_focused_tests);
    try std.testing.expect(options.setByCliName("jest/no-focused-tests", true));
    try std.testing.expect(options.jest_no_focused_tests);

    try std.testing.expect(!options.jest_no_identical_title);
    try std.testing.expect(options.setByCliName("jest/no-identical-title", true));
    try std.testing.expect(options.jest_no_identical_title);

    try std.testing.expect(!options.jest_no_interpolation_in_snapshots);
    try std.testing.expect(options.setByCliName("jest/no-interpolation-in-snapshots", true));
    try std.testing.expect(options.jest_no_interpolation_in_snapshots);

    try std.testing.expect(!options.jest_no_jasmine_globals);
    try std.testing.expect(options.setByCliName("jest/no-jasmine-globals", true));
    try std.testing.expect(options.jest_no_jasmine_globals);

    try std.testing.expect(!options.jest_no_mocks_import);
    try std.testing.expect(options.setByCliName("jest/no-mocks-import", true));
    try std.testing.expect(options.jest_no_mocks_import);

    try std.testing.expect(!options.jest_no_standalone_expect);
    try std.testing.expect(options.setByCliName("jest/no-standalone-expect", true));
    try std.testing.expect(options.jest_no_standalone_expect);

    try std.testing.expect(!options.jest_valid_describe_callback);
    try std.testing.expect(options.setByCliName("jest/valid-describe-callback", true));
    try std.testing.expect(options.jest_valid_describe_callback);

    try std.testing.expect(!options.jest_valid_expect_in_promise);
    try std.testing.expect(options.setByCliName("jest/valid-expect-in-promise", true));
    try std.testing.expect(options.jest_valid_expect_in_promise);

    try std.testing.expect(!options.jest_valid_expect);
    try std.testing.expect(options.setByCliName("jest/valid-expect", true));
    try std.testing.expect(options.jest_valid_expect);

    try std.testing.expect(!options.jest_valid_title);
    try std.testing.expect(options.setByCliName("jest/valid-title", true));
    try std.testing.expect(options.jest_valid_title);

    try std.testing.expect(!options.unused_imports_no_unused_imports);
    try std.testing.expect(options.setByCliName("unused-imports/no-unused-imports", true));
    try std.testing.expect(options.unused_imports_no_unused_imports);

    try std.testing.expect(!options.setByCliName("unknown-rule", true));
}

test "Options can apply ESLint-style rule config values" {
    var options = Options{};

    try options.setByRuleConfigValue("no-debugger", .{ .string = "off" });
    try std.testing.expect(!options.no_debugger);

    try options.setByRuleConfigValue("no-debugger", .{ .integer = 2 });
    try std.testing.expect(options.no_debugger);

    var array = std.json.Array.init(std.testing.allocator);
    defer array.deinit();
    try array.append(.{ .string = "warn" });
    try options.setByRuleConfigValue("jsx-a11y/aria-props", .{ .array = array });
    try std.testing.expect(options.jsx_a11y_aria_props);

    var jsx_a11y_alt_text_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"elements\":[\"img\",\"input[type=\\\"image\\\"]\"],\"img\":[\"Image\"],\"object\":[\"Object\"],\"area\":[\"Area\"],\"input[type=\\\"image\\\"]\":[\"InputImage\"]}]",
        .{},
    );
    defer jsx_a11y_alt_text_config.deinit();
    try options.setByRuleConfigValue("jsx-a11y/alt-text", jsx_a11y_alt_text_config.value);
    try std.testing.expect(options.jsx_a11y_alt_text);
    try std.testing.expect(options.jsx_a11y_alt_text_img);
    try std.testing.expect(!options.jsx_a11y_alt_text_object);
    try std.testing.expect(!options.jsx_a11y_alt_text_area);
    try std.testing.expect(options.jsx_a11y_alt_text_input_image);
    try std.testing.expect(options.jsx_a11y_alt_text_img_components.contains("Image"));
    try std.testing.expect(options.jsx_a11y_alt_text_object_components.contains("Object"));
    try std.testing.expect(options.jsx_a11y_alt_text_area_components.contains("Area"));
    try std.testing.expect(options.jsx_a11y_alt_text_input_image_components.contains("InputImage"));

    var jsx_a11y_anchor_has_content_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"components\":[\"Anchor\"]}]",
        .{},
    );
    defer jsx_a11y_anchor_has_content_config.deinit();
    try options.setByRuleConfigValue("jsx-a11y/anchor-has-content", jsx_a11y_anchor_has_content_config.value);
    try std.testing.expect(options.jsx_a11y_anchor_has_content);
    try std.testing.expect(options.jsx_a11y_anchor_has_content_components.contains("Anchor"));
    try std.testing.expect(!options.jsx_a11y_anchor_has_content_components.contains("Link"));

    var jsx_a11y_aria_role_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowedInvalidRoles\":[\"text\"],\"ignoreNonDOM\":false}]",
        .{},
    );
    defer jsx_a11y_aria_role_config.deinit();
    try options.setByRuleConfigValue("jsx-a11y/aria-role", jsx_a11y_aria_role_config.value);
    try std.testing.expect(options.jsx_a11y_aria_role);
    try std.testing.expect(options.jsx_a11y_aria_role_allowed_invalid_roles.contains("text"));
    try std.testing.expect(!options.jsx_a11y_aria_role_allowed_invalid_roles.contains("datepicker"));
    try std.testing.expect(!options.jsx_a11y_aria_role_ignore_non_dom);

    var jsx_a11y_img_redundant_alt_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"components\":[\"Image\"],\"words\":[\"Bild\"]}]",
        .{},
    );
    defer jsx_a11y_img_redundant_alt_config.deinit();
    try options.setByRuleConfigValue("jsx-a11y/img-redundant-alt", jsx_a11y_img_redundant_alt_config.value);
    try std.testing.expect(options.jsx_a11y_img_redundant_alt);
    try std.testing.expect(options.jsx_a11y_img_redundant_alt_components.contains("Image"));
    try std.testing.expect(!options.jsx_a11y_img_redundant_alt_components.contains("Picture"));
    try std.testing.expect(options.jsx_a11y_img_redundant_alt_words.containsIgnoreCase("bild"));
    try std.testing.expect(!options.jsx_a11y_img_redundant_alt_words.containsIgnoreCase("foto"));

    var jsx_a11y_no_distracting_elements_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"elements\":[\"blink\"]}]",
        .{},
    );
    defer jsx_a11y_no_distracting_elements_config.deinit();
    try options.setByRuleConfigValue("jsx-a11y/no-distracting-elements", jsx_a11y_no_distracting_elements_config.value);
    try std.testing.expect(options.jsx_a11y_no_distracting_elements);
    try std.testing.expect(!options.jsx_a11y_no_distracting_elements_marquee);
    try std.testing.expect(options.jsx_a11y_no_distracting_elements_blink);

    try options.setByRuleConfigValue("prettier/prettier", .{ .string = "error" });

    var react_button_has_type_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"button\":true,\"submit\":false,\"reset\":false}]",
        .{},
    );
    defer react_button_has_type_config.deinit();
    try options.setByRuleConfigValue("react/button-has-type", react_button_has_type_config.value);
    try std.testing.expect(options.react_button_has_type);
    try std.testing.expect(options.react_button_has_type_button);
    try std.testing.expect(!options.react_button_has_type_submit);
    try std.testing.expect(!options.react_button_has_type_reset);

    var react_forbid_prop_types_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"forbid\":[\"array\"]}]",
        .{},
    );
    defer react_forbid_prop_types_config.deinit();
    try options.setByRuleConfigValue("react/forbid-prop-types", react_forbid_prop_types_config.value);
    try std.testing.expect(options.react_forbid_prop_types);
    try std.testing.expect(!options.react_forbid_prop_types_forbid_any);
    try std.testing.expect(options.react_forbid_prop_types_forbid_array);
    try std.testing.expect(!options.react_forbid_prop_types_forbid_object);
    try std.testing.expect(!options.react_forbid_prop_types_check_context_types);
    try std.testing.expect(!options.react_forbid_prop_types_check_child_context_types);

    var react_forbid_prop_types_context_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"checkContextTypes\":true,\"checkChildContextTypes\":true}]",
        .{},
    );
    defer react_forbid_prop_types_context_config.deinit();
    try options.setByRuleConfigValue("react/forbid-prop-types", react_forbid_prop_types_context_config.value);
    try std.testing.expect(options.react_forbid_prop_types);
    try std.testing.expect(options.react_forbid_prop_types_check_context_types);
    try std.testing.expect(options.react_forbid_prop_types_check_child_context_types);

    var react_default_props_match_prop_types_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowRequiredDefaults\":true}]",
        .{},
    );
    defer react_default_props_match_prop_types_config.deinit();
    try options.setByRuleConfigValue("react/default-props-match-prop-types", react_default_props_match_prop_types_config.value);
    try std.testing.expect(options.react_default_props_match_prop_types);
    try std.testing.expect(options.react_default_props_match_prop_types_allow_required_defaults);

    var react_display_name_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"checkContextObjects\":true}]",
        .{},
    );
    defer react_display_name_config.deinit();
    try options.setByRuleConfigValue("react/display-name", react_display_name_config.value);
    try std.testing.expect(options.react_display_name);
    try std.testing.expect(options.react_display_name_check_context_objects);

    var react_display_name_ignore_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreTranspilerName\":true}]",
        .{},
    );
    defer react_display_name_ignore_config.deinit();
    try options.setByRuleConfigValue("react/display-name", react_display_name_ignore_config.value);
    try std.testing.expect(options.react_display_name);
    try std.testing.expect(options.react_display_name_ignore_transpiler_name);

    var react_jsx_filename_extension_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"extensions\":[\".tsx\"]}]",
        .{},
    );
    defer react_jsx_filename_extension_config.deinit();
    try options.setByRuleConfigValue("react/jsx-filename-extension", react_jsx_filename_extension_config.value);
    try std.testing.expect(options.react_jsx_filename_extension);
    try std.testing.expectEqual(@as(usize, 1), options.react_jsx_filename_extension_extensions.len());
    try std.testing.expectEqualStrings(".tsx", options.react_jsx_filename_extension_extensions.at(0));
    try std.testing.expectEqual(ReactJsxFilenameExtensionAllow.always, options.react_jsx_filename_extension_allow);

    var react_jsx_filename_extension_allow_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":\"as-needed\"}]",
        .{},
    );
    defer react_jsx_filename_extension_allow_config.deinit();
    try options.setByRuleConfigValue("react/jsx-filename-extension", react_jsx_filename_extension_allow_config.value);
    try std.testing.expect(options.react_jsx_filename_extension);
    try std.testing.expectEqual(ReactJsxFilenameExtensionAllow.as_needed, options.react_jsx_filename_extension_allow);

    var react_jsx_no_bind_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowArrowFunctions\":true,\"allowFunctions\":true,\"allowBind\":true,\"ignoreRefs\":true,\"ignoreDOMComponents\":true}]",
        .{},
    );
    defer react_jsx_no_bind_config.deinit();
    try options.setByRuleConfigValue("react/jsx-no-bind", react_jsx_no_bind_config.value);
    try std.testing.expect(options.react_jsx_no_bind);
    try std.testing.expect(options.react_jsx_no_bind_allow_arrow_functions);
    try std.testing.expect(options.react_jsx_no_bind_allow_functions);
    try std.testing.expect(options.react_jsx_no_bind_allow_bind);
    try std.testing.expect(options.react_jsx_no_bind_ignore_refs);
    try std.testing.expect(options.react_jsx_no_bind_ignore_dom_components);

    var react_jsx_key_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"checkKeyMustBeforeSpread\":true,\"checkFragmentShorthand\":true,\"warnOnDuplicates\":true}]",
        .{},
    );
    defer react_jsx_key_config.deinit();
    try options.setByRuleConfigValue("react/jsx-key", react_jsx_key_config.value);
    try std.testing.expect(options.react_jsx_key);
    try std.testing.expect(options.react_jsx_key_check_key_must_before_spread);
    try std.testing.expect(options.react_jsx_key_check_fragment_shorthand);
    try std.testing.expect(options.react_jsx_key_warn_on_duplicates);

    var react_jsx_no_target_blank_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowReferrer\":true,\"enforceDynamicLinks\":\"never\",\"warnOnSpreadAttributes\":true,\"links\":false,\"forms\":true}]",
        .{},
    );
    defer react_jsx_no_target_blank_config.deinit();
    try options.setByRuleConfigValue("react/jsx-no-target-blank", react_jsx_no_target_blank_config.value);
    try std.testing.expect(options.react_jsx_no_target_blank);
    try std.testing.expect(options.react_jsx_no_target_blank_allow_referrer);
    try std.testing.expect(!options.react_jsx_no_target_blank_enforce_dynamic_links);
    try std.testing.expect(options.react_jsx_no_target_blank_warn_on_spread_attributes);
    try std.testing.expect(!options.react_jsx_no_target_blank_links);
    try std.testing.expect(options.react_jsx_no_target_blank_forms);

    var react_jsx_pascal_case_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowAllCaps\":false,\"allowLeadingUnderscore\":true,\"allowNamespace\":true,\"ignore\":[\"bar\",\"Legacy_widget\"]}]",
        .{},
    );
    defer react_jsx_pascal_case_config.deinit();
    try options.setByRuleConfigValue("react/jsx-pascal-case", react_jsx_pascal_case_config.value);
    try std.testing.expect(options.react_jsx_pascal_case);
    try std.testing.expect(!options.react_jsx_pascal_case_allow_all_caps);
    try std.testing.expect(options.react_jsx_pascal_case_allow_leading_underscore);
    try std.testing.expect(options.react_jsx_pascal_case_allow_namespace);
    try std.testing.expect(options.react_jsx_pascal_case_ignore.contains("bar"));
    try std.testing.expect(options.react_jsx_pascal_case_ignore.contains("Legacy_widget"));
    try std.testing.expect(!options.react_jsx_pascal_case_ignore.contains("other"));

    var react_prop_types_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"skipUndeclared\":true,\"ignore\":[\"name\",\"user\"]}]",
        .{},
    );
    defer react_prop_types_config.deinit();
    try options.setByRuleConfigValue("react/prop-types", react_prop_types_config.value);
    try std.testing.expect(options.react_prop_types);
    try std.testing.expect(options.react_prop_types_skip_undeclared);
    try std.testing.expect(options.react_prop_types_ignore.contains("name"));
    try std.testing.expect(options.react_prop_types_ignore.ignoresPath("user.name"));
    try std.testing.expect(!options.react_prop_types_ignore.contains("age"));

    var react_prop_types_custom_validators_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"customValidators\":[\"CustomValidator\"]}]",
        .{},
    );
    defer react_prop_types_custom_validators_config.deinit();
    try options.setByRuleConfigValue("react/prop-types", react_prop_types_custom_validators_config.value);
    try std.testing.expect(options.react_prop_types_custom_validators.contains("CustomValidator"));
    try std.testing.expect(!options.react_prop_types_custom_validators.contains("OtherValidator"));

    var react_no_string_refs_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"noTemplateLiterals\":true}]",
        .{},
    );
    defer react_no_string_refs_config.deinit();
    try options.setByRuleConfigValue("react/no-string-refs", react_no_string_refs_config.value);
    try std.testing.expect(options.react_no_string_refs);
    try std.testing.expect(options.react_no_string_refs_no_template_literals);

    var react_no_multi_comp_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreStateless\":false}]",
        .{},
    );
    defer react_no_multi_comp_config.deinit();
    try options.setByRuleConfigValue("react/no-multi-comp", react_no_multi_comp_config.value);
    try std.testing.expect(options.react_no_multi_comp);
    try std.testing.expect(!options.react_no_multi_comp_ignore_stateless);

    var react_no_children_prop_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowFunctions\":true}]",
        .{},
    );
    defer react_no_children_prop_config.deinit();
    try options.setByRuleConfigValue("react/no-children-prop", react_no_children_prop_config.value);
    try std.testing.expect(options.react_no_children_prop);
    try std.testing.expect(options.react_no_children_prop_allow_functions);

    var react_no_unknown_property_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignore\":[\"class\",\"data-Foo\"],\"requireDataLowercase\":true}]",
        .{},
    );
    defer react_no_unknown_property_config.deinit();
    try options.setByRuleConfigValue("react/no-unknown-property", react_no_unknown_property_config.value);
    try std.testing.expect(options.react_no_unknown_property);
    try std.testing.expect(options.react_no_unknown_property_ignore.contains("class"));
    try std.testing.expect(options.react_no_unknown_property_ignore.contains("data-Foo"));
    try std.testing.expect(!options.react_no_unknown_property_ignore.contains("other"));
    try std.testing.expect(options.react_no_unknown_property_require_data_lowercase);

    var react_self_closing_comp_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"component\":false,\"html\":true}]",
        .{},
    );
    defer react_self_closing_comp_config.deinit();
    try options.setByRuleConfigValue("react/self-closing-comp", react_self_closing_comp_config.value);
    try std.testing.expect(options.react_self_closing_comp);
    try std.testing.expect(!options.react_self_closing_comp_component);
    try std.testing.expect(options.react_self_closing_comp_html);

    var react_no_unescaped_entities_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"forbid\":[\">\",{\"char\":\"}\"}]}]",
        .{},
    );
    defer react_no_unescaped_entities_config.deinit();
    try options.setByRuleConfigValue("react/no-unescaped-entities", react_no_unescaped_entities_config.value);
    try std.testing.expect(options.react_no_unescaped_entities);
    try std.testing.expect(options.react_no_unescaped_entities_forbid_gt);
    try std.testing.expect(!options.react_no_unescaped_entities_forbid_double_quote);
    try std.testing.expect(!options.react_no_unescaped_entities_forbid_single_quote);
    try std.testing.expect(options.react_no_unescaped_entities_forbid_closing_brace);

    var react_prefer_es6_class_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"never\"]",
        .{},
    );
    defer react_prefer_es6_class_config.deinit();
    try options.setByRuleConfigValue("react/prefer-es6-class", react_prefer_es6_class_config.value);
    try std.testing.expect(options.react_prefer_es6_class);
    try std.testing.expectEqual(ReactPreferEs6ClassStyle.never, options.react_prefer_es6_class_style);

    var react_no_unused_prop_types_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"skipShapeProps\":false,\"ignore\":[\"age\",\"user\"]}]",
        .{},
    );
    defer react_no_unused_prop_types_config.deinit();
    try options.setByRuleConfigValue("react/no-unused-prop-types", react_no_unused_prop_types_config.value);
    try std.testing.expect(options.react_no_unused_prop_types);
    try std.testing.expect(!options.react_no_unused_prop_types_skip_shape_props);
    try std.testing.expect(options.react_no_unused_prop_types_ignore.contains("age"));
    try std.testing.expect(options.react_no_unused_prop_types_ignore.ignoresPath("user.id"));
    try std.testing.expect(!options.react_no_unused_prop_types_ignore.contains("role"));
    try std.testing.expect(!options.react_no_unused_prop_types_custom_validators.contains("CustomValidator"));

    var react_no_unused_prop_types_custom_validators_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"customValidators\":[\"CustomValidator\"]}]",
        .{},
    );
    defer react_no_unused_prop_types_custom_validators_config.deinit();
    try options.setByRuleConfigValue("react/no-unused-prop-types", react_no_unused_prop_types_custom_validators_config.value);
    try std.testing.expect(options.react_no_unused_prop_types_custom_validators.contains("CustomValidator"));
    try std.testing.expect(!options.react_no_unused_prop_types_custom_validators.contains("OtherValidator"));

    var array_callback_return_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowImplicit\":false,\"checkForEach\":true,\"allowVoid\":true}]",
        .{},
    );
    defer array_callback_return_config.deinit();
    try options.setByRuleConfigValue("array-callback-return", array_callback_return_config.value);
    try std.testing.expect(options.array_callback_return);
    try std.testing.expectEqual(ArrayCallbackReturnAllowImplicit.no, options.array_callback_return_allow_implicit);
    try std.testing.expectEqual(ArrayCallbackReturnCheckForEach.yes, options.array_callback_return_check_for_each);
    try std.testing.expectEqual(ArrayCallbackReturnAllowVoid.yes, options.array_callback_return_allow_void);

    var capitalized_comments_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"never\",{\"ignoreInlineComments\":true,\"ignoreConsecutiveComments\":true}]",
        .{},
    );
    defer capitalized_comments_config.deinit();
    try options.setByRuleConfigValue("capitalized-comments", capitalized_comments_config.value);
    try std.testing.expect(options.capitalized_comments);
    try std.testing.expectEqual(CapitalizedCommentsMode.never, options.capitalized_comments_mode);
    try std.testing.expectEqual(CapitalizedCommentsIgnoreInlineComments.yes, options.capitalized_comments_ignore_inline_comments);
    try std.testing.expectEqual(CapitalizedCommentsIgnoreConsecutiveComments.yes, options.capitalized_comments_ignore_consecutive_comments);

    var class_methods_use_this_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"enforceForClassFields\":false,\"exceptMethods\":[\"render\",\"#private\"],\"ignoreOverrideMethods\":true,\"ignoreClassesWithImplements\":\"public-fields\"}]",
        .{},
    );
    defer class_methods_use_this_config.deinit();
    try options.setByRuleConfigValue("class-methods-use-this", class_methods_use_this_config.value);
    try std.testing.expect(options.class_methods_use_this);
    try std.testing.expect(!options.class_methods_use_this_enforce_for_class_fields);
    try std.testing.expect(options.class_methods_use_this_except_methods.contains("render"));
    try std.testing.expect(options.class_methods_use_this_except_methods.contains("#private"));
    try std.testing.expect(options.class_methods_use_this_ignore_override_methods);
    try std.testing.expectEqual(ClassMethodsUseThisIgnoreClassesWithImplements.public_fields, options.class_methods_use_this_ignore_classes_with_implements);

    var no_invalid_this_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"capIsConstructor\":false}]",
        .{},
    );
    defer no_invalid_this_config.deinit();
    try options.setByRuleConfigValue("no-invalid-this", no_invalid_this_config.value);
    try std.testing.expect(options.no_invalid_this);
    try std.testing.expectEqual(NoInvalidThisCapIsConstructor.no, options.no_invalid_this_cap_is_constructor);

    var consistent_return_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"treatUndefinedAsUnspecified\":true}]",
        .{},
    );
    defer consistent_return_config.deinit();
    try options.setByRuleConfigValue("consistent-return", consistent_return_config.value);
    try std.testing.expect(options.consistent_return);
    try std.testing.expect(options.consistent_return_treat_undefined_as_unspecified);

    var import_no_cycle_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"amd\":true,\"commonjs\":true,\"maxDepth\":1}]",
        .{},
    );
    defer import_no_cycle_config.deinit();
    try options.setByRuleConfigValue("import/no-cycle", import_no_cycle_config.value);
    try std.testing.expect(options.import_no_cycle);
    try std.testing.expect(options.import_no_cycle_amd);
    try std.testing.expect(options.import_no_cycle_commonjs);
    try std.testing.expectEqual(@as(usize, 1), options.import_no_cycle_max_depth);

    var import_no_duplicates_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"considerQueryString\":true}]",
        .{},
    );
    defer import_no_duplicates_config.deinit();
    try options.setByRuleConfigValue("import/no-duplicates", import_no_duplicates_config.value);
    try std.testing.expect(options.import_no_duplicates);
    try std.testing.expect(options.import_no_duplicates_consider_query_string);

    var import_no_unresolved_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"amd\":true,\"commonjs\":true,\"ignore\":[\"\\\\.img$\",\"^virtual:\"]}]",
        .{},
    );
    defer import_no_unresolved_config.deinit();
    try options.setByRuleConfigValue("import/no-unresolved", import_no_unresolved_config.value);
    try std.testing.expect(options.import_no_unresolved);
    try std.testing.expect(options.import_no_unresolved_amd);
    try std.testing.expect(options.import_no_unresolved_commonjs);
    try std.testing.expectEqual(@as(usize, 2), options.import_no_unresolved_ignore.count);
    try std.testing.expectEqualStrings("\\.img$", options.import_no_unresolved_ignore.at(0));
    try std.testing.expectEqualStrings("^virtual:", options.import_no_unresolved_ignore.at(1));

    var dot_notation_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowKeywords\":false}]",
        .{},
    );
    defer dot_notation_config.deinit();
    try options.setByRuleConfigValue("dot-notation", dot_notation_config.value);
    try std.testing.expect(options.dot_notation);
    try std.testing.expectEqual(DotNotationAllowKeywords.no, options.dot_notation_allow_keywords);

    try options.setByRuleConfigValue("@typescript-eslint/dot-notation", .{ .string = "off" });
    try std.testing.expect(!options.typescript_eslint_dot_notation);
    try std.testing.expectEqual(DotNotationAllowKeywords.no, options.dot_notation_allow_keywords);

    var typescript_dot_notation_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowKeywords\":true}]",
        .{},
    );
    defer typescript_dot_notation_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/dot-notation", typescript_dot_notation_config.value);
    try std.testing.expect(options.typescript_eslint_dot_notation);
    try std.testing.expectEqual(DotNotationAllowKeywords.yes, options.dot_notation_allow_keywords);

    var curly_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"multi-line\"]",
        .{},
    );
    defer curly_config.deinit();
    try options.setByRuleConfigValue("curly", curly_config.value);
    try std.testing.expect(options.curly);
    try std.testing.expectEqual(CurlyStyle.multi_line, options.curly_style);

    var curly_multi_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"multi\"]",
        .{},
    );
    defer curly_multi_config.deinit();
    try options.setByRuleConfigValue("curly", curly_multi_config.value);
    try std.testing.expectEqual(CurlyStyle.multi, options.curly_style);

    var curly_multi_or_nest_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"multi-or-nest\"]",
        .{},
    );
    defer curly_multi_or_nest_config.deinit();
    try options.setByRuleConfigValue("curly", curly_multi_or_nest_config.value);
    try std.testing.expectEqual(CurlyStyle.multi_or_nest, options.curly_style);

    var eqeqeq_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"allow-null\"]",
        .{},
    );
    defer eqeqeq_config.deinit();
    try options.setByRuleConfigValue("eqeqeq", eqeqeq_config.value);
    try std.testing.expect(options.eqeqeq);
    try std.testing.expectEqual(EqeqeqStyle.allow_null, options.eqeqeq_style);

    var eqeqeq_smart_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"smart\"]",
        .{},
    );
    defer eqeqeq_smart_config.deinit();
    try options.setByRuleConfigValue("eqeqeq", eqeqeq_smart_config.value);
    try std.testing.expectEqual(EqeqeqStyle.smart, options.eqeqeq_style);

    var accessor_pairs_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"getWithoutSet\":true,\"setWithoutGet\":false,\"enforceForClassMembers\":false}]",
        .{},
    );
    defer accessor_pairs_config.deinit();
    try options.setByRuleConfigValue("accessor-pairs", accessor_pairs_config.value);
    try std.testing.expect(options.accessor_pairs);
    try std.testing.expectEqual(AccessorPairsGetWithoutSet.yes, options.accessor_pairs_get_without_set);
    try std.testing.expectEqual(AccessorPairsSetWithoutGet.no, options.accessor_pairs_set_without_get);
    try std.testing.expectEqual(AccessorPairsEnforceForClassMembers.no, options.accessor_pairs_enforce_for_class_members);

    var profile_a_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"externalPackages\":{\"moment\":\"dayjs\"}}]",
        .{},
    );
    defer profile_a_config.deinit();
    try options.setByRuleConfigValue("@alipay/ant/no-deprecated-dependence", profile_a_config.value);
    try std.testing.expectEqual(DeprecatedDependenceProfile.profile_a, options.alipay_ant_no_deprecated_dependence_profile);

    var profile_b_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"externalPackages\":{\"@example/bridge\":\"appkit\"}}]",
        .{},
    );
    defer profile_b_config.deinit();
    try options.setByRuleConfigValue("@alipay/ant/no-deprecated-dependence", profile_b_config.value);
    try std.testing.expectEqual(DeprecatedDependenceProfile.profile_b, options.alipay_ant_no_deprecated_dependence_profile);

    var restricted_disable_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"warn\",\"no-nested-ternary\"]",
        .{},
    );
    defer restricted_disable_config.deinit();
    try options.setByRuleConfigValue("eslint-comments/no-restricted-disable", restricted_disable_config.value);
    try std.testing.expect(options.eslint_comments_no_restricted_disable);
    try std.testing.expect(options.eslint_comments_no_restricted_disable_no_nested_ternary);

    var func_name_matching_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"never\",{\"includeCommonJSModuleExports\":true,\"considerPropertyDescriptor\":true}]",
        .{},
    );
    defer func_name_matching_config.deinit();
    try options.setByRuleConfigValue("func-name-matching", func_name_matching_config.value);
    try std.testing.expect(options.func_name_matching);
    try std.testing.expectEqual(FuncNameMatchingStyle.never, options.func_name_matching_style);
    try std.testing.expect(options.func_name_matching_include_commonjs_module_exports);
    try std.testing.expect(options.func_name_matching_consider_property_descriptor);

    var getter_return_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowImplicit\":true}]",
        .{},
    );
    defer getter_return_config.deinit();
    try options.setByRuleConfigValue("getter-return", getter_return_config.value);
    try std.testing.expect(options.getter_return);
    try std.testing.expect(options.getter_return_allow_implicit);

    var func_names_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"never\",{\"generators\":\"as-needed\"}]",
        .{},
    );
    defer func_names_config.deinit();
    try options.setByRuleConfigValue("func-names", func_names_config.value);
    try std.testing.expect(options.func_names);
    try std.testing.expectEqual(FuncNamesStyle.never, options.func_names_style);
    try std.testing.expect(options.func_names_has_generator_style);
    try std.testing.expectEqual(FuncNamesStyle.as_needed, options.func_names_generator_style);

    var func_style_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"declaration\",{\"allowArrowFunctions\":true,\"allowTypeAnnotation\":true,\"overrides\":{\"namedExports\":\"ignore\"}}]",
        .{},
    );
    defer func_style_config.deinit();
    try options.setByRuleConfigValue("func-style", func_style_config.value);
    try std.testing.expect(options.func_style);
    try std.testing.expectEqual(FuncStyleStyle.declaration, options.func_style_style);
    try std.testing.expect(options.func_style_allow_arrow_functions);
    try std.testing.expect(options.func_style_allow_type_annotation);
    try std.testing.expectEqual(FuncStyleNamedExports.ignore, options.func_style_named_exports);

    var grouped_accessor_pairs_get_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"getBeforeSet\"]",
        .{},
    );
    defer grouped_accessor_pairs_get_config.deinit();
    try options.setByRuleConfigValue("grouped-accessor-pairs", grouped_accessor_pairs_get_config.value);
    try std.testing.expect(options.grouped_accessor_pairs);
    try std.testing.expectEqual(GroupedAccessorPairsStyle.get_before_set, options.grouped_accessor_pairs_style);

    var grouped_accessor_pairs_set_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"setBeforeGet\"]",
        .{},
    );
    defer grouped_accessor_pairs_set_config.deinit();
    try options.setByRuleConfigValue("grouped-accessor-pairs", grouped_accessor_pairs_set_config.value);
    try std.testing.expect(options.grouped_accessor_pairs);
    try std.testing.expectEqual(GroupedAccessorPairsStyle.set_before_get, options.grouped_accessor_pairs_style);

    var logical_assignment_operators_never_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"never\"]",
        .{},
    );
    defer logical_assignment_operators_never_config.deinit();
    try options.setByRuleConfigValue("logical-assignment-operators", logical_assignment_operators_never_config.value);
    try std.testing.expect(options.logical_assignment_operators);
    try std.testing.expectEqual(LogicalAssignmentOperatorsStyle.never, options.logical_assignment_operators_style);

    var logical_assignment_operators_if_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"always\",{\"enforceForIfStatements\":true}]",
        .{},
    );
    defer logical_assignment_operators_if_config.deinit();
    try options.setByRuleConfigValue("logical-assignment-operators", logical_assignment_operators_if_config.value);
    try std.testing.expect(options.logical_assignment_operators);
    try std.testing.expectEqual(LogicalAssignmentOperatorsStyle.always, options.logical_assignment_operators_style);
    try std.testing.expectEqual(
        LogicalAssignmentOperatorsEnforceForIfStatements.yes,
        options.logical_assignment_operators_enforce_for_if_statements,
    );

    var max_params_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"max\":2,\"countThis\":\"always\"}]",
        .{},
    );
    defer max_params_config.deinit();
    try options.setByRuleConfigValue("max-params", max_params_config.value);
    try std.testing.expect(options.max_params);
    try std.testing.expectEqual(@as(usize, 2), options.max_params_max);
    try std.testing.expectEqual(MaxParamsCountThis.always, options.max_params_count_this);

    var no_bitwise_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"|\",\"~\",\">>\"],\"int32Hint\":true}]",
        .{},
    );
    defer no_bitwise_config.deinit();
    try options.setByRuleConfigValue("no-bitwise", no_bitwise_config.value);
    try std.testing.expect(options.no_bitwise);
    try std.testing.expect(!options.no_bitwise_allow_bitwise_and);
    try std.testing.expect(options.no_bitwise_allow_bitwise_or);
    try std.testing.expect(!options.no_bitwise_allow_bitwise_xor);
    try std.testing.expect(options.no_bitwise_allow_bitwise_not);
    try std.testing.expect(!options.no_bitwise_allow_left_shift);
    try std.testing.expect(options.no_bitwise_allow_right_shift);
    try std.testing.expect(!options.no_bitwise_allow_unsigned_right_shift);
    try std.testing.expect(options.no_bitwise_int32_hint);

    var no_console_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"warn\",\"error\",\"todo\"]}]",
        .{},
    );
    defer no_console_config.deinit();
    try options.setByRuleConfigValue("no-console", no_console_config.value);
    try std.testing.expect(options.no_console);
    try std.testing.expect(options.no_console_allow.contains("warn"));
    try std.testing.expect(options.no_console_allow.contains("error"));
    try std.testing.expect(options.no_console_allow.contains("todo"));
    try std.testing.expect(!options.no_console_allow.contains("log"));

    var no_duplicate_imports_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowSeparateTypeImports\":true,\"includeExports\":true}]",
        .{},
    );
    defer no_duplicate_imports_config.deinit();
    try options.setByRuleConfigValue("no-duplicate-imports", no_duplicate_imports_config.value);
    try std.testing.expect(options.no_duplicate_imports);
    try std.testing.expect(options.no_duplicate_imports_allow_separate_type_imports);
    try std.testing.expect(options.no_duplicate_imports_include_exports);

    var no_multi_assign_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreNonDeclaration\":true}]",
        .{},
    );
    defer no_multi_assign_config.deinit();
    try options.setByRuleConfigValue("no-multi-assign", no_multi_assign_config.value);
    try std.testing.expect(options.no_multi_assign);
    try std.testing.expect(options.no_multi_assign_ignore_non_declaration);

    var no_cond_assign_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"always\"]",
        .{},
    );
    defer no_cond_assign_config.deinit();
    try options.setByRuleConfigValue("no-cond-assign", no_cond_assign_config.value);
    try std.testing.expect(options.no_cond_assign);
    try std.testing.expectEqual(NoCondAssignStyle.always, options.no_cond_assign_style);

    var no_constant_condition_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"checkLoops\":\"none\"}]",
        .{},
    );
    defer no_constant_condition_config.deinit();
    try options.setByRuleConfigValue("no-constant-condition", no_constant_condition_config.value);
    try std.testing.expect(options.no_constant_condition);
    try std.testing.expectEqual(NoConstantConditionCheckLoops.none, options.no_constant_condition_check_loops);

    var no_constant_condition_false_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"checkLoops\":false}]",
        .{},
    );
    defer no_constant_condition_false_config.deinit();
    try options.setByRuleConfigValue("no-constant-condition", no_constant_condition_false_config.value);
    try std.testing.expectEqual(NoConstantConditionCheckLoops.none, options.no_constant_condition_check_loops);

    var no_confusing_arrow_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowParens\":false}]",
        .{},
    );
    defer no_confusing_arrow_config.deinit();
    try options.setByRuleConfigValue("no-confusing-arrow", no_confusing_arrow_config.value);
    try std.testing.expect(options.no_confusing_arrow);
    try std.testing.expectEqual(NoConfusingArrowAllowParens.no, options.no_confusing_arrow_allow_parens);

    var no_empty_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowEmptyCatch\":true}]",
        .{},
    );
    defer no_empty_config.deinit();
    try options.setByRuleConfigValue("no-empty", no_empty_config.value);
    try std.testing.expect(options.no_empty);
    try std.testing.expectEqual(NoEmptyAllowEmptyCatch.yes, options.no_empty_allow_empty_catch);

    var no_eval_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowIndirect\":true}]",
        .{},
    );
    defer no_eval_config.deinit();
    try options.setByRuleConfigValue("no-eval", no_eval_config.value);
    try std.testing.expect(options.no_eval);
    try std.testing.expect(options.no_eval_allow_indirect);

    var no_extend_native_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"exceptions\":[\"Array\",\"Object\"]}]",
        .{},
    );
    defer no_extend_native_config.deinit();
    try options.setByRuleConfigValue("no-extend-native", no_extend_native_config.value);
    try std.testing.expect(options.no_extend_native);
    try std.testing.expect(options.no_extend_native_exceptions.contains("Array"));
    try std.testing.expect(options.no_extend_native_exceptions.contains("Object"));
    try std.testing.expect(!options.no_extend_native_exceptions.contains("String"));

    var no_global_assign_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"exceptions\":[\"Object\",\"NaN\"]}]",
        .{},
    );
    defer no_global_assign_config.deinit();
    try options.setByRuleConfigValue("no-global-assign", no_global_assign_config.value);
    try std.testing.expect(options.no_global_assign);
    try std.testing.expect(options.no_global_assign_exceptions.contains("Object"));
    try std.testing.expect(options.no_global_assign_exceptions.contains("NaN"));
    try std.testing.expect(!options.no_global_assign_exceptions.contains("undefined"));

    var no_empty_function_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"functions\",\"constructors\"]}]",
        .{},
    );
    defer no_empty_function_config.deinit();
    try options.setByRuleConfigValue("no-empty-function", no_empty_function_config.value);
    try std.testing.expect(options.no_empty_function);
    try std.testing.expect(options.no_empty_function_allow.functions);
    try std.testing.expect(options.no_empty_function_allow.constructors);
    try std.testing.expect(!options.no_empty_function_allow.arrowFunctions);

    var no_empty_function_extended_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"asyncFunctions\",\"generatorFunctions\",\"asyncMethods\",\"generatorMethods\",\"getters\",\"setters\"]}]",
        .{},
    );
    defer no_empty_function_extended_config.deinit();
    try options.setByRuleConfigValue("no-empty-function", no_empty_function_extended_config.value);
    try std.testing.expect(options.no_empty_function_allow.asyncFunctions);
    try std.testing.expect(options.no_empty_function_allow.generatorFunctions);
    try std.testing.expect(options.no_empty_function_allow.asyncMethods);
    try std.testing.expect(options.no_empty_function_allow.generatorMethods);
    try std.testing.expect(options.no_empty_function_allow.getters);
    try std.testing.expect(options.no_empty_function_allow.setters);

    var typescript_no_empty_function_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"arrowFunctions\",\"methods\",\"private-constructors\",\"protected-constructors\",\"decoratedFunctions\",\"overrideMethods\"]}]",
        .{},
    );
    defer typescript_no_empty_function_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-empty-function", typescript_no_empty_function_config.value);
    try std.testing.expect(options.typescript_eslint_no_empty_function);
    try std.testing.expect(options.typescript_eslint_no_empty_function_allow.arrowFunctions);
    try std.testing.expect(options.typescript_eslint_no_empty_function_allow.methods);
    try std.testing.expect(options.typescript_eslint_no_empty_function_allow.privateConstructors);
    try std.testing.expect(options.typescript_eslint_no_empty_function_allow.protectedConstructors);
    try std.testing.expect(options.typescript_eslint_no_empty_function_allow.decoratedFunctions);
    try std.testing.expect(options.typescript_eslint_no_empty_function_allow.overrideMethods);
    try std.testing.expect(!options.typescript_eslint_no_empty_function_allow.functions);

    var typescript_no_empty_interface_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowSingleExtends\":true}]",
        .{},
    );
    defer typescript_no_empty_interface_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-empty-interface", typescript_no_empty_interface_config.value);
    try std.testing.expect(options.typescript_eslint_no_empty_interface);
    try std.testing.expect(options.typescript_eslint_no_empty_interface_allow_single_extends);

    var typescript_no_empty_object_type_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowInterfaces\":\"with-single-extends\",\"allowObjectTypes\":\"always\",\"allowWithName\":\"Props$\"}]",
        .{},
    );
    defer typescript_no_empty_object_type_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-empty-object-type", typescript_no_empty_object_type_config.value);
    try std.testing.expect(options.typescript_eslint_no_empty_object_type);
    try std.testing.expectEqual(TypescriptEslintNoEmptyObjectTypeAllowInterfaces.with_single_extends, options.typescript_eslint_no_empty_object_type_allow_interfaces);
    try std.testing.expectEqual(TypescriptEslintNoEmptyObjectTypeAllowObjectTypes.always, options.typescript_eslint_no_empty_object_type_allow_object_types);
    try std.testing.expectEqualStrings("Props$", options.typescript_eslint_no_empty_object_type_allow_with_name.pattern().?);

    var no_else_return_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowElseIf\":false}]",
        .{},
    );
    defer no_else_return_config.deinit();
    try options.setByRuleConfigValue("no-else-return", no_else_return_config.value);
    try std.testing.expect(options.no_else_return);
    try std.testing.expect(!options.no_else_return_allow_else_if);

    var no_empty_pattern_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowObjectPatternsAsParameters\":true}]",
        .{},
    );
    defer no_empty_pattern_config.deinit();
    try options.setByRuleConfigValue("no-empty-pattern", no_empty_pattern_config.value);
    try std.testing.expect(options.no_empty_pattern);
    try std.testing.expect(options.no_empty_pattern_allow_object_patterns_as_parameters);

    var no_extra_boolean_cast_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"enforceForInnerExpressions\":true}]",
        .{},
    );
    defer no_extra_boolean_cast_config.deinit();
    try options.setByRuleConfigValue("no-extra-boolean-cast", no_extra_boolean_cast_config.value);
    try std.testing.expect(options.no_extra_boolean_cast);
    try std.testing.expect(options.no_extra_boolean_cast_enforce_for_inner_expressions);

    var no_extra_boolean_cast_legacy_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"enforceForLogicalOperands\":true}]",
        .{},
    );
    defer no_extra_boolean_cast_legacy_config.deinit();
    options.no_extra_boolean_cast_enforce_for_inner_expressions = false;
    try options.setByRuleConfigValue("no-extra-boolean-cast", no_extra_boolean_cast_legacy_config.value);
    try std.testing.expect(options.no_extra_boolean_cast);
    try std.testing.expect(options.no_extra_boolean_cast_enforce_for_inner_expressions);

    var no_extra_boolean_cast_precedence_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"enforceForInnerExpressions\":false,\"enforceForLogicalOperands\":true}]",
        .{},
    );
    defer no_extra_boolean_cast_precedence_config.deinit();
    try options.setByRuleConfigValue("no-extra-boolean-cast", no_extra_boolean_cast_precedence_config.value);
    try std.testing.expect(!options.no_extra_boolean_cast_enforce_for_inner_expressions);

    var no_fallthrough_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowEmptyCase\":true,\"commentPattern\":\"^ intentional fallthrough$\",\"reportUnusedFallthroughComment\":true}]",
        .{},
    );
    defer no_fallthrough_config.deinit();
    try options.setByRuleConfigValue("no-fallthrough", no_fallthrough_config.value);
    try std.testing.expect(options.no_fallthrough);
    try std.testing.expectEqual(NoFallthroughAllowEmptyCase.yes, options.no_fallthrough_allow_empty_case);
    try std.testing.expectEqualStrings(" intentional fallthrough", options.no_fallthrough_comment_pattern.pattern().?);
    try std.testing.expect(options.no_fallthrough_report_unused_fallthrough_comment);

    var no_implicit_coercion_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"boolean\":false,\"number\":false,\"string\":true}]",
        .{},
    );
    defer no_implicit_coercion_config.deinit();
    try options.setByRuleConfigValue("no-implicit-coercion", no_implicit_coercion_config.value);
    try std.testing.expect(options.no_implicit_coercion);
    try std.testing.expectEqual(NoImplicitCoercionBoolean.no, options.no_implicit_coercion_boolean);
    try std.testing.expectEqual(NoImplicitCoercionNumber.no, options.no_implicit_coercion_number);
    try std.testing.expectEqual(NoImplicitCoercionString.yes, options.no_implicit_coercion_string);

    var no_implicit_coercion_allow_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"!!\",\"~\",\"+\",\"*\",\"-\",\"- -\"],\"disallowTemplateShorthand\":true}]",
        .{},
    );
    defer no_implicit_coercion_allow_config.deinit();
    try options.setByRuleConfigValue("no-implicit-coercion", no_implicit_coercion_allow_config.value);
    try std.testing.expect(options.no_implicit_coercion_allow_double_negation);
    try std.testing.expect(options.no_implicit_coercion_allow_bitwise_not);
    try std.testing.expect(options.no_implicit_coercion_allow_plus);
    try std.testing.expect(options.no_implicit_coercion_allow_multiply);
    try std.testing.expect(options.no_implicit_coercion_allow_subtract);
    try std.testing.expect(options.no_implicit_coercion_allow_double_negative);
    try std.testing.expect(options.no_implicit_coercion_disallow_template_shorthand);

    var no_inner_declarations_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"both\"]",
        .{},
    );
    defer no_inner_declarations_config.deinit();
    try options.setByRuleConfigValue("no-inner-declarations", no_inner_declarations_config.value);
    try std.testing.expect(options.no_inner_declarations);
    try std.testing.expectEqual(NoInnerDeclarationsMode.both, options.no_inner_declarations_mode);

    var no_labels_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowLoop\":true,\"allowSwitch\":true}]",
        .{},
    );
    defer no_labels_config.deinit();
    try options.setByRuleConfigValue("no-labels", no_labels_config.value);
    try std.testing.expect(options.no_labels);
    try std.testing.expectEqual(NoLabelsAllowLoop.yes, options.no_labels_allow_loop);
    try std.testing.expectEqual(NoLabelsAllowSwitch.yes, options.no_labels_allow_switch);

    var new_cap_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"newIsCap\":false,\"capIsNew\":false,\"properties\":false,\"newIsCapExceptions\":[\"lowerFactory\"],\"capIsNewExceptions\":[\"UpperFactory\"],\"newIsCapExceptionPattern\":\"^lower.*Factory$\",\"capIsNewExceptionPattern\":\"^Upper.*Factory$\"}]",
        .{},
    );
    defer new_cap_config.deinit();
    try options.setByRuleConfigValue("new-cap", new_cap_config.value);
    try std.testing.expect(options.new_cap);
    try std.testing.expect(!options.new_cap_new_is_cap);
    try std.testing.expect(!options.new_cap_cap_is_new);
    try std.testing.expect(!options.new_cap_properties);
    try std.testing.expect(options.new_cap_new_is_cap_exceptions.contains("lowerFactory"));
    try std.testing.expect(!options.new_cap_new_is_cap_exceptions.contains("otherFactory"));
    try std.testing.expect(options.new_cap_cap_is_new_exceptions.contains("UpperFactory"));
    try std.testing.expect(!options.new_cap_cap_is_new_exceptions.contains("OtherFactory"));
    try std.testing.expectEqualStrings("^lower.*Factory$", options.new_cap_new_is_cap_exception_pattern.pattern().?);
    try std.testing.expectEqualStrings("^Upper.*Factory$", options.new_cap_cap_is_new_exception_pattern.pattern().?);

    var no_multi_spaces_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreEOLComments\":true,\"exceptions\":{\"Property\":false,\"BinaryExpression\":true,\"VariableDeclarator\":true,\"ImportDeclaration\":true}}]",
        .{},
    );
    defer no_multi_spaces_config.deinit();
    try options.setByRuleConfigValue("no-multi-spaces", no_multi_spaces_config.value);
    try std.testing.expect(options.no_multi_spaces);
    try std.testing.expectEqual(NoMultiSpacesIgnoreEOLComments.yes, options.no_multi_spaces_ignore_eol_comments);
    try std.testing.expect(!options.no_multi_spaces_exceptions.property);
    try std.testing.expect(options.no_multi_spaces_exceptions.binary_expression);
    try std.testing.expect(options.no_multi_spaces_exceptions.variable_declarator);
    try std.testing.expect(options.no_multi_spaces_exceptions.import_declaration);

    var no_multiple_empty_lines_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"max\":1}]",
        .{},
    );
    defer no_multiple_empty_lines_config.deinit();
    try options.setByRuleConfigValue("no-multiple-empty-lines", no_multiple_empty_lines_config.value);
    try std.testing.expect(options.no_multiple_empty_lines);
    try std.testing.expectEqual(@as(usize, 1), options.no_multiple_empty_lines_max);
    try std.testing.expectEqual(@as(?usize, null), options.no_multiple_empty_lines_max_bof);
    try std.testing.expectEqual(@as(?usize, null), options.no_multiple_empty_lines_max_eof);

    var no_multiple_empty_lines_bof_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"maxBOF\":0}]",
        .{},
    );
    defer no_multiple_empty_lines_bof_config.deinit();
    try options.setByRuleConfigValue("no-multiple-empty-lines", no_multiple_empty_lines_bof_config.value);
    try std.testing.expect(options.no_multiple_empty_lines);
    try std.testing.expectEqual(@as(usize, 2), options.no_multiple_empty_lines_max);
    try std.testing.expectEqual(@as(?usize, 0), options.no_multiple_empty_lines_max_bof);
    try std.testing.expectEqual(@as(?usize, null), options.no_multiple_empty_lines_max_eof);

    var no_multiple_empty_lines_eof_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"maxEOF\":0}]",
        .{},
    );
    defer no_multiple_empty_lines_eof_config.deinit();
    try options.setByRuleConfigValue("no-multiple-empty-lines", no_multiple_empty_lines_eof_config.value);
    try std.testing.expect(options.no_multiple_empty_lines);
    try std.testing.expectEqual(@as(usize, 2), options.no_multiple_empty_lines_max);
    try std.testing.expectEqual(@as(?usize, null), options.no_multiple_empty_lines_max_bof);
    try std.testing.expectEqual(@as(?usize, 0), options.no_multiple_empty_lines_max_eof);

    var no_param_reassign_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"props\":true,\"ignorePropertyModificationsFor\":[\"req\",\"res\"],\"ignorePropertyModificationsForRegex\":[\"^ctx\",\"Response$\"]}]",
        .{},
    );
    defer no_param_reassign_config.deinit();
    try options.setByRuleConfigValue("no-param-reassign", no_param_reassign_config.value);
    try std.testing.expect(options.no_param_reassign);
    try std.testing.expectEqual(NoParamReassignProps.yes, options.no_param_reassign_props);
    try std.testing.expect(options.no_param_reassign_ignore_property_modifications_for.contains("req"));
    try std.testing.expect(options.no_param_reassign_ignore_property_modifications_for.contains("res"));
    try std.testing.expect(!options.no_param_reassign_ignore_property_modifications_for.contains("ctx"));
    try std.testing.expectEqual(@as(usize, 2), options.no_param_reassign_ignore_property_modifications_for_regex.count);
    try std.testing.expectEqualStrings("^ctx", options.no_param_reassign_ignore_property_modifications_for_regex.at(0));
    try std.testing.expectEqualStrings("Response$", options.no_param_reassign_ignore_property_modifications_for_regex.at(1));

    var no_redeclare_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"builtinGlobals\":true}]",
        .{},
    );
    defer no_redeclare_config.deinit();
    try options.setByRuleConfigValue("no-redeclare", no_redeclare_config.value);
    try std.testing.expect(options.no_redeclare);
    try std.testing.expectEqual(NoRedeclareBuiltinGlobals.yes, options.no_redeclare_builtin_globals);

    var no_restricted_properties_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"object\":\"disallowedObject\",\"property\":\"disallowedProperty\",\"message\":\"Use allowedObject.allowedProperty.\"},{\"property\":\"push\",\"allowObjects\":[\"router\"]},{\"object\":\"config\",\"allowProperties\":[\"settings\",\"version\"]}]",
        .{},
    );
    defer no_restricted_properties_config.deinit();
    try options.setByRuleConfigValue("no-restricted-properties", no_restricted_properties_config.value);
    try std.testing.expect(options.no_restricted_properties);
    try std.testing.expectEqual(@as(usize, 3), options.no_restricted_properties_entries.count);
    try std.testing.expectEqualStrings("disallowedObject", options.no_restricted_properties_entries.at(0).object().?);
    try std.testing.expectEqualStrings("disallowedProperty", options.no_restricted_properties_entries.at(0).property().?);
    try std.testing.expectEqualStrings("Use allowedObject.allowedProperty.", options.no_restricted_properties_entries.at(0).message().?);
    try std.testing.expect(options.no_restricted_properties_entries.at(1).allow_objects.contains("router"));
    try std.testing.expect(options.no_restricted_properties_entries.at(2).allow_properties.contains("settings"));
    try std.testing.expect(options.no_restricted_properties_entries.at(2).allow_properties.contains("version"));

    var no_restricted_globals_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"event\",{\"name\":\"fdescribe\",\"message\":\"Use describe instead.\"}]",
        .{},
    );
    defer no_restricted_globals_config.deinit();
    try options.setByRuleConfigValue("no-restricted-globals", no_restricted_globals_config.value);
    try std.testing.expect(options.no_restricted_globals);
    try std.testing.expectEqual(@as(usize, 2), options.no_restricted_globals_entries.count);
    try std.testing.expectEqualStrings("event", options.no_restricted_globals_entries.at(0).name());
    try std.testing.expectEqualStrings("fdescribe", options.no_restricted_globals_entries.at(1).name());
    try std.testing.expectEqualStrings("Use describe instead.", options.no_restricted_globals_entries.at(1).message().?);

    var no_restricted_globals_object_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"globals\":[\"event\"],\"checkGlobalObject\":true,\"globalObjects\":[\"customGlobal\"]}]",
        .{},
    );
    defer no_restricted_globals_object_config.deinit();
    try options.setByRuleConfigValue("no-restricted-globals", no_restricted_globals_object_config.value);
    try std.testing.expect(options.no_restricted_globals);
    try std.testing.expectEqual(@as(usize, 1), options.no_restricted_globals_entries.count);
    try std.testing.expectEqualStrings("event", options.no_restricted_globals_entries.at(0).name());
    try std.testing.expect(options.no_restricted_globals_entries.check_global_object);
    try std.testing.expect(options.no_restricted_globals_entries.global_objects.contains("customGlobal"));

    var typescript_no_redeclare_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"builtinGlobals\":true,\"ignoreDeclarationMerge\":false}]",
        .{},
    );
    defer typescript_no_redeclare_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-redeclare", typescript_no_redeclare_config.value);
    try std.testing.expect(options.typescript_eslint_no_redeclare);
    try std.testing.expect(options.typescript_eslint_no_redeclare_builtin_globals);
    try std.testing.expect(!options.typescript_eslint_no_redeclare_ignore_declaration_merge);

    var no_irregular_whitespace_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"skipStrings\":false,\"skipComments\":true,\"skipRegExps\":true,\"skipTemplates\":true,\"skipJSXText\":true}]",
        .{},
    );
    defer no_irregular_whitespace_config.deinit();
    try options.setByRuleConfigValue("no-irregular-whitespace", no_irregular_whitespace_config.value);
    try std.testing.expect(options.no_irregular_whitespace);
    try std.testing.expect(!options.no_irregular_whitespace_skip_strings);
    try std.testing.expect(options.no_irregular_whitespace_skip_comments);
    try std.testing.expect(options.no_irregular_whitespace_skip_reg_exps);
    try std.testing.expect(options.no_irregular_whitespace_skip_templates);
    try std.testing.expect(options.no_irregular_whitespace_skip_jsx_text);

    var no_inline_comments_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignorePattern\":\"eslint-disable|istanbul ignore\"}]",
        .{},
    );
    defer no_inline_comments_config.deinit();
    try options.setByRuleConfigValue("no-inline-comments", no_inline_comments_config.value);
    try std.testing.expect(options.no_inline_comments);
    try std.testing.expectEqualStrings("eslint-disable|istanbul ignore", options.no_inline_comments_ignore_pattern.pattern().?);

    var no_shadow_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"done\"],\"builtinGlobals\":true,\"hoist\":\"all\",\"ignoreOnInitialization\":true}]",
        .{},
    );
    defer no_shadow_config.deinit();
    try options.setByRuleConfigValue("no-shadow", no_shadow_config.value);
    try std.testing.expect(options.no_shadow);
    try std.testing.expect(options.no_shadow_allow.contains("done"));
    try std.testing.expect(!options.no_shadow_allow.contains("other"));
    try std.testing.expect(options.no_shadow_builtin_globals);
    try std.testing.expectEqual(NoShadowHoist.all, options.no_shadow_hoist);
    try std.testing.expect(options.no_shadow_ignore_on_initialization);

    var no_underscore_dangle_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"_allowed\"],\"allowAfterThis\":true,\"allowAfterSuper\":true,\"allowAfterThisConstructor\":true,\"allowFunctionParams\":false,\"allowInArrayDestructuring\":false,\"allowInObjectDestructuring\":false,\"enforceInMethodNames\":true,\"enforceInClassFields\":true}]",
        .{},
    );
    defer no_underscore_dangle_config.deinit();
    try options.setByRuleConfigValue("no-underscore-dangle", no_underscore_dangle_config.value);
    try std.testing.expect(options.no_underscore_dangle);
    try std.testing.expect(options.no_underscore_dangle_allow_after_this);
    try std.testing.expect(options.no_underscore_dangle_allow_after_super);
    try std.testing.expect(options.no_underscore_dangle_allow_after_this_constructor);
    try std.testing.expectEqual(NoUnderscoreDangleAllowFunctionParams.no, options.no_underscore_dangle_allow_function_params);
    try std.testing.expectEqual(NoUnderscoreDangleAllowDestructuring.no, options.no_underscore_dangle_allow_in_array_destructuring);
    try std.testing.expectEqual(NoUnderscoreDangleAllowDestructuring.no, options.no_underscore_dangle_allow_in_object_destructuring);
    try std.testing.expect(options.no_underscore_dangle_enforce_in_method_names);
    try std.testing.expect(options.no_underscore_dangle_enforce_in_class_fields);
    try std.testing.expect(options.no_underscore_dangle_allow.contains("_allowed"));
    try std.testing.expect(!options.no_underscore_dangle_allow.contains("_other"));

    var typescript_no_shadow_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allow\":[\"value\"],\"builtinGlobals\":true,\"hoist\":\"never\",\"ignoreOnInitialization\":true,\"ignoreTypeValueShadow\":true,\"ignoreFunctionTypeParameterNameValueShadow\":false}]",
        .{},
    );
    defer typescript_no_shadow_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-shadow", typescript_no_shadow_config.value);
    try std.testing.expect(options.typescript_eslint_no_shadow);
    try std.testing.expect(options.typescript_eslint_no_shadow_allow.contains("value"));
    try std.testing.expect(!options.typescript_eslint_no_shadow_allow.contains("other"));
    try std.testing.expect(options.typescript_eslint_no_shadow_builtin_globals);
    try std.testing.expectEqual(NoShadowHoist.never, options.typescript_eslint_no_shadow_hoist);
    try std.testing.expect(options.typescript_eslint_no_shadow_ignore_on_initialization);
    try std.testing.expect(options.typescript_eslint_no_shadow_ignore_type_value_shadow);
    try std.testing.expect(!options.typescript_eslint_no_shadow_ignore_function_type_parameter_name_value_shadow);

    var typescript_no_this_alias_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowedNames\":[\"that\"],\"allowDestructuring\":false}]",
        .{},
    );
    defer typescript_no_this_alias_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-this-alias", typescript_no_this_alias_config.value);
    try std.testing.expect(options.typescript_eslint_no_this_alias);
    try std.testing.expect(options.typescript_eslint_no_this_alias_allowed_names.contains("that"));
    try std.testing.expect(!options.typescript_eslint_no_this_alias_allowed_names.contains("self"));
    try std.testing.expect(!options.typescript_eslint_no_this_alias_allow_destructuring);

    var no_plusplus_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowForLoopAfterthoughts\":true}]",
        .{},
    );
    defer no_plusplus_config.deinit();
    try options.setByRuleConfigValue("no-plusplus", no_plusplus_config.value);
    try std.testing.expect(options.no_plusplus);
    try std.testing.expectEqual(NoPlusplusAllowForLoopAfterthoughts.yes, options.no_plusplus_allow_for_loop_afterthoughts);

    var object_shorthand_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"methods\",{\"avoidQuotes\":true,\"ignoreConstructors\":true}]",
        .{},
    );
    defer object_shorthand_config.deinit();
    try options.setByRuleConfigValue("object-shorthand", object_shorthand_config.value);
    try std.testing.expect(options.object_shorthand);
    try std.testing.expectEqual(ObjectShorthandStyle.methods, options.object_shorthand_style);
    try std.testing.expect(options.object_shorthand_avoid_quotes);
    try std.testing.expect(options.object_shorthand_ignore_constructors);

    var object_shorthand_arrows_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"always\",{\"avoidExplicitReturnArrows\":true}]",
        .{},
    );
    defer object_shorthand_arrows_config.deinit();
    try options.setByRuleConfigValue("object-shorthand", object_shorthand_arrows_config.value);
    try std.testing.expect(options.object_shorthand);
    try std.testing.expect(options.object_shorthand_avoid_explicit_return_arrows);

    var operator_assignment_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"never\"]",
        .{},
    );
    defer operator_assignment_config.deinit();
    try options.setByRuleConfigValue("operator-assignment", operator_assignment_config.value);
    try std.testing.expect(options.operator_assignment);
    try std.testing.expectEqual(OperatorAssignmentStyle.never, options.operator_assignment_style);

    var prefer_const_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"destructuring\":\"all\",\"ignoreReadBeforeAssign\":false}]",
        .{},
    );
    defer prefer_const_config.deinit();
    try options.setByRuleConfigValue("prefer-const", prefer_const_config.value);
    try std.testing.expect(options.prefer_const);
    try std.testing.expectEqual(PreferConstDestructuring.all, options.prefer_const_destructuring);
    try std.testing.expect(!options.prefer_const_ignore_read_before_assign);

    var prefer_destructuring_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"VariableDeclarator\":{\"array\":false,\"object\":true},\"AssignmentExpression\":{\"array\":true,\"object\":false}}]",
        .{},
    );
    defer prefer_destructuring_config.deinit();
    try options.setByRuleConfigValue("prefer-destructuring", prefer_destructuring_config.value);
    try std.testing.expect(options.prefer_destructuring);
    try std.testing.expect(!options.prefer_destructuring_variable_declarator_array);
    try std.testing.expect(options.prefer_destructuring_variable_declarator_object);
    try std.testing.expect(options.prefer_destructuring_assignment_expression_array);
    try std.testing.expect(!options.prefer_destructuring_assignment_expression_object);
    try std.testing.expect(!options.prefer_destructuring_enforce_for_renamed_properties);

    var prefer_destructuring_top_level_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"array\":false,\"object\":true},{\"enforceForRenamedProperties\":true}]",
        .{},
    );
    defer prefer_destructuring_top_level_config.deinit();
    try options.setByRuleConfigValue("prefer-destructuring", prefer_destructuring_top_level_config.value);
    try std.testing.expect(!options.prefer_destructuring_variable_declarator_array);
    try std.testing.expect(options.prefer_destructuring_variable_declarator_object);
    try std.testing.expect(!options.prefer_destructuring_assignment_expression_array);
    try std.testing.expect(options.prefer_destructuring_assignment_expression_object);
    try std.testing.expect(options.prefer_destructuring_enforce_for_renamed_properties);

    var prefer_promise_reject_errors_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowEmptyReject\":true}]",
        .{},
    );
    defer prefer_promise_reject_errors_config.deinit();
    try options.setByRuleConfigValue("prefer-promise-reject-errors", prefer_promise_reject_errors_config.value);
    try std.testing.expect(options.prefer_promise_reject_errors);
    try std.testing.expect(options.prefer_promise_reject_errors_allow_empty_reject);

    var no_promise_executor_return_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowVoid\":true}]",
        .{},
    );
    defer no_promise_executor_return_config.deinit();
    try options.setByRuleConfigValue("no-promise-executor-return", no_promise_executor_return_config.value);
    try std.testing.expect(options.no_promise_executor_return);
    try std.testing.expect(options.no_promise_executor_return_allow_void);

    var promise_no_callback_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"exceptions\":[\"next\"],\"timeoutsErr\":true}]",
        .{},
    );
    defer promise_no_callback_config.deinit();
    try options.setByRuleConfigValue("promise/no-callback-in-promise", promise_no_callback_config.value);
    try std.testing.expect(options.promise_no_callback_in_promise);
    try std.testing.expect(options.promise_no_callback_in_promise_exceptions.contains("next"));
    try std.testing.expect(options.promise_no_callback_in_promise_timeouts_err);

    var promise_catch_or_return_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowFinally\":true,\"allowThen\":true,\"allowThenStrict\":true,\"terminationMethod\":[\"catch\",\"done\"]}]",
        .{},
    );
    defer promise_catch_or_return_config.deinit();
    try options.setByRuleConfigValue("promise/catch-or-return", promise_catch_or_return_config.value);
    try std.testing.expect(options.promise_catch_or_return);
    try std.testing.expect(options.promise_catch_or_return_allow_finally);
    try std.testing.expect(options.promise_catch_or_return_allow_then);
    try std.testing.expect(options.promise_catch_or_return_allow_then_strict);
    try std.testing.expect(options.promise_catch_or_return_termination_methods.contains("catch"));
    try std.testing.expect(options.promise_catch_or_return_termination_methods.contains("done"));

    var promise_always_return_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreLastCallback\":true,\"ignoreAssignmentVariable\":[\"window\"]}]",
        .{},
    );
    defer promise_always_return_config.deinit();
    try options.setByRuleConfigValue("promise/always-return", promise_always_return_config.value);
    try std.testing.expect(options.promise_always_return);
    try std.testing.expect(options.promise_always_return_ignore_last_callback);
    try std.testing.expect(options.promise_always_return_ignore_assignment_variables.custom);
    try std.testing.expect(options.promise_always_return_ignore_assignment_variables.contains("window"));
    try std.testing.expect(!options.promise_always_return_ignore_assignment_variables.contains("globalThis"));

    var prefer_regex_literals_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"disallowRedundantWrapping\":true}]",
        .{},
    );
    defer prefer_regex_literals_config.deinit();
    try options.setByRuleConfigValue("prefer-regex-literals", prefer_regex_literals_config.value);
    try std.testing.expect(options.prefer_regex_literals);
    try std.testing.expect(options.prefer_regex_literals_disallow_redundant_wrapping);

    var radix_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"as-needed\"]",
        .{},
    );
    defer radix_config.deinit();
    try options.setByRuleConfigValue("radix", radix_config.value);
    try std.testing.expect(options.radix);
    try std.testing.expectEqual(RadixStyle.as_needed, options.radix_style);

    var require_atomic_updates_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowProperties\":true}]",
        .{},
    );
    defer require_atomic_updates_config.deinit();
    try options.setByRuleConfigValue("require-atomic-updates", require_atomic_updates_config.value);
    try std.testing.expect(options.require_atomic_updates);
    try std.testing.expect(options.require_atomic_updates_allow_properties);

    var require_unicode_regexp_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"requireFlag\":\"v\"}]",
        .{},
    );
    defer require_unicode_regexp_config.deinit();
    try options.setByRuleConfigValue("require-unicode-regexp", require_unicode_regexp_config.value);
    try std.testing.expect(options.require_unicode_regexp);
    try std.testing.expectEqual(RequireUnicodeRegexpRequireFlag.v, options.require_unicode_regexp_require_flag);

    var max_lines_per_function_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"max\":12,\"skipBlankLines\":true,\"skipComments\":true,\"IIFEs\":true}]",
        .{},
    );
    defer max_lines_per_function_config.deinit();
    try options.setByRuleConfigValue("max-lines-per-function", max_lines_per_function_config.value);
    try std.testing.expect(options.max_lines_per_function);
    try std.testing.expectEqual(@as(usize, 12), options.max_lines_per_function_max);
    try std.testing.expect(options.max_lines_per_function_skip_blank_lines);
    try std.testing.expect(options.max_lines_per_function_skip_comments);
    try std.testing.expect(options.max_lines_per_function_iifes);

    var sort_vars_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreCase\":true}]",
        .{},
    );
    defer sort_vars_config.deinit();
    try options.setByRuleConfigValue("sort-vars", sort_vars_config.value);
    try std.testing.expect(options.sort_vars);
    try std.testing.expect(options.sort_vars_ignore_case);

    var strict_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"global\"]",
        .{},
    );
    defer strict_config.deinit();
    try options.setByRuleConfigValue("strict", strict_config.value);
    try std.testing.expect(options.strict);
    try std.testing.expectEqual(StrictMode.global, options.strict_mode);

    var no_useless_rename_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreDestructuring\":true,\"ignoreImport\":true,\"ignoreExport\":true}]",
        .{},
    );
    defer no_useless_rename_config.deinit();
    try options.setByRuleConfigValue("no-useless-rename", no_useless_rename_config.value);
    try std.testing.expect(options.no_useless_rename);
    try std.testing.expect(options.no_useless_rename_ignore_destructuring);
    try std.testing.expect(options.no_useless_rename_ignore_import);
    try std.testing.expect(options.no_useless_rename_ignore_export);

    var no_useless_escape_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowRegexCharacters\":[\"#\",\"-\"]}]",
        .{},
    );
    defer no_useless_escape_config.deinit();
    try options.setByRuleConfigValue("no-useless-escape", no_useless_escape_config.value);
    try std.testing.expect(options.no_useless_escape);
    try std.testing.expect(options.no_useless_escape_allow_regex_characters.contains('#'));
    try std.testing.expect(options.no_useless_escape_allow_regex_characters.contains('-'));
    try std.testing.expect(!options.no_useless_escape_allow_regex_characters.contains('^'));

    var no_unsafe_negation_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"enforceForOrderingRelations\":true}]",
        .{},
    );
    defer no_unsafe_negation_config.deinit();
    try options.setByRuleConfigValue("no-unsafe-negation", no_unsafe_negation_config.value);
    try std.testing.expect(options.no_unsafe_negation);
    try std.testing.expect(options.no_unsafe_negation_enforce_for_ordering_relations);

    var no_unreachable_loop_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignore\":[\"WhileStatement\",\"ForOfStatement\"]}]",
        .{},
    );
    defer no_unreachable_loop_config.deinit();
    try options.setByRuleConfigValue("no-unreachable-loop", no_unreachable_loop_config.value);
    try std.testing.expect(options.no_unreachable_loop);
    try std.testing.expect(options.no_unreachable_loop_ignore_while);
    try std.testing.expect(options.no_unreachable_loop_ignore_for_of);
    try std.testing.expect(!options.no_unreachable_loop_ignore_for);

    var no_unsafe_optional_chaining_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"disallowArithmeticOperators\":true}]",
        .{},
    );
    defer no_unsafe_optional_chaining_config.deinit();
    try options.setByRuleConfigValue("no-unsafe-optional-chaining", no_unsafe_optional_chaining_config.value);
    try std.testing.expect(options.no_unsafe_optional_chaining);
    try std.testing.expect(options.no_unsafe_optional_chaining_disallow_arithmetic_operators);

    var no_return_assign_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"always\"]",
        .{},
    );
    defer no_return_assign_config.deinit();
    try options.setByRuleConfigValue("no-return-assign", no_return_assign_config.value);
    try std.testing.expect(options.no_return_assign);
    try std.testing.expectEqual(NoReturnAssignStyle.always, options.no_return_assign_style);

    var no_sequences_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowInParentheses\":false}]",
        .{},
    );
    defer no_sequences_config.deinit();
    try options.setByRuleConfigValue("no-sequences", no_sequences_config.value);
    try std.testing.expect(options.no_sequences);
    try std.testing.expectEqual(NoSequencesAllowInParentheses.no, options.no_sequences_allow_in_parentheses);

    var no_useless_computed_key_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"enforceForClassMembers\":false}]",
        .{},
    );
    defer no_useless_computed_key_config.deinit();
    try options.setByRuleConfigValue("no-useless-computed-key", no_useless_computed_key_config.value);
    try std.testing.expect(options.no_useless_computed_key);
    try std.testing.expectEqual(
        NoUselessComputedKeyEnforceForClassMembers.no,
        options.no_useless_computed_key_enforce_for_class_members,
    );

    var no_unused_expressions_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowShortCircuit\":true,\"allowTernary\":true,\"allowTaggedTemplates\":false}]",
        .{},
    );
    defer no_unused_expressions_config.deinit();
    try options.setByRuleConfigValue("no-unused-expressions", no_unused_expressions_config.value);
    try std.testing.expect(options.no_unused_expressions);
    try std.testing.expectEqual(NoUnusedExpressionsAllowShortCircuit.yes, options.no_unused_expressions_allow_short_circuit);
    try std.testing.expectEqual(NoUnusedExpressionsAllowTernary.yes, options.no_unused_expressions_allow_ternary);
    try std.testing.expectEqual(NoUnusedExpressionsAllowTaggedTemplates.no, options.no_unused_expressions_allow_tagged_templates);

    var no_unused_expressions_default_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\"]",
        .{},
    );
    defer no_unused_expressions_default_config.deinit();
    try options.setByRuleConfigValue("no-unused-expressions", no_unused_expressions_default_config.value);
    try std.testing.expectEqual(NoUnusedExpressionsAllowTaggedTemplates.no, options.no_unused_expressions_allow_tagged_templates);

    var typescript_no_unused_expressions_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowShortCircuit\":false,\"allowTernary\":false,\"allowTaggedTemplates\":false}]",
        .{},
    );
    defer typescript_no_unused_expressions_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-expressions", typescript_no_unused_expressions_config.value);
    try std.testing.expect(options.typescript_eslint_no_unused_expressions);
    try std.testing.expectEqual(NoUnusedExpressionsAllowShortCircuit.no, options.typescript_eslint_no_unused_expressions_allow_short_circuit);
    try std.testing.expectEqual(NoUnusedExpressionsAllowTernary.no, options.typescript_eslint_no_unused_expressions_allow_ternary);
    try std.testing.expectEqual(NoUnusedExpressionsAllowTaggedTemplates.no, options.typescript_eslint_no_unused_expressions_allow_tagged_templates);

    var no_unused_vars_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"args\":\"all\",\"argsIgnorePattern\":\"^_\",\"caughtErrors\":\"none\",\"caughtErrorsIgnorePattern\":\"^ignoredError\",\"destructuredArrayIgnorePattern\":\"^ignoredItem\",\"ignoreClassWithStaticInitBlock\":true,\"ignoreRestSiblings\":true,\"ignoreUsingDeclarations\":true,\"reportUsedIgnorePattern\":true,\"varsIgnorePattern\":\"^ignored\"}]",
        .{},
    );
    defer no_unused_vars_config.deinit();
    try options.setByRuleConfigValue("no-unused-vars", no_unused_vars_config.value);
    try std.testing.expect(options.no_unused_vars);
    try std.testing.expectEqual(NoUnusedVarsVars.all, options.no_unused_vars_vars);
    try std.testing.expectEqual(NoUnusedVarsArgs.all, options.no_unused_vars_args);
    try std.testing.expectEqual(NoUnusedVarsCaughtErrors.none, options.no_unused_vars_caught_errors);
    try std.testing.expect(options.no_unused_vars_ignore_rest_siblings);
    try std.testing.expect(options.no_unused_vars_ignore_class_with_static_init_block);
    try std.testing.expect(options.no_unused_vars_ignore_using_declarations);
    try std.testing.expect(options.no_unused_vars_report_used_ignore_pattern);
    try std.testing.expectEqualStrings("^_", options.no_unused_vars_args_ignore_pattern.pattern().?);
    try std.testing.expectEqualStrings("^ignoredError", options.no_unused_vars_caught_errors_ignore_pattern.pattern().?);
    try std.testing.expectEqualStrings("^ignoredItem", options.no_unused_vars_destructured_array_ignore_pattern.pattern().?);
    try std.testing.expectEqualStrings("^ignored", options.no_unused_vars_vars_ignore_pattern.pattern().?);

    var typescript_no_unused_vars_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"vars\":\"local\",\"args\":\"none\",\"argsIgnorePattern\":\"^unused\",\"caughtErrors\":\"none\",\"caughtErrorsIgnorePattern\":\"Error$\",\"destructuredArrayIgnorePattern\":\"Item$\",\"ignoreClassWithStaticInitBlock\":true,\"ignoreRestSiblings\":false,\"ignoreUsingDeclarations\":true,\"reportUsedIgnorePattern\":true,\"varsIgnorePattern\":\"Ignored$\"}]",
        .{},
    );
    defer typescript_no_unused_vars_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-unused-vars", typescript_no_unused_vars_config.value);
    try std.testing.expect(options.typescript_eslint_no_unused_vars);
    try std.testing.expectEqual(NoUnusedVarsVars.local, options.typescript_eslint_no_unused_vars_vars);
    try std.testing.expectEqual(NoUnusedVarsArgs.none, options.typescript_eslint_no_unused_vars_args);
    try std.testing.expectEqual(NoUnusedVarsCaughtErrors.none, options.typescript_eslint_no_unused_vars_caught_errors);
    try std.testing.expect(!options.typescript_eslint_no_unused_vars_ignore_rest_siblings);
    try std.testing.expect(options.typescript_eslint_no_unused_vars_ignore_class_with_static_init_block);
    try std.testing.expect(options.typescript_eslint_no_unused_vars_ignore_using_declarations);
    try std.testing.expect(options.typescript_eslint_no_unused_vars_report_used_ignore_pattern);
    try std.testing.expectEqualStrings("^unused", options.typescript_eslint_no_unused_vars_args_ignore_pattern.pattern().?);
    try std.testing.expectEqualStrings("Error$", options.typescript_eslint_no_unused_vars_caught_errors_ignore_pattern.pattern().?);
    try std.testing.expectEqualStrings("Item$", options.typescript_eslint_no_unused_vars_destructured_array_ignore_pattern.pattern().?);
    try std.testing.expectEqualStrings("Ignored$", options.typescript_eslint_no_unused_vars_vars_ignore_pattern.pattern().?);

    var typescript_ban_types_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"extendDefaults\":false,\"types\":{\"String\":false,\"object\":\"Use a named object shape.\",\"CustomType\":{\"message\":\"Use BetterType instead.\"}}}]",
        .{},
    );
    defer typescript_ban_types_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/ban-types", typescript_ban_types_config.value);
    try std.testing.expect(options.typescript_eslint_ban_types);
    try std.testing.expect(!options.typescript_eslint_ban_types_config.extend_defaults);
    try std.testing.expect(options.typescript_eslint_ban_types_config.disabled.contains("String"));
    try std.testing.expectEqualStrings(
        "Use a named object shape.",
        options.typescript_eslint_ban_types_config.custom.messageFor("object") orelse "",
    );
    try std.testing.expectEqualStrings(
        "Use BetterType instead.",
        options.typescript_eslint_ban_types_config.custom.messageFor("CustomType") orelse "",
    );

    var typescript_consistent_type_assertions_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"assertionStyle\":\"angle-bracket\",\"objectLiteralTypeAssertions\":\"allow-as-parameter\",\"arrayLiteralTypeAssertions\":\"never\"}]",
        .{},
    );
    defer typescript_consistent_type_assertions_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/consistent-type-assertions", typescript_consistent_type_assertions_config.value);
    try std.testing.expect(options.typescript_eslint_consistent_type_assertions);
    try std.testing.expectEqual(
        TypescriptEslintConsistentTypeAssertionsStyle.angle_bracket,
        options.typescript_eslint_consistent_type_assertions_assertion_style,
    );
    try std.testing.expectEqual(
        TypescriptEslintLiteralTypeAssertions.allow_as_parameter,
        options.typescript_eslint_consistent_type_assertions_object_literal_type_assertions,
    );
    try std.testing.expectEqual(
        TypescriptEslintLiteralTypeAssertions.never,
        options.typescript_eslint_consistent_type_assertions_array_literal_type_assertions,
    );

    var typescript_explicit_member_accessibility_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"accessibility\":\"explicit\"}]",
        .{},
    );
    defer typescript_explicit_member_accessibility_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/explicit-member-accessibility", typescript_explicit_member_accessibility_config.value);
    try std.testing.expect(options.typescript_eslint_explicit_member_accessibility);
    try std.testing.expectEqual(
        TypescriptEslintExplicitMemberAccessibility.explicit,
        options.typescript_eslint_explicit_member_accessibility_accessibility,
    );

    var typescript_explicit_member_accessibility_off_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"accessibility\":\"off\"}]",
        .{},
    );
    defer typescript_explicit_member_accessibility_off_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/explicit-member-accessibility", typescript_explicit_member_accessibility_off_config.value);
    try std.testing.expectEqual(
        TypescriptEslintExplicitMemberAccessibility.off,
        options.typescript_eslint_explicit_member_accessibility_accessibility,
    );

    var typescript_no_inferrable_types_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"ignoreParameters\":true,\"ignoreProperties\":true}]",
        .{},
    );
    defer typescript_no_inferrable_types_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-inferrable-types", typescript_no_inferrable_types_config.value);
    try std.testing.expect(options.typescript_eslint_no_inferrable_types);
    try std.testing.expect(options.typescript_eslint_no_inferrable_types_ignore_parameters);
    try std.testing.expect(options.typescript_eslint_no_inferrable_types_ignore_properties);

    var typescript_no_invalid_void_type_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowAsThisParameter\":true,\"allowInGenericTypeArguments\":[\"Promise\",\"React.VoidFunctionComponent\"]}]",
        .{},
    );
    defer typescript_no_invalid_void_type_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-invalid-void-type", typescript_no_invalid_void_type_config.value);
    try std.testing.expect(options.typescript_eslint_no_invalid_void_type);
    try std.testing.expect(options.typescript_eslint_no_invalid_void_type_allow_as_this_parameter);
    try std.testing.expect(!options.typescript_eslint_no_invalid_void_type_allow_in_generic_type_arguments);
    try std.testing.expect(options.typescript_eslint_no_invalid_void_type_allowed_generic_type_names.contains("Promise"));
    try std.testing.expect(options.typescript_eslint_no_invalid_void_type_allowed_generic_type_names.contains("React.VoidFunctionComponent"));
    try std.testing.expect(!options.typescript_eslint_no_invalid_void_type_allowed_generic_type_names.contains("Map"));

    var typescript_no_require_imports_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowAsImport\":true,\"allow\":[\"^legacy-\",\"fs$\"]}]",
        .{},
    );
    defer typescript_no_require_imports_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-require-imports", typescript_no_require_imports_config.value);
    try std.testing.expect(options.typescript_eslint_no_require_imports);
    try std.testing.expect(options.typescript_eslint_no_require_imports_allow_as_import);
    try std.testing.expectEqual(@as(usize, 2), options.typescript_eslint_no_require_imports_allow.count);
    try std.testing.expectEqualStrings("^legacy-", options.typescript_eslint_no_require_imports_allow.at(0));
    try std.testing.expectEqualStrings("fs$", options.typescript_eslint_no_require_imports_allow.at(1));

    var typescript_restrict_plus_operands_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowNumberAndString\":true}]",
        .{},
    );
    defer typescript_restrict_plus_operands_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/restrict-plus-operands", typescript_restrict_plus_operands_config.value);
    try std.testing.expect(options.typescript_eslint_restrict_plus_operands);
    try std.testing.expect(options.typescript_eslint_restrict_plus_operands_allow_number_and_string);

    var no_use_before_define_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"functions\":false,\"classes\":false,\"variables\":false,\"allowNamedExports\":true}]",
        .{},
    );
    defer no_use_before_define_config.deinit();
    try options.setByRuleConfigValue("no-use-before-define", no_use_before_define_config.value);
    try std.testing.expect(options.no_use_before_define);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.no, options.no_use_before_define_check_functions);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.no, options.no_use_before_define_check_classes);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.no, options.no_use_before_define_check_variables);
    try std.testing.expect(options.no_use_before_define_allow_named_exports);

    var no_use_before_define_nofunc_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"nofunc\"]",
        .{},
    );
    defer no_use_before_define_nofunc_config.deinit();
    try options.setByRuleConfigValue("no-use-before-define", no_use_before_define_nofunc_config.value);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.no, options.no_use_before_define_check_functions);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.yes, options.no_use_before_define_check_classes);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.yes, options.no_use_before_define_check_variables);

    var no_undef_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"typeof\":true}]",
        .{},
    );
    defer no_undef_config.deinit();
    try options.setByRuleConfigValue("no-undef", no_undef_config.value);
    try std.testing.expect(options.no_undef);
    try std.testing.expect(options.no_undef_typeof);

    var no_tabs_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowIndentationTabs\":true}]",
        .{},
    );
    defer no_tabs_config.deinit();
    try options.setByRuleConfigValue("no-tabs", no_tabs_config.value);
    try std.testing.expect(options.no_tabs);
    try std.testing.expect(options.no_tabs_allow_indentation_tabs);

    var no_self_assign_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"props\":false}]",
        .{},
    );
    defer no_self_assign_config.deinit();
    try options.setByRuleConfigValue("no-self-assign", no_self_assign_config.value);
    try std.testing.expect(options.no_self_assign);
    try std.testing.expect(!options.no_self_assign_props);

    var no_unneeded_ternary_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"defaultAssignment\":false}]",
        .{},
    );
    defer no_unneeded_ternary_config.deinit();
    try options.setByRuleConfigValue("no-unneeded-ternary", no_unneeded_ternary_config.value);
    try std.testing.expect(options.no_unneeded_ternary);
    try std.testing.expect(!options.no_unneeded_ternary_default_assignment);

    var typescript_no_use_before_define_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"functions\":true,\"classes\":false,\"variables\":false,\"typedefs\":false,\"enums\":false,\"allowNamedExports\":true,\"ignoreTypeReferences\":false}]",
        .{},
    );
    defer typescript_no_use_before_define_config.deinit();
    try options.setByRuleConfigValue("@typescript-eslint/no-use-before-define", typescript_no_use_before_define_config.value);
    try std.testing.expect(options.typescript_eslint_no_use_before_define);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.yes, options.typescript_eslint_no_use_before_define_check_functions);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.no, options.typescript_eslint_no_use_before_define_check_classes);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.no, options.typescript_eslint_no_use_before_define_check_variables);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.no, options.typescript_eslint_no_use_before_define_check_typedefs);
    try std.testing.expectEqual(NoUseBeforeDefineCheck.no, options.typescript_eslint_no_use_before_define_check_enums);
    try std.testing.expect(options.typescript_eslint_no_use_before_define_allow_named_exports);
    try std.testing.expect(!options.typescript_eslint_no_use_before_define_ignore_type_references);

    var no_void_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowAsStatement\":true}]",
        .{},
    );
    defer no_void_config.deinit();
    try options.setByRuleConfigValue("no-void", no_void_config.value);
    try std.testing.expect(options.no_void);
    try std.testing.expectEqual(NoVoidAllowAsStatement.yes, options.no_void_allow_as_statement);

    var no_warning_comments_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"terms\":[\"review\",\"blocked by upstream\"],\"location\":\"anywhere\",\"decoration\":[\"/\",\"*\"]}]",
        .{},
    );
    defer no_warning_comments_config.deinit();
    try options.setByRuleConfigValue("no-warning-comments", no_warning_comments_config.value);
    try std.testing.expect(options.no_warning_comments);
    try std.testing.expectEqual(NoWarningCommentsLocation.anywhere, options.no_warning_comments_location);
    try std.testing.expectEqual(NoWarningCommentsDecoration.slash_asterisk, options.no_warning_comments_decoration);
    try std.testing.expectEqual(@as(usize, 2), options.no_warning_comments_terms.len());
    try std.testing.expectEqualStrings("review", options.no_warning_comments_terms.at(0));
    try std.testing.expectEqualStrings("blocked by upstream", options.no_warning_comments_terms.at(1));

    var valid_typeof_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"requireStringLiterals\":true}]",
        .{},
    );
    defer valid_typeof_config.deinit();
    try options.setByRuleConfigValue("valid-typeof", valid_typeof_config.value);
    try std.testing.expect(options.valid_typeof);
    try std.testing.expect(options.valid_typeof_require_string_literals);

    var spaced_comment_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"never\",{\"markers\":[\"/\",\"!\"],\"exceptions\":[\"-\",\"+\"]}]",
        .{},
    );
    defer spaced_comment_config.deinit();
    try options.setByRuleConfigValue("spaced-comment", spaced_comment_config.value);
    try std.testing.expect(options.spaced_comment);
    try std.testing.expectEqual(SpacedCommentStyle.never, options.spaced_comment_style);
    try std.testing.expect(options.spaced_comment_markers.matches("/ reference"));
    try std.testing.expect(options.spaced_comment_markers.matches("! license"));
    try std.testing.expect(!options.spaced_comment_markers.matches("# plain"));
    try std.testing.expect(options.spaced_comment_exceptions.matches("- separator"));
    try std.testing.expect(options.spaced_comment_exceptions.matches("+ separator"));
    try std.testing.expect(!options.spaced_comment_exceptions.matches("# plain"));

    var wrap_iife_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"inside\"]",
        .{},
    );
    defer wrap_iife_config.deinit();
    try options.setByRuleConfigValue("wrap-iife", wrap_iife_config.value);
    try std.testing.expect(options.wrap_iife);
    try std.testing.expectEqual(WrapIifeStyle.inside, options.wrap_iife_style);

    var yoda_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"always\"]",
        .{},
    );
    defer yoda_config.deinit();
    try options.setByRuleConfigValue("yoda", yoda_config.value);
    try std.testing.expect(options.yoda);
    try std.testing.expectEqual(YodaStyle.always, options.yoda_style);

    var yoda_only_equality_config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",\"never\",{\"onlyEquality\":true}]",
        .{},
    );
    defer yoda_only_equality_config.deinit();
    try options.setByRuleConfigValue("yoda", yoda_only_equality_config.value);
    try std.testing.expectEqual(YodaStyle.never, options.yoda_style);
    try std.testing.expect(options.yoda_only_equality);

    try std.testing.expectError(
        Options.RuleConfigError.UnsupportedRuleConfigValue,
        options.setByRuleConfigValue("no-debugger", .{ .string = "sometimes" }),
    );
    try std.testing.expectError(
        Options.RuleConfigError.UnknownRule,
        options.setByRuleConfigValue("unknown-rule", .{ .string = "off" }),
    );
}

test "Options parses ESLint-style rule severities" {
    try std.testing.expectEqual(null, try Options.severityFromRuleConfigValue(.{ .string = "off" }));
    try std.testing.expectEqual(Severity.warning, try Options.severityFromRuleConfigValue(.{ .string = "warn" }));
    try std.testing.expectEqual(Severity.@"error", try Options.severityFromRuleConfigValue(.{ .string = "error" }));
    try std.testing.expectEqual(Severity.warning, try Options.severityFromRuleConfigValue(.{ .integer = 1 }));
    try std.testing.expectEqual(Severity.@"error", try Options.severityFromRuleConfigValue(.{ .integer = 2 }));
    try std.testing.expectEqual(Severity.@"error", try Options.severityFromRuleConfigValue(.{ .bool = true }));

    var array = std.json.Array.init(std.testing.allocator);
    defer array.deinit();
    try array.append(.{ .string = "warn" });
    try std.testing.expectEqual(Severity.warning, try Options.severityFromRuleConfigValue(.{ .array = array }));
}
