import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { writeFile as writeFileAsync } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, extname, isAbsolute, join, relative, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";

import { resolveBinary } from "./lib/binary.js";
import { createLegacyConfigResolver } from "./lib/legacy-config.cjs";
import { formatESLintResults } from "./lib/stylish-formatter.cjs";
import {
  findConfigPath as findConfigPathFromDirectory,
  readConfig
} from "./lib/config-loader.js";

export { platformPackageName, resolveBinary } from "./lib/binary.js";

export const version = JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8")).version;

const LINTABLE_EXTENSIONS = new Set([".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts"]);
const MAX_AUTOFIX_PASSES = 10;
const CONFIG_DISCOVERY_CACHE = Symbol("configDiscoveryCache");
const LEGACY_CONFIG_ENABLED = Symbol("legacyConfigEnabled");
const LEGACY_CONFIG_RESOLVER = Symbol("legacyConfigResolver");
const JS_KEYWORDS = new Set([
  "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
  "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in",
  "instanceof", "let", "new", "return", "super", "switch", "this", "throw", "try", "typeof",
  "var", "void", "while", "with", "yield"
]);
const AST_TRAVERSAL_SKIP_KEYS = new Set([
  "type", "parent", "loc", "range", "tokens", "comments", "leadingComments", "trailingComments",
  "innerComments", "raw", "value", "name", "regex", "bigint", "errors"
]);
const RULE_TESTER_INITIAL_CONFIG = { rules: {} };
let ruleTesterDefaultConfig = { rules: {} };
let ruleTesterDescribe = null;
let ruleTesterIt = null;
let ruleTesterItOnly = null;
const FISHLINT_DROP_FLAGS = new Set([
  "--cache",
  "--color",
  "--debug",
  "--disable-legacy",
  "--disable-setup",
  "--no-cache",
  "--no-color",
  "--no-error-on-unmatched-pattern",
  "--no-eslintrc",
  "--no-ignore",
  "--no-inline-config",
  "--no-warn-ignored",
  "--pass-on-no-patterns",
  "--quiet",
  "--report-unused-disable-directives",
  "--stats",
  "--stdin",
  "--verbose",
  "-v"
]);
const FISHLINT_DROP_VALUE_FLAGS = new Set([
  "--cache-location",
  "--cache-strategy",
  "--env",
  "--global",
  "--ignore-path",
  "--ignore-pattern",
  "--max-warnings",
  "--output-file",
  "--parser",
  "--parser-options",
  "--plugin",
  "--print-config",
  "--resolve-plugins-relative-to",
  "--rule",
  "--rulesdir",
  "--stdin-filename",
  "-E",
  "-o"
]);
const BUILTIN_RULE_IDS = [
  "accessor-pairs",
  "array-callback-return",
  "arrow-body-style",
  "block-scoped-var",
  "camelcase",
  "capitalized-comments",
  "class-methods-use-this",
  "complexity",
  "consistent-return",
  "consistent-this",
  "constructor-super",
  "curly",
  "default-case",
  "default-case-last",
  "default-param-last",
  "dot-notation",
  "eol-last",
  "eqeqeq",
  "for-direction",
  "func-name-matching",
  "func-names",
  "func-style",
  "getter-return",
  "grouped-accessor-pairs",
  "guard-for-in",
  "id-denylist",
  "id-length",
  "id-match",
  "init-declarations",
  "linebreak-style",
  "logical-assignment-operators",
  "max-classes-per-file",
  "max-depth",
  "max-lines",
  "max-lines-per-function",
  "max-nested-callbacks",
  "max-params",
  "max-statements",
  "new-cap",
  "new-parens",
  "no-alert",
  "no-array-constructor",
  "no-async-promise-executor",
  "no-await-in-loop",
  "no-bitwise",
  "no-buffer-constructor",
  "no-caller",
  "no-case-declarations",
  "no-class-assign",
  "no-confusing-arrow",
  "no-comma-operator",
  "no-compare-neg-zero",
  "no-cond-assign",
  "no-console",
  "no-const-assign",
  "no-constant-binary-expression",
  "no-constant-condition",
  "no-constructor-return",
  "no-continue",
  "no-control-regex",
  "no-debugger",
  "no-delete-var",
  "no-div-regex",
  "no-dupe-args",
  "no-dupe-class-members",
  "no-dupe-else-if",
  "no-dupe-keys",
  "no-duplicate-case",
  "no-duplicate-imports",
  "no-else-return",
  "no-empty",
  "no-empty-block-statements",
  "no-empty-character-class",
  "no-empty-function",
  "no-empty-pattern",
  "no-empty-static-block",
  "no-eq-null",
  "no-eval",
  "no-ex-assign",
  "no-extend-native",
  "no-extra-bind",
  "no-extra-boolean-cast",
  "no-extra-label",
  "no-extra-semi",
  "no-fallthrough",
  "no-floating-decimal",
  "no-for-in",
  "no-func-assign",
  "no-global-assign",
  "no-global-is-finite",
  "no-global-is-nan",
  "no-implicit-coercion",
  "no-implicit-globals",
  "no-implied-eval",
  "no-import-assign",
  "no-inline-comments",
  "no-inner-declarations",
  "no-invalid-regexp",
  "no-invalid-this",
  "no-irregular-whitespace",
  "no-iterator",
  "no-label-var",
  "no-labels",
  "no-lone-blocks",
  "no-lonely-if",
  "no-loop-func",
  "no-loss-of-precision",
  "no-magic-numbers",
  "no-mixed-spaces-and-tabs",
  "no-misleading-character-class",
  "no-multi-assign",
  "no-multi-spaces",
  "no-multi-str",
  "no-multiple-empty-lines",
  "no-negated-condition",
  "no-nested-ternary",
  "no-new",
  "no-new-func",
  "no-new-native-nonconstructor",
  "no-new-object",
  "no-new-require",
  "no-new-symbol",
  "no-new-wrappers",
  "no-nonoctal-decimal-escape",
  "no-obj-calls",
  "no-object-constructor",
  "no-octal",
  "no-octal-escape",
  "no-param-reassign",
  "no-path-concat",
  "no-plusplus",
  "no-process-env",
  "no-process-exit",
  "no-promise-executor-return",
  "no-proto",
  "no-prototype-builtins",
  "no-redeclare",
  "no-restricted-exports",
  "no-restricted-globals",
  "no-restricted-imports",
  "no-restricted-modules",
  "no-restricted-properties",
  "no-restricted-syntax",
  "no-regex-spaces",
  "no-return-assign",
  "no-return-await",
  "no-script-url",
  "no-self-assign",
  "no-self-compare",
  "no-sequences",
  "no-setter-return",
  "no-shadow",
  "no-shadow-restricted-names",
  "no-sparse-arrays",
  "no-tabs",
  "no-template-curly-in-string",
  "no-ternary",
  "no-this-before-super",
  "no-throw-literal",
  "no-trailing-spaces",
  "no-undef",
  "no-undef-init",
  "no-unassigned-vars",
  "no-underscore-dangle",
  "no-undefined",
  "no-unneeded-ternary",
  "no-unexpected-multiline",
  "no-unmodified-loop-condition",
  "no-unreachable",
  "no-unreachable-loop",
  "no-unsafe-finally",
  "no-unsafe-negation",
  "no-unsafe-optional-chaining",
  "no-unused-expressions",
  "no-unused-labels",
  "no-unused-private-class-members",
  "no-unused-vars",
  "no-use-before-define",
  "no-useless-assignment",
  "no-useless-backreference",
  "no-useless-call",
  "no-useless-catch",
  "no-useless-computed-key",
  "no-useless-concat",
  "no-useless-constructor",
  "no-useless-escape",
  "no-useless-rename",
  "no-useless-return",
  "no-var",
  "no-void",
  "no-warning-comments",
  "no-with",
  "object-shorthand",
  "one-var",
  "operator-assignment",
  "prefer-arrow-callback",
  "prefer-const",
  "prefer-destructuring",
  "prefer-exponentiation-operator",
  "prefer-named-capture-group",
  "prefer-numeric-literals",
  "prefer-object-has-own",
  "prefer-object-spread",
  "prefer-promise-reject-errors",
  "preserve-caught-error",
  "prefer-regex-literals",
  "prefer-rest-params",
  "prefer-spread",
  "prefer-template",
  "radix",
  "require-await",
  "require-atomic-updates",
  "require-unicode-regexp",
  "require-yield",
  "sort-imports",
  "sort-keys",
  "sort-vars",
  "spaced-comment",
  "strict",
  "symbol-description",
  "unicode-bom",
  "use-isnan",
  "valid-typeof",
  "vars-on-top",
  "wrap-iife",
  "yoda",
  "eslint-comments/no-restricted-disable",
  "import/default",
  "import/export",
  "import/first",
  "import/named",
  "import/namespace",
  "import/newline-after-import",
  "import/no-amd",
  "import/no-cycle",
  "import/no-duplicates",
  "import/no-named-as-default",
  "import/no-named-as-default-member",
  "import/no-unresolved",
  "import/no-self-import",
  "jest/no-conditional-expect",
  "jest/no-deprecated-functions",
  "jest/no-export",
  "jest/no-focused-tests",
  "jest/no-identical-title",
  "jest/no-interpolation-in-snapshots",
  "jest/no-jasmine-globals",
  "jest/no-mocks-import",
  "jest/no-standalone-expect",
  "jest/valid-describe-callback",
  "jest/valid-expect-in-promise",
  "jest/valid-expect",
  "jest/valid-title",
  "promise/no-promise-in-callback",
  "promise/no-return-in-finally",
  "promise/no-return-wrap",
  "promise/param-names",
  "promise/valid-params",
  "jsx-a11y/alt-text",
  "jsx-a11y/anchor-has-content",
  "jsx-a11y/aria-props",
  "jsx-a11y/aria-proptypes",
  "jsx-a11y/aria-role",
  "jsx-a11y/aria-unsupported-elements",
  "jsx-a11y/iframe-has-title",
  "jsx-a11y/img-redundant-alt",
  "jsx-a11y/no-access-key",
  "jsx-a11y/no-distracting-elements",
  "jsx-a11y/role-has-required-aria-props",
  "jsx-a11y/role-supports-aria-props",
  "jsx-a11y/scope",
  "promise/always-return",
  "promise/catch-or-return",
  "promise/no-callback-in-promise",
  "promise/no-nesting",
  "promise/no-new-statics",
  "react/button-has-type",
  "react/default-props-match-prop-types",
  "react/display-name",
  "react/forbid-prop-types",
  "react/jsx-boolean-value",
  "react/jsx-filename-extension",
  "react/jsx-key",
  "react/jsx-no-bind",
  "react/jsx-no-comment-textnodes",
  "react/jsx-no-duplicate-props",
  "react/jsx-no-undef",
  "react/jsx-uses-react",
  "react/jsx-uses-vars",
  "react/jsx-no-target-blank",
  "react/jsx-pascal-case",
  "react/no-access-state-in-setstate",
  "react/no-array-index-key",
  "react/no-children-prop",
  "react/no-danger",
  "react/no-danger-with-children",
  "react/no-deprecated",
  "react/no-direct-mutation-state",
  "react/no-find-dom-node",
  "react/no-forward-ref",
  "react/no-is-mounted",
  "react/no-multi-comp",
  "react/no-unstable-nested-components",
  "react/no-redundant-should-component-update",
  "react/no-render-return-value",
  "react/no-string-refs",
  "react/no-this-in-sfc",
  "react/no-typos",
  "react/no-unescaped-entities",
  "react/no-unknown-property",
  "react/no-unused-prop-types",
  "react/no-unused-state",
  "react/no-will-update-set-state",
  "react/prefer-es6-class",
  "react/prop-types",
  "react/require-render-return",
  "react/self-closing-comp",
  "react/style-prop-object",
  "react/void-dom-elements-no-children",
  "react-hooks/exhaustive-deps",
  "react-hooks/rules-of-hooks",
  "react-hooks/use-memo",
  "react-hooks/void-use-memo",
  "react-hooks/set-state-in-render",
  "react-hooks/purity",
  "unused-imports/no-unused-imports",
  "@typescript-eslint/adjacent-overload-signatures",
  "@typescript-eslint/array-type",
  "@typescript-eslint/ban-ts-comment",
  "@typescript-eslint/ban-tslint-comment",
  "@typescript-eslint/ban-types",
  "@typescript-eslint/class-literal-property-style",
  "@typescript-eslint/consistent-type-assertions",
  "@typescript-eslint/consistent-type-definitions",
  "@typescript-eslint/dot-notation",
  "@typescript-eslint/explicit-member-accessibility",
  "@typescript-eslint/member-ordering",
  "@typescript-eslint/method-signature-style",
  "@typescript-eslint/no-array-constructor",
  "@typescript-eslint/no-confusing-non-null-assertion",
  "@typescript-eslint/no-dupe-class-members",
  "@typescript-eslint/no-empty-function",
  "@typescript-eslint/no-empty-interface",
  "@typescript-eslint/no-empty-object-type",
  "@typescript-eslint/no-duplicate-enum-values",
  "@typescript-eslint/no-extra-semi",
  "@typescript-eslint/no-extra-non-null-assertion",
  "@typescript-eslint/no-explicit-any",
  "@typescript-eslint/no-inferrable-types",
  "@typescript-eslint/no-invalid-void-type",
  "@typescript-eslint/no-loop-func",
  "@typescript-eslint/no-loss-of-precision",
  "@typescript-eslint/no-misused-new",
  "@typescript-eslint/no-namespace",
  "@typescript-eslint/no-non-null-asserted-optional-chain",
  "@typescript-eslint/no-redeclare",
  "@typescript-eslint/no-require-imports",
  "@typescript-eslint/no-shadow",
  "@typescript-eslint/no-this-alias",
  "@typescript-eslint/no-unsafe-declaration-merging",
  "@typescript-eslint/no-unsafe-function-type",
  "@typescript-eslint/triple-slash-reference",
  "@typescript-eslint/typedef",
  "@typescript-eslint/unified-signatures",
  "@typescript-eslint/no-unnecessary-parameter-property-assignment",
  "@typescript-eslint/no-unnecessary-type-constraint",
  "@typescript-eslint/no-useless-constructor",
  "@typescript-eslint/no-useless-empty-export",
  "@typescript-eslint/no-unused-expressions",
  "@typescript-eslint/no-unused-vars",
  "@typescript-eslint/no-use-before-define",
  "@typescript-eslint/no-var-requires",
  "@typescript-eslint/no-wrapper-object-types",
  "@typescript-eslint/prefer-as-const",
  "@typescript-eslint/prefer-namespace-keyword",
  "@typescript-eslint/restrict-plus-operands"
];
const NATIVE_ONLY_RULE_IDS = [
  "@alipay/ant/disallow-typos",
  "@alipay/ant/exhaustive-deps",
  "@alipay/ant/jsx-handler-names",
  "@alipay/ant/no-deprecated-dependence",
  "@alipay/ant/no-deprecated-variable",
  "@alipay/ant/no-import-files-from-pages-in-common",
  "@alipay/ant/no-negative-conditionals",
  "@alipay/ant/no-import-src",
  "@alipay/ant/no-phantom-dependencies",
  "@alipay/ant/no-too-large-file",
  "@alipay/ant/prefer-elseif-end-with-else",
  "@alipay/ant/prefer-catch-unsafe-func-call",
  "@alipay/ant/prefer-click-with-debounce",
  "@alipay/ant/prefer-import-as-required",
  "@alipay/ant/no-spread-params",
  "@alipay/ant/prefer-managed-resource",
  "@alipay/ant/prefer-safe-image-renderer",
  "@alipay/ant/prefer-import-from-stdlib",
  "@alipay/spmLint/use-labeled-spm",
  "@alipay/spmLint/valid-manual-click",
  "@alipay/spmLint/valid-manual-expo",
  "@alipay/spmLint/valid-manual-param",
  "@alipay/spmLint/valid-manual-pv",
  "semantic-errors"
];
const NATIVE_RULE_IDS = [...BUILTIN_RULE_IDS, ...NATIVE_ONLY_RULE_IDS];
const FIXABLE_BUILTIN_RULE_IDS = new Set([
  "@typescript-eslint/no-explicit-any",
  "jest/no-deprecated-functions",
  "jest/no-jasmine-globals",
  "no-extra-semi",
  "@typescript-eslint/no-extra-semi",
  "unused-imports/no-unused-imports"
]);
const SUGGESTION_BUILTIN_RULE_IDS = new Set([
  "@typescript-eslint/no-explicit-any",
  "jest/no-focused-tests"
]);
const BUILTIN_RULES = new Map(BUILTIN_RULE_IDS.map((ruleId) => [ruleId, createBuiltinRule(ruleId)]));

export class UtooLint {
  static get version() {
    return version;
  }

  static get configType() {
    return "flat";
  }

  static get defaultConfig() {
    return [];
  }

  static async fromOptionsModule(optionsURL) {
    if (!(optionsURL instanceof URL)) {
      throw new TypeError("Argument must be a URL object");
    }
    const loaded = await import(optionsURL.href);
    return new UtooLint(loaded.default ?? loaded);
  }

  static async outputFixes(results) {
    if (!Array.isArray(results)) {
      throw new Error("'results' must be an array");
    }

    await Promise.all(
      results
        .filter((result) => {
          if (typeof result !== "object" || result === null) {
            throw new Error("'results' must include only objects");
          }
          return typeof result.output === "string" && isAbsolute(result.filePath);
        })
        .map((result) => writeFileAsync(result.filePath, result.output))
    );
  }

  static getErrorResults(results) {
    return getErrorResults(results);
  }

  constructor(options = {}) {
    this.options = { ...options };
  }

  async lintFiles(patterns, options = {}) {
    const mergedOptions = withConfigCache(mergeLintOptions(this.options, options));
    const customRuleConfig = [mergedOptions.baseConfig, mergedOptions.overrideConfig].filter(Boolean);
    const customRuleFilterMap = customRuleMapForConfig(customRuleConfig, new Map());
    const nativeOptions = lintOptionsWithoutCustomRules(mergedOptions, customRuleFilterMap);
    const report = lintFiles(patterns, nativeOptions);
    throwOnUnmatchedPatternDiagnostics(report, nativeOptions);
    const results = reportToESLintResults(report, {
      cwd: mergedOptions.cwd,
      filePaths: reportFilePaths(report, mergedOptions.cwd, explicitLintFilePaths(report.filePaths ?? patterns, mergedOptions.cwd)),
      ruleSeverityForFile: (filePath) => ruleSeverityMapForOptions(nativeOptions, filePath)
    });
    appendCustomLintFileMessages(results, customRuleConfig, mergedOptions);
    return maybeFilterQuietResults(results, mergedOptions);
  }

  async lintText(code, options = {}) {
    if (typeof code !== "string") {
      throw new TypeError("code must be a string");
    }

    const mergedOptions = withConfigCache(mergeLintOptions(this.options, options));
    const filePath = normalizeESLintFilePath(textFilePathForOptions(options, "<text>"), mergedOptions.cwd);
    const customRuleConfig = [mergedOptions.baseConfig, mergedOptions.overrideConfig].filter(Boolean);
    const customRuleMap = customRuleMapForConfig(customRuleConfig, new Map(), filePath, mergedOptions.cwd);
    const customRuleFilterMap = customRuleMapForConfig(customRuleConfig, new Map());
    const nativeOptions = lintOptionsWithoutCustomRules(mergedOptions, customRuleFilterMap);
    const report = lintText(code, nativeOptions);
    const results = reportToESLintResults(report, {
      source: code,
      filePath,
      includeEmptyTextResult: report.files !== 0 || (report.diagnostics?.length ?? 0) > 0 || (report.suppressedDiagnostics?.length ?? 0) > 0,
      ruleSeverityForFile: (filePath) => ruleSeverityMapForOptions(nativeOptions, filePath)
    });
    if (report.files !== 0) {
      appendCustomLintTextMessages(results, code, filePath, customRuleConfig, customRuleMap, mergedOptions);
    }
    return maybeFilterQuietResults(results, mergedOptions);
  }

  async isPathIgnored(filePath) {
    return isPathIgnored(filePath, withConfigCache(mergeLintOptions(this.options, {})));
  }

  async calculateConfigForFile(filePath) {
    return publicCalculatedConfig(withConfigCache(eslintConstructorOptions(this.options)), filePath);
  }

  async findConfigFile(filePath) {
    const options = withConfigCache(eslintConstructorOptions(this.options));
    if (options.legacyConfigFile) {
      return resolvePath(options.cwd ?? process.cwd(), options.legacyConfigFile);
    }
    if (options.noConfig) {
      return undefined;
    }
    if (filePath) {
      return configPathForFile(options, filePath);
    }
    return configPathForOptions(options);
  }

