import { extendedRuleAdditions } from "./extended-rules.mjs";

export const sharedRules = [
  {
    name: "no-const-assign",
    utooOption: "no_const_assign",
    eslint: "no-const-assign",
    oxlint: "no-const-assign",
    biomeGroup: "correctness",
    biome: "noConstAssign"
  },
  {
    name: "no-empty-character-class",
    utooOption: "no_empty_character_class",
    eslint: "no-empty-character-class",
    oxlint: "no-empty-character-class",
    biomeGroup: "correctness",
    biome: "noEmptyCharacterClassInRegex"
  },
  {
    name: "no-empty-pattern",
    utooOption: "no_empty_pattern",
    eslint: "no-empty-pattern",
    oxlint: "no-empty-pattern",
    biomeGroup: "correctness",
    biome: "noEmptyPattern"
  },
  {
    name: "no-unsafe-finally",
    utooOption: "no_unsafe_finally",
    eslint: "no-unsafe-finally",
    oxlint: "no-unsafe-finally",
    biomeGroup: "correctness",
    biome: "noUnsafeFinally"
  },
  {
    name: "use-isnan",
    utooOption: "use_isnan",
    eslint: "use-isnan",
    oxlint: "use-isnan",
    biomeGroup: "correctness",
    biome: "useIsNan"
  },
  {
    name: "valid-typeof",
    utooOption: "valid_typeof",
    eslint: "valid-typeof",
    oxlint: "valid-typeof",
    biomeGroup: "correctness",
    biome: "useValidTypeof"
  },
  {
    name: "no-debugger",
    utooOption: "no_debugger",
    eslint: "no-debugger",
    oxlint: "no-debugger",
    biomeGroup: "suspicious",
    biome: "noDebugger"
  },
  {
    name: "no-duplicate-case",
    utooOption: "no_duplicate_case",
    eslint: "no-duplicate-case",
    oxlint: "no-duplicate-case",
    biomeGroup: "suspicious",
    biome: "noDuplicateCase"
  },
  {
    name: "no-fallthrough",
    utooOption: "no_fallthrough",
    eslint: "no-fallthrough",
    oxlint: "no-fallthrough",
    biomeGroup: "suspicious",
    biome: "noFallthroughSwitchClause"
  },
  {
    name: "no-global-assign",
    utooOption: "no_global_assign",
    eslint: "no-global-assign",
    oxlint: "no-global-assign",
    biomeGroup: "suspicious",
    biome: "noGlobalAssign"
  },
  {
    name: "no-import-assign",
    utooOption: "no_import_assign",
    eslint: "no-import-assign",
    oxlint: "no-import-assign",
    biomeGroup: "suspicious",
    biome: "noImportAssign"
  },
  {
    name: "no-unsafe-negation",
    utooOption: "no_unsafe_negation",
    eslint: "no-unsafe-negation",
    oxlint: "no-unsafe-negation",
    biomeGroup: "suspicious",
    biome: "noUnsafeNegation"
  }
];

export function rulesForProfile(profile = process.env.UTOO_LINT_BENCH_RULE_SET ?? "shared") {
  if (profile === "shared") return sharedRules;
  if (profile === "extended") return [...sharedRules, ...extendedRuleAdditions];
  throw new Error(`Unknown benchmark rule set: ${profile}. Expected shared or extended.`);
}

export function eslintRuleConfig(severity = "error", rules = sharedRules) {
  return Object.fromEntries(rules.map((rule) => [rule.eslint, severity]));
}

export function oxlintRuleArgs(severity = "-D", rules = sharedRules) {
  return ["-A", "all", ...rules.flatMap((rule) => [severity, rule.oxlint])];
}

export function utooRuleArgs(rules = sharedRules) {
  return [`--rules=${rules.map((rule) => rule.name).join(",")}`];
}

export function benchmarkRuleNames(rules = sharedRules) {
  return rules.map((rule) => rule.name);
}
