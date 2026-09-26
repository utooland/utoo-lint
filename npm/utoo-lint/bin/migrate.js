import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { basename, dirname, extname, relative, resolve as resolvePath } from "node:path";
import { pathToFileURL } from "node:url";

import { Legacy } from "@eslint/eslintrc";
import eslintJs from "@eslint/js";

import { Linter } from "../index.js";

const ESLINT_CONFIG_FILENAMES = [
  "eslint.config.js",
  "eslint.config.mjs",
  "eslint.config.cjs",
  ".eslintrc.js",
  ".eslintrc.cjs",
  ".eslintrc.json",
  ".eslintrc"
];
const JAVASCRIPT_CONFIG_EXTENSIONS = new Set([".js", ".mjs", ".cjs"]);
const IGNORED_RULES = new Map([
  ["prettier/prettier", "formatting is outside utoo-lint"]
]);
// Add aliases only after reviewing the source rule against the target rule's
// implemented behavior and supported options.
const REVIEWED_RULE_ALIASES = new Map([
  ["no-native-reassign", "no-global-assign"],
  ["@typescript-eslint/no-invalid-this", "no-invalid-this"],
  ["@eslint-react/no-array-index-key", "react/no-array-index-key"],
  ["@eslint-react/dom-no-find-dom-node", "react/no-find-dom-node"],
  ["@eslint-react/dom-no-render-return-value", "react/no-render-return-value"],
  ["@eslint-react/dom-no-void-elements-with-children", "react/void-dom-elements-no-children"],
  ["@eslint-react/rules-of-hooks", "react-hooks/rules-of-hooks"]
]);
const SCHEMA_URL = "https://raw.githubusercontent.com/utooland/utoo-lint/main/npm/utoo-lint/schema.json";
const MIGRATION_SOURCE = Symbol("migrationSource");
const JAVASCRIPT_CONFIG_LOADER_SCRIPT = `
import { writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const loaded = await import(pathToFileURL(process.argv[1]).href);
const seen = new Set();

function strip(value) {
  if (value === null || typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "function" || typeof value === "symbol" || typeof value === "undefined") {
    return undefined;
  }
  if (typeof value !== "object") {
    return undefined;
  }
  if (seen.has(value)) {
    return undefined;
  }
  seen.add(value);
  if (Array.isArray(value)) {
    const items = value.map(strip).filter((item) => item !== undefined);
    seen.delete(value);
    return items;
  }
  const object = {};
  for (const [key, item] of Object.entries(value)) {
    const stripped = strip(item);
    if (stripped !== undefined) {
      object[key] = stripped;
    }
  }
  seen.delete(value);
  return object;
}

const json = JSON.stringify(strip(loaded.default ?? loaded));
if (json === undefined) {
  throw new TypeError("config did not export a migratable value");
}
writeFileSync(3, json);
`;

export async function runMigrate(args) {
  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    printMigrateHelp();
    return 0;
  }

  const source = args[0];
  if (source !== "eslint") {
    console.error(`utoo-lint migrate: unsupported source "${source}"`);
    console.error("Supported sources: eslint");
    return 2;
  }

  let options;
  try {
    options = parseEslintMigrateArgs(args.slice(1));
  } catch (error) {
    console.error(error.message);
    return 2;
  }

  if (options.help) {
    printEslintMigrateHelp();
    return 0;
  }

  let result;
  try {
    result = migrateEslintConfig(options);
  } catch (error) {
    console.error(error.message);
    return 2;
  }

  const configJson = JSON.stringify(result.config, null, 2) + "\n";
  if (options.print) {
    process.stdout.write(configJson);
  } else {
    if (existsSync(options.output) && !options.force) {
      console.error(`utoo-lint migrate eslint: ${options.output} already exists; pass --force to overwrite it`);
      return 2;
    }
    writeFileSync(options.output, configJson);
  }

  writeReport(result.report, options, options.print ? process.stderr : process.stdout);
  return result.report.unsupportedRules.length > 0 ? 1 : 0;
}