  getRulesMetaForResults(results) {
    if (!Array.isArray(results)) {
      throw new Error("'results' must be an array");
    }
    const options = eslintConstructorOptions(this.options);
    const customRuleConfig = [options.baseConfig, options.overrideConfig].filter(Boolean);
    const rulesByFilePath = new Map();
    return rulesMetaForResults(results, (ruleId, result) => {
      if (customRuleConfig.length === 0 || typeof result.filePath !== "string") {
        return undefined;
      }
      const filePath = normalizeESLintFilePath(result.filePath, options.cwd);
      if (!rulesByFilePath.has(filePath)) {
        rulesByFilePath.set(filePath, customRuleMapForConfig(customRuleConfig, new Map(), filePath, options.cwd));
      }
      return rulesByFilePath.get(filePath).get(ruleId)?.meta;
    });
  }

  hasFlag(flag) {
    return hasFlagInOptions(this.options, flag);
  }

  async loadFormatter(name = "stylish") {
    const eslint = this;
    return {
      format(results) {
        return formatResultsByName(results, name, {
          rulesMeta: (results) => eslint.getRulesMetaForResults(results)
        }, eslint.options);
      }
    };
  }
}

export { UtooLint as ESLint };

export async function loadESLint() {
  return UtooLint;
}

export class Linter {
  static get version() {
    return version;
  }

  constructor(options = {}) {
    this.flags = flagsFromOptions(options);
    this.rules = new Map();
    this.parsers = new Map();
    this.sourceCode = null;
    this.suppressedMessages = [];
    this.times = { passes: [] };
    this.fixPassCount = 0;
  }

  verify(code, config = {}, options = {}) {
    if (typeof code !== "string") {
      throw new TypeError("code must be a string");
    }

    const verifyOptions = typeof options === "string" ? { filename: options } : { ...options };
    const filePath = verifyOptions.filename ?? verifyOptions.filePath ?? "input.js";
    const normalizedFilePath = normalizeESLintFilePath(filePath, verifyOptions.cwd);
    const sourceCode = createLinterSourceCode(
      code,
      parserForConfig(config, this.parsers, normalizedFilePath, verifyOptions.cwd),
      parserOptionsForConfig(config, normalizedFilePath, verifyOptions.cwd)
    );
    const customRuleMap = customRuleMapForConfig(config, this.rules, normalizedFilePath, verifyOptions.cwd);
    const customRuleFilterMap = customRuleMapForConfig(config, this.rules);
    const customRules = customRuleEntriesForConfig(config, customRuleMap, normalizedFilePath, verifyOptions.cwd);
    const nativeConfig = configWithoutCustomRules(config, customRuleFilterMap);
    const lintOptions = {
      cwd: verifyOptions.cwd,
      filePath,
      noConfig: true,
      noIgnore: true,
      warnIgnored: false,
      overrideConfig: nativeConfig
    };
    const report = lintText(code, lintOptions);
    const ruleSeverities = ruleSeverityMapForOptions(lintOptions, normalizedFilePath);
    this.sourceCode = sourceCode;
    const customRuleMessages = runCustomLinterRules(customRules, sourceCode, {
      cwd: verifyOptions.cwd,
      filename: filePath,
      config: calculatedConfig({ cwd: verifyOptions.cwd, noConfig: true, overrideConfig: config }, normalizedFilePath)
    });
    const nativeRuleFilter = applyDisableDirectives(
      (report.diagnostics ?? []).map((diagnostic) => diagnosticToESLintMessage(diagnostic, ruleSeverities)),
      sourceCode
    );
    const customRuleFilter = applyDisableDirectives(customRuleMessages, sourceCode);
    this.suppressedMessages = [
      ...(report.suppressedDiagnostics ?? []).map((diagnostic) => suppressedDiagnosticToESLintMessage(diagnostic, ruleSeverities)),
      ...nativeRuleFilter.suppressedMessages,
      ...customRuleFilter.suppressedMessages
    ];
    this.times = { passes: [] };
    this.fixPassCount = 0;
    return [
      ...nativeRuleFilter.messages,
      ...customRuleFilter.messages
    ];
  }

  verifyAndFix(code, config = {}, options = {}) {
    let output = code;
    let fixed = false;
    let fixPassCount = 0;
    for (let pass = 0; pass < MAX_AUTOFIX_PASSES; pass += 1) {
      const messages = this.verify(output, config, options);
      const fixedOutput = applyRuleFixes(output, messages.flatMap((message) => ruleFixItems(message.fix)));
      if (fixedOutput === output) {
        this.fixPassCount = fixPassCount;
        return {
          fixed,
          messages,
          output
        };
      }
      fixed = true;
      fixPassCount += 1;
      output = fixedOutput;
    }
    const messages = this.verify(output, config, options);
    this.fixPassCount = fixPassCount;
    return {
      fixed,
      messages,
      output
    };
  }

  getSourceCode() {
    return this.sourceCode;
  }

  getSuppressedMessages() {
    return this.suppressedMessages;
  }

  getTimes() {
    return this.times;
  }

  getFixPassCount() {
    return this.fixPassCount;
  }

  hasFlag(flag) {
    return this.flags.includes(flag);
  }

  getRules() {
    return new Map([...BUILTIN_RULES, ...this.rules]);
  }

  defineRule(ruleId, rule) {
    if (typeof ruleId !== "string" || ruleId.length === 0) {
      throw new TypeError("Linter#defineRule requires a rule id string");
    }
    this.rules.set(ruleId, rule);
  }

  defineRules(rules) {
    if (typeof rules !== "object" || rules === null) {
      throw new TypeError("Linter#defineRules requires a rules object");
    }
    for (const [ruleId, rule] of Object.entries(rules)) {
      this.defineRule(ruleId, rule);
    }
  }

  defineParser(parserId, parser) {
    if (typeof parserId !== "string" || parserId.length === 0) {
      throw new TypeError("Linter#defineParser requires a parser id string");
    }
    this.parsers.set(parserId, parser);
  }
}

function parserForConfig(config, parsers, filePath, cwd) {
  let parser = null;
  for (const entry of matchingConfigEntries(config, filePath, cwd)) {
    parser = entry.languageOptions?.parser ?? entry.parser ?? parser;
  }
  if (typeof parser === "string") {
    return parsers.get(parser) ?? null;
  }
  return parser && typeof parser === "object" ? parser : null;
}

function parserOptionsForConfig(config, filePath, cwd) {
  const configData = configDataFromConfig(config, filePath, cwd);
  return {
    ...(configData.parserOptions ?? {}),
    ...(configData.languageOptions?.parserOptions ?? {}),
    filename: filePath,
    filePath,
    cwd
  };
}

function customRuleEntriesForConfig(config, rules, filePath, cwd) {
  const entries = new Map();
  for (const [ruleId, ruleConfig] of Object.entries(rulesFromConfig(config, filePath, cwd))) {
    if (!rules.has(ruleId)) {
      continue;
    }
    const severity = ruleConfigSeverity(ruleConfig);
    if (severity === 0) {
      entries.delete(ruleId);
      continue;
    }
    entries.set(ruleId, {
      ruleId,
      rule: rules.get(ruleId),
      severity,
      options: Array.isArray(ruleConfig) ? ruleConfig.slice(1) : []
    });
  }
  return [...entries.values()];
}

function customRuleMapForConfig(config, definedRules, filePath, cwd) {
  return new Map([
    ...pluginRulesForConfig(config, filePath, cwd),
    ...definedRules
  ]);
}

function pluginRulesForConfig(config, filePath, cwd) {
  const rules = new Map();
  for (const entry of matchingConfigEntries(config, filePath, cwd)) {
    if (!entry.plugins || typeof entry.plugins !== "object") {
      continue;
    }
    for (const [pluginName, plugin] of Object.entries(entry.plugins)) {
      if (!plugin?.rules || typeof plugin.rules !== "object") {
        continue;
      }
      for (const [ruleName, rule] of Object.entries(plugin.rules)) {
        rules.set(`${pluginName}/${ruleName}`, rule);
      }
    }
  }
  return rules;
}

function matchingConfigEntries(config, filePath = undefined, cwd = undefined) {
  if (!config) {
    return [];
  }
  if (Array.isArray(config)) {
    return config.flatMap((entry) => matchingConfigEntries(entry, filePath, cwd));
  }
  if (typeof config !== "object" || !configAppliesToFile(config, filePath, cwd)) {
    return [];
  }
  return [config];
}

function configWithoutCustomRules(config, rules) {
  if (Array.isArray(config)) {
    return config.map((item) => configWithoutCustomRules(item, rules));
  }
  if (!config || typeof config !== "object" || !config.rules || typeof config.rules !== "object") {
    return config;
  }

  let removedCustomRule = false;
  const nativeRules = {};
  for (const [ruleId, ruleConfig] of Object.entries(config.rules)) {
    if (rules.has(ruleId)) {
      removedCustomRule = true;
      continue;
    }
    nativeRules[ruleId] = ruleConfig;
  }
  return removedCustomRule ? { ...config, rules: nativeRules } : config;
}

function lintOptionsWithoutCustomRules(options, rules) {
  if (rules.size === 0) {
    return options;
  }
  return {
    ...options,
    baseConfig: configWithoutCustomRules(options.baseConfig, rules),
    overrideConfig: configWithoutCustomRules(options.overrideConfig, rules)
  };
}

function appendCustomLintTextMessages(results, code, filePath, config, rules, options) {
  const customRules = customRuleEntriesForConfig(config, rules, filePath, options.cwd);
  if (customRules.length === 0) {
    return results;
  }
  let result = results.find((item) => item.filePath === filePath);
  const effectiveCode = typeof result?.output === "string" ? result.output : code;
  const sourceCode = createLinterSourceCode(effectiveCode);
  const messages = runCustomLinterRules(customRules, sourceCode, {
    cwd: options.cwd,
    filename: filePath,
    config: calculatedConfig({ cwd: options.cwd, noConfig: true, baseConfig: options.baseConfig, overrideConfig: options.overrideConfig }, filePath)
  });
  const filtered = applyDisableDirectives(messages, sourceCode);
  if (filtered.messages.length === 0 && filtered.suppressedMessages.length === 0) {
    return results;
  }

  if (!result) {
    result = emptyESLintResult(filePath, effectiveCode);
    results.push(result);
  }
  result.messages.push(...filtered.messages);
  result.suppressedMessages.push(...filtered.suppressedMessages);
  applyResultFixes(result, effectiveCode, options);
  finalizeESLintResult(result);
  return results;
}

function appendCustomLintFileMessages(results, config, options) {
  for (const result of results) {
    const filePath = result.filePath;
    const rules = customRuleMapForConfig(config, new Map(), filePath, options.cwd);
    const customRules = customRuleEntriesForConfig(config, rules, filePath, options.cwd);
    if (customRules.length === 0) {
      continue;
    }
    let code = result.output;
    if (typeof code !== "string") {
      try {
        code = readFileSync(filePath, "utf8");
      } catch {
        continue;
      }
    }
    const sourceCode = createLinterSourceCode(code);
    const messages = runCustomLinterRules(customRules, sourceCode, {
      cwd: options.cwd,
      filename: filePath,
      config: calculatedConfig({ cwd: options.cwd, noConfig: true, baseConfig: options.baseConfig, overrideConfig: options.overrideConfig }, filePath)
    });
    const filtered = applyDisableDirectives(messages, sourceCode);
    if (filtered.messages.length === 0 && filtered.suppressedMessages.length === 0) {
      continue;
    }
    result.messages.push(...filtered.messages);
    result.suppressedMessages.push(...filtered.suppressedMessages);
    applyResultFixes(result, code, options);
    finalizeESLintResult(result);
  }
  return results;
}

function applyResultFixes(result, code, options) {
  if (!options.fix) {
    return;
  }
  const output = applyRuleFixes(code, result.messages.flatMap((message) => ruleFixItems(message.fix)));
  if (output !== code) {
    result.output = output;
  }
}

function runCustomLinterRules(ruleEntries, sourceCode, options) {
  if (ruleEntries.length === 0) {
    return [];
  }

  const messages = [];
  const program = sourceCode.ast ?? { type: "Program", range: [0, sourceCode.text.length] };
  for (const ruleEntry of ruleEntries) {
    const context = createCustomRuleContext(ruleEntry, sourceCode, options, messages);
    const listeners = customRuleListeners(ruleEntry.rule, context);
    if (customRuleChildNodes(program, sourceCode.visitorKeys).length > 0) {
      traverseCustomRuleAst(program, listeners, context, sourceCode.visitorKeys);
    } else {
      runCustomRuleTokenListeners(program, sourceCode.tokens, listeners, context);
    }
  }
  return messages;
}

function applyDisableDirectives(messages, sourceCode) {
  if (messages.length === 0) {
    return { messages, suppressedMessages: [] };
  }
  const directives = sourceCode.getDisableDirectives()
    .filter((directive) => directive.node?.loc?.start?.line)
    .filter((directive) => directive.type !== "eslint-disable-line" || directive.node.loc.start.line === directive.node.loc.end.line)
    .sort((left, right) => left.node.loc.start.line - right.node.loc.start.line);
  const utlintDirectives = sourceCode.getAllComments()
    .map((comment) => utlintDirectiveFromComment(comment, sourceCode))
    .filter(Boolean)
    .sort((left, right) => left.node.range[0] - right.node.range[0]);
  if (directives.length === 0 && utlintDirectives.length === 0) {
    return { messages, suppressedMessages: [] };
  }

  const kept = [];
  const suppressed = [];
  for (const message of messages) {
    if (!message.ruleId || message.ruleId === "parse" || message.ruleId === "io") {
      kept.push(message);
      continue;
    }
    const directive = utlintDirectiveForMessage(message, utlintDirectives) ?? disableDirectiveForMessage(message, directives);
    if (directive) {
      suppressed.push({
        ...message,
        suppressions: [{
          kind: "directive",
          justification: directive.justification
        }]
      });
    } else {
      kept.push(message);
    }
  }
  return { messages: kept, suppressedMessages: suppressed };
}

function utlintDirectiveFromComment(comment, sourceCode) {
  const match = String(comment?.value ?? "").trim().match(/^(utlint-ignore(?:-all|-start|-end)?)\b\s*(.*)$/u);
  if (!match) {
    return null;
  }

  const [, type, tail] = match;
  const colon = tail.indexOf(":");
  const rawRuleId = (colon === -1 ? tail : tail.slice(0, colon)).trim();
  const justification = colon === -1 ? "" : tail.slice(colon + 1).trim();
  const nextToken = sourceCode.getAllTokens().find((token) => token.range?.[0] >= comment.range?.[1]);
  return {
    type,
    node: comment,
    ruleId: rawRuleId || null,
    justification,
    nextCodeLine: nextToken?.loc?.start?.line ?? null,
    topLevel: sourceCode.getAllTokens().every((token) => token.range?.[0] >= comment.range?.[0])
  };
}

function utlintDirectiveForMessage(message, directives) {
  let allRulesRangeDepth = 0;
  let namedRuleRangeDepth = 0;
  let allRulesRangeDirective = null;
  let namedRuleRangeDirective = null;

  for (const directive of directives) {
    if (directive.node.loc.start.line > message.line) {
      break;
    }
    if (directive.type === "utlint-ignore-start") {
      if (directive.ruleId == null) {
        allRulesRangeDirective ??= directive;
        allRulesRangeDepth += 1;
      } else if (directive.ruleId === message.ruleId) {
        namedRuleRangeDirective ??= directive;
        namedRuleRangeDepth += 1;
      }
      continue;
    }
    if (directive.type === "utlint-ignore-end") {
      if (directive.ruleId == null && allRulesRangeDepth > 0) {
        allRulesRangeDepth -= 1;
        if (allRulesRangeDepth === 0) allRulesRangeDirective = null;
      } else if (directive.ruleId === message.ruleId && namedRuleRangeDepth > 0) {
        namedRuleRangeDepth -= 1;
        if (namedRuleRangeDepth === 0) namedRuleRangeDirective = null;
      }
      continue;
    }
    if (directive.type === "utlint-ignore-all" && directive.topLevel && disableDirectiveMatchesRule(directive, message.ruleId)) {
      return directive;
    }
    if (directive.type === "utlint-ignore" && directive.nextCodeLine === message.line && disableDirectiveMatchesRule(directive, message.ruleId)) {
      return directive;
    }
  }

  return namedRuleRangeDirective ?? allRulesRangeDirective;
}

function disableDirectiveForMessage(message, directives) {
  const active = {
    all: null,
    allEnabledRules: new Set(),
    rules: new Map()
  };
  for (const directive of directives) {
    const line = directive.node.loc.start.line;
    if (directive.type === "eslint-disable-line" && line === message.line && disableDirectiveMatchesRule(directive, message.ruleId)) {
      return directive;
    }
    if (directive.type === "eslint-disable-next-line" && line + 1 === message.line && disableDirectiveMatchesRule(directive, message.ruleId)) {
      return directive;
    }
    if (line > message.line) {
      break;
    }
    if (directive.type === "eslint-disable") {
      if (directive.ruleId) {
        active.rules.set(directive.ruleId, directive);
        active.allEnabledRules.delete(directive.ruleId);
      } else {
        active.all = directive;
        active.allEnabledRules.clear();
      }
    } else if (directive.type === "eslint-enable") {
      if (directive.ruleId) {
        active.rules.delete(directive.ruleId);
        if (active.all) {
          active.allEnabledRules.add(directive.ruleId);
        }
      } else {
        active.all = null;
        active.allEnabledRules.clear();
        active.rules.clear();
      }
    }
  }
  if (active.rules.has(message.ruleId)) {
    return active.rules.get(message.ruleId);
  }
  if (active.all && !active.allEnabledRules.has(message.ruleId)) {
    return active.all;
  }
  return null;
}

function disableDirectiveMatchesRule(directive, ruleId) {
  return directive.ruleId == null || directive.ruleId === ruleId;
}

function traverseCustomRuleAst(node, listeners, context, visitorKeys, seen = new Set(), ancestors = [], siblings = {}) {
  if (!node || typeof node !== "object" || typeof node.type !== "string" || seen.has(node)) {
    return;
  }
  seen.add(node);
  for (const listener of customRuleMatchingListeners(listeners, node, false, ancestors, siblings, visitorKeys)) {
    context.setCurrentNode(node);
    listener(node);
  }
  const children = customRuleChildNodes(node, visitorKeys);
  for (const [index, child] of children.entries()) {
    traverseCustomRuleAst(child, listeners, context, visitorKeys, seen, [...ancestors, node], {
      previous: children[index - 1] ?? null,
      previousAll: children.slice(0, index)
    });
  }
  for (const listener of customRuleMatchingListeners(listeners, node, true, ancestors, siblings, visitorKeys)) {
    context.setCurrentNode(node);
    listener(node);
  }
}

function customRuleMatchingListeners(listeners, node, exit, ancestors = [], siblings = {}, visitorKeys = null) {
  const matches = [];
  for (const [selector, listener] of Object.entries(listeners)) {
    if (typeof listener !== "function" || !customRuleSelectorMatches(selector, node, exit, ancestors, siblings, visitorKeys)) {
      continue;
    }
    matches.push(listener);
  }
  return matches;
}

function customRuleSelectorMatches(selector, node, exit, ancestors = [], siblings = {}, visitorKeys = null) {
  const suffix = ":exit";
  const isExit = selector.endsWith(suffix);
  if (isExit !== exit) {
    return false;
  }
  const expression = isExit ? selector.slice(0, -suffix.length) : selector;
  const childSelector = customRuleSplitTopLevelSelector(expression, ">");
  if (childSelector) {
    const parent = ancestors.at(-1);
    return Boolean(parent)
      && customRuleSimpleSelectorMatches(childSelector[0].trim(), parent, visitorKeys)
      && customRuleSimpleSelectorMatches(childSelector[1].trim(), node, visitorKeys);
  }
  const adjacentSelector = customRuleSplitTopLevelSelector(expression, "+");
  if (adjacentSelector) {
    return Boolean(siblings.previous)
      && customRuleSimpleSelectorMatches(adjacentSelector[0].trim(), siblings.previous, visitorKeys)
      && customRuleSimpleSelectorMatches(adjacentSelector[1].trim(), node, visitorKeys);
  }
  const siblingSelector = customRuleSplitTopLevelSelector(expression, "~");
  if (siblingSelector) {
    return (siblings.previousAll ?? []).some((sibling) => customRuleSimpleSelectorMatches(siblingSelector[0].trim(), sibling, visitorKeys))
      && customRuleSimpleSelectorMatches(siblingSelector[1].trim(), node, visitorKeys);
  }
  const descendantSelector = customRuleSplitTopLevelDescendantSelector(expression);
  if (descendantSelector) {
    return ancestors.some((ancestor) => customRuleSimpleSelectorMatches(descendantSelector[0].trim(), ancestor, visitorKeys))
      && customRuleSimpleSelectorMatches(descendantSelector[1].trim(), node, visitorKeys);
  }
  return customRuleSimpleSelectorMatches(expression, node, visitorKeys);
}

