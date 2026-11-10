import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { readdirSync, statSync } from "node:fs";
import { sharedRules } from "./shared-rules.mjs";

const negativeSource = `import imported from "fixture-module";
const value = 1;
value = 2;
const regex = /[]/;
const {} = {};
function unsafe() {
  try { work(); } finally { return 1; }
}
input === NaN;
typeof input === "strnig";
debugger;
switch (input) {
  case 1: break;
  case 1: break;
}
switch (input) {
  case 1: work();
  default: break;
}
Object = null;
imported = 2;
!input in object;
`;

const cleanSource = `import imported from "fixture-module";
export type Record = { value: number };
let value = 1;
value = 2;
const regex = /[a]/;
const { id } = { id: 1 };
function safe() {
  try { console.log(imported); } finally { console.log(value); }
}
Number.isNaN(value);
typeof value === "number";
switch (value) {
  case 1: break;
  case 2: break;
}
Object.assign({}, { value });
const local = imported;
!("value" in { value });
console.log(regex, id, local, safe);
`;

const extendedCleanSource = `export const value: number = 1;
export function identity(input: number): number { return input; }
`;

// These are kept separate from the combined fixture so the historical 12-rule
// preflight stays unchanged while larger profiles can check each rule alone.
const sharedValidationSources = {
  "no-const-assign": "const value = 1; value = 2;",
  "no-empty-character-class": "const regex = /[]/;",
  "no-empty-pattern": "const {} = {};",
  "no-unsafe-finally": "function unsafe() { try { work(); } finally { return 1; } }",
  "use-isnan": "input === NaN;",
  "valid-typeof": 'typeof input === "strnig";',
  "no-debugger": "debugger;",
  "no-duplicate-case": "switch (input) { case 1: break; case 1: break; }",
  "no-fallthrough": "switch (input) { case 1: work(); default: break; }",
  "no-global-assign": "Object = null;",
  "no-import-assign": 'import imported from "fixture-module"; imported = 2;',
  "no-unsafe-negation": "!input in object;"
};

export async function verifySharedRules(benchmarks, targetFiles, rules = sharedRules) {
  await mkdir("fixtures", { recursive: true });
  const directory = await mkdtemp(join("fixtures", "verify-shared-rules-"));
  const negativePath = join(directory, "negative.ts");
  const cleanPath = join(directory, "clean.ts");
  const tools = [];
  const legacyProfile = rules.length === sharedRules.length &&
    rules.every((rule, index) => rule.name === sharedRules[index].name);

  try {
    const fixtures = [];
    if (legacyProfile) {
      await writeFile(negativePath, negativeSource);
    } else {
      await writeFile(negativePath, negativeSource);
      for (const rule of rules) {
        const validation = rule.validation ?? sharedValidationSources[rule.name];
        const source = typeof validation === "string" ? validation : validation?.source;
        const expectedCount = typeof validation === "object" ? validation?.expectedCount ?? rule.expectedCount ?? 1 : rule.expectedCount ?? 1;
        if (typeof source !== "string" || !Number.isInteger(expectedCount) || expectedCount < 1) {
          throw new Error(`Rule ${rule.name} needs a validation source and a positive expected diagnostic count`);
        }
        const path = join(directory, `${rule.name}.ts`);
        await writeFile(path, source);
        fixtures.push({ rule, path, expectedCount });
      }
    }
    await writeFile(cleanPath, legacyProfile ? cleanSource : extendedCleanSource);
    for (const benchmark of benchmarks) {
      const ruleCounts = Object.fromEntries(rules.map((rule) => [rule.name, 0]));
      let negativeDiagnostics = 0;
      let fullProfileDiagnostics;
      if (legacyProfile) {
        const negative = verifyFile(benchmark, negativePath, 1, rules);
        for (const rule of negative.rules) {
          if (!Object.hasOwn(ruleCounts, rule)) {
            throw new Error(`${benchmark.name} reported an unexpected validation diagnostic: ${rule}`);
          }
          ruleCounts[rule] += 1;
        }
        const mismatches = Object.entries(ruleCounts).filter(([, count]) => count !== 1);
        if (mismatches.length > 0) {
          throw new Error(`${benchmark.name} shared-rule validation failed: ${JSON.stringify(Object.fromEntries(mismatches))}`);
        }
        negativeDiagnostics = negative.rules.length;
      } else {
        // Exercise the complete config as well as the isolated-rule overrides.
        // The npm wrapper can use a different execution path for --rules.
        const fullProfile = verifyFile(benchmark, directory, fixtures.length + 2, rules);
        for (const { rule, expectedCount } of fixtures) {
          if (fullProfile.rules.filter((name) => name === rule.name).length < expectedCount) {
            throw new Error(`${benchmark.name} full-profile validation did not run ${rule.name}`);
          }
        }
        if (fullProfile.rules.some((name) => !Object.hasOwn(ruleCounts, name))) {
          throw new Error(`${benchmark.name} full-profile validation reported an unselected rule`);
        }
        fullProfileDiagnostics = fullProfile.rules.length;
        for (const fixture of fixtures) {
          const isolated = isolateRule(benchmark, fixture.rule, rules);
          const negative = verifyFile(isolated, fixture.path, 1, rules);
          const expected = fixture.expectedCount;
          if (negative.rules.length !== expected || negative.rules.some((name) => name !== fixture.rule.name)) {
            throw new Error(`${benchmark.name} validation for ${fixture.rule.name} expected ${expected} diagnostic(s) from that rule, got ${JSON.stringify(negative.rules)} (status ${negative.status})`);
          }
          ruleCounts[fixture.rule.name] = negative.rules.length;
          negativeDiagnostics += negative.rules.length;
        }
      }
      const clean = verifyFile(benchmark, cleanPath, 1, rules);
      if (clean.rules.length > 0 || clean.status !== 0) {
        throw new Error(`${benchmark.name} reported diagnostics on the clean validation control: ${clean.rules.join(", ")}`);
      }
      tools.push({
        name: benchmark.name,
        negativeDiagnostics,
        ...(fullProfileDiagnostics === undefined ? {} : { fullProfileDiagnostics, fullProfileFiles: fixtures.length + 2 }),
        cleanDiagnostics: 0,
        ruleCounts
      });
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }

  // Remove validation fixtures first, even when the target includes fixtures/.
  if (targetFiles !== undefined) {
    for (const [index, benchmark] of benchmarks.entries()) {
      const target = verifyFile(benchmark, benchmark.targetInputs ?? benchmark.args.at(-1), targetFiles, rules);
      if (target.rules.length > 0 || target.status !== 0) {
        throw new Error(`${benchmark.name} reported diagnostics on the benchmark corpus: ${target.rules.join(", ")}`);
      }
      Object.assign(tools[index], { targetFiles, targetDiagnostics: 0 });
    }
  }

  return { rules: rules.map((rule) => rule.name), tools };
}

function isolateRule(benchmark, rule, rules) {
  const targets = benchmark.targetInputs ?? [benchmark.args.at(-1)];
  let args = benchmark.baseArgs ?? benchmark.args.slice(0, -1);
  switch (benchmark.name) {
    case "utoo-lint":
      args = withoutOptions(args, ["--rules"]);
      args.push(`--rules=${rule.name}`);
      break;
    case "oxlint":
      args = withoutOptions(args, ["-A", "-W", "-D", "--allow", "--warn", "--deny"]);
      args.push("-A", "all", "-D", rule.oxlint);
      break;
    case "bun":
    case "eslint": {
      args = withoutOptions(args, ["--rule"]);
      const configuredRules = new Set([...sharedRules, ...rules].map((entry) => entry.eslint));
      args.push(...Array.from(configuredRules, (name) => `--rule=${name}:off`), `--rule=${rule.eslint}:error`);
      break;
    }
    case "biome":
      args = withoutOptions(args, ["--only"]);
      args.push(`--only=${rule.biomeGroup}/${rule.biome}`);
      break;
    default:
      throw new Error(`Cannot isolate validation rules for ${benchmark.name}`);
  }
  return { ...benchmark, baseArgs: args, args: [...args, ...targets] };
}

function withoutOptions(args, options) {
  const filtered = [];
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (options.includes(arg)) {
      index += 1;
    } else if (!options.some((option) => arg.startsWith(`${option}=`))) {
      filtered.push(arg);
    }
  }
  return filtered;
}