function parseEslintMigrateArgs(args) {
  const options = {
    cwd: process.cwd(),
    force: false,
    from: undefined,
    help: false,
    output: "utlint.config.json",
    print: false,
    report: "text"
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--force") {
      options.force = true;
    } else if (arg === "--print") {
      options.print = true;
    } else if (arg === "--from") {
      options.from = requireValue(args, ++index, "--from");
    } else if (arg.startsWith("--from=")) {
      options.from = arg.slice("--from=".length);
    } else if (arg === "--output" || arg === "-o") {
      options.output = requireValue(args, ++index, arg);
    } else if (arg.startsWith("--output=")) {
      options.output = arg.slice("--output=".length);
    } else if (arg === "--report") {
      options.report = parseReportFormat(requireValue(args, ++index, "--report"));
    } else if (arg.startsWith("--report=")) {
      options.report = parseReportFormat(arg.slice("--report=".length));
    } else {
      throw new Error(`utoo-lint migrate eslint: unknown option ${arg}`);
    }
  }

  options.cwd = resolvePath(options.cwd);
  options.output = resolvePath(options.cwd, options.output);
  if (options.from) {
    options.from = resolvePath(options.cwd, options.from);
  }
  return options;
}

function requireValue(args, index, flag) {
  const value = args[index];
  if (!value) {
    throw new Error(`utoo-lint migrate eslint: ${flag} requires a value`);
  }
  return value;
}

function parseReportFormat(value) {
  if (value === "text" || value === "json") {
    return value;
  }
  throw new Error(`utoo-lint migrate eslint: unsupported --report value ${value}`);
}

function migrateEslintConfig(options) {
  const sourcePath = options.from ?? findEslintConfig(options.cwd);
  if (!sourcePath) {
    throw new Error("utoo-lint migrate eslint: no ESLint config found; pass --from PATH");
  }

  const eslintConfig = loadEslintConfig(sourcePath, options.cwd);
  const supportedRuleIds = new Set(new Linter().getRules().keys());
  const migrationInput = migrationInputFromConfig(
    eslintConfig,
    sourcePath,
    realpathSync(dirname(options.output))
  );
  const entries = migrationInput.entries;
  const migratedEntries = [];
  const supportedRules = [];
  let unsupportedRules = [];
  const ignoredRules = [];
  const translatedRules = [];

  for (const entry of entries) {
    const rules = {};
    if (entry.rules && typeof entry.rules === "object") {
      for (const [ruleId, ruleConfig] of Object.entries(entry.rules)) {
        const migratedRuleId = REVIEWED_RULE_ALIASES.get(ruleId) ?? ruleId;
        if (IGNORED_RULES.has(ruleId)) {
          ignoredRules.push({ ruleId, reason: IGNORED_RULES.get(ruleId) });
          continue;
        }
        if (!supportedRuleIds.has(migratedRuleId)) {
          if (isRuleDisabled(ruleConfig)) {
            unsupportedRules = removeDisabledUnsupportedRule(unsupportedRules, ruleId, entry);
            continue;
          }
          const source = entry[MIGRATION_SOURCE];
          unsupportedRules.push({ ruleId, scope: migrationRuleScope(entry), source });
          continue;
        }
        rules[migratedRuleId] = migratableRuleConfig(ruleConfig);
        supportedRules.push(migratedRuleId);
        if (migratedRuleId !== ruleId) {
          translatedRules.push({ sourceRuleId: ruleId, targetRuleId: migratedRuleId });
        }
      }
    }
    migratedEntries.push(migratableConfigEntry(entry, rules));
  }

  const config = Array.isArray(eslintConfig) || migratedEntries.length > 1
    ? [{ $schema: SCHEMA_URL }, ...migratedEntries]
    : { $schema: SCHEMA_URL, ...(migratedEntries[0] ?? { rules: {} }) };

  return {
    config,
    report: {
      source: sourcePath,
      output: options.print ? null : options.output,
      supportedRules: uniqueSorted(supportedRules),
      unsupportedRules: uniqueSorted(unsupportedRules.map((rule) => rule.ruleId)),
      ignoredRules: uniqueByRuleId(ignoredRules),
      translatedRules: uniqueTranslatedRules(translatedRules),
      inheritedSources: migrationInput.inheritedSources,
      unsupportedInheritedRules: uniqueUnsupportedInheritedRules(
        unsupportedRules
          .filter((rule) => rule.source?.inherited)
          .map((rule) => ({
            ruleId: rule.ruleId,
            sourceName: rule.source.name,
            sourcePath: rule.source.filePath
          }))
      ),
      optionDroppedRules: []
    }
  };
}