function customRuleSimpleSelectorMatches(expression, node, visitorKeys = null) {
  const hasSelector = expression.match(/^(.+?):has\((.+)\)$/u);
  if (hasSelector) {
    return customRuleSimpleSelectorMatches(hasSelector[1].trim(), node, visitorKeys)
      && customRuleDescendants(node, visitorKeys).some((descendant) => (
        customRuleSplitSelectorList(hasSelector[2]).some((selector) => customRuleSimpleSelectorMatches(selector.trim(), descendant, visitorKeys))
      ));
  }
  const notSelector = expression.match(/^(.+?):not\((.+)\)$/u);
  if (notSelector) {
    return customRuleSimpleSelectorMatches(notSelector[1].trim(), node, visitorKeys)
      && !customRuleSimpleSelectorMatches(notSelector[2].trim(), node, visitorKeys);
  }
  const matchesSelector = expression.match(/^(.*?):matches\((.+)\)$/u);
  if (matchesSelector) {
    const prefix = matchesSelector[1].trim();
    if (prefix && !customRuleSimpleSelectorMatches(prefix, node, visitorKeys)) {
      return false;
    }
    return customRuleSplitSelectorList(matchesSelector[2]).some((selector) => (
      customRuleSimpleSelectorMatches(selector.trim(), node, visitorKeys)
    ));
  }
  if (expression === node.type) {
    return true;
  }
  const match = expression.match(/^([A-Za-z_$][\w$-]*|\*)?(?:\[([^\]]+)\])?$/u);
  if (!match) {
    return false;
  }
  const [, type = "*", attribute] = match;
  if (type !== "*" && type !== node.type) {
    return false;
  }
  return attribute ? customRuleAttributeSelectorMatches(node, attribute.trim()) : type === "*" || type === node.type;
}

function customRuleDescendants(node, visitorKeys, seen = new Set()) {
  const descendants = [];
  for (const child of customRuleChildNodes(node, visitorKeys)) {
    if (seen.has(child)) {
      continue;
    }
    seen.add(child);
    descendants.push(child, ...customRuleDescendants(child, visitorKeys, seen));
  }
  return descendants;
}

function customRuleSplitTopLevelSelector(expression, separator) {
  let state = customRuleSelectorScanState();
  for (let index = 0; index < expression.length; index += 1) {
    state = customRuleUpdateSelectorScanState(state, expression[index]);
    if (state.depth === 0 && !state.quote && expression[index] === separator) {
      return [expression.slice(0, index), expression.slice(index + 1)];
    }
  }
  return null;
}

function customRuleSplitTopLevelDescendantSelector(expression) {
  let state = customRuleSelectorScanState();
  for (let index = 0; index < expression.length; index += 1) {
    state = customRuleUpdateSelectorScanState(state, expression[index]);
    if (state.depth === 0 && !state.quote && /\s/u.test(expression[index])) {
      const left = expression.slice(0, index).trim();
      const right = expression.slice(index).trim();
      return left && right ? [left, right] : null;
    }
  }
  return null;
}

function customRuleSplitSelectorList(value) {
  const selectors = [];
  let state = customRuleSelectorScanState();
  let start = 0;
  for (let index = 0; index < value.length; index += 1) {
    state = customRuleUpdateSelectorScanState(state, value[index]);
    if (state.depth === 0 && !state.quote && value[index] === ",") {
      selectors.push(value.slice(start, index));
      start = index + 1;
    }
  }
  selectors.push(value.slice(start));
  return selectors.filter((selector) => selector.trim());
}

function customRuleSelectorScanState() {
  return { depth: 0, quote: null, escaped: false };
}

function customRuleUpdateSelectorScanState(state, char) {
  if (state.escaped) {
    return { ...state, escaped: false };
  }
  if (char === "\\") {
    return { ...state, escaped: true };
  }
  if (state.quote) {
    return char === state.quote ? { ...state, quote: null } : state;
  }
  if (char === "\"" || char === "'") {
    return { ...state, quote: char };
  }
  if (char === "[" || char === "(") {
    return { ...state, depth: state.depth + 1 };
  }
  if ((char === "]" || char === ")") && state.depth > 0) {
    return { ...state, depth: state.depth - 1 };
  }
  return state;
}

function customRuleAttributeSelectorMatches(node, attribute) {
  const match = attribute.match(/^([\w$.-]+)\s*(!=|=)\s*(.+)$/u);
  if (!match) {
    return customRuleValueByPath(node, attribute) != null;
  }
  const [, path, operator, rawExpected] = match;
  const actual = customRuleValueByPath(node, path);
  const expected = customRuleSelectorValue(rawExpected);
  return operator === "="
    ? String(actual) === expected
    : String(actual) !== expected;
}

function customRuleSelectorValue(raw) {
  const value = raw.trim();
  const quote = value[0];
  if ((quote === "\"" || quote === "'") && value.at(-1) === quote) {
    return value.slice(1, -1);
  }
  return value;
}

function customRuleValueByPath(node, path) {
  return path.split(".").reduce((value, key) => (
    value && typeof value === "object" ? value[key] : undefined
  ), node);
}

function customRuleChildNodes(node, visitorKeys) {
  const keys = Array.isArray(visitorKeys?.[node.type])
    ? visitorKeys[node.type]
    : Object.keys(node).filter((key) => !AST_TRAVERSAL_SKIP_KEYS.has(key));
  const children = [];
  for (const key of keys) {
    const value = node[key];
    const values = Array.isArray(value) ? value : [value];
    for (const child of values) {
      if (child && typeof child === "object" && typeof child.type === "string") {
        children.push(child);
      }
    }
  }
  return children;
}

function runCustomRuleTokenListeners(program, tokens, listeners, context) {
  if (typeof listeners.Program === "function") {
    context.setCurrentNode(program);
    listeners.Program(program);
  }
  for (const node of tokens) {
    if (typeof listeners[node.type] === "function") {
      context.setCurrentNode(node);
      listeners[node.type](node);
    }
  }
  for (let index = tokens.length - 1; index >= 0; index -= 1) {
    const node = tokens[index];
    const exitListener = listeners[`${node.type}:exit`];
    if (typeof exitListener === "function") {
      context.setCurrentNode(node);
      exitListener(node);
    }
  }
  if (typeof listeners["Program:exit"] === "function") {
    context.setCurrentNode(program);
    listeners["Program:exit"](program);
  }
}

function createCustomRuleContext(ruleEntry, sourceCode, options, messages) {
  const filename = options.filename ?? "<input>";
  const cwd = options.cwd ?? "";
  const config = options.config ?? {};
  const languageOptions = config.languageOptions ?? {};
  const parserOptions = languageOptions.parserOptions ?? config.parserOptions ?? {};
  let currentNode = sourceCode.ast ?? null;
  const context = {
    id: ruleEntry.ruleId,
    options: ruleEntry.options,
    filename,
    physicalFilename: filename,
    cwd,
    sourceCode,
    settings: config.settings ?? {},
    parserOptions,
    parserPath: config.parser ?? languageOptions.parser ?? null,
    parserServices: sourceCode.parserServices ?? {},
    languageOptions,
    getCwd() {
      return cwd;
    },
    getFilename() {
      return filename;
    },
    getPhysicalFilename() {
      return filename;
    },
    getSourceCode() {
      return sourceCode;
    },
    getScope() {
      return sourceCode.getScope(currentNode);
    },
    getAncestors() {
      return currentNode ? sourceCode.getAncestors(currentNode) : [];
    },
    getDeclaredVariables(node) {
      return sourceCode.getDeclaredVariables(node);
    },
    markVariableAsUsed(name) {
      return sourceCode.markVariableAsUsed(name, currentNode);
    },
    report(...args) {
      messages.push(customRuleMessageFromReport(ruleEntry, sourceCode, args));
    }
  };
  Object.defineProperty(context, "setCurrentNode", {
    value(node) {
      currentNode = node;
    }
  });
  return context;
}

function customRuleListeners(rule, context) {
  if (typeof rule === "function") {
    return rule(context) ?? {};
  }
  if (typeof rule?.create === "function") {
    return rule.create(context) ?? {};
  }
  return {};
}

function customRuleMessageFromReport(ruleEntry, sourceCode, args) {
  const descriptor = customRuleReportDescriptor(args);
  const node = descriptor.node ?? null;
  const location = customRuleReportLocation(sourceCode, descriptor, node);
  const message = customRuleReportMessage(ruleEntry.rule, descriptor);
  const result = {
    ruleId: ruleEntry.ruleId,
    severity: ruleEntry.severity,
    message,
    line: location.start.line,
    column: location.start.column + 1,
    nodeType: node?.type ?? null
  };
  if (location.end) {
    result.endLine = location.end.line;
    result.endColumn = location.end.column + 1;
  }
  const fix = customRuleFix(sourceCode, descriptor);
  if (fix) {
    result.fix = fix;
  }
  if (Array.isArray(descriptor.suggest)) {
    result.suggestions = customRuleSuggestions(ruleEntry.rule, sourceCode, descriptor.suggest);
  }
  return result;
}

function customRuleReportDescriptor(args) {
  const [first, second, third, fourth] = args;
  if (first && typeof first === "object" && (
    Object.hasOwn(first, "message")
    || Object.hasOwn(first, "messageId")
    || Object.hasOwn(first, "node")
    || Object.hasOwn(first, "loc")
  )) {
    return first;
  }
  if (typeof second === "string") {
    return { node: first, message: second, data: third };
  }
  return { node: first, loc: second, message: third, data: fourth };
}

function customRuleReportMessage(rule, descriptor) {
  if (descriptor.messageId != null) {
    return ruleTesterMessageForId(rule, descriptor.messageId, descriptor.data);
  }
  if (typeof descriptor.message === "string") {
    return replaceRuleMessageData(descriptor.message, descriptor.data);
  }
  return "";
}

function customRuleReportLocation(sourceCode, descriptor, node) {
  const loc = descriptor.loc ?? node?.loc ?? sourceCode.getLoc(node);
  const start = loc?.start ?? loc ?? { line: 1, column: 0 };
  const end = loc?.end ?? null;
  return {
    start: {
      line: start.line ?? 1,
      column: start.column ?? 0
    },
    end: end ? {
      line: end.line ?? start.line ?? 1,
      column: end.column ?? start.column ?? 0
    } : null
  };
}

function customRuleSuggestions(rule, sourceCode, suggestions) {
  return suggestions.map((suggestion) => {
    const result = {
      desc: customRuleSuggestionDescription(rule, suggestion)
    };
    if (suggestion.messageId != null) {
      result.messageId = suggestion.messageId;
    }
    const fix = customRuleSuggestionFix(sourceCode, suggestion);
    if (fix) {
      result.fix = fix;
    }
    return result;
  });
}

function customRuleSuggestionDescription(rule, suggestion) {
  if (typeof suggestion.desc === "string") {
    return replaceRuleMessageData(suggestion.desc, suggestion.data);
  }
  if (suggestion.messageId != null) {
    return ruleTesterMessageForId(rule, suggestion.messageId, suggestion.data);
  }
  return "";
}

function customRuleSuggestionFix(sourceCode, suggestion) {
  return customRuleFix(sourceCode, suggestion);
}

function customRuleFix(sourceCode, descriptor) {
  if (typeof descriptor.fix !== "function") {
    return null;
  }
  const value = descriptor.fix(customRuleFixer(sourceCode));
  const fixes = ruleFixItems(value);
  if (fixes.length === 0) {
    return null;
  }
  return fixes.length === 1 ? fixes[0] : fixes;
}

function customRuleFixer(sourceCode) {
  return {
    insertTextAfter(node, text) {
      const range = sourceCode.getRange(node);
      return { range: [range[1], range[1]], text };
    },
    insertTextAfterRange(range, text) {
      return { range: [range[1], range[1]], text };
    },
    insertTextBefore(node, text) {
      const range = sourceCode.getRange(node);
      return { range: [range[0], range[0]], text };
    },
    insertTextBeforeRange(range, text) {
      return { range: [range[0], range[0]], text };
    },
    remove(node) {
      return this.replaceText(node, "");
    },
    removeRange(range) {
      return this.replaceTextRange(range, "");
    },
    replaceText(node, text) {
      return this.replaceTextRange(sourceCode.getRange(node), text);
    },
    replaceTextRange(range, text) {
      return { range: [range[0], range[1]], text };
    }
  };
}

export class SourceCode {
  static splitLines(text) {
    if (typeof text !== "string") {
      throw new TypeError("SourceCode.splitLines requires source text");
    }
    return text.split(/\r\n|\r|\n/u);
  }

  constructor(textOrConfig, astIfNoConfig = null) {
    if (typeof textOrConfig === "string") {
      this.text = textOrConfig;
      this.ast = astIfNoConfig;
      this.parserServices = {};
      this.scopeManager = null;
      this.visitorKeys = null;
      this.hasBOM = false;
    } else if (textOrConfig && typeof textOrConfig === "object" && typeof textOrConfig.text === "string") {
      this.text = textOrConfig.text;
      this.ast = textOrConfig.ast ?? null;
      this.parserServices = textOrConfig.parserServices ?? {};
      this.scopeManager = textOrConfig.scopeManager ?? null;
      this.visitorKeys = textOrConfig.visitorKeys ?? null;
      this.hasBOM = Boolean(textOrConfig.hasBOM);
    } else {
      throw new TypeError("SourceCode requires source text");
    }
    this.lines = SourceCode.splitLines(this.text);
    this.comments = Array.isArray(this.ast?.comments) ? this.ast.comments : [];
    this.tokens = Array.isArray(this.ast?.tokens) ? this.ast.tokens : [];
    this.lineStartIndices = sourceLineStartIndices(this.text);
  }

  getText(node, beforeCount = 0, afterCount = 0) {
    if (node?.range) {
      return this.text.slice(Math.max(node.range[0] - beforeCount, 0), node.range[1] + afterCount);
    }
    return this.text;
  }

  getLines() {
    return this.lines;
  }

  getAllComments() {
    return this.comments;
  }

  getIndexFromLoc(loc) {
    return this.lineStartIndices[Math.max(loc.line - 1, 0)] + loc.column;
  }

  getLocFromIndex(index) {
    const clamped = Math.max(0, Math.min(index, this.text.length));
    let line = 0;
    while (line + 1 < this.lineStartIndices.length && this.lineStartIndices[line + 1] <= clamped) {
      line += 1;
    }
    return {
      line: line + 1,
      column: clamped - this.lineStartIndices[line]
    };
  }

  getRange(node) {
    if (node?.range) {
      return [node.range[0], node.range[1]];
    }
    if (node?.loc) {
      return [this.getIndexFromLoc(node.loc.start), this.getIndexFromLoc(node.loc.end)];
    }
    return [0, this.text.length];
  }

  getLoc(node) {
    if (node?.loc) {
      return node.loc;
    }
    const range = this.getRange(node);
    return {
      start: this.getLocFromIndex(range[0]),
      end: this.getLocFromIndex(range[1])
    };
  }

  getAllTokens() {
    return this.tokens;
  }

  getTokens(node, beforeCount = 0, afterCount = 0) {
    const options = sourceTokenRangeOptions(beforeCount, afterCount);
    const items = sourceTokenItems(this, options);
    if (!node) {
      return sourceApplyTokenFilter(items, options);
    }
    const range = expandSourceRange(this.getRange(node), options.beforeCount, options.afterCount, this.text.length);
    return sourceApplyTokenFilter(sourceItemsInRange(items, range), options);
  }

  getFirstToken(node, skipOrOptions = 0) {
    return sourceForwardToken(this.getTokens(node, sourceTokenOptions(skipOrOptions, "skip")), skipOrOptions);
  }

  getFirstTokens(node, countOrOptions = 1) {
    return sourceForwardTokens(this.getTokens(node, sourceTokenOptions(countOrOptions, "count")), countOrOptions);
  }

  getLastToken(node, skipOrOptions = 0) {
    return sourceBackwardToken(this.getTokens(node, sourceTokenOptions(skipOrOptions, "skip")), skipOrOptions);
  }

  getLastTokens(node, countOrOptions = 1) {
    return sourceBackwardTokens(this.getTokens(node, sourceTokenOptions(countOrOptions, "count")), countOrOptions);
  }

  getTokenBefore(nodeOrToken, skipOrOptions = 0) {
    const options = sourceTokenOptions(skipOrOptions, "skip");
    return sourceBackwardToken(sourceApplyTokenFilter(sourceItemsBefore(sourceTokenItems(this, options), this.getRange(nodeOrToken)[0]), options), options);
  }

  getTokensBefore(nodeOrToken, countOrOptions = 1) {
    const options = sourceTokenOptions(countOrOptions, "count");
    return sourceBackwardTokens(sourceApplyTokenFilter(sourceItemsBefore(sourceTokenItems(this, options), this.getRange(nodeOrToken)[0]), options), options);
  }

  getTokenAfter(nodeOrToken, skipOrOptions = 0) {
    const options = sourceTokenOptions(skipOrOptions, "skip");
    return sourceForwardToken(sourceApplyTokenFilter(sourceItemsAfter(sourceTokenItems(this, options), this.getRange(nodeOrToken)[1]), options), options);
  }

  getTokensAfter(nodeOrToken, countOrOptions = 1) {
    const options = sourceTokenOptions(countOrOptions, "count");
    return sourceForwardTokens(sourceApplyTokenFilter(sourceItemsAfter(sourceTokenItems(this, options), this.getRange(nodeOrToken)[1]), options), options);
  }

  getTokensBetween(left, right, optionsOrCount) {
    const options = sourceTokenOptions(optionsOrCount, "count");
    return sourceForwardTokens(sourceTokensBetween(this, left, right, options), options);
  }

  getFirstTokenBetween(left, right, skipOrOptions = 0) {
    const options = sourceTokenOptions(skipOrOptions, "skip");
    return sourceForwardToken(sourceTokensBetween(this, left, right, options), options);
  }

  getFirstTokensBetween(left, right, countOrOptions = 1) {
    const options = sourceTokenOptions(countOrOptions, "count");
    return sourceForwardTokens(sourceTokensBetween(this, left, right, options), options);
  }

  getLastTokenBetween(left, right, skipOrOptions = 0) {
    const options = sourceTokenOptions(skipOrOptions, "skip");
    return sourceBackwardToken(sourceTokensBetween(this, left, right, options), options);
  }

  getLastTokensBetween(left, right, countOrOptions = 1) {
    const options = sourceTokenOptions(countOrOptions, "count");
    return sourceBackwardTokens(sourceTokensBetween(this, left, right, options), options);
  }

  getTokenByRangeStart(index, options = {}) {
    return sourceTokenItems(this, sourceTokenOptions(options, "skip")).find((token) => token.range?.[0] === index) ?? null;
  }

  getTokenOrCommentBefore(nodeOrToken) {
    return sourceItemsBefore(sourceTokensAndComments(this), this.getRange(nodeOrToken)[0]).at(-1) ?? null;
  }

  getTokenOrCommentAfter(nodeOrToken) {
    return sourceItemsAfter(sourceTokensAndComments(this), this.getRange(nodeOrToken)[1])[0] ?? null;
  }

  getCommentsBefore(nodeOrToken) {
    return sourceItemsBefore(this.comments, this.getRange(nodeOrToken)[0]);
  }

  getCommentsAfter(nodeOrToken) {
    return sourceItemsAfter(this.comments, this.getRange(nodeOrToken)[1]);
  }

  getCommentsInside(node) {
    return sourceItemsInRange(this.comments, this.getRange(node));
  }

  getComments(node) {
    return {
      before: this.getCommentsBefore(node),
      after: this.getCommentsAfter(node),
      inside: this.getCommentsInside(node)
    };
  }

  getJSDocComment(node) {
    return this.getCommentsBefore(node).findLast((comment) => String(comment.value ?? "").startsWith("*")) ?? null;
  }

  commentsExistBetween(left, right) {
    return sourceItemsBetween(this.comments, this.getRange(left)[1], this.getRange(right)[0]).length > 0;
  }

  isSpaceBetween(left, right) {
    return /\s/u.test(this.text.slice(this.getRange(left)[1], this.getRange(right)[0]));
  }

  isSpaceBetweenTokens(left, right) {
    return this.isSpaceBetween(left, right);
  }

  getNodeByRangeIndex(index) {
    return sourceNodeByRangeIndex(this.ast, index);
  }

  getAncestors(node) {
    return node ? sourceAncestorsForNode(this.ast, node) ?? [] : [];
  }

  getDeclaredVariables(node) {
    return typeof this.scopeManager?.getDeclaredVariables === "function" ? this.scopeManager.getDeclaredVariables(node) : [];
  }

  getScope(node) {
    if (node && typeof this.scopeManager?.acquire === "function") {
      return this.scopeManager.acquire(node, true) ?? this.scopeManager.acquire(node, false) ?? this.scopeManager.globalScope ?? null;
    }
    return this.scopeManager?.globalScope ?? null;
  }

  markVariableAsUsed(name, node) {
    return markScopeVariableAsUsed(this.getScope(node), name);
  }

  getDisableDirectives() {
    return this.comments.flatMap((comment) => disableDirectivesFromComment(comment));
  }

  getInlineConfigNodes() {
    return this.comments.filter((comment) => isInlineConfigComment(comment));
  }

  applyInlineConfig() {
    return undefined;
  }

  applyLanguageOptions() {
    return undefined;
  }

  finalize() {
    return undefined;
  }