function verifyFile(benchmark, path, expectedFiles = 1, selectedRules = sharedRules) {
  // Reuse the exact rule/config flags, replacing only the input file list.
  const args = (benchmark.baseArgs ?? benchmark.args.slice(0, -1)).filter((arg) =>
    arg !== "--silent" && !arg.startsWith("--max-diagnostics=")
  );
  const paths = Array.isArray(path) ? path : validationInputs(path);
  args.push(...(benchmark.name === "biome" ? ["--reporter=json", "--max-diagnostics=none"] : ["--format=json"]), ...paths);
  const result = spawnSync(benchmark.command, args, {
    encoding: "utf8",
    timeout: 30000,
    maxBuffer: 64 * 1024 * 1024,
    env: { ...process.env, CI: "1", NO_COLOR: "1" }
  });
  const details = [result.error?.message, result.stdout?.trim(), result.stderr?.trim()].filter(Boolean).join("\n");
  if (result.error || ![0, 1].includes(result.status)) {
    throw new Error(`${benchmark.name} validation command failed with status ${result.status}:\n${details}`);
  }

  let report;
  try {
    report = JSON.parse(result.stdout);
  } catch (error) {
    throw new Error(`${benchmark.name} validation did not produce valid JSON (${error.message}):\n${details}`);
  }

  let files;
  let rules;
  if (Array.isArray(report) && report.every((file) => Array.isArray(file.messages))) {
    files = report.length;
    rules = report.flatMap((file) => file.messages.map((diagnostic) => diagnostic.ruleId));
  } else if (Array.isArray(report.diagnostics)) {
    if (benchmark.name === "biome") {
      files = report.summary?.unchanged;
      const ruleNames = new Map(selectedRules.map((rule) => [`lint/${rule.biomeGroup}/${rule.biome}`, rule.name]));
      rules = report.diagnostics.map((diagnostic) => ruleNames.get(diagnostic.category) ?? diagnostic.category);
    } else if (benchmark.name === "utoo-lint") {
      files = report.files;
      rules = report.diagnostics.map((diagnostic) => diagnostic.ruleId);
    } else {
      files = report.number_of_files;
      rules = report.diagnostics.map((diagnostic) => /^eslint\(([^)]+)\)$/.exec(diagnostic.code)?.[1] ?? diagnostic.code);
    }
  } else {
    throw new Error(`${benchmark.name} validation returned an unrecognized JSON report:\n${details}`);
  }
  if (files !== expectedFiles) {
    throw new Error(`${benchmark.name} validation checked ${files ?? "an unknown number of"} files; expected ${expectedFiles}:\n${details}`);
  }
  return { rules, status: result.status };
}

function validationInputs(path) {
  if (!statSync(path).isDirectory()) return [path];
  return readdirSync(path, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)).flatMap((entry) => {
    const child = join(path, entry.name);
    if (entry.isDirectory()) return validationInputs(child);
    return entry.isFile() && /\.(?:[cm]?[jt]sx?)$/.test(entry.name) ? [child] : [];
  });
}