function migrationInputFromConfig(eslintConfig, sourcePath, outputDirectory) {
  if (!isClassicEslintConfig(eslintConfig, sourcePath)) {
    return { entries: normalizeConfigEntries(eslintConfig), inheritedSources: [] };
  }

  const basePath = realpathSync(dirname(sourcePath));
  const factory = new MigrationConfigArrayFactory({
    cwd: basePath,
    getEslintRecommendedConfig: () => eslintJs.configs.recommended,
    getEslintAllConfig: () => eslintJs.configs.all
  });

  let configArray;
  try {
    configArray = factory.create(eslintConfig, {
      basePath,
      filePath: sourcePath,
      name: sourcePath
    });
  } catch (error) {
    throw new Error(`utoo-lint migrate eslint: unable to resolve classic config ${sourcePath}: ${error.message}`);
  }

  return migrationInputFromClassicConfigArray(configArray, basePath, outputDirectory);
}

function isClassicEslintConfig(eslintConfig, sourcePath) {
  if (/^\.eslintrc(?:\.|$)/u.test(basename(sourcePath))) {
    return true;
  }
  return Boolean(
    eslintConfig &&
    !Array.isArray(eslintConfig) &&
    typeof eslintConfig === "object" &&
    (eslintConfig.extends || eslintConfig.overrides || eslintConfig.ignorePatterns)
  );
}

class MigrationConfigArrayFactory extends Legacy.ConfigArrayFactory {
  activeSources = [];

  _loadPlugin(name, context) {
    return super._loadPlugin(name, {
      ...context,
      pluginBasePath: context.filePath ? dirname(context.filePath) : context.pluginBasePath
    });
  }

  *_normalizeConfigData(configData, context) {
    const source = classicContextSource(context);
    const cycleIndex = this.activeSources.findIndex((active) => active.key === source.key);
    if (cycleIndex !== -1) {
      const chain = [...this.activeSources.slice(cycleIndex), source].map((active) => active.label).join(" -> ");
      throw new Error(`Circular ESLint extends chain detected: ${chain}`);
    }

    this.activeSources.push(source);
    try {
      yield* super._normalizeConfigData(configData, context);
    } finally {
      this.activeSources.pop();
    }
  }
}

function classicContextSource(context) {
  const label = classicSourceName(context.name ?? context.filePath ?? "inline config");
  const key = label.startsWith("plugin:")
    ? `plugin:${context.filePath ?? ""}:${label}`
    : context.filePath
      ? `file:${resolvePath(context.filePath)}`
      : `name:${label}`;
  return { key, label };
}

function migrationInputFromClassicConfigArray(configArray, basePath, outputDirectory) {
  const entries = [];
  const inheritedSources = [];
  const records = [...configArray].map((element) => ({
    element,
    source: classicElementSource(element),
    selector: rebaseClassicSelector(classicSelector(element.criteria), basePath, outputDirectory),
    ignorePatterns: element.ignorePattern?.getPatternsRelativeTo(basePath) ?? []
  }));
  const scopedIgnores = new Map();

  for (const record of records) {
    if (record.element.criteria && record.ignorePatterns.length > 0) {
      const key = classicOverrideChainKey(record.element);
      scopedIgnores.set(key, uniquePatterns([...(scopedIgnores.get(key) ?? []), ...record.ignorePatterns]));
    }
  }

  for (const { element, source, selector, ignorePatterns } of records) {
    if (source.inherited) {
      inheritedSources.push({ name: source.name, filePath: source.filePath });
    }

    const effectiveIgnorePatterns = (element.criteria
      ? scopedIgnores.get(classicOverrideChainKey(element)) ?? []
      : ignorePatterns).map((pattern) => rebaseClassicPattern(pattern, basePath, outputDirectory, true));
    const rebasedIgnorePatterns = ignorePatterns.map(
      (pattern) => rebaseClassicPattern(pattern, basePath, outputDirectory, true)
    );
    const hasRules = element.rules && typeof element.rules === "object";

    if (rebasedIgnorePatterns.length > 0 && !element.criteria) {
      entries.push(withMigrationSource({ ignores: rebasedIgnorePatterns }, source));
    }

    if (hasRules) {
      const entry = { ...selector, rules: element.rules };
      if (effectiveIgnorePatterns.length > 0 && element.criteria) {
        entry.ignores = uniquePatterns([...(entry.ignores ?? []), ...effectiveIgnorePatterns]);
      }
      entries.push(withMigrationSource(entry, source));
    } else if (rebasedIgnorePatterns.length > 0 && element.criteria) {
      entries.push(withMigrationSource({ ...selector, ignores: [...(selector.ignores ?? []), ...rebasedIgnorePatterns] }, source));
    }
  }

  return {
    entries,
    inheritedSources: uniqueInheritedSources(inheritedSources)
  };
}