  traverse() {
    return [];
  }

  isGlobalReference() {
    return false;
  }
}

function sourceLineStartIndices(text) {
  const indices = [0];
  for (let index = 0; index < text.length; index += 1) {
    if (text[index] === "\n") {
      indices.push(index + 1);
    }
  }
  return indices;
}

function expandSourceRange(range, beforeCount, afterCount, textLength) {
  return [
    Math.max(range[0] - beforeCount, 0),
    Math.min(range[1] + afterCount, textLength)
  ];
}

function sourceItemsInRange(items, range) {
  return items.filter((item) => item.range && item.range[0] >= range[0] && item.range[1] <= range[1]);
}

function sourceItemsBefore(items, index) {
  return items.filter((item) => item.range && item.range[1] <= index);
}

function sourceItemsAfter(items, index) {
  return items.filter((item) => item.range && item.range[0] >= index);
}

function sourceItemsBetween(items, start, end) {
  return items.filter((item) => item.range && item.range[0] >= start && item.range[1] <= end);
}

function sourceTokensAndComments(sourceCode) {
  return [...sourceCode.tokens, ...sourceCode.comments].sort((left, right) => (left.range?.[0] ?? 0) - (right.range?.[0] ?? 0));
}

function sourceTokensBetween(sourceCode, left, right, options) {
  return sourceApplyTokenFilter(
    sourceItemsBetween(sourceTokenItems(sourceCode, options), sourceCode.getRange(left)[1], sourceCode.getRange(right)[0]),
    options
  );
}

function sourceTokenItems(sourceCode, options) {
  return options.includeComments ? sourceTokensAndComments(sourceCode) : sourceCode.tokens;
}

function sourceTokenRangeOptions(beforeCount, afterCount) {
  if (beforeCount && typeof beforeCount === "object") {
    return sourceTokenOptions(beforeCount, "count");
  }
  return {
    beforeCount: sourceTokenCount(beforeCount, 0),
    afterCount: sourceTokenCount(afterCount, 0),
    includeComments: false,
    filter: null,
    skip: 0,
    count: null
  };
}

function sourceTokenOptions(optionsOrNumber, numericKey) {
  const options = optionsOrNumber && typeof optionsOrNumber === "object" ? optionsOrNumber : { [numericKey]: optionsOrNumber };
  return {
    beforeCount: sourceTokenCount(options.beforeCount, 0),
    afterCount: sourceTokenCount(options.afterCount, 0),
    includeComments: Boolean(options.includeComments),
    filter: typeof options.filter === "function" ? options.filter : null,
    skip: sourceTokenCount(options.skip, 0),
    count: options.count === undefined ? null : sourceTokenCount(options.count, 1)
  };
}

function sourceTokenCount(value, defaultValue) {
  return Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : defaultValue;
}

function sourceApplyTokenFilter(items, options) {
  return options.filter ? items.filter((item) => options.filter(item)) : items;
}

function sourceForwardToken(items, optionsOrNumber) {
  const options = sourceTokenOptions(optionsOrNumber, "skip");
  return items[options.skip] ?? null;
}

function sourceForwardTokens(items, optionsOrNumber) {
  const options = sourceTokenOptions(optionsOrNumber, "count");
  const start = options.skip;
  const end = options.count === null ? undefined : start + options.count;
  return items.slice(start, end);
}

function sourceBackwardToken(items, optionsOrNumber) {
  const options = sourceTokenOptions(optionsOrNumber, "skip");
  return items.at(-(options.skip + 1)) ?? null;
}

function sourceBackwardTokens(items, optionsOrNumber) {
  const options = sourceTokenOptions(optionsOrNumber, "count");
  if (options.count === 0) {
    return [];
  }
  const end = options.skip === 0 ? undefined : -options.skip;
  const available = end === undefined ? items : items.slice(0, end);
  return options.count === null ? available : available.slice(-options.count);
}

function sourceNodeByRangeIndex(node, index, seen = new Set()) {
  if (!node || typeof node !== "object" || seen.has(node)) {
    return null;
  }
  seen.add(node);
  if (!node.range || index < node.range[0] || index > node.range[1]) {
    return null;
  }
  for (const value of Object.values(node)) {
    const children = Array.isArray(value) ? value : [value];
    for (const child of children) {
      const match = sourceNodeByRangeIndex(child, index, seen);
      if (match) {
        return match;
      }
    }
  }
  return node;
}

function sourceAncestorsForNode(root, target, ancestors = [], seen = new Set()) {
  if (!root || typeof root !== "object" || seen.has(root)) {
    return null;
  }
  if (root === target) {
    return ancestors;
  }
  seen.add(root);

  for (const value of Object.values(root)) {
    const children = Array.isArray(value) ? value : [value];
    for (const child of children) {
      if (!child || typeof child !== "object") {
        continue;
      }
      const result = sourceAncestorsForNode(child, target, [...ancestors, root], seen);
      if (result) {
        return result;
      }
    }
  }
  return null;
}

function markScopeVariableAsUsed(scope, name) {
  let current = scope;
  while (current) {
    const variable = scopeVariableByName(current, name);
    if (variable) {
      variable.eslintUsed = true;
      return true;
    }
    current = current.upper ?? null;
  }
  return false;
}

function scopeVariableByName(scope, name) {
  if (scope?.set instanceof Map && scope.set.has(name)) {
    return scope.set.get(name);
  }
  if (Array.isArray(scope?.variables)) {
    return scope.variables.find((variable) => variable?.name === name) ?? null;
  }
  return null;
}

function isInlineConfigComment(comment) {
  return /^(?:eslint(?:-disable|-enable|-disable-next-line|-disable-line|-env)?|global|globals|exported)(?:\s|$)/u.test(String(comment?.value ?? "").trim());
}

function disableDirectivesFromComment(comment) {
  const match = String(comment?.value ?? "").trim().match(/^(eslint-(?:disable-next-line|disable-line|disable|enable))\b\s*(.*)$/u);
  if (!match) {
    return [];
  }

  const [, type, rawValue] = match;
  const [rawRules, justification = ""] = rawValue.split(/\s--\s/u, 2).map((value) => value.trim());
  const ruleIds = rawRules.split(",").map((ruleId) => ruleId.trim()).filter(Boolean);
  if (ruleIds.length === 0) {
    return [{ type, node: comment, value: null, ruleId: null, justification }];
  }
  return ruleIds.map((ruleId) => ({ type, node: comment, value: ruleId, ruleId, justification }));
}

export class RuleTester {
  static get version() {
    return version;
  }

  static setDefaultConfig(config) {
    if (typeof config !== "object" || config === null) {
      throw new TypeError("RuleTester.setDefaultConfig: config must be an object");
    }
    ruleTesterDefaultConfig = config;
    ruleTesterDefaultConfig.rules = ruleTesterDefaultConfig.rules || {};
  }

  static getDefaultConfig() {
    return ruleTesterDefaultConfig;
  }

  static resetDefaultConfig() {
    ruleTesterDefaultConfig = {
      rules: {
        ...RULE_TESTER_INITIAL_CONFIG.rules
      }
    };
  }

  static get describe() {
    return ruleTesterDescribe ?? (typeof globalThis.describe === "function" ? globalThis.describe : ruleTesterDescribeDefaultHandler);
  }

  static set describe(value) {
    ruleTesterDescribe = value;
  }

  static get it() {
    return ruleTesterIt ?? (typeof globalThis.it === "function" ? globalThis.it : ruleTesterItDefaultHandler);
  }

  static set it(value) {
    ruleTesterIt = value;
  }

  static only(item) {
    if (typeof item === "string") {
      return { code: item, only: true };
    }
    return { ...item, only: true };
  }

  static get itOnly() {
    if (typeof ruleTesterItOnly === "function") {
      return ruleTesterItOnly;
    }
    if (typeof ruleTesterIt === "function" && typeof ruleTesterIt.only === "function") {
      return Function.bind.call(ruleTesterIt.only, ruleTesterIt);
    }
    if (typeof globalThis.it === "function" && typeof globalThis.it.only === "function") {
      return Function.bind.call(globalThis.it.only, globalThis.it);
    }
    if (typeof ruleTesterDescribe === "function" || typeof ruleTesterIt === "function") {
      throw new Error("Set `RuleTester.itOnly` to use `only` with a custom test framework.");
    }
    throw new Error("To use `only`, use RuleTester with a test framework that provides `it.only()` like Mocha.");
  }

  static set itOnly(value) {
    ruleTesterItOnly = value;
  }

  constructor(config = {}) {
    this.config = mergeRuleTesterConfig(ruleTesterDefaultConfig, config);
  }

  run(ruleName, rule, tests = {}) {
    const linter = new Linter();
    linter.defineRule(ruleName, rule);
    RuleTester.describe(ruleName, () => {
      RuleTester.describe("valid", () => {
        for (const test of tests.valid ?? []) {
          const testCase = normalizeRuleTesterCase(test);
          RuleTester[testCase.only ? "itOnly" : "it"](testCase.name ?? testCase.code, () => {
            const messages = linter.verify(testCase.code, ruleTesterConfig(ruleName, this.config, testCase, "error"), ruleTesterOptions(testCase));
            if (messages.length > 0) {
              throw new Error(`Should have no errors but had ${messages.length}: ${JSON.stringify(messages)}`);
            }
          });
        }
      });

      RuleTester.describe("invalid", () => {
        for (const test of tests.invalid ?? []) {
          const testCase = normalizeRuleTesterCase(test);
          RuleTester[testCase.only ? "itOnly" : "it"](testCase.name ?? testCase.code, () => {
            const config = ruleTesterConfig(ruleName, this.config, testCase, "error");
            const options = ruleTesterOptions(testCase);
            const result = Object.hasOwn(testCase, "output")
              ? linter.verifyAndFix(testCase.code, config, options)
              : { messages: linter.verify(testCase.code, config, options), output: testCase.code };
            const messages = result.messages;
            assertRuleTesterErrors(testCase, messages, rule);
            assertRuleTesterOutput(testCase, result.output);
          });
        }
      });
    });
  }
}

function ruleTesterDescribeDefaultHandler(_text, method) {
  return method();
}

function ruleTesterItDefaultHandler(_text, method) {
  return method();
}

function mergeRuleTesterConfig(baseConfig, overrideConfig) {
  return {
    ...baseConfig,
    ...overrideConfig,
    rules: mergeRuleConfigMaps(baseConfig.rules, overrideConfig.rules)
  };
}

function normalizeRuleTesterCase(test) {
  if (typeof test === "string") {
    return { code: test };
  }
  if (!test || typeof test !== "object" || typeof test.code !== "string") {
    throw new TypeError("RuleTester cases must be strings or objects with a code string");
  }
  return test;
}

function ruleTesterConfig(ruleName, baseConfig, testCase, defaultSeverity) {
  return {
    ...baseConfig,
    ...testCase,
    rules: {
      [ruleName]: testCase.options ? [defaultSeverity, ...testCase.options] : defaultSeverity,
      ...(baseConfig.rules ?? {}),
      ...(testCase.rules ?? {})
    }
  };
}

function ruleTesterOptions(testCase) {
  return {
    filename: testCase.filename ?? testCase.filePath ?? "input.js"
  };
}

function assertRuleTesterErrors(testCase, messages, rule) {
  const expected = testCase.errors;
  if (typeof expected === "number") {
    if (messages.length !== expected) {
      throw new Error(`Should have ${expected} error${expected === 1 ? "" : "s"} but had ${messages.length}: ${JSON.stringify(messages)}`);
    }
    return;
  }

  if (!Array.isArray(expected)) {
    if (messages.length === 0) {
      throw new Error("Should have at least one error but had 0: []");
    }
    return;
  }

  if (messages.length !== expected.length) {
    throw new Error(`Should have ${expected.length} error${expected.length === 1 ? "" : "s"} but had ${messages.length}: ${JSON.stringify(messages)}`);
  }

  expected.forEach((expectation, index) => {
    if (typeof expectation === "number") {
      return;
    }
    const message = messages[index];
    for (const property of ["message", "line", "column", "endLine", "endColumn"]) {
      if (expectation[property] != null && message[property] !== expectation[property]) {
        throw new Error(`Error ${index + 1} ${property} should be ${JSON.stringify(expectation[property])} but was ${JSON.stringify(message[property])}`);
      }
    }
    if (expectation.messageId != null) {
      const expectedMessage = ruleTesterMessageForId(rule, expectation.messageId, expectation.data);
      if (message.message !== expectedMessage) {
        throw new Error(`Error ${index + 1} messageId ${JSON.stringify(expectation.messageId)} should resolve to ${JSON.stringify(expectedMessage)} but message was ${JSON.stringify(message.message)}`);
      }
    }
    if (expectation.type != null && message.nodeType !== expectation.type) {
      throw new Error(`Error ${index + 1} type should be ${JSON.stringify(expectation.type)} but was ${JSON.stringify(message.nodeType)}`);
    }
    if (Object.hasOwn(expectation, "suggestions")) {
      assertRuleTesterSuggestions(index, message.suggestions ?? [], expectation.suggestions, testCase.code, rule);
    }
  });
}

function assertRuleTesterSuggestions(errorIndex, actualSuggestions, expectedSuggestions, code, rule) {
  if (expectedSuggestions == null) {
    if (actualSuggestions.length > 0) {
      throw new Error(`Error ${errorIndex + 1} should have no suggestions but had ${actualSuggestions.length}: ${JSON.stringify(actualSuggestions)}`);
    }
    return;
  }
  if (typeof expectedSuggestions === "number") {
    if (actualSuggestions.length !== expectedSuggestions) {
      throw new Error(`Error ${errorIndex + 1} should have ${expectedSuggestions} suggestion${expectedSuggestions === 1 ? "" : "s"} but had ${actualSuggestions.length}: ${JSON.stringify(actualSuggestions)}`);
    }
    return;
  }
  if (!Array.isArray(expectedSuggestions)) {
    throw new TypeError("RuleTester suggestions must be a number, null, or an array");
  }
  if (actualSuggestions.length !== expectedSuggestions.length) {
    throw new Error(`Error ${errorIndex + 1} should have ${expectedSuggestions.length} suggestion${expectedSuggestions.length === 1 ? "" : "s"} but had ${actualSuggestions.length}: ${JSON.stringify(actualSuggestions)}`);
  }

  expectedSuggestions.forEach((expectation, suggestionIndex) => {
    const suggestion = actualSuggestions[suggestionIndex];
    if (expectation.messageId != null) {
      const expectedDesc = ruleTesterMessageForId(rule, expectation.messageId, expectation.data);
      if (suggestion.desc !== expectedDesc) {
        throw new Error(`Error ${errorIndex + 1} suggestion ${suggestionIndex + 1} messageId ${JSON.stringify(expectation.messageId)} should resolve to ${JSON.stringify(expectedDesc)} but desc was ${JSON.stringify(suggestion.desc)}`);
      }
    }
    if (expectation.desc != null && suggestion.desc !== expectation.desc) {
      throw new Error(`Error ${errorIndex + 1} suggestion ${suggestionIndex + 1} desc should be ${JSON.stringify(expectation.desc)} but was ${JSON.stringify(suggestion.desc)}`);
    }
    if (Object.hasOwn(expectation, "output")) {
      const output = applyRuleTesterSuggestionFixes(code, suggestion.fix);
      if (output !== expectation.output) {
        throw new Error(`Error ${errorIndex + 1} suggestion ${suggestionIndex + 1} output should be ${JSON.stringify(expectation.output)} but was ${JSON.stringify(output)}`);
      }
    }
  });
}

function applyRuleTesterSuggestionFixes(code, fix) {
  return applyRuleFixes(code, fix);
}

function applyRuleFixes(code, fix) {
  return ruleFixItems(fix)
    .sort((left, right) => right.range[0] - left.range[0])
    .reduce((output, item) => output.slice(0, item.range[0]) + item.text + output.slice(item.range[1]), code);
}

function ruleFixItems(fix) {
  if (!fix) {
    return [];
  }
  if (Array.isArray(fix)) {
    return fix.flatMap((item) => ruleFixItems(item));
  }
  return fix.range ? [fix] : [];
}

function ruleTesterMessageForId(rule, messageId, data = {}) {
  const template = rule?.meta?.messages?.[messageId];
  if (typeof template !== "string") {
    throw new Error(`RuleTester messageId ${JSON.stringify(messageId)} was not found in rule.meta.messages`);
  }
  return replaceRuleMessageData(template, data);
}

function replaceRuleMessageData(template, data = {}) {
  return template.replace(/\{\{\s*([^{}]+?)\s*\}\}/gu, (placeholder, key) => (
    Object.hasOwn(data, key) ? String(data[key]) : placeholder
  ));
}

function assertRuleTesterOutput(testCase, actualOutput) {
  if (!Object.hasOwn(testCase, "output")) {
    return;
  }
  if (testCase.output == null) {
    return;
  }
  if (testCase.output !== actualOutput) {
    throw new Error(`Output is incorrect. Expected ${JSON.stringify(testCase.output)} but was ${JSON.stringify(actualOutput)}.`);
  }
}

function createLinterSourceCode(text, parser = null, parserOptions = {}) {
  const parsed = parseSourceCode(text, parser, parserOptions);
  if (parsed) {
    return parsed;
  }
  return new SourceCode({
    text,
    ast: {
      type: "Program",
      range: [0, text.length],
      comments: sourceCommentsFromText(text),
      tokens: sourceTokensFromText(text)
    }
  });
}

function parseSourceCode(text, parser, parserOptions) {
  if (!parser) {
    return null;
  }
  if (typeof parser.parseForESLint === "function") {
    const result = parser.parseForESLint(text, parserOptions) ?? {};
    return new SourceCode({
      text,
      ast: result.ast ?? null,
      parserServices: result.services ?? result.parserServices ?? {},
      scopeManager: result.scopeManager ?? null,
      visitorKeys: result.visitorKeys ?? null
    });
  }
  if (typeof parser.parse === "function") {
    return new SourceCode({
      text,
      ast: parser.parse(text, parserOptions)
    });
  }
  return null;
}

function sourceTokensFromText(text) {
  const tokens = [];
  const lineStarts = sourceLineStartIndices(text);
  let index = 0;

  while (index < text.length) {
    const char = text[index];
    const next = text[index + 1];
    if (/\s/u.test(char)) {
      index += 1;
      continue;
    }
    if (char === "/" && next === "/") {
      index += 2;
      while (index < text.length && text[index] !== "\n" && text[index] !== "\r") {
        index += 1;
      }
      continue;
    }
    if (char === "/" && next === "*") {
      const close = text.indexOf("*/", index + 2);
      index = close === -1 ? text.length : close + 2;
      continue;
    }
    if (char === "\"" || char === "'" || char === "`") {
      const start = index;
      const end = skipQuotedSourceText(text, index, char);
      tokens.push(sourceTokenNode("String", text.slice(start, end), start, end, lineStarts));
      index = end;
      continue;
    }
    if (isIdentifierStart(char)) {
      const start = index;
      index += 1;
      while (index < text.length && isIdentifierPart(text[index])) {
        index += 1;
      }
      const value = text.slice(start, index);
      tokens.push(sourceTokenNode(JS_KEYWORDS.has(value) ? "Keyword" : "Identifier", value, start, index, lineStarts));
      continue;
    }
    if (isDigit(char)) {
      const start = index;
      index += 1;
      while (index < text.length && /[0-9._a-fA-FxXbBoO]/u.test(text[index])) {
        index += 1;
      }
      tokens.push(sourceTokenNode("Numeric", text.slice(start, index), start, index, lineStarts));
      continue;
    }
    const punctuator = sourcePunctuatorAt(text, index);
    tokens.push(sourceTokenNode("Punctuator", punctuator, index, index + punctuator.length, lineStarts));
    index += punctuator.length;
  }
  return tokens;
}

function sourceCommentsFromText(text) {
  const comments = [];
  const lineStarts = sourceLineStartIndices(text);
  let index = 0;

  while (index < text.length) {
    const char = text[index];
    const next = text[index + 1];
    if (char === "\"" || char === "'" || char === "`") {
      index = skipQuotedSourceText(text, index, char);
      continue;
    }
    if (char === "/" && next === "/") {
      const start = index;
      const valueStart = index + 2;
      let end = valueStart;
      while (end < text.length && text[end] !== "\n" && text[end] !== "\r") {
        end += 1;
      }
      comments.push(sourceCommentNode("Line", text.slice(valueStart, end), start, end, lineStarts));
      index = end;
      continue;
    }
    if (char === "/" && next === "*") {
      const start = index;
      const valueStart = index + 2;
      const close = text.indexOf("*/", valueStart);
      const valueEnd = close === -1 ? text.length : close;
      const end = close === -1 ? text.length : close + 2;
      comments.push(sourceCommentNode("Block", text.slice(valueStart, valueEnd), start, end, lineStarts));
      index = end;
      continue;
    }
    index += 1;
  }
  return comments;
}

function skipQuotedSourceText(text, start, quote) {
  let index = start + 1;
  while (index < text.length) {
    if (text[index] === "\\") {
      index += 2;
      continue;
    }
    if (text[index] === quote) {
      return index + 1;
    }
    index += 1;
  }
  return text.length;
}

