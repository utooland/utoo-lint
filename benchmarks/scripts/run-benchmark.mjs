import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpus, release } from "node:os";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import { benchmarkRuleNames, oxlintRuleArgs, rulesForProfile, utooRuleArgs } from "./shared-rules.mjs";
import { verifySharedRules } from "./verify-shared-rules.mjs";

const args = parseArgs(process.argv.slice(2));
const runs = positiveInt(args.runs, 8, "runs");
const warmups = nonNegativeInt(args.warmups, 2, "warmups");
const target = args.target ?? "fixtures/src";
const skipEslint = Boolean(args["skip-eslint"]);
const includeBun = Boolean(args.bun || process.env.BUN_BIN) && !args["skip-bun"];
const ruleSet = args["rule-set"] ?? "shared";
const selectedRules = rulesForProfile(ruleSet);
process.env.UTOO_LINT_BENCH_RULE_SET = ruleSet;

const localBin = join("node_modules", ".bin");
const utooBin = process.env.UTOO_LINT_BIN ?? join("..", "zig-out", "bin", process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint");
const bunBin = process.env.BUN_BIN ?? "bun";

const benchmarks = [
  {
    name: "utoo-lint",
    command: utooBin,
    args: ["--no-config", ...utooRuleArgs(selectedRules), target],
    requiredPath: utooBin
  },
  {
    name: "bun",
    command: bunBin,
    args: ["lint", "--flavor=eslint", "--config=eslint.config.js", "--no-ignore", "--silent", target],
    optional: !includeBun
  },
  {
    name: "oxlint",
    command: bin("oxlint"),
    args: [...oxlintRuleArgs("-D", selectedRules), "--no-ignore", "--silent", target],
    requiredPath: bin("oxlint")
  },
  {
    name: "biome",
    command: bin("biome"),
    args: ["lint", "--config-path=biome.json",
      ...(ruleSet === "extended" ? selectedRules.map((rule) => `--only=${rule.biomeGroup}/${rule.biome}`) : []),
      "--max-diagnostics=0", target],
    requiredPath: bin("biome")
  },
  {
    name: "eslint",
    command: bin("eslint"),
    args: ["--max-warnings=0", "--no-warn-ignored", target],
    requiredPath: bin("eslint"),
    optional: skipEslint
  }
].filter((benchmark) => !benchmark.optional);

for (const benchmark of benchmarks) {
  if (benchmark.requiredPath && !existsSync(benchmark.requiredPath)) {
    throw new Error(
      `${benchmark.name} binary was not found at ${benchmark.requiredPath}. Run npm install, or build utoo-lint first.`
    );
  }
}

if (includeBun) {
  const probe = spawnSync(bunBin, ["lint", "--help"], { encoding: "utf8", timeout: 10000 });
  if (probe.error || probe.status !== 0 || !/--flavor/.test(`${probe.stdout}${probe.stderr}`)) {
    throw new Error(
      `Bun at ${bunBin} does not expose the required built-in lint CLI. Set BUN_BIN to a supported binary, or omit --bun/BUN_BIN.\n${probe.error?.message ?? probe.stderr?.trim() ?? ""}`
    );
  }
}

const targetFiles = await countFiles(target);
if (targetFiles === 0) {
  throw new Error(`No lintable files found in ${target}`);
}
const validation = await verifySharedRules(benchmarks, targetFiles, selectedRules);
console.log(`Verified ${validation.rules.length} shared rules and clean controls for ${benchmarks.length} tools.`);

const sourceCommit = commandOutput("git", ["rev-parse", "HEAD"]);
const sourceDirty = Boolean(commandOutput("git", ["status", "--porcelain"]));
const results = benchmarks.map((benchmark) => ({
  name: benchmark.name,
  version: benchmark.name === "utoo-lint" ? null : commandOutput(benchmark.command, ["--version"]),
  ...(benchmark.name === "bun" ? { revision: commandOutput(benchmark.command, ["--revision"]) } : {}),
  command: [benchmark.command, ...benchmark.args].join(" "),
  runs,
  warmups,
  samplesMs: []
}));
// Rotate the starting tool to spread startup/order effects across the samples.
for (let round = 0; round < warmups; round += 1) {
  for (let offset = 0; offset < benchmarks.length; offset += 1) {
    runCommand(benchmarks[(round + offset) % benchmarks.length], true);
  }
}
for (let round = 0; round < runs; round += 1) {
  for (let offset = 0; offset < benchmarks.length; offset += 1) {
    const index = (round + offset) % benchmarks.length;
    results[index].samplesMs.push(runCommand(benchmarks[index], false));
  }
}
for (const result of results) {
  result.summary = summarize(result.samplesMs);
}

const fastest = Math.min(...results.map((result) => result.summary.medianMs));
const printable = results.map((result) => ({
  tool: result.name,
  median: formatMs(result.summary.medianMs),
  mean: formatMs(result.summary.meanMs),
  min: formatMs(result.summary.minMs),
  max: formatMs(result.summary.maxMs),
  relative: `${(result.summary.medianMs / fastest).toFixed(2)}x`
}));

console.log(`Rule set: ${ruleSet}`);
console.log(`Rules: ${benchmarkRuleNames(selectedRules).join(", ")}`);
console.log(`Target: ${target} (${targetFiles} file(s))`);
console.table(printable);

await mkdir("results", { recursive: true });
await writeFile(
  "results/latest.json",
  `${JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      node: process.version,
      platform: process.platform,
      arch: process.arch,
      osRelease: release(),
      cpu: { model: cpus()[0]?.model ?? null, logicalCores: cpus().length },
      sourceCommit,
      sourceDirty,
      utooBuildMode: process.env.UTOO_LINT_BUILD_MODE ?? null,
      utooBinarySha256: createHash("sha256").update(await readFile(utooBin)).digest("hex"),
      sampling: "round-robin with a rotated starting tool; fresh CLI processes",
      dependencyVersions: await dependencyVersions(),
      validation,
      ruleSet,
      target,
      targetFiles,
      rules: benchmarkRuleNames(selectedRules),
      results
    },
    null,
    2
  )}\n`
);

console.log("Wrote results/latest.json");

function commandOutput(command, commandArgs) {
  const result = spawnSync(command, commandArgs, { encoding: "utf8", timeout: 10000 });
  return result.status === 0 ? result.stdout.trim() || result.stderr.trim() : null;
}

async function dependencyVersions() {
  const names = ["typescript", "typescript-eslint", "@eslint/js"];
  return Object.fromEntries(await Promise.all(names.map(async (name) => {
    const manifest = JSON.parse(await readFile(join("node_modules", name, "package.json"), "utf8"));
    return [name, manifest.version];
  })));
}

function runCommand(benchmark, isWarmup) {
  const started = performance.now();
  const result = spawnSync(benchmark.command, benchmark.args, {
    cwd: process.cwd(),
    env: {
      ...process.env,
      CI: "1",
      NO_COLOR: "1"
    },
    encoding: "utf8",
    stdio: isWarmup ? "ignore" : "pipe"
  });
  const elapsed = performance.now() - started;

  if (result.error || result.status !== 0) {
    const detail = [
      result.error?.message,
      result.stdout?.trim(),
      result.stderr?.trim()
    ]
      .filter(Boolean)
      .join("\n");
    throw new Error(`${benchmark.name} failed with status ${result.status ?? "unknown"}:\n${detail}`);
  }

  return Number(elapsed.toFixed(3));
}

function summarize(samples) {
  const sorted = [...samples].sort((a, b) => a - b);
  const sum = samples.reduce((total, value) => total + value, 0);
  const mean = sum / samples.length;
  const variance = samples.reduce((total, value) => total + (value - mean) ** 2, 0) / samples.length;

  return {
    minMs: sorted[0],
    maxMs: sorted[sorted.length - 1],
    meanMs: Number(mean.toFixed(3)),
    medianMs: median(sorted),
    standardDeviationMs: Number(Math.sqrt(variance).toFixed(3))
  };
}

function median(sorted) {
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) {
    return sorted[middle];
  }
  return Number(((sorted[middle - 1] + sorted[middle]) / 2).toFixed(3));
}