function classicOverrideChainKey(element) {
  const segments = String(element.name ?? "").split(" » ");
  let overrideIndex = -1;
  for (let index = 0; index < segments.length; index += 1) {
    if (/#overrides\[\d+\]/u.test(segments[index])) {
      overrideIndex = index;
    }
  }
  return overrideIndex === -1
    ? `criteria:${classicCriteriaKey(element.criteria)}`
    : `override:${segments.slice(0, overrideIndex + 1).join(" » ")}`;
}

function rebaseClassicSelector(selector, basePath, outputDirectory) {
  return {
    ...(selector.files ? {
      files: selector.files.map((value) => Array.isArray(value)
        ? value.map((pattern) => rebaseClassicPattern(pattern, basePath, outputDirectory))
        : rebaseClassicPattern(value, basePath, outputDirectory))
    } : {}),
    ...(selector.ignores ? {
      ignores: selector.ignores.map(
        (pattern) => rebaseClassicPattern(pattern, basePath, outputDirectory, true)
      )
    } : {})
  };
}

function rebaseClassicPattern(pattern, basePath, outputDirectory, preserveBasenameMatch = false) {
  const negated = pattern.startsWith("!");
  const unsignedPattern = negated ? pattern.slice(1) : pattern;
  const rootAnchored = unsignedPattern.startsWith("/");
  const value = rootAnchored ? unsignedPattern.slice(1) : unsignedPattern;
  if (preserveBasenameMatch && !rootAnchored && !value.includes("/")) {
    return pattern;
  }

  const absolutePattern = resolvePath(basePath, value);
  const relativePattern = normalizeMigrationPath(relative(outputDirectory, absolutePattern));
  const rebased = relativePattern === ".." || relativePattern.startsWith("../")
    ? normalizeMigrationPath(absolutePattern)
    : relativePattern || ".";
  const anchoredPattern = rootAnchored && !rebased.includes("/") ? `/${rebased}` : rebased;
  return negated ? `!${anchoredPattern}` : anchoredPattern;
}

function normalizeMigrationPath(path) {
  return path.replaceAll("\\", "/");
}

function classicCriteriaKey(criteria) {
  return JSON.stringify(classicSelector(criteria));
}

function classicSelector(criteria) {
  if (!criteria) {
    return {};
  }

  const includeGroups = [];
  const ignores = [];
  for (const patternGroup of criteria.patterns) {
    includeGroups.push(uniquePatterns(
      (patternGroup.includes ?? []).flatMap((matcher) => expandClassicExtglobs(classicIncludePattern(matcher)))
    ));
    ignores.push(...(patternGroup.excludes ?? []).flatMap(
      (matcher) => expandClassicExtglobs(classicExcludePattern(matcher))
    ));
  }
  const files = classicFileSelectors(includeGroups);

  return {
    ...(files.length > 0 ? { files } : {}),
    ...(ignores.length > 0 ? { ignores: uniquePatterns(ignores) } : {})
  };
}

function classicIncludePattern(matcher) {
  return matcher.options?.matchBase && !matcher.pattern.includes("/")
    ? `**/${matcher.pattern}`
    : matcher.pattern;
}

function classicExcludePattern(matcher) {
  return matcher.options?.matchBase === false && !matcher.pattern.includes("/")
    ? `/${matcher.pattern}`
    : matcher.pattern;
}