function isIdentifierStart(char) {
  return /[$_\p{ID_Start}]/u.test(char);
}

function isIdentifierPart(char) {
  return /[$_\u200c\u200d\p{ID_Continue}]/u.test(char);
}

function isDigit(char) {
  return /[0-9]/u.test(char);
}

function sourcePunctuatorAt(text, index) {
  const candidates = ["===", "!==", ">>>", "**=", "<<=", ">>=", "=>", "==", "!=", "<=", ">=", "++", "--", "&&", "||", "??", "+=", "-=", "*=", "/=", "%=", "**", "<<", ">>", "?.", "..."];
  return candidates.find((candidate) => text.startsWith(candidate, index)) ?? text[index];
}

function sourceTokenNode(type, value, start, end, lineStarts) {
  return {
    type,
    value,
    range: [start, end],
    loc: {
      start: sourceLocFromIndex(lineStarts, start),
      end: sourceLocFromIndex(lineStarts, end)
    }
  };
}

function sourceCommentNode(type, value, start, end, lineStarts) {
  return {
    type,
    value,
    range: [start, end],
    loc: {
      start: sourceLocFromIndex(lineStarts, start),
      end: sourceLocFromIndex(lineStarts, end)
    }
  };
}

function sourceLocFromIndex(lineStarts, index) {
  let line = 0;
  while (line + 1 < lineStarts.length && lineStarts[line + 1] <= index) {
    line += 1;
  }
  return {
    line: line + 1,
    column: index - lineStarts[line]
  };
}

export class CLIEngine {
  static get version() {
    return version;
  }

  static outputFixes(report) {
    const results = Array.isArray(report) ? report : report?.results;
    if (!Array.isArray(results)) {
      throw new Error("'report' must be an ESLint report or result array");
    }

    for (const result of results) {
      if (typeof result !== "object" || result === null) {
        throw new Error("'report' must include only result objects");
      }
      if (typeof result.output === "string" && isAbsolute(result.filePath)) {
        writeFileSync(result.filePath, result.output);
      }
    }
  }

  static getErrorResults(results) {
    return getErrorResults(results);
  }

  constructor(options = {}) {
    this.options = { ...options };
    this.plugins = new Map();
  }

  executeOnFiles(patterns) {
    const mergedOptions = withConfigCache(eslintConstructorOptions(this.options));
    const report = lintFiles(patterns, mergedOptions);
    throwOnUnmatchedPatternDiagnostics(report, mergedOptions);
    const results = maybeFilterQuietResults(reportToESLintResults(report, {
      cwd: mergedOptions.cwd,
      filePaths: reportFilePaths(report, mergedOptions.cwd, explicitLintFilePaths(report.filePaths ?? patterns, mergedOptions.cwd)),
      ruleSeverityForFile: (filePath) => ruleSeverityMapForOptions(mergedOptions, filePath)
    }), mergedOptions);
    return resultsToCLIEngineReport(results);
  }

  executeOnText(code, filePathOrOptions = "input.js") {
    const textOptions =
      typeof filePathOrOptions === "object" && filePathOrOptions !== null
        ? filePathOrOptions
        : {};
    const filePath =
      typeof filePathOrOptions === "object" && filePathOrOptions !== null
        ? filePathOrOptions.filePath ?? filePathOrOptions.filename ?? "input.js"
        : filePathOrOptions;
    const mergedOptions = withConfigCache({
      ...eslintConstructorOptions(this.options),
      ...textOptions
    });
    const report = lintText(code, {
      ...mergedOptions,
      filePath
    });
    const results = maybeFilterQuietResults(reportToESLintResults(report, {
      source: code,
      filePath: normalizeESLintFilePath(filePath, mergedOptions.cwd),
      includeEmptyTextResult: report.files !== 0 || (report.diagnostics?.length ?? 0) > 0 || (report.suppressedDiagnostics?.length ?? 0) > 0,
      ruleSeverityForFile: (filePath) => ruleSeverityMapForOptions(mergedOptions, filePath)
    }), mergedOptions);
    return resultsToCLIEngineReport(results);
  }

  getFormatter(name = "stylish") {
    return (results) => {
      return formatResultsByName(results, name, {}, this.options);
    };
  }

  getRules() {
    return new Linter().getRules();
  }

  addPlugin(name, pluginObject) {
    this.plugins.set(name, pluginObject);
  }

  resolveFileGlobPatterns(patterns) {
    return normalizeStringArray(Array.isArray(patterns) ? patterns : [patterns], "patterns");
  }

  isPathIgnored(filePath) {
    return isPathIgnored(filePath, withConfigCache(eslintConstructorOptions(this.options)));
  }

  getConfigForFile(filePath) {
    return publicCalculatedConfig(withConfigCache(eslintConstructorOptions(this.options)), filePath);
  }
}

const DEFAULT_NATIVE_MAX_BUFFER = 64 * 1024 * 1024;

function nativeMaxBuffer(options, env) {
  const configured = options.maxBuffer ?? env.UTOO_LINT_MAX_BUFFER;
  if (configured === undefined || configured === "") {
    return DEFAULT_NATIVE_MAX_BUFFER;
  }
  const value = typeof configured === "number" ? configured : Number(configured);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new TypeError("maxBuffer and UTOO_LINT_MAX_BUFFER must be a positive integer byte count");
  }
  return value;
}

export function run(args = [], options = {}) {
  const cliArgs = normalizeStringArray(args, "args");
  const env = options.env ? { ...process.env, ...options.env } : process.env;
  const binary = options.binary ?? resolveBinary({ env });

  return spawnSync(binary, cliArgs, {
    cwd: options.cwd,
    env,
    encoding: options.encoding ?? "utf8",
    input: options.input,
    stdio: options.stdio,
    maxBuffer: nativeMaxBuffer(options, env)
  });
}

const UTOO_LINT_CLI_VALUE_FLAGS = new Set(["--config", "-c", "--format", "-f", "--rules", "--threads"]);

function parseUtooLintCliArgs(args = []) {
  const values = normalizeStringArray(args, "args");
  const passthroughArgs = [];
  const targets = [];
  const options = {};
  let help = false;
  let versionFlag = false;

  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (arg === "--") {
      targets.push(...values.slice(index + 1));
      break;
    }
    if (arg === "--help" || arg === "-h") {
      help = true;
      passthroughArgs.push(arg);
      continue;
    }
    if (arg === "--version" || arg === "-v") {
      versionFlag = true;
      continue;
    }
    if (UTOO_LINT_CLI_VALUE_FLAGS.has(arg)) {
      const value = values[index + 1];
      if (!value) {
        throw new Error(`utoo-lint: ${arg} requires a value`);
      }
      appendCliOption(passthroughArgs, options, arg, value);
      index += 1;
      continue;
    }
    if (arg.startsWith("--config=")) {
      appendCliOption(passthroughArgs, options, "--config", arg.slice("--config=".length));
      continue;
    }
    if (arg.startsWith("--format=")) {
      appendCliOption(passthroughArgs, options, "--format", arg.slice("--format=".length));
      continue;
    }
    if (arg.startsWith("--rules=")) {
      appendCliOption(passthroughArgs, options, "--rules", arg.slice("--rules=".length));
      continue;
    }
    if (arg.startsWith("--threads=")) {
      appendCliOption(passthroughArgs, options, "--threads", arg.slice("--threads=".length));
      continue;
    }
    if (arg === "--no-config") {
      options.noConfig = true;
      delete options.config;
      continue;
    }
    if (arg === "--json") {
      passthroughArgs.push(arg);
      continue;
    }
    if (arg === "--color") {
      options.color = true;
      continue;
    }
    if (arg === "--no-color") {
      options.color = false;
      continue;
    }
    if (arg.startsWith("-")) {
      passthroughArgs.push(arg);
      continue;
    }
    targets.push(arg);
  }

  return { help, options, passthroughArgs, targets, version: versionFlag };
}

function appendCliOption(passthroughArgs, options, flag, value) {
  if (value == null || value === "") {
    throw new Error(`utoo-lint: ${flag} requires a value`);
  }
  switch (flag) {
    case "--config":
    case "-c":
      options.config = value;
      delete options.noConfig;
      return;
    case "--format":
    case "-f":
      options.format = value;
      return;
    case "--rules":
      options.rules = value;
      return;
    case "--threads":
      options.threads = value;
      return;
    default:
      passthroughArgs.push(`${flag}=${value}`);
  }
}

function completedRunResult(status, stdout, stderr, options = {}) {
  const inherited = options.stdio === "inherit";
  if (inherited) {
    if (stdout) {
      process.stdout.write(stdout);
    }
    if (stderr) {
      process.stderr.write(stderr);
    }
  }
  return {
    status,
    signal: null,
    error: undefined,
    stdout: inherited ? null : stdout,
    stderr: inherited ? null : stderr,
    output: [null, inherited ? null : stdout, inherited ? null : stderr],
    pid: 0
  };
}

export function runCli(args = [], options = {}) {
  const parsed = parseUtooLintCliArgs(args);
  if (parsed.version) {
    return completedRunResult(0, `v${version}\n`, "", options);
  }
  if (parsed.help) {
    return run(parsed.passthroughArgs, options);
  }

  const cliOptions = withConfigCache({
    ...options,
    ...parsed.options,
    extraArgs: parsed.passthroughArgs,
    preserveNativeDefaults: Boolean(parsed.options.noConfig)
  });
  const usesDefaultTargets = parsed.targets.length === 0;
  const targets = usesDefaultTargets ? defaultLintTargets(cliOptions) : parsed.targets;
  const report = lintFiles(targets, { ...cliOptions, useDefaultConfigTargets: usesDefaultTargets });
  report.diagnostics = normalizeReportDiagnostics(report.diagnostics, cliOptions);
  report.exitCode = exitCodeForDiagnostics(report.diagnostics);
  const status = report.exitCode ?? exitCodeForDiagnostics(report.diagnostics);
  if (cliOptions.format === "json" || parsed.passthroughArgs.includes("--json")) {
    return completedRunResult(status, `${JSON.stringify(publicCliReport(report))}\n`, report.stderr ?? "", options);
  }
  return completedRunResult(status, "", `${report.stderr ?? ""}${formatNativeTextReport(report, cliOptions)}`, options);
}

function publicCliReport(report) {
  return {
    files: report.files ?? 0,
    filePaths: report.filePaths ?? [],
    diagnostics: report.diagnostics ?? [],
    suppressedDiagnostics: report.suppressedDiagnostics ?? [],
    outputs: report.outputs ?? []
  };
}

function formatNativeTextReport(report, options = {}) {
  const diagnostics = report.diagnostics ?? [];
  const files = report.files ?? 0;
  const color = shouldUseColor(options);

  if (diagnostics.length === 0) {
    return `${paint(color, "\u001b[32m", "✓")} ${pluralize(files, "file")} checked, no problems found\n`;
  }

  const lines = [];
  const locationWidth = diagnostics.reduce(
    (width, diagnostic) => Math.max(width, diagnosticLocation(diagnostic).length),
    0
  );
  let currentFile;

  for (const diagnostic of diagnostics) {
    const filePath = diagnostic.filePath ?? "<unknown>";
    if (filePath !== currentFile) {
      if (lines.length > 0) lines.push("");
      lines.push(paint(color, "\u001b[1m", filePath));
      currentFile = filePath;
    }

    const location = diagnosticLocation(diagnostic).padStart(locationWidth);
    const severity = diagnostic.severity === "warning" || diagnostic.severity === 1 ? "warning" : "error";
    const severityColor = severity === "error" ? "\u001b[31m" : "\u001b[33m";
    const message = String(diagnostic.message ?? "").replace(/\s*[\r\n]+\s*/g, " ");
    const rule = diagnostic.ruleId ? `  ${paint(color, "\u001b[2m", diagnostic.ruleId)}` : "";
    lines.push(
      `  ${paint(color, "\u001b[2m", location)}  ${paint(color, severityColor, severity.padEnd(7))}  ${message}${rule}`
    );
  }

  const errors = diagnostics.filter((diagnostic) => diagnostic.severity === "error" || diagnostic.severity === 2).length;
  const warnings = diagnostics.length - errors;
  const markerColor = errors > 0 ? "\u001b[31m" : "\u001b[33m";
  lines.push("");
  lines.push(
    `${paint(color, markerColor, "✖")} ${pluralize(diagnostics.length, "problem")} (${pluralize(errors, "error")}, ${pluralize(warnings, "warning")})`
  );

  const fixable = diagnostics.filter(diagnosticIsFixable).length;
  const fixRequested = options.fix || options.extraArgs?.includes("--fix") || options.extraArgs?.includes("--fix-dry-run");
  if (fixable > 0 && !fixRequested) {
    lines.push(`  ${pluralize(fixable, "problem")} potentially fixable with the \`--fix\` option.`);
  }
  lines.push(`  ${pluralize(files, "file")} checked`);
  return `${lines.join("\n")}\n`;
}

function diagnosticLocation(diagnostic) {
  return `${diagnostic.line ?? 0}:${diagnostic.column ?? 0}`;
}

function diagnosticIsFixable(diagnostic) {
  return Boolean(diagnostic.fix) || (Array.isArray(diagnostic.fixes) && diagnostic.fixes.length > 0);
}

function pluralize(count, noun) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

function paint(enabled, code, text) {
  return enabled ? `${code}${text}\u001b[0m` : text;
}

function shouldUseColor(options = {}) {
  if (options.color === true) return true;
  if (options.color === false) return false;
  const env = options.env ? { ...process.env, ...options.env } : process.env;
  if (env.NO_COLOR !== undefined || env.NODE_DISABLE_COLORS !== undefined) return false;
  if ((env.FORCE_COLOR && env.FORCE_COLOR !== "0") || (env.CLICOLOR_FORCE && env.CLICOLOR_FORCE !== "0")) return true;
  return Boolean(process.stderr.isTTY);
}

export function runFishlint(args = [], options = {}) {
  const cliArgs = normalizeStringArray(args, "args");
  const env = options.env ? { ...process.env, ...options.env } : { ...process.env };
  if (options.binary) {
    env.UTOO_LINT_BIN = options.binary;
  }

  return spawnSync(process.execPath, [fileURLToPath(new URL("./bin/fishlint.js", import.meta.url)), ...cliArgs], {
    cwd: options.cwd,
    env,
    encoding: options.encoding ?? "utf8",
    input: options.input,
    stdio: options.stdio,
    maxBuffer: nativeMaxBuffer(options, env)
  });
}

export function translateFishlintArgs(args = [], options = {}) {
  const values = normalizeStringArray(args, "args");
  const warn = options.warn ?? (() => {});

  if (values.length === 0) {
    return ["--help"];
  }

  const [command, ...rest] = values;
  if (command !== "eslint") {
    throw new Error(`utoo-lint fishlint compatibility only supports the eslint command, received: ${command}`);
  }

  const translated = [];
  const globTargets = [];
  let index = 0;

  while (index < rest.length) {
    const arg = rest[index];
    if (arg === "--") {
      index += 1;
      continue;
    }
    if (FISHLINT_DROP_FLAGS.has(arg)) {
      if (arg === "--no-eslintrc") {
        translated.push("--no-config");
      }
      index += 1;
      continue;
    }
    if (startsWithFlagValue(arg, FISHLINT_DROP_FLAGS)) {
      if (arg.startsWith("--no-eslintrc=") && booleanFlagValue(arg) !== false) {
        translated.push("--no-config");
      }
      index += 1;
      continue;
    }
    if (FISHLINT_DROP_VALUE_FLAGS.has(arg)) {
      const value = rest[index + 1];
      if (!value) {
        throw new Error(`utoo-lint: fishlint ${arg} requires a value`);
      }
      index += 2;
      continue;
    }
    if (startsWithFlagValue(arg, FISHLINT_DROP_VALUE_FLAGS)) {
      index += 1;
      continue;
    }
    if (arg === "--fix") {
      translated.push("--fix");
      index += 1;
      continue;
    }
    if (arg === "--fix-dry-run") {
      translated.push("--fix-dry-run");
      index += 1;
      continue;
    }
    if (arg === "--fix-type") {
      const value = rest[index + 1];
      if (!value) {
        throw new Error("utoo-lint: fishlint --fix-type requires a value");
      }
      warn("utoo-lint: fishlint --fix-type is ignored because utoo-lint does not apply fixes yet.");
      index += 2;
      continue;
    }
    if (arg.startsWith("--fix-type=")) {
      warn("utoo-lint: fishlint --fix-type is ignored because utoo-lint does not apply fixes yet.");
      index += 1;
      continue;
    }
    if (arg === "--format" || arg === "-f") {
      const value = rest[index + 1];
      if (!value) {
        throw new Error(`utoo-lint: fishlint ${arg} requires a formatter name`);
      }
      translated.push(`--format=${translateFishlintFormat(value, warn)}`);
      index += 2;
      continue;
    }
    if (arg.startsWith("--format=")) {
      translated.push(`--format=${translateFishlintFormat(arg.slice("--format=".length), warn)}`);
      index += 1;
      continue;
    }
    if (arg === "--threads") {
      const value = rest[index + 1];
      if (!value) {
        throw new Error("utoo-lint: fishlint --threads requires a number");
      }
      translated.push(`--threads=${value}`);
      index += 2;
      continue;
    }
    if (arg.startsWith("--threads=")) {
      translated.push(arg);
      index += 1;
      continue;
    }
    if (arg === "--rules") {
      const value = rest[index + 1];
      if (!value) {
        throw new Error("utoo-lint: fishlint --rules requires a comma-separated rule list");
      }
      translated.push(`--rules=${value}`);
      index += 2;
      continue;
    }
    if (arg.startsWith("--rules=")) {
      translated.push(arg);
      index += 1;
      continue;
    }
    if (arg === "--config" || arg === "-c") {
      const value = rest[index + 1];
      if (!value) {
        throw new Error(`utoo-lint: fishlint ${arg} requires a path`);
      }
      translated.push(`--config=${value}`);
      index += 2;
      continue;
    }
    if (arg.startsWith("--config=")) {
      translated.push(arg);
      index += 1;
      continue;
    }
    if (arg === "--ext") {
      const value = rest[index + 1];
      if (!value) {
        throw new Error("utoo-lint: fishlint --ext requires an extension list");
      }
      index += 2;
      continue;
    }
    if (arg.startsWith("--ext=")) {
      index += 1;
      continue;
    }
    if (arg === "--glob") {
      const value = rest[index + 1];
      if (!value) {
        throw new Error("utoo-lint: fishlint --glob requires a path");
      }
      globTargets.push(value);
      index += 2;
      continue;
    }
    if (arg.startsWith("--glob=")) {
      globTargets.push(arg.slice("--glob=".length));
      index += 1;
      continue;
    }
    translated.push(arg);
    index += 1;
  }

  if (globTargets.length > 0) {
    translated.push(...globTargets);
  }

  return translated;
}

function translateFishlintFormat(format, warn) {
  if (format === "json" || format === "text") {
    return format;
  }
  if (format === "json-with-metadata") {
    return "json";
  }
  if (format !== "stylish") {
    warn(`utoo-lint: fishlint formatter '${format}' is not implemented; using native text output.`);
  }
  return "text";
}

function startsWithFlagValue(arg, flags) {
  for (const flag of flags) {
    if (arg.startsWith(`${flag}=`)) {
      return true;
    }
  }
  return false;
}

function booleanFlagValue(arg) {
  const value = arg.slice(arg.indexOf("=") + 1).trim().toLowerCase();
  if (value === "false" || value === "0") {
    return false;
  }
  return true;
}

export function lintFiles(paths, options = {}) {
  options = withConfigCache(options);
  const usesDefaultTargets = paths == null || options.useDefaultConfigTargets;
  const targets = lintTargetsForInput(paths, options);
  const ignoredDiagnostics = ignoredLintPathDiagnostics(targets, options);
  let lintPaths = filteredLintPaths(targets, options);
  if (usesDefaultTargets) {
    lintPaths = filterDefaultConfigLintPaths(lintPaths, options);
  }
  if (options[LEGACY_CONFIG_ENABLED] && (!options.noConfig || options.legacyConfigFile) && !options.deferDiagnosticConfigFiltering) {
    lintPaths = expandNativeConfigRunPaths(lintPaths, options).filter((filePath) => !isPathIgnored(filePath, options));
  }
  if (lintPaths.length === 0) {
    return { files: 0, filePaths: [], diagnostics: ignoredDiagnostics, suppressedDiagnostics: [], exitCode: exitCodeForDiagnostics(ignoredDiagnostics) };
  }

  const nativeFlatOptions = nativeFlatConfigOptions(options);
  if (nativeFlatOptions) {
    const report = runNativeLintReport(lintPaths, nativeFlatOptions);
    return finalizeLintReport(report, ignoredDiagnostics, options);
  }

  const configRuns = nativeConfigRunsForFiles(expandNativeConfigRunPaths(lintPaths, options), options);
  if (configRuns) {
    const report = mergeNativeReports(
      configRuns.map(({ paths: runPaths, options: runOptions }) => runNativeLintReport(runPaths, runOptions))
    );
    return finalizeLintReport(report, ignoredDiagnostics, options);
  }

  const report = runNativeLintReport(lintPaths, options);
  return finalizeLintReport(report, ignoredDiagnostics, options);
}