function formatMs(value) {
  return `${value.toFixed(1)} ms`;
}

function bin(name) {
  const suffix = process.platform === "win32" ? ".cmd" : "";
  return join(localBin, `${name}${suffix}`);
}

async function countFiles(path) {
  const pathStat = await stat(path);
  if (pathStat.isFile()) {
    return 1;
  }
  if (!pathStat.isDirectory()) {
    return 0;
  }

  let count = 0;
  for (const entry of await readdir(path, { withFileTypes: true })) {
    const child = join(path, entry.name);
    if (entry.isDirectory()) {
      count += await countFiles(child);
    } else if (entry.isFile() && /\.(?:[cm]?[jt]sx?)$/.test(entry.name)) {
      count += 1;
    }
  }
  return count;
}

function parseArgs(argv) {
  const result = {};
  for (const arg of argv) {
    if (!arg.startsWith("--")) {
      throw new Error(`Unknown positional argument: ${arg}`);
    }

    const [rawKey, rawValue] = arg.slice(2).split("=", 2);
    result[rawKey] = rawValue ?? "true";
  }
  return result;
}

function positiveInt(value, fallback, name) {
  if (value === undefined) {
    return fallback;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`--${name} must be a positive integer`);
  }
  return parsed;
}

function nonNegativeInt(value, fallback, name) {
  if (value === undefined) {
    return fallback;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`--${name} must be a non-negative integer`);
  }
  return parsed;
}