function expandClassicExtglobs(pattern) {
  let expansions = [pattern];
  while (expansions.some((value) => /@\([^()]*\)/u.test(value))) {
    expansions = expansions.flatMap((value) => {
      const match = /@\(([^()]*)\)/u.exec(value);
      if (!match) {
        return value;
      }
      const alternatives = match[1].split("|");
      if (alternatives.some((alternative) =>
        !alternative ||
        alternative.includes("/") ||
        alternative.includes("\\") ||
        /[*?[\]{}()]/u.test(alternative)
      )) {
        throw unsupportedClassicExtglobError(pattern);
      }
      return alternatives.map((alternative) =>
        `${value.slice(0, match.index)}${alternative}${value.slice(match.index + match[0].length)}`
      );
    });
  }
  if (/[?+*!@]\(/u.test(expansions[0])) {
    throw unsupportedClassicExtglobError(pattern);
  }
  return uniquePatterns(expansions);
}

function unsupportedClassicExtglobError(pattern) {
  return new Error(
    `utoo-lint migrate eslint: cannot migrate classic selector pattern "${pattern}": ` +
    "only literal @(one|two) extglob alternatives without path separators are supported"
  );
}

function classicFileSelectors(includeGroups) {
  const groups = includeGroups.filter((group) => group.length > 0);
  if (groups.length <= 1) {
    return groups[0] ?? [];
  }

  let selectors = [[]];
  for (const group of groups) {
    selectors = selectors.flatMap((selector) => group.map((pattern) => [...selector, pattern]));
  }
  return selectors;
}

function uniquePatterns(patterns) {
  return [...new Set(patterns)];
}

function migrationRuleScope(entry) {
  if (!entry.files && !entry.ignores) {
    return null;
  }
  return {
    files: migratableFilePatterns(entry.files),
    ignores: migratablePatterns(entry.ignores)
  };
}

function removeDisabledUnsupportedRule(rules, ruleId, entry) {
  const disabledScope = migrationRuleScope(entry);
  const remaining = [];
  for (const rule of rules) {
    if (rule.ruleId !== ruleId) {
      remaining.push(rule);
      continue;
    }
    const scope = subtractDisabledScope(rule.scope, disabledScope);
    if (scope !== undefined) {
      remaining.push({ ...rule, scope });
    }
  }
  return remaining;
}

function subtractDisabledScope(enabledScope, disabledScope) {
  if (disabledScope === null) {
    return undefined;
  }
  if (enabledScope === null) {
    return enabledScope;
  }
  if (
    disabledScope.ignores.length > 0 &&
    JSON.stringify(enabledScope.ignores) !== JSON.stringify(disabledScope.ignores)
  ) {
    return enabledScope;
  }
  if (disabledScope.files.length === 0) {
    return undefined;
  }
  if (enabledScope.files.length === 0) {
    return enabledScope;
  }

  const disabledGroups = disabledScope.files.map((selector) => Array.isArray(selector) ? selector : [selector]);
  const files = enabledScope.files.filter((selector) => {
    const enabledGroup = Array.isArray(selector) ? selector : [selector];
    return !disabledGroups.some((disabledGroup) => selectorGroupCovers(enabledGroup, disabledGroup));
  });
  return files.length === 0 ? undefined : { ...enabledScope, files };
}

function selectorGroupCovers(enabledGroup, disabledGroup) {
  return disabledGroup.every((disabledPattern) => enabledGroup.some((enabledPattern) =>
    globPatternCovers(enabledPattern, disabledPattern)
  ));
}

function globPatternCovers(enabledPattern, disabledPattern) {
  if (enabledPattern === disabledPattern) {
    return true;
  }
  const enabledSegments = enabledPattern.split("/");
  const disabledSegments = disabledPattern.split("/");
  return globSegmentsCover(enabledSegments, disabledSegments, 0, 0);
}

function globSegmentsCover(enabled, disabled, enabledIndex, disabledIndex) {
  if (disabledIndex === disabled.length) {
    return enabledIndex === enabled.length;
  }
  if (disabled[disabledIndex] === "**") {
    if (disabledIndex === disabled.length - 1) {
      return true;
    }
    for (let index = enabledIndex; index <= enabled.length; index += 1) {
      if (globSegmentsCover(enabled, disabled, index, disabledIndex + 1)) {
        return true;
      }
    }
    return false;
  }
  if (enabledIndex === enabled.length || enabled[enabledIndex] === "**") {
    return false;
  }
  return globSegmentCovers(enabled[enabledIndex], disabled[disabledIndex]) &&
    globSegmentsCover(enabled, disabled, enabledIndex + 1, disabledIndex + 1);
}

function globSegmentCovers(enabledSegment, disabledSegment) {
  if (enabledSegment === disabledSegment) {
    return true;
  }
  if (/[?[{]/u.test(disabledSegment)) {
    return false;
  }
  const expression = new RegExp(`^${disabledSegment
    .split("*")
    .map((part) => part.replace(/[.+?^${}()|[\]\\]/gu, "\\$&"))
    .join(".*")}$`);
  return expression.test(enabledSegment);
}

function classicElementSource(element) {
  const name = classicSourceName(element.name ?? element.filePath ?? "inline config");
  return {
    inherited: String(element.name ?? "").includes(" » "),
    name,
    filePath: element.filePath || null
  };
}

function classicSourceName(name) {
  return String(name).split(" » ").at(-1).replace(/#overrides\[\d+\]$/u, "");
}

function withMigrationSource(entry, source) {
  Object.defineProperty(entry, MIGRATION_SOURCE, { value: source });
  return entry;
}

function findEslintConfig(cwd) {
  let current = cwd;
  while (true) {
    for (const filename of ESLINT_CONFIG_FILENAMES) {
      const candidate = resolvePath(current, filename);
      if (existsSync(candidate)) {
        return candidate;
      }
    }
    const parent = dirname(current);
    if (parent === current) {
      return undefined;
    }
    current = parent;
  }
}

function loadEslintConfig(path, cwd) {
  if (JAVASCRIPT_CONFIG_EXTENSIONS.has(extname(path))) {
    const result = spawnSync(process.execPath, ["--input-type=module", "--eval", JAVASCRIPT_CONFIG_LOADER_SCRIPT, path], {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe", "pipe"]
    });
    if (result.error) {
      throw result.error;
    }
    if (result.status !== 0) {
      throw new Error(`utoo-lint migrate eslint: unable to load ${path}: ${(result.stderr ?? "").trim() || "JavaScript config loader failed"}`);
    }
    return parseJson(result.output?.[3] ?? "", path);
  }
  return parseJson(readFileSync(path, "utf8"), path);
}

function parseJson(source, path) {
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new Error(`utoo-lint migrate eslint: unable to parse ${path}: ${error.message}`);
  }
}

function normalizeConfigEntries(config) {
  if (Array.isArray(config)) {
    return config.flatMap(normalizeConfigEntries);
  }
  if (config && typeof config === "object") {
    return [config];
  }
  return [];
}

function migratableConfigEntry(entry, rules) {
  const migrated = {};
  if (typeof entry.name === "string") {
    migrated.name = entry.name;
  }
  const files = migratableFilePatterns(entry.files);
  if (files.length > 0) {
    migrated.files = files;
  }
  const ignores = migratablePatterns(entry.ignores);
  if (ignores.length > 0) {
    migrated.ignores = ignores;
  }
  if (!isGlobalIgnoreEntry(entry)) {
    migrated.rules = sortObjectByKey(rules);
  }
  return migrated;
}

function migratableFilePatterns(value) {
  const result = [];
  const seen = new Set();
  for (const pattern of Array.isArray(value) ? value : [value]) {
    const migrated = Array.isArray(pattern)
      ? migratablePatterns(pattern)
      : typeof pattern === "string"
        ? pattern
        : null;
    if (migrated === null || (Array.isArray(migrated) && migrated.length === 0)) {
      continue;
    }
    const key = JSON.stringify(migrated);
    if (!seen.has(key)) {
      seen.add(key);
      result.push(migrated);
    }
  }
  return result;
}

function migratablePatterns(value) {
  const patterns = [];
  collectMigratablePatterns(value, patterns);
  return [...new Set(patterns)];
}

function collectMigratablePatterns(value, patterns) {
  for (const pattern of Array.isArray(value) ? value : [value]) {
    if (Array.isArray(pattern)) {
      collectMigratablePatterns(pattern, patterns);
    } else if (typeof pattern === "string") {
      patterns.push(pattern);
    }
  }
}

function isGlobalIgnoreEntry(entry) {
  return Boolean(entry.ignores) && Object.keys(entry).every((key) => key === "name" || key === "ignores");
}

function migratableRuleConfig(ruleConfig) {
  return Array.isArray(ruleConfig) ? [...ruleConfig] : ruleConfig;
}

function isRuleDisabled(ruleConfig) {
  const severity = Array.isArray(ruleConfig) ? ruleConfig[0] : ruleConfig;
  return severity === "off" || severity === 0 || severity === false;
}

function sortObjectByKey(object) {
  return Object.fromEntries(Object.entries(object).sort(([left], [right]) => left.localeCompare(right)));
}

function uniqueSorted(values) {
  return [...new Set(values)].sort();
}

function uniqueByRuleId(values) {
  const result = new Map();
  for (const value of values) {
    result.set(value.ruleId, value);
  }
  return [...result.values()].sort((left, right) => left.ruleId.localeCompare(right.ruleId));
}

function uniqueTranslatedRules(values) {
  const result = new Map();
  for (const value of values) {
    result.set(value.sourceRuleId, value);
  }
  return [...result.values()].sort((left, right) => left.sourceRuleId.localeCompare(right.sourceRuleId));
}

function uniqueInheritedSources(values) {
  const result = new Map();
  for (const value of values) {
    result.set(`${value.name}\0${value.filePath ?? ""}`, value);
  }
  return [...result.values()].sort((left, right) =>
    left.name.localeCompare(right.name) || String(left.filePath ?? "").localeCompare(String(right.filePath ?? ""))
  );
}

function uniqueUnsupportedInheritedRules(values) {
  const result = new Map();
  for (const value of values) {
    result.set(`${value.ruleId}\0${value.sourceName}\0${value.sourcePath ?? ""}`, value);
  }
  return [...result.values()].sort((left, right) =>
    left.ruleId.localeCompare(right.ruleId) ||
    left.sourceName.localeCompare(right.sourceName) ||
    String(left.sourcePath ?? "").localeCompare(String(right.sourcePath ?? ""))
  );
}

function writeReport(report, options, stream) {
  if (options.report === "json") {
    stream.write(JSON.stringify(report, null, 2) + "\n");
    return;
  }

  stream.write(`utoo-lint migrate eslint: read ${pathToFileURL(report.source).href}\n`);
  if (report.output) {
    stream.write(`utoo-lint migrate eslint: wrote ${report.output}\n`);
  }
  stream.write(`utoo-lint migrate eslint: migrated ${report.supportedRules.length} supported rule(s)\n`);
  if (report.inheritedSources.length > 0) {
    stream.write(`utoo-lint migrate eslint: resolved ${report.inheritedSources.length} inherited config source(s): ${report.inheritedSources.map(formatInheritedSource).join(", ")}\n`);
  }
  if (report.translatedRules.length > 0) {
    stream.write(`utoo-lint migrate eslint: translated ${report.translatedRules.length} rule alias(es): ${report.translatedRules.map((rule) => `${rule.sourceRuleId} -> ${rule.targetRuleId}`).join(", ")}\n`);
  }
  if (report.ignoredRules.length > 0) {
    stream.write(`utoo-lint migrate eslint: ignored ${report.ignoredRules.length} rule(s): ${report.ignoredRules.map((rule) => rule.ruleId).join(", ")}\n`);
  }
  if (report.unsupportedRules.length > 0) {
    stream.write(`utoo-lint migrate eslint: ${report.unsupportedRules.length} unsupported rule(s): ${report.unsupportedRules.join(", ")}\n`);
  }
  if (report.unsupportedInheritedRules.length > 0) {
    stream.write(`utoo-lint migrate eslint: unsupported inherited rule source(s): ${report.unsupportedInheritedRules.map((rule) => `${rule.ruleId} from ${formatInheritedSource({ name: rule.sourceName, filePath: rule.sourcePath })}`).join(", ")}\n`);
  }
}

function formatInheritedSource(source) {
  return source.filePath ? `${source.name} (${pathToFileURL(source.filePath).href})` : source.name;
}

function printMigrateHelp() {
  console.log(`Usage:
  utoo-lint migrate eslint [options]

Sources:
  eslint                  Convert an ESLint config into utlint.config.json

Run "utoo-lint migrate eslint --help" for source-specific options.`);
}

function printEslintMigrateHelp() {
  console.log(`Usage:
  utoo-lint migrate eslint [options]

Options:
  --from=PATH             Read ESLint config from PATH
  --output=PATH, -o PATH  Write utoo config to PATH (default: utlint.config.json)
  --force                 Overwrite the output file when it exists
  --print                 Print the generated config instead of writing it
  --report=text|json      Select migration report format
  --help, -h              Show this help message`);
}