function nativeFlatConfigOptions(options) {
  if (defersLegacyIgnores(options)) {
    // A legacy config may cascade from a nested directory even with baseConfig.
    return undefined;
  }
  if (options.rules || options.extraArgs?.some((arg) => arg.startsWith("--") && arg !== "--fix" && arg !== "--fix-dry-run")) {
    return undefined;
  }

  const fileConfigPath = options.noConfig ? undefined : configPathForOptions(options);
  const inlineConfigs = [options.baseConfig, options.overrideConfig].filter(Boolean);
  if (fileConfigPath && inlineConfigs.length > 0) {
    return undefined;
  }

  let config;
  let configRoot;
  if (fileConfigPath) {
    config = readConfig(fileConfigPath, options.cwd, options.configCache);
    configRoot = dirname(fileConfigPath);
  } else if (inlineConfigs.length > 0) {
    config = inlineConfigs.length === 1 ? inlineConfigs[0] : inlineConfigs;
    configRoot = resolvePath(options.cwd ?? process.cwd());
  } else {
    return undefined;
  }

  if (configCanUseNativeRulesFastPath(config)) {
    return undefined;
  }

  const serializedConfig = nativeSerializableConfig(config);
  return {
    ...options,
    nativeFlatConfigData: Array.isArray(serializedConfig) ? serializedConfig : [serializedConfig],
    nativeConfigRoot: configRoot,
    nativeConfigCwd: resolvePath(options.cwd ?? process.cwd())
  };
}

function configCanUseNativeRulesFastPath(config) {
  const entries = Array.isArray(config) ? config : [config];
  let hasEnabledRule = false;
  for (const entry of entries) {
    if (!entry || typeof entry !== "object" || Object.keys(entry.settings ?? {}).length > 0) {
      return false;
    }
    for (const ruleConfig of Object.values(entry.rules ?? {})) {
      if (ruleConfigSeverity(ruleConfig) === 0) {
        continue;
      }
      if (!isPureRuleSeverity(ruleConfig)) {
        return false;
      }
      hasEnabledRule = true;
    }
  }
  return hasEnabledRule;
}

function nativeSerializableConfig(config) {
  if (Array.isArray(config)) {
    return config.map(nativeSerializableConfig);
  }
  if (!config || typeof config !== "object") {
    return config;
  }
  return Object.fromEntries(
    ["$schema", "name", "files", "ignores", "rules", "settings"]
      .filter((key) => config[key] !== undefined)
      .map((key) => [key, config[key]])
  );
}

function expandNativeConfigRunPaths(paths, options) {
  const cwd = options.cwd ?? process.cwd();
  const patterns = ignoreDisabled(options) || defersLegacyIgnores(options) ? [] : ignorePatternsForOptions(options, cwd);
  return paths.flatMap((path) => expandLintTarget(path, cwd, patterns) ?? [path]);
}

function runNativeLintReport(paths, options) {
  return withTemporaryConfig(options, (resolvedOptions) => {
    const cliArgs = buildLintArgs(paths, resolvedOptions);
    const result = run(cliArgs, { ...resolvedOptions, stdio: undefined, encoding: "utf8" });

    if (result.error) {
      throw result.error;
    }

    const status = result.status ?? 1;
    const stdout = result.stdout ?? "";
    const stderr = result.stderr ?? "";

    if (status !== 0 && status !== 1) {
      throw new Error(stderr.trim() || `utoo-lint exited with status ${status}`);
    }

    let report;
    try {
      report = JSON.parse(stdout);
    } catch (error) {
      throw new Error(`utoo-lint returned invalid JSON: ${error.message}`);
    }

    report.exitCode = status;
    if (stderr) {
      Object.defineProperty(report, "stderr", {
        value: stderr,
        enumerable: false
      });
    }

    return report;
  });
}

function finalizeLintReport(report, ignoredDiagnostics, options) {
  report.diagnostics = [
    ...(report.diagnostics ?? []),
    ...ignoredDiagnostics
  ];
  if (!options.deferDiagnosticConfigFiltering) {
    report.filePaths = normalizeReportFilePaths(report.filePaths, options);
    report.diagnostics = normalizeDiagnosticFilePaths(report.diagnostics, options);
    report.suppressedDiagnostics = normalizeDiagnosticFilePaths(report.suppressedDiagnostics, options);
    report.outputs = normalizeReportOutputs(report.outputs, options);
    report.diagnostics = normalizeReportDiagnostics(report.diagnostics, options);
    report.suppressedDiagnostics = normalizeReportDiagnostics(report.suppressedDiagnostics, options);
    report.exitCode = exitCodeForDiagnostics(report.diagnostics);
  }
  return report;
}

function nativeConfigRunsForFiles(paths, options) {
  if (options.noConfig && !options.legacyConfigFile && !options.baseConfig && !options.overrideConfig) {
    return undefined;
  }

  const groups = new Map();
  let hasConfigSource = Boolean(options.baseConfig || options.overrideConfig);
  for (const filePath of paths) {
    const matchPath = paths.length === 1
      ? options.filePath ?? options.filename ?? filePath
      : filePath;
    const fileConfigPath = options.noConfig ? undefined : configPathForFile(options, matchPath);
    const configured = Boolean(options.baseConfig || options.overrideConfig || fileConfigPath || legacyConfigForFile(options, matchPath));
    hasConfigSource ||= configured;
    const calculated = configured ? calculatedConfig({ ...options, rules: undefined }, matchPath) : {};
    let rules = calculated.rules;
    const settings = calculated.settings;
    if (configured && options.rules) {
      rules = selectedRulesWithConfigOptions(rules, options.rules);
    }
    const signature = configured ? stableConfigSignature({ rules, settings }) : "<native-defaults>";
    if (!groups.has(signature)) {
      groups.set(signature, { paths: [], rules, settings, configured });
    }
    groups.get(signature).paths.push(filePath);
  }

  if (!hasConfigSource) {
    return undefined;
  }

  return [...groups.values()].map((group) => {
    if (!group.configured) {
      return {
        paths: group.paths,
        options: {
          ...options,
          config: undefined,
          noConfig: true,
          baseConfig: undefined,
          overrideConfig: undefined
        }
      };
    }

    const selectedRules = severityOnlyNativeRuleNames(group.rules, group.settings);
    if (selectedRules) {
      return {
        paths: group.paths,
        options: {
          ...options,
          config: undefined,
          noConfig: true,
          baseConfig: undefined,
          overrideConfig: undefined,
          rules: selectedRules,
          forceMaterializedConfig: undefined
        }
      };
    }

    return {
      paths: group.paths,
      options: {
        ...options,
        config: undefined,
        noConfig: true,
        baseConfig: undefined,
        overrideConfig: {
          rules: allDisabledNativeRules(group.rules),
          ...(group.settings ? { settings: group.settings } : {})
        },
        forceMaterializedConfig: true
      }
    };
  });
}

function severityOnlyNativeRuleNames(rules, settings) {
  if (Object.keys(settings ?? {}).length > 0) {
    return undefined;
  }

  const selected = [];
  for (const [rule, config] of Object.entries(rules ?? {})) {
    if (ruleConfigSeverity(config) === 0) {
      continue;
    }
    if (!isPureRuleSeverity(config)) {
      return undefined;
    }
    selected.push(rule);
  }
  return selected.length > 0 ? selected : undefined;
}

function isPureRuleSeverity(config) {
  if (Array.isArray(config)) {
    if (config.length !== 1) {
      return false;
    }
    [config] = config;
  }
  if (typeof config === "boolean") {
    return true;
  }
  if (typeof config === "number") {
    return config === 0 || config === 1 || config === 2;
  }
  return typeof config === "string" && ["off", "warn", "warning", "error", "0", "1", "2"].includes(config.toLowerCase());
}

function allDisabledNativeRules(rules) {
  return {
    ...Object.fromEntries(NATIVE_RULE_IDS.map((rule) => [rule, "off"])),
    ...Object.fromEntries(Object.entries(rules ?? {}).filter(
      ([rule, value]) => NATIVE_RULE_IDS.includes(rule) || ruleConfigSeverity(value) > 0
    ))
  };
}

function selectedRulesWithConfigOptions(configRules, selectedRules) {
  const selected = rulesFromNativeRuleList(selectedRules);
  return Object.fromEntries(
    Object.keys(selected).map((rule) => [
      rule,
      configRules?.[rule] != null && ruleConfigSeverity(configRules[rule]) > 0
        ? configRules[rule]
        : selected[rule]
    ])
  );
}

function stableConfigSignature(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableConfigSignature(item)).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableConfigSignature(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function mergeNativeReports(reports) {
  const report = {
    files: reports.reduce((count, item) => count + (item.files ?? 0), 0),
    filePaths: reports.flatMap((item) => item.filePaths ?? []),
    diagnostics: reports.flatMap((item) => item.diagnostics ?? []),
    suppressedDiagnostics: reports.flatMap((item) => item.suppressedDiagnostics ?? []),
    outputs: reports.flatMap((item) => item.outputs ?? []),
    exitCode: reports.some((item) => item.exitCode) ? 1 : 0
  };
  const stderr = reports.map((item) => item.stderr ?? "").join("");
  if (stderr) {
    Object.defineProperty(report, "stderr", { value: stderr, enumerable: false });
  }
  return report;
}

export function lintText(code, options = {}) {
  options = withConfigCache(options);
  if (typeof code !== "string") {
    throw new TypeError("code must be a string");
  }

  const tmp = mkdtempSync(join(tmpdir(), "utoo-lint-"));
  const requestedPath = textFilePathForOptions(options, "text.js");
  const extension = extname(requestedPath) || ".js";
  const tempFile = join(tmp, `input${extension}`);
  const discoveredConfig =
    !options.noConfig && !options.config && !options.overrideConfig
      ? configPathForOptions(options)
      : undefined;

  try {
    if (isPathIgnored(requestedPath, options)) {
      const diagnostics = options.warnIgnored === false ? [] : [ignoredFileDiagnostic(normalizeESLintFilePath(requestedPath, options.cwd))];
      return {
        files: 0,
        filePaths: [],
        diagnostics,
        suppressedDiagnostics: [],
        exitCode: exitCodeForDiagnostics(diagnostics)
      };
    }

    writeFileSync(tempFile, code);
    const report = lintFiles([tempFile], {
      ...options,
      cwd: options.cwd,
      config: options.config ?? discoveredConfig,
      noConfig: options.noConfig,
      deferDiagnosticConfigFiltering: true
    });
    report.filePaths = (report.filePaths ?? []).map((filePath) => (filePath === tempFile ? requestedPath : filePath));
    report.outputs = (report.outputs ?? []).map((fixed) => ({
      ...fixed,
      filePath: fixed.filePath === tempFile ? requestedPath : fixed.filePath
    }));
    report.diagnostics = report.diagnostics.map((diagnostic) => ({
      ...diagnostic,
      filePath: requestedPath
    }));
    report.suppressedDiagnostics = (report.suppressedDiagnostics ?? []).map((diagnostic) => ({
      ...diagnostic,
      filePath: requestedPath
    }));
    report.diagnostics = normalizeReportDiagnostics(report.diagnostics, options);
    report.suppressedDiagnostics = normalizeReportDiagnostics(report.suppressedDiagnostics, options);
    report.exitCode = exitCodeForDiagnostics(report.diagnostics);
    return report;
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function buildLintArgs(paths, options) {
  return buildNativeLintArgs(paths, {
    ...options,
    format: "json",
    extraArgs: options.extraArgs
  });
}

function buildNativeLintArgs(paths, options) {
  const cliArgs = [];

  if (options.noConfig) {
    cliArgs.push("--no-config");
  }
  if (!options.nativeFlatConfigData && !options.rules && !options.forceMaterializedConfig && (options.config || options.baseConfig || options.overrideConfig)) {
    const configForRuleSelection = options.noConfig
      ? undefined
      : options.config ? readConfig(options.config, options.cwd, options.configCache) : undefined;
    const enabledRules = enabledRuleNamesFromConfigs(
      configForRuleSelection,
      options.baseConfig,
      options.overrideConfig
    );
    if (enabledRules.length > 0) {
      cliArgs.push(`--rules=${enabledRules.join(",")}`);
    }
  }
  if (options.config) {
    cliArgs.push(`--config=${options.config}`);
  }
  if (options.nativeConfigRoot) {
    cliArgs.push(`--config-root=${options.nativeConfigRoot}`);
  }
  if (options.nativeConfigCwd) {
    cliArgs.push(`--config-cwd=${options.nativeConfigCwd}`);
  }
  if (options.rules) {
    const rules = Array.isArray(options.rules) ? options.rules.join(",") : options.rules;
    if (rules) {
      cliArgs.push(`--rules=${rules}`);
    }
  }
  if (options.threads != null) {
    cliArgs.push(`--threads=${options.threads}`);
  }

  if (options.format) {
    cliArgs.push(`--format=${options.format}`);
  }

  if (options.fix) {
    cliArgs.push("--fix-dry-run");
  }

  if (options.extraArgs) {
    cliArgs.push(...normalizeStringArray(options.extraArgs, "extraArgs"));
  }

  cliArgs.push(...normalizeStringArray(Array.isArray(paths) ? paths : [paths], "paths"));
  return cliArgs;
}

function mergeLintOptions(base, override) {
  return {
    ...eslintConstructorOptions(base),
    ...override
  };
}

function withConfigCache(options) {
  if (options.configCache && options[CONFIG_DISCOVERY_CACHE]) {
    return options;
  }

  return {
    ...options,
    // Executable configs are otherwise re-evaluated at every per-file lookup.
    configCache: options.configCache ?? new Map(),
    // Discovery results must not survive into a later public invocation.
    [CONFIG_DISCOVERY_CACHE]: new Map()
  };
}

function eslintConstructorOptions(options) {
  const mapped = {
    [LEGACY_CONFIG_ENABLED]: true,
    cwd: options.cwd,
    threads: options.threads,
    binary: options.binary,
    env: options.env,
    extraArgs: options.extraArgs,
    config: options.config,
    legacyConfigFile: options.config == null ? options.configFile : undefined,
    ignorePath: options.ignorePath,
    ignorePatterns: options.ignorePatterns,
    noIgnore: options.noIgnore ?? options.ignore === false,
    baseConfig: options.baseConfig,
    noConfig: options.noConfig,
    fix: options.fix,
    quiet: options.quiet,
    errorOnUnmatchedPattern: options.errorOnUnmatchedPattern,
    warnIgnored: options.warnIgnored
  };

  if (options.useEslintrc === false || options.overrideConfigFile === true) {
    mapped.noConfig = true;
  }
  if (typeof options.overrideConfigFile === "string") {
    mapped.config = options.overrideConfigFile;
    mapped.legacyConfigFile = undefined;
  }
  if (mapped.config && /(?:^|[/\\\\])\.eslintrc(?:\.(?:js|cjs|json|yaml|yml))?$/.test(mapped.config)) {
    mapped.legacyConfigFile = mapped.config;
    mapped.config = undefined;
  }
  if (options.overrideConfig) {
    mapped.overrideConfig = Array.isArray(options.overrideConfig) ? options.overrideConfig : { ...options.overrideConfig };
  }
  return mapped;
}

function flagsFromOptions(options = {}) {
  return Array.isArray(options.flags) ? [...options.flags] : [];
}

function hasFlagInOptions(options, flag) {
  return flagsFromOptions(options).includes(flag);
}

function calculatedConfig(options = {}, filePath) {
  const configData = mergeConfigData(
    mergeConfigData(configDataFromConfig(options.baseConfig, filePath, options.cwd), configDataFromFileConfig(options, filePath)),
    configDataFromConfig(options.overrideConfig, filePath, options.cwd)
  );
  return {
    ...configData,
    rules: mergeRuleConfigMaps(
      rulesFromConfig(options.baseConfig, filePath, options.cwd),
      rulesFromFileConfig(options, filePath),
      rulesFromConfig(options.overrideConfig, filePath, options.cwd),
      rulesFromNativeRuleList(options.rules)
    )
  };
}

function configDataFromConfig(config, filePath, cwd) {
  if (!config) {
    return {};
  }
  if (Array.isArray(config)) {
    return config.reduce((result, entry) => mergeConfigData(result, configDataFromConfig(entry, filePath, cwd)), {});
  }
  if (!configAppliesToFile(config, filePath, cwd)) {
    return {};
  }

  const result = {};
  if (config.settings && typeof config.settings === "object") {
    result.settings = { ...config.settings };
  }
  if (config.languageOptions && typeof config.languageOptions === "object") {
    result.languageOptions = { ...config.languageOptions };
  }
  if (config.parserOptions && typeof config.parserOptions === "object") {
    result.parserOptions = { ...config.parserOptions };
  }
  if (config.globals && typeof config.globals === "object") {
    result.globals = { ...config.globals };
  }
  if (config.env && typeof config.env === "object") {
    result.env = { ...config.env };
  }
  if (config.parser != null) {
    result.parser = config.parser;
  }
  return result;
}

function mergeConfigData(base, override) {
  const result = { ...base, ...override };
  if (base.settings || override.settings) {
    result.settings = { ...(base.settings ?? {}), ...(override.settings ?? {}) };
  }
  if (base.languageOptions || override.languageOptions) {
    result.languageOptions = { ...(base.languageOptions ?? {}), ...(override.languageOptions ?? {}) };
  }
  if (base.parserOptions || override.parserOptions) {
    result.parserOptions = { ...(base.parserOptions ?? {}), ...(override.parserOptions ?? {}) };
  }
  if (base.globals || override.globals) {
    result.globals = { ...(base.globals ?? {}), ...(override.globals ?? {}) };
  }
  if (base.env || override.env) {
    result.env = { ...(base.env ?? {}), ...(override.env ?? {}) };
  }
  return result;
}

function publicCalculatedConfig(options = {}, filePath) {
  const config = calculatedConfig(options, filePath);
  return {
    ...config,
    rules: Object.fromEntries(
      Object.entries(config.rules ?? {}).map(([rule, value]) => [rule, publicRuleConfigValue(value)])
    )
  };
}

function publicRuleConfigValue(value) {
  if (Array.isArray(value)) {
    const [severity, ...rest] = value;
    return [ruleConfigSeverity(severity), ...rest];
  }
  return [ruleConfigSeverity(value)];
}

function rulesFromNativeRuleList(rules) {
  if (!rules) {
    return {};
  }
  const values = Array.isArray(rules) ? rules : String(rules).split(",");
  const result = {};
  for (const rule of values) {
    const name = String(rule).trim();
    if (name) {
      result[name] = "warn";
    }
  }
  return result;
}

function rulesFromConfig(config, filePath, cwd) {
  if (!config) {
    return {};
  }
  if (Array.isArray(config)) {
    return config.reduce(
      (rules, entry) => mergeRuleConfigMaps(rules, rulesFromConfig(entry, filePath, cwd)),
      {}
    );
  }
  if (!configAppliesToFile(config, filePath, cwd)) {
    return {};
  }
  return config.rules && typeof config.rules === "object" ? config.rules : {};
}

function rulesFromFileConfig(options, filePath) {
  if (options.noConfig && !options.legacyConfigFile) {
    return {};
  }

  const configPath = filePath ? configPathForFile(options, filePath) : configPathForOptions(options);
  if (!configPath) {
    return legacyConfigForFile(options, filePath)?.rules ?? {};
  }

  const config = readConfig(configPath, options.cwd, options.configCache);
  return rulesFromConfig(config, filePath, dirname(configPath));
}

function configDataFromFileConfig(options, filePath) {
  if (options.noConfig && !options.legacyConfigFile) {
    return {};
  }

  const configPath = filePath ? configPathForFile(options, filePath) : configPathForOptions(options);
  if (!configPath) {
    return configDataFromConfig(legacyConfigForFile(options, filePath), filePath, options.cwd);
  }

  const config = readConfig(configPath, options.cwd, options.configCache);
  return configDataFromConfig(config, filePath, dirname(configPath));
}

function legacyConfigForFile(options, filePath) {
  if (!options[LEGACY_CONFIG_ENABLED] || (options.noConfig && !options.legacyConfigFile)) return undefined;
  if (filePath ? configPathForFile(options, filePath) : configPathForOptions(options)) return undefined;
  const cwd = resolvePath(options.cwd ?? process.cwd());
  let resolver = options.configCache?.get(LEGACY_CONFIG_RESOLVER);
  if (!resolver) {
    resolver = createLegacyConfigResolver(cwd, {
      configFile: options.legacyConfigFile,
      useEslintrc: !options.noConfig,
      ignorePath: options.ignorePath,
      ignorePatterns: [
        ...ignorePatternsFromConfig(options.baseConfig),
        ...normalizeIgnorePatterns(options.ignorePatterns),
        ...ignorePatternsFromConfig(options.overrideConfig)
      ]
    });
    options.configCache?.set(LEGACY_CONFIG_RESOLVER, resolver);
  }
  return resolver(normalizeESLintFilePath(filePath ?? options.filePath ?? options.filename ?? "__placeholder__.js", cwd));
}

function lintTargetsForInput(paths, options = {}) {
  if (paths == null) {
    return defaultLintTargets(options);
  }
  return normalizeStringArray(Array.isArray(paths) ? paths : [paths], "paths");
}

function defaultLintTargets(options = {}) {
  if (options.noConfig) {
    return ["."];
  }

  const configPath = configPathForOptions(options);
  if (!configPath) {
    return ["."];
  }

  const config = readConfig(configPath, options.cwd, options.configCache);
  if (configHasUnscopedRules(config)) {
    return ["."];
  }

  const targets = filePatternsFromConfig(config);
  return targets.length > 0
    ? targets.map((target) => resolveConfigPattern(target, dirname(configPath)))
    : ["."];
}

function filterDefaultConfigLintPaths(paths, options) {
  const configPath = configPathForOptions(options);
  if (!configPath) {
    return paths;
  }
  const config = readConfig(configPath, options.cwd, options.configCache);
  if (!configHasFileSelectors(config)) {
    return paths;
  }
  const cwd = dirname(configPath);
  return paths.filter((filePath) => configSelectsFile(config, filePath, cwd));
}

function configHasFileSelectors(config) {
  if (Array.isArray(config)) {
    return config.some(configHasFileSelectors);
  }
  return Boolean(config && typeof config === "object" && normalizeConfigFileSelectors(config.files).length > 0);
}

function configHasUnscopedRules(config) {
  if (Array.isArray(config)) {
    return config.some(configHasUnscopedRules);
  }
  return Boolean(
    config &&
    typeof config === "object" &&
    normalizeConfigFileSelectors(config.files).length === 0 &&
    config.rules &&
    typeof config.rules === "object" &&
    Object.keys(config.rules).length > 0
  );
}

function configSelectsFile(config, filePath, cwd) {
  if (Array.isArray(config)) {
    return config.some((entry) => configSelectsFile(entry, filePath, cwd));
  }
  if (!config || typeof config !== "object") {
    return false;
  }
  const selectors = normalizeConfigFileSelectors(config.files);
  return selectors.length > 0
    ? configAppliesToFile(config, filePath, cwd)
    : configHasUnscopedRules(config) && configAppliesToFile(config, filePath, cwd);
}

function resolveConfigPattern(pattern, configDirectory) {
  if (isAbsolute(pattern)) {
    return pattern;
  }
  return resolvePath(configDirectory, pattern.replace(/^[/\\]/, ""));
}

function filePatternsFromConfig(config) {
  if (!config) {
    return [];
  }
  if (Array.isArray(config)) {
    return config.flatMap((entry) => filePatternsFromConfig(entry));
  }
  return normalizeConfigPatterns(config.files);
}

function configAppliesToFile(config, filePath, cwd) {
  if (!filePath) {
    return true;
  }

  const normalized = normalizeIgnoredPath(filePath, cwd ?? process.cwd());
  const files = normalizeConfigFileSelectors(config.files);
  if (files.length > 0 && !files.some((selector) => selector.every(
    (pattern) => matchesConfigFilePattern(normalized, normalizeIgnoredPattern(pattern))
  ))) {
    return false;
  }

  const ignores = normalizeIgnorePatterns(config.ignores);
  return !pathIgnoredByPatterns(normalized, ignores);
}

function normalizeConfigFileSelectors(patterns) {
  if (!patterns) {
    return [];
  }
  const values = Array.isArray(patterns) ? patterns : [patterns];
  return values.flatMap((value) => {
    if (typeof value === "string") {
      return [[value]];
    }
    if (Array.isArray(value)) {
      const selector = normalizeConfigPatterns(value);
      return selector.length > 0 ? [selector] : [];
    }
    return [];
  });
}

function normalizeConfigPatterns(patterns) {
  if (!patterns) {
    return [];
  }
  const values = Array.isArray(patterns) ? patterns : [patterns];
  return values.flatMap((value) => {
    if (typeof value === "string") {
      return [value];
    }
    if (Array.isArray(value)) {
      return normalizeConfigPatterns(value);
    }
    return [];
  });
}

function configPathForOptions(options) {
  if (options.legacyConfigFile) return undefined;
  if (options.config) {
    return resolvePath(options.cwd ?? process.cwd(), options.config);
  }

  const cwd = options.cwd ?? process.cwd();
  return configPathFromDirectory(cwd, options);
}

function configPathForFile(options, filePath) {
  if (options.legacyConfigFile) return undefined;
  if (options.noConfig) {
    return undefined;
  }
  if (options.config) {
    return resolvePath(options.cwd ?? process.cwd(), options.config);
  }
  return configPathFromDirectory(configSearchDirectoryForFile(filePath, options.cwd), options);
}

function configSearchDirectoryForFile(filePath, cwd) {
  const absolute = normalizeESLintFilePath(filePath, cwd);
  try {
    if (statSync(absolute).isDirectory()) {
      return absolute;
    }
  } catch {
    // Non-existent filenames are common for editor integrations.
  }
  return dirname(absolute);
}

function configPathFromDirectory(directory, options) {
  return findConfigPathFromDirectory(directory, options[CONFIG_DISCOVERY_CACHE]);
}

function withTemporaryConfig(options, callback) {
  if (options.nativeFlatConfigData !== undefined) {
    const tmp = mkdtempSync(join(tmpdir(), "utoo-lint-flat-config-"));
    const configPath = join(tmp, "utlint.config.json");
    try {
      writeFileSync(configPath, JSON.stringify(options.nativeFlatConfigData));
      return callback({
        ...options,
        config: configPath,
        noConfig: false,
        baseConfig: undefined,
        overrideConfig: undefined,
        forceMaterializedConfig: true
      });
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  }

  const fileConfigPath = !options.noConfig ? configPathForOptions(options) : undefined;
  const shouldMaterializeFileConfig = Boolean(fileConfigPath);
  const fileConfig = shouldMaterializeFileConfig
    ? readConfig(fileConfigPath, options.cwd, options.configCache)
    : undefined;
  const configs = [options.baseConfig, fileConfig, options.overrideConfig];
  const rules = shouldMaterializeFileConfig
    ? materializedRulesFromConfigs(...configs)
    : runtimeRulesFromConfigs(...configs);
  const settings = configs.reduce(
    (result, config) => ({
      ...result,
      ...(configDataFromConfig(config, options.filePath ?? options.filename, options.cwd).settings ?? {})
    }),
    {}
  );
  const hasSettings = Object.keys(settings).length > 0;
  if (Object.keys(rules).length === 0 && !hasSettings) {
    if (shouldMaterializeFileConfig) {
      return callback({
        ...options,
        config: undefined,
        noConfig: true
      });
    }
    return callback(options);
  }
  const enabledRules = enabledRuleNamesFromConfigs(...configs);
  const hasExplicitOffRules = Object.values(rules).some((value) => ruleConfigSeverity(value) === 0);
  if (!shouldMaterializeFileConfig && !hasSettings && !hasRuleOptions(rules) && !hasExplicitOffRules && !options.forceMaterializedConfig) {
    return callback({
      ...options,
      config: shouldMaterializeFileConfig ? undefined : options.config,
      noConfig: shouldMaterializeFileConfig ? true : options.noConfig ?? true,
      rules: options.rules ?? enabledRules
    });
  }

  const tmp = mkdtempSync(join(tmpdir(), "utoo-lint-config-"));
  const configPath = join(tmp, "utlint.config.json");
  try {
    writeFileSync(configPath, JSON.stringify({ rules, ...(hasSettings ? { settings } : {}) }));
    return callback({
      ...options,
      config: shouldMaterializeFileConfig ? configPath : options.config ?? configPath,
      noConfig: false,
      rules: options.forceMaterializedConfig ? undefined : options.rules
    });
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function enabledRuleNames(rules) {
  return Object.entries(rules)
    .filter(([, value]) => ruleConfigSeverity(value) > 0)
    .map(([rule]) => rule);
}

function runtimeRulesFromConfigs(...configs) {
  return mergeRuleConfigMaps(...configs.map(runtimeRulesFromConfig));
}

function materializedRulesFromConfigs(...configs) {
  return runtimeRulesFromConfigs(...configs);
}

function runtimeRulesFromConfig(config) {
  if (!config) {
    return {};
  }
  if (Array.isArray(config)) {
    return config.reduce(
      (rules, entry) => mergeRuleConfigMaps(rules, runtimeRulesFromConfig(entry)),
      {}
    );
  }

  const rules = {};
  for (const [rule, value] of Object.entries(rulesFromConfig(config))) {
    rules[rule] = value;
  }
  return rules;
}

function mergeRuleConfigMaps(...ruleMaps) {
  const result = {};
  for (const rules of ruleMaps) {
    for (const [ruleId, ruleConfig] of Object.entries(rules ?? {})) {
      const previous = result[ruleId];
      if (previous !== undefined && isSeverityOnlyRuleConfig(ruleConfig) && Array.isArray(previous) && previous.length > 1) {
        const severity = Array.isArray(ruleConfig) ? ruleConfig[0] : ruleConfig;
        result[ruleId] = [severity, ...previous.slice(1)];
      } else {
        result[ruleId] = ruleConfig;
      }
    }
  }
  return result;
}

function isSeverityOnlyRuleConfig(ruleConfig) {
  return !Array.isArray(ruleConfig) || ruleConfig.length === 1;
}

function enabledRuleNamesFromConfigs(...configs) {
  const rules = new Set();
  for (const config of configs) {
    for (const rule of enabledRuleNamesFromConfig(config)) {
      rules.add(rule);
    }
  }
  return [...rules];
}

function enabledRuleNamesFromConfig(config) {
  if (!config) {
    return [];
  }
  if (Array.isArray(config)) {
    return config.flatMap((entry) => enabledRuleNamesFromConfig(entry));
  }
  return enabledRuleNames(rulesFromConfig(config));
}

function hasRuleOptions(rules) {
  return Object.values(rules).some((value) => Array.isArray(value) && value.length > 1);
}

function normalizeStringArray(values, name) {
  if (!Array.isArray(values)) {
    throw new TypeError(`${name} must be an array of strings`);
  }
  for (const value of values) {
    if (typeof value !== "string") {
      throw new TypeError(`${name} must be an array of strings`);
    }
  }
  return values;
}

function reportToESLintResults(report, textOptions = {}) {
  const byFile = new Map();

  for (const diagnostic of report.diagnostics ?? []) {
    const filePath = textOptions.filePath ?? normalizeESLintFilePath(diagnostic.filePath, textOptions.cwd);
    if (!byFile.has(filePath)) {
      byFile.set(filePath, emptyESLintResult(filePath, textOptions.source));
    }
    const ruleSeverities = textOptions.ruleSeverityForFile?.(filePath) ?? textOptions.ruleSeverities;
    if (diagnostic.ruleId && ruleSeverities?.get(diagnostic.ruleId) === 0) {
      continue;
    }
    byFile.get(filePath).messages.push(diagnosticToESLintMessage(diagnostic, ruleSeverities));
  }

  for (const diagnostic of report.suppressedDiagnostics ?? []) {
    const filePath = textOptions.filePath ?? normalizeESLintFilePath(diagnostic.filePath, textOptions.cwd);
    if (!byFile.has(filePath)) {
      byFile.set(filePath, emptyESLintResult(filePath, textOptions.source));
    }
    const ruleSeverities = textOptions.ruleSeverityForFile?.(filePath) ?? textOptions.ruleSeverities;
    if (diagnostic.ruleId && ruleSeverities?.get(diagnostic.ruleId) === 0) {
      continue;
    }
    byFile.get(filePath).suppressedMessages.push(suppressedDiagnosticToESLintMessage(diagnostic, ruleSeverities));
  }

  for (const fixed of report.outputs ?? []) {
    const filePath = textOptions.filePath ?? normalizeESLintFilePath(fixed.filePath, textOptions.cwd);
    if (!byFile.has(filePath)) {
      byFile.set(filePath, emptyESLintResult(filePath, textOptions.source));
    }
    byFile.get(filePath).output = fixed.output;
  }

  if (textOptions.filePath && textOptions.includeEmptyTextResult !== false && !byFile.has(textOptions.filePath)) {
    byFile.set(textOptions.filePath, emptyESLintResult(textOptions.filePath, textOptions.source));
  }
  for (const filePath of textOptions.filePaths ?? []) {
    if (!byFile.has(filePath)) {
      byFile.set(filePath, emptyESLintResult(filePath));
    }
  }

  for (const result of byFile.values()) {
    applyCompatibilityDisableDirectives(result, textOptions);
    finalizeESLintResult(result);
  }

  return [...byFile.values()];
}

function applyCompatibilityDisableDirectives(result, textOptions) {
  if (result.messages.length === 0) {
    return;
  }

  let source = result.source;
  if (typeof source !== "string" && textOptions.filePath === result.filePath) {
    source = textOptions.source;
  }
  if (typeof source !== "string") {
    try {
      source = readFileSync(result.filePath, "utf8");
    } catch {
      return;
    }
  }
  if (!source.includes("eslint-")) {
    return;
  }

  const filtered = applyDisableDirectives(result.messages, createLinterSourceCode(source));
  result.messages = filtered.messages;
  result.suppressedMessages.push(...filtered.suppressedMessages);
}

function normalizeReportDiagnostics(diagnostics, options = {}) {
  return (diagnostics ?? []).flatMap((diagnostic) => {
    if (!diagnostic?.ruleId) {
      return [diagnostic];
    }
    if (diagnostic.ruleId === "io" || diagnostic.ruleId === "parse") {
      return [diagnostic];
    }

    const filePath = normalizeESLintFilePath(diagnostic.filePath, options.cwd);
    const filterUnconfiguredRules = hasRuleConfigSource(options, filePath);
    const ruleSeverities = ruleSeverityMapForOptions(options, filePath);
    const severity = ruleSeverities?.get(diagnostic.ruleId);
    if (!options.preserveNativeDefaults && filterUnconfiguredRules && !ruleSeverities?.has(diagnostic.ruleId)) {
      return [];
    }
    if (severity === 0) {
      return [];
    }
    if (severity === 1 || severity === 2) {
      return [{ ...diagnostic, severity: severity === 2 ? "error" : "warning" }];
    }
    return [diagnostic];
  });
}

function normalizeReportFilePaths(filePaths, options = {}) {
  return (filePaths ?? []).map((filePath) => normalizeESLintFilePath(filePath, options.cwd));
}

function normalizeReportOutputs(outputs, options = {}) {
  return (outputs ?? []).map((fixed) => ({
    ...fixed,
    filePath: normalizeESLintFilePath(fixed.filePath, options.cwd)
  }));
}

function normalizeDiagnosticFilePaths(diagnostics, options = {}) {
  return (diagnostics ?? []).map((diagnostic) => ({
    ...diagnostic,
    filePath: normalizeESLintFilePath(diagnostic.filePath, options.cwd)
  }));
}

function hasRuleConfigSource(options = {}, filePath) {
  if (options.baseConfig || options.overrideConfig || options.rules) {
    return true;
  }
  return !options.noConfig && Boolean(
    filePath ? configPathForFile(options, filePath) : configPathForOptions(options)
  );
}

function exitCodeForDiagnostics(diagnostics) {
  return diagnostics?.some((diagnostic) => diagnostic?.severity === "error" || diagnostic?.severity === 2) ? 1 : 0;
}

function throwOnUnmatchedPatternDiagnostics(report, options = {}) {
  if (options.errorOnUnmatchedPattern === false) {
    return;
  }
  const diagnostic = (report.diagnostics ?? []).find((item) => item?.ruleId === "io" && /unable to stat path/i.test(item.message ?? ""));
  if (diagnostic) {
    throw new Error(`No files matching '${unmatchedPatternDisplayPath(diagnostic.filePath, options.cwd)}' were found.`);
  }
}

function unmatchedPatternDisplayPath(filePath, cwd) {
  const root = resolvePath(cwd ?? process.cwd());
  if (typeof filePath === "string" && filePath.startsWith(`${root}/`)) {
    return filePath.slice(root.length + 1);
  }
  return filePath;
}

function normalizeESLintFilePath(filePath, cwd) {
  if (filePath === "<text>") return filePath;
  if (isAbsolute(filePath)) return filePath;
  return resolvePath(cwd ?? process.cwd(), filePath);
}

function textFilePathForOptions(options = {}, fallback) {
  return options.filePath ?? options.filename ?? fallback;
}

function reportFilePaths(report, cwd, fallbackFilePaths = []) {
  const filePaths = new Set();
  if (Array.isArray(report.filePaths)) {
    for (const filePath of report.filePaths) {
      if (typeof filePath === "string") {
        filePaths.add(normalizeESLintFilePath(filePath, cwd));
      }
    }
  }
  for (const filePath of fallbackFilePaths) {
    filePaths.add(filePath);
  }
  return [...filePaths];
}

function explicitLintFilePaths(patterns, cwd) {
  const files = [];
  for (const pattern of normalizeStringArray(Array.isArray(patterns) ? patterns : [patterns], "patterns")) {
    if (hasGlobMagic(pattern)) continue;

    const filePath = normalizeESLintFilePath(pattern, cwd);
    if (!isLintableFilePath(filePath)) continue;

    try {
      if (statSync(filePath).isFile()) {
        files.push(filePath);
      }
    } catch {
      // Let the native binary report missing paths. This helper only fills in
      // empty ESLint results for files that were checked successfully.
    }
  }
  return files;
}

function hasGlobMagic(pattern) {
  return /[*?[\]{}()!+@]/.test(pattern);
}

function isLintableFilePath(filePath) {
  return LINTABLE_EXTENSIONS.has(extname(filePath));
}

function filteredLintPaths(paths, options = {}) {
  const values = normalizeStringArray(Array.isArray(paths) ? paths : [paths], "paths");
  const cwd = options.cwd ?? process.cwd();
  const patterns = ignoreDisabled(options) || defersLegacyIgnores(options) ? [] : ignorePatternsForOptions(options, cwd);
  if (patterns.length === 0 && options.errorOnUnmatchedPattern !== false && !values.some(hasGlobMagic)) {
    return values;
  }
  const excludedPatterns = negatedLintPatterns(values);

  const filtered = new Set();
  for (const target of values) {
    if (isNegatedLintPattern(target)) {
      continue;
    }
    if (hasGlobMagic(target)) {
      const expanded = expandGlobTarget(target, cwd, patterns);
      if (expanded.length > 0) {
        for (const filePath of expanded) {
          filtered.add(filePath);
        }
        continue;
      }
      if (options.errorOnUnmatchedPattern === false) {
        continue;
      }
      if (!pathIgnoredByPatterns(normalizeIgnoredPath(target, cwd), patterns)) {
        filtered.add(target);
      }
      continue;
    }

    const expanded = expandLintTarget(target, cwd, patterns);
    if (expanded == null) {
      if (options.errorOnUnmatchedPattern === false) {
        continue;
      }
      if (!pathIgnoredByPatterns(normalizeIgnoredPath(target, cwd), patterns)) {
        filtered.add(target);
      }
      continue;
    }
    for (const filePath of expanded) {
      filtered.add(filePath);
    }
  }
  return [...filtered].filter((filePath) => !pathIgnoredByPatterns(normalizeIgnoredPath(filePath, cwd), excludedPatterns));
}

function negatedLintPatterns(values) {
  return values
    .filter(isNegatedLintPattern)
    .map((value) => value.slice(1))
    .filter((value) => value.length > 0);
}

function isNegatedLintPattern(value) {
  return value.startsWith("!") && value.length > 1;
}

function expandGlobTarget(target, cwd, patterns) {
  const base = globBaseDirectory(target);
  const absoluteBase = normalizeESLintFilePath(base, cwd);
  let stat;
  try {
    stat = statSync(absoluteBase);
  } catch {
    return [];
  }
  if (!stat.isDirectory()) {
    return [];
  }

  const expression = new RegExp(`^${globPatternRegExpSource(normalizePath(target))}$`);
  const files = [];
  collectGlobFiles(base, cwd, patterns, expression, files);
  return files;
}

function globBaseDirectory(pattern) {
  const segments = normalizePath(pattern).split("/");
  const baseSegments = [];
  for (const segment of segments) {
    if (hasGlobMagic(segment)) {
      break;
    }
    baseSegments.push(segment);
  }
  return baseSegments.length > 0 ? baseSegments.join("/") : ".";
}

function collectGlobFiles(target, cwd, patterns, expression, files) {
  const absolute = normalizeESLintFilePath(target, cwd);
  for (const entry of readdirSync(absolute, { withFileTypes: true })) {
    if (shouldSkipDirectoryEntry(entry.name)) {
      continue;
    }

    const child = join(target, entry.name);
    if (entry.isDirectory()) {
      if (shouldTraverseDirectory(normalizeIgnoredPath(child, cwd), patterns)) {
        collectGlobFiles(child, cwd, patterns, expression, files);
      }
      continue;
    }
    if (
      entry.isFile() &&
      isLintableFilePath(child) &&
      expression.test(normalizePath(child)) &&
      !pathIgnoredByPatterns(normalizeIgnoredPath(child, cwd), patterns)
    ) {
      files.push(child);
    }
  }
}

function ignoredLintPathDiagnostics(paths, options = {}) {
  if (ignoreDisabled(options) || options.warnIgnored === false) {
    return [];
  }

  const cwd = options.cwd ?? process.cwd();
  const patterns = ignorePatternsForOptions(options, cwd);
  if (patterns.length === 0 && !options[LEGACY_CONFIG_ENABLED]) {
    return [];
  }

  const diagnostics = [];
  for (const target of normalizeStringArray(Array.isArray(paths) ? paths : [paths], "paths")) {
    if (hasGlobMagic(target)) continue;

    const filePath = normalizeESLintFilePath(target, cwd);
    if (!isLintableFilePath(filePath)) continue;

    try {
      if (!statSync(filePath).isFile()) continue;
    } catch {
      continue;
    }

    if (isPathIgnored(filePath, options)) {
      diagnostics.push(ignoredFileDiagnostic(filePath));
    }
  }
  return diagnostics;
}

function ignoredFileDiagnostic(filePath) {
  return {
    filePath,
    line: 0,
    column: 0,
    severity: "warning",
    message: "File ignored because of a matching ignore pattern. Use noIgnore to override.",
    ruleId: null
  };
}

function expandLintTarget(target, cwd, patterns) {
  const absolute = normalizeESLintFilePath(target, cwd);
  let stat;
  try {
    stat = statSync(absolute);
  } catch {
    return null;
  }

  if (stat.isFile()) {
    return isLintableFilePath(target) && !pathIgnoredByPatterns(normalizeIgnoredPath(target, cwd), patterns) ? [target] : [];
  }
  if (!stat.isDirectory() || !shouldTraverseDirectory(normalizeIgnoredPath(target, cwd), patterns)) {
    return [];
  }

  const files = [];
  collectLintableFiles(target, cwd, patterns, files);
  return files;
}

function collectLintableFiles(target, cwd, patterns, files) {
  const absolute = normalizeESLintFilePath(target, cwd);
  for (const entry of readdirSync(absolute, { withFileTypes: true })) {
    if (shouldSkipDirectoryEntry(entry.name)) {
      continue;
    }

    const child = join(target, entry.name);
    if (entry.isDirectory()) {
      if (shouldTraverseDirectory(normalizeIgnoredPath(child, cwd), patterns)) {
        collectLintableFiles(child, cwd, patterns, files);
      }
      continue;
    }
    if (entry.isFile() && isLintableFilePath(child) && !pathIgnoredByPatterns(normalizeIgnoredPath(child, cwd), patterns)) {
      files.push(child);
    }
  }
}

function shouldSkipDirectoryEntry(name) {
  return name === ".git" || name === ".zig-cache" || name === "node_modules" || name === "vendor" || name === "zig-out";
}

function isPathIgnored(filePath, options = {}) {
  if (typeof filePath !== "string") {
    throw new TypeError("filePath must be a string");
  }
  if (ignoreDisabled(options)) {
    return false;
  }

  const cwd = options.cwd ?? process.cwd();
  const legacyConfig = legacyConfigForFile(options, filePath);
  if (legacyConfig) {
    return Boolean(legacyConfig.isIgnored?.(normalizeESLintFilePath(filePath, cwd)));
  }
  const normalized = normalizeIgnoredPath(filePath, cwd);
  const patterns = ignorePatternsForOptions(options, cwd, filePath);
  return pathIgnoredByPatterns(normalized, patterns);
}

function defersLegacyIgnores(options) {
  return options[LEGACY_CONFIG_ENABLED] && (options.legacyConfigFile || (!options.noConfig && !configPathForOptions(options)));
}

function ignoreDisabled(options = {}) {
  return options.noIgnore || options.ignore === false;
}

function ignorePatternsForOptions(options, cwd, filePath) {
  const patterns = [];
  for (const pattern of normalizeIgnorePatterns(options.ignorePatterns)) {
    patterns.push(pattern);
  }
  patterns.push(...ignorePatternsFromConfig(options.baseConfig));

  const ignorePath = options.ignorePath ?? ".eslintignore";
  if (ignorePath) {
    patterns.push(...readIgnoreFile(resolvePath(cwd, ignorePath)));
  }
  patterns.push(...ignorePatternsFromFileConfig(options, filePath));
  patterns.push(...ignorePatternsFromConfig(options.overrideConfig));
  return patterns;
}

function ignorePatternsFromFileConfig(options, filePath) {
  if (options.noConfig) {
    return [];
  }

  const configPath = filePath ? configPathForFile(options, filePath) : configPathForOptions(options);
  if (!configPath) {
    return [];
  }

  const cwd = options.cwd ?? process.cwd();
  return ignorePatternsFromConfig(readConfig(configPath, options.cwd, options.configCache)).map((pattern) =>
    rebaseConfigPattern(pattern, dirname(configPath), cwd)
  );
}

function rebaseConfigPattern(pattern, configDirectory, cwd) {
  const negated = pattern.startsWith("!");
  const value = negated ? pattern.slice(1) : pattern;
  const absolute = resolveConfigPattern(value, configDirectory);
  const relativePattern = normalizePath(relative(resolvePath(cwd), absolute));
  const rebased = relativePattern === ".." || relativePattern.startsWith("../")
    ? normalizePath(absolute)
    : relativePattern;
  return negated ? `!${rebased}` : rebased;
}

function ignorePatternsFromConfig(config) {
  if (!config) {
    return [];
  }
  if (Array.isArray(config)) {
    return config.flatMap((entry) => ignorePatternsFromConfig(entry));
  }

  const flatConfigIgnores = isGlobalIgnoreEntry(config) ? normalizeIgnorePatterns(config.ignores) : [];
  return [
    ...normalizeIgnorePatterns(config.ignorePatterns),
    ...flatConfigIgnores
  ];
}

function isGlobalIgnoreEntry(config) {
  if (!config || typeof config !== "object" || !config.ignores) {
    return false;
  }
  return Object.keys(config).every((key) => key === "name" || key === "ignores");
}

function normalizeIgnorePatterns(patterns) {
  if (!patterns) {
    return [];
  }
  const values = Array.isArray(patterns) ? patterns : [patterns];
  for (const value of values) {
    if (typeof value !== "string") {
      throw new TypeError("ignorePatterns must be a string or an array of strings");
    }
  }
  return values;
}

function readIgnoreFile(path) {
  if (!existsSync(path)) {
    return [];
  }

  return readFileSync(path, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));
}

function normalizeIgnoredPath(filePath, cwd) {
  const root = resolvePath(cwd);
  const absolute = normalizeESLintFilePath(filePath, root);
  const relative =
    absolute === root || absolute.startsWith(`${root}/`) || absolute.startsWith(`${root}\\`)
      ? absolute.slice(root.length).replace(/^[/\\]/, "")
      : absolute;
  return normalizePath(relative);
}

function normalizeIgnoredPattern(pattern) {
  return normalizePath(pattern.replace(/^!/, "")).replace(/\/+$/, "");
}

function pathIgnoredByPatterns(target, patterns) {
  let ignored = false;
  for (const pattern of patterns) {
    const negated = pattern.startsWith("!");
    if (matchesIgnorePattern(target, normalizeIgnoredPattern(pattern))) {
      ignored = !negated;
    }
  }
  return ignored;
}

function shouldTraverseDirectory(target, patterns) {
  return !pathIgnoredByPatterns(target, patterns) || patterns.some(
    (pattern) => pattern.startsWith("!") && negatedPatternMayMatchDescendant(target, pattern)
  );
}

function negatedPatternMayMatchDescendant(target, pattern) {
  pattern = normalizeIgnoredPattern(pattern);
  if (pattern.startsWith("/")) {
    pattern = pattern.slice(1);
    if (target.startsWith("/")) {
      target = target.slice(1);
    }
  }
  if (!pattern.includes("/")) {
    return true;
  }

  const directoryPattern = pattern.slice(0, pattern.lastIndexOf("/"));
  if (hasGlobSyntax(directoryPattern)) {
    const directoryExpression = new RegExp(`^${globPatternRegExpSource(directoryPattern)}(?:/.*)?$`);
    if (directoryExpression.test(target)) {
      return true;
    }
  }

  const globIndex = pattern.search(/[*?[{]/u);
  const staticPrefix = (globIndex === -1 ? pattern : pattern.slice(0, globIndex)).replace(/\/+$/u, "");
  return !staticPrefix ||
    staticPrefix === target ||
    staticPrefix.startsWith(`${target}/`) ||
    target.startsWith(`${staticPrefix}/`);
}

function matchesIgnorePattern(target, pattern) {
  const anchored = pattern.startsWith("/");
  if (anchored) {
    pattern = pattern.slice(1);
    if (target.startsWith("/")) {
      target = target.slice(1);
    }
  }
  if (pattern.endsWith("/**")) {
    const directoryPattern = pattern.slice(0, -3);
    if (hasGlobSyntax(directoryPattern)) {
      const expression = new RegExp(`^${globPatternRegExpSource(directoryPattern)}(?:/.*)?$`);
      return expression.test(target);
    }
    return target === directoryPattern || target.startsWith(`${directoryPattern}/`);
  }
  if (pattern.startsWith("**/")) {
    const suffix = pattern.slice(3);
    if (!hasGlobSyntax(suffix)) {
      return target.endsWith(suffix) || target.includes(`/${suffix}`);
    }
  }
  if (!hasGlobSyntax(pattern)) {
    if (anchored || pattern.includes("/")) {
      return target === pattern || target.startsWith(`${pattern}/`);
    }
    return target === pattern || target.endsWith(`/${pattern}`) || target.startsWith(`${pattern}/`);
  }

  const prefix = anchored || pattern.includes("/") ? "^" : "(^|/)";
  const expression = new RegExp(`${prefix}${globPatternRegExpSource(pattern)}$`);
  return expression.test(target);
}

function matchesConfigFilePattern(target, pattern) {
  if (!hasGlobSyntax(pattern)) {
    return target === pattern || target.startsWith(`${pattern}/`) || target.endsWith(`/${pattern}`);
  }
  const expression = new RegExp(`^${globPatternRegExpSource(pattern)}$`);
  return expression.test(target);
}

function hasGlobSyntax(pattern) {
  return /[*?[\]{}]/.test(pattern);
}

function normalizePath(path) {
  return path.replaceAll("\\", "/").replace(/^\.\//, "");
}

function globPatternRegExpSource(pattern) {
  let source = "";
  for (let index = 0; index < pattern.length; index += 1) {
    const char = pattern[index];
    if (char === "*") {
      if (pattern[index + 1] === "*") {
        if (pattern[index + 2] === "/") {
          source += "(?:.*/)?";
          index += 2;
        } else {
          source += ".*";
          index += 1;
        }
      } else {
        source += "[^/]*";
      }
      continue;
    }
    if (char === "?") {
      source += "[^/]";
      continue;
    }
    if (char === "{") {
      const end = pattern.indexOf("}", index + 1);
      if (end !== -1) {
        const parts = pattern.slice(index + 1, end).split(",");
        source += `(?:${parts.map(escapeRegExp).join("|")})`;
        index = end;
        continue;
      }
    }
    if (char === "[") {
      const end = pattern.indexOf("]", index + 1);
      if (end !== -1) {
        const raw = pattern.slice(index + 1, end);
        if (raw.length > 0) {
          const negated = raw[0] === "!" || raw[0] === "^";
          const body = raw.slice(negated ? 1 : 0);
          if (body.length > 0) {
            source += `[${negated ? "^" : ""}${escapeCharacterClass(body)}]`;
            index = end;
            continue;
          }
        }
      }
    }
    source += escapeRegExp(char);
  }
  return source;
}

function escapeRegExp(value) {
  return value.replace(/[|\\{}()[\]^$+?.]/g, "\\$&");
}

function escapeCharacterClass(value) {
  return value.replace(/[\\\]]/g, "\\$&");
}

function getErrorResults(results) {
  if (!Array.isArray(results)) {
    throw new Error("'results' must be an array");
  }

  const filtered = [];
  for (const result of results) {
    const messages = (result.messages ?? []).filter((message) => message.severity === 2);
    if (messages.length === 0) continue;
    filtered.push({
      ...result,
      messages,
      suppressedMessages: (result.suppressedMessages ?? []).filter((message) => message.severity === 2),
      errorCount: messages.length,
      warningCount: 0,
      fixableWarningCount: 0
    });
  }
  return filtered;
}

function ruleMetaForRuleId(ruleId) {
  const meta = {
    docs: {
      url: ruleDocsUrl(ruleId)
    }
  };
  if (FIXABLE_BUILTIN_RULE_IDS.has(ruleId)) {
    meta.fixable = "code";
  }
  if (SUGGESTION_BUILTIN_RULE_IDS.has(ruleId)) {
    meta.hasSuggestions = true;
  }
  return meta;
}

function createBuiltinRule(ruleId) {
  return {
    meta: ruleMetaForRuleId(ruleId),
    create() {
      return {};
    }
  };
}

function ruleDocsUrl(ruleId) {
  if (ruleId.startsWith("@typescript-eslint/")) {
    return `https://typescript-eslint.io/rules/${ruleId.slice("@typescript-eslint/".length)}/`;
  }
  if (ruleId.startsWith("eslint-comments/")) {
    return `https://mysticatea.github.io/eslint-plugin-eslint-comments/rules/${ruleId.slice("eslint-comments/".length)}.html`;
  }
  if (ruleId.startsWith("import/")) {
    return `https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/${ruleId.slice("import/".length)}.md`;
  }
  if (ruleId.startsWith("jsx-a11y/")) {
    return `https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/${ruleId.slice("jsx-a11y/".length)}.md`;
  }
  if (ruleId.startsWith("react-hooks/")) {
    return `https://react.dev/reference/eslint-plugin-react-hooks/lints/${ruleId.slice("react-hooks/".length)}`;
  }
  if (ruleId.startsWith("react/")) {
    return `https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/${ruleId.slice("react/".length)}.md`;
  }
  return `https://eslint.org/docs/latest/rules/${ruleId}`;
}

function resultsToCLIEngineReport(results) {
  const report = {
    results,
    errorCount: 0,
    fatalErrorCount: 0,
    warningCount: 0,
    fixableErrorCount: 0,
    fixableWarningCount: 0,
    usedDeprecatedRules: []
  };

  for (const result of results) {
    report.errorCount += result.errorCount ?? 0;
    report.fatalErrorCount += result.fatalErrorCount ?? 0;
    report.warningCount += result.warningCount ?? 0;
    report.fixableErrorCount += result.fixableErrorCount ?? 0;
    report.fixableWarningCount += result.fixableWarningCount ?? 0;
  }

  return report;
}

function emptyESLintResult(filePath, source) {
  const result = {
    filePath,
    messages: [],
    suppressedMessages: [],
    errorCount: 0,
    fatalErrorCount: 0,
    warningCount: 0,
    fixableErrorCount: 0,
    fixableWarningCount: 0,
    usedDeprecatedRules: []
  };
  if (source != null) {
    result.source = source;
  }
  return result;
}

function diagnosticToESLintMessage(diagnostic, ruleSeverities) {
  const message = {
    ruleId: diagnostic.ruleId,
    severity: ruleSeverities?.get(diagnostic.ruleId) ?? (diagnostic.severity === "error" ? 2 : 1),
    message: diagnostic.message,
    line: diagnostic.line,
    column: diagnostic.column,
    nodeType: null
  };
  if (diagnostic.endLine != null) {
    message.endLine = diagnostic.endLine;
  }
  if (diagnostic.endColumn != null) {
    message.endColumn = diagnostic.endColumn;
  }
  const fixes = (diagnostic.fixes ?? []).map((fix) => ({
    range: fix.range,
    text: fix.text
  }));
  if (fixes.length > 0) {
    message.fix = fixes.length === 1 ? fixes[0] : fixes;
  }
  const suggestions = (diagnostic.suggestions ?? []).map((suggestion) => {
    const suggestionFixes = (suggestion.fix ?? []).map((fix) => ({
      range: fix.range,
      text: fix.text
    }));
    return {
      desc: suggestion.desc,
      ...(suggestionFixes.length === 0 ? {} : {
        fix: suggestionFixes.length === 1 ? suggestionFixes[0] : suggestionFixes
      })
    };
  });
  if (suggestions.length > 0) {
    message.suggestions = suggestions;
  }
  return message;
}

function suppressedDiagnosticToESLintMessage(diagnostic, ruleSeverities) {
  return {
    ...diagnosticToESLintMessage(diagnostic, ruleSeverities),
    suppressions: diagnostic.suppressions?.length > 0
      ? diagnostic.suppressions
      : [{
          kind: diagnostic.suppression?.kind ?? "directive",
          justification: diagnostic.suppression?.justification ?? ""
        }]
  };
}

function finalizeESLintResult(result) {
  result.errorCount = 0;
  result.warningCount = 0;
  result.fixableErrorCount = 0;
  result.fixableWarningCount = 0;
  for (const message of result.messages) {
    if (message.severity === 2) {
      result.errorCount += 1;
      if (ruleFixItems(message.fix).length > 0) {
        result.fixableErrorCount += 1;
      }
    } else {
      result.warningCount += 1;
      if (ruleFixItems(message.fix).length > 0) {
        result.fixableWarningCount += 1;
      }
    }
  }
}

function maybeFilterQuietResults(results, options = {}) {
  if (!options.quiet) {
    return results;
  }

  for (const result of results) {
    result.messages = (result.messages ?? []).filter((message) => message.severity === 2);
    result.suppressedMessages = (result.suppressedMessages ?? []).filter((message) => message.severity === 2);
    result.fixableWarningCount = 0;
    finalizeESLintResult(result);
  }
  return results;
}

function formatResultsByName(input, name = "stylish", metadata = {}, options = {}) {
  const results = formatterResults(input);
  if (name === "json") {
    return JSON.stringify(input);
  }
  if (name === "json-with-metadata") {
    return JSON.stringify({
      results,
      metadata: {
        rulesMeta: typeof metadata.rulesMeta === "function" ? metadata.rulesMeta(results) : rulesMetaForResults(results)
      }
    });
  }
  if (name === "compact") {
    return formatCompactResults(results);
  }
  if (name === "unix") {
    return formatUnixResults(results);
  }
  return formatESLintResults(results, options);
}

function formatterResults(input) {
  if (Array.isArray(input)) {
    return input;
  }
  if (input && typeof input === "object" && Array.isArray(input.results)) {
    return input.results;
  }
  if (input && typeof input === "object" && Array.isArray(input.diagnostics)) {
    return reportToESLintResults(input, {
      filePaths: (input.filePaths ?? []).map((filePath) => normalizeESLintFilePath(filePath))
    });
  }
  throw new Error("'results' must be an array or lint report");
}

function formatCompactResults(results) {
  const lines = [];
  for (const result of results) {
    for (const message of result.messages ?? []) {
      lines.push(`${result.filePath}: line ${message.line}, col ${message.column}, ${message.severity === 2 ? "Error" : "Warning"} - ${message.message} (${message.ruleId ?? ""})`);
    }
  }
  return lines.join("\n");
}

function formatUnixResults(results) {
  const lines = [];
  for (const result of results) {
    for (const message of result.messages ?? []) {
      lines.push(`${result.filePath}:${message.line}:${message.column}: ${message.message} [${message.severity === 2 ? "Error" : "Warning"}/${message.ruleId ?? ""}]`);
    }
  }
  return lines.join("\n");
}

function rulesMetaForResults(results, ruleMetaForMessage) {
  if (!Array.isArray(results)) {
    throw new Error("'results' must be an array");
  }

  const meta = {};
  for (const result of results) {
    for (const message of [...(result.messages ?? []), ...(result.suppressedMessages ?? [])]) {
      if (message.ruleId) {
        meta[message.ruleId] = ruleMetaForMessage?.(message.ruleId, result, message) ?? ruleMetaForRuleId(message.ruleId);
      }
    }
  }
  return meta;
}

function ruleSeverityMap(rules) {
  if (!rules) return undefined;

  const severities = new Map();
  for (const [rule, config] of Object.entries(rules)) {
    const severity = ruleConfigSeverity(config);
    severities.set(rule, severity);
  }
  return severities;
}

function ruleSeverityMapForOptions(options, filePath) {
  return ruleSeverityMap(calculatedConfig(options, filePath).rules);
}

function ruleConfigSeverity(config) {
  const severity = Array.isArray(config) ? config[0] : config;
  if (severity === false || severity === 0) return 0;
  if (severity === true || severity === 2) return 2;
  if (severity === 1) return 1;
  if (typeof severity === "string") {
    switch (severity.toLowerCase()) {
      case "off":
      case "0":
        return 0;
      case "warn":
      case "warning":
      case "1":
        return 1;
      case "error":
      case "2":
        return 2;
      default:
        return 1;
    }
  }
  return 1;
}
