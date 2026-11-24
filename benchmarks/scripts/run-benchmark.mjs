import { mkdir, readFile, readdir, realpath, stat, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpus, loadavg, release, totalmem } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { createRequire } from "node:module";
import { performance } from "node:perf_hooks";
import { benchmarkRuleNames, oxlintRuleArgs, rulesForProfile, utooRuleArgs } from "./shared-rules.mjs";
import { verifySharedRules } from "./verify-shared-rules.mjs";

const args = parseArgs(process.argv.slice(2));
const runs = positiveInt(args.runs, 8, "runs");
const warmups = nonNegativeInt(args.warmups, 2, "warmups");
const target = args.target ?? "fixtures/src";
const output = args.output ?? "results/latest.json";
const timeoutMs = positiveInt(args["timeout-ms"], 120000, "timeout-ms");
const skipEslint = Boolean(args["skip-eslint"]);
const includeBun = Boolean(args.bun || process.env.BUN_BIN) && !args["skip-bun"];
const ruleSet = args["rule-set"] ?? "shared";
const selectedRules = rulesForProfile(ruleSet);
process.env.UTOO_LINT_BENCH_RULE_SET = ruleSet;

const localBin = join("node_modules", ".bin");
const utooBin = process.env.UTOO_LINT_BIN ?? join("..", "zig-out", "bin", process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint");
const utooCli = args["utoo-cli"];
if (utooCli && process.env.UTOO_LINT_BIN) {
  throw new Error("Unset UTOO_LINT_BIN when benchmarking a published npm CLI; its platform binary must come from the installed package.");
}
const bunBin = process.env.BUN_BIN ?? "bun";

const benchmarks = [
  {
    name: "utoo-lint",
    command: utooCli ?? utooBin,
    args: utooCli ? ["--config=utlint.config.ts", target] : ["--no-config", ...utooRuleArgs(selectedRules), target],
    requiredPath: utooCli ?? utooBin
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
  let probe = spawnSync(bunBin, ["lint", "--help", "--all"], { encoding: "utf8", timeout: 10000 });
  if (probe.status !== 0) probe = spawnSync(bunBin, ["lint", "--help"], { encoding: "utf8", timeout: 10000 });
  if (probe.error || probe.status !== 0 || !/--flavor/.test(`${probe.stdout}${probe.stderr}`)) {
    throw new Error(
      `Bun at ${bunBin} does not expose the required built-in lint CLI. Set BUN_BIN to a supported binary, or omit --bun/BUN_BIN.\n${probe.error?.message ?? probe.stderr?.trim() ?? ""}`
    );
  }
}

// Pass the same explicit file list to every tool. Recent Oxlint versions still
// honor VCS directory ignores with --no-ignore; fixtures are intentionally ignored.
// Directory discovery is therefore outside the timed region for every tool.
const targetInputs = await lintableFiles(target);
const targetFiles = targetInputs.length;
if (targetFiles === 0) {
  throw new Error(`No lintable files found in ${target}`);
}
for (const benchmark of benchmarks) {
  benchmark.baseArgs = benchmark.args.slice(0, -1);
  benchmark.targetInputs = targetInputs;
  benchmark.args = [...benchmark.baseArgs, ...targetInputs];
}
const validation = await verifySharedRules(benchmarks, targetFiles, selectedRules);
console.log(`Verified ${validation.rules.length} shared rules and clean controls for ${benchmarks.length} tools.`);
const corpus = await corpusInventory(target);
const provenance = await utooProvenance();
const bunProvenance = includeBun && existsSync(bunBin) ? await bunPackageProvenance() : {};
const loadAverageBefore = loadavg();

const sourceCommit = commandOutput("git", ["rev-parse", "HEAD"]);
const sourceDirty = Boolean(commandOutput("git", ["status", "--porcelain"]));
const results = benchmarks.map((benchmark) => ({
  name: benchmark.name,
  version: benchmark.name === "utoo-lint" && !utooCli ? null : commandOutput(benchmark.command, ["--version"]),
  ...(benchmark.name === "bun" ? { revision: commandOutput(benchmark.command, ["--revision"]) } : {}),
  command: [benchmark.command, ...benchmark.args].join(" "),
  runs,
  warmups,
  samplesMs: []
}));
// Rotate the starting tool to spread startup/order effects across the samples.
for (let round = 0; round < warmups; round += 1) {
  for (let offset = 0; offset < benchmarks.length; offset += 1) {
    runCommand(benchmarks[(round + offset) % benchmarks.length]);
  }
}
for (let round = 0; round < runs; round += 1) {
  for (let offset = 0; offset < benchmarks.length; offset += 1) {
    const index = (round + offset) % benchmarks.length;
    results[index].samplesMs.push(runCommand(benchmarks[index]));
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

await mkdir(dirname(output), { recursive: true });
await writeFile(
  output,
  `${JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      node: process.version,
      platform: process.platform,
      arch: process.arch,
      osRelease: release(),
      cpu: { model: cpus()[0]?.model ?? null, logicalCores: cpus().length },
      totalMemoryBytes: totalmem(),
      hostLoad: { before: loadAverageBefore, after: loadavg() },
      sourceCommit,
      sourceDirty,
      utooBuildMode: process.env.UTOO_LINT_BUILD_MODE ?? null,
      ...provenance,
      ...bunProvenance,
      sampling: "round-robin with a rotated starting tool; fresh CLI processes",
      inputMode: "identical explicit file list; directory discovery excluded for all tools",
      timeoutMs,
      dependencyVersions: await dependencyVersions(),
      artifactHashes: await artifactHashes(),
      corpus,
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

console.log(`Wrote ${output}`);

async function utooProvenance() {
  if (!utooCli) {
    return { utooMode: "native", utooBinarySha256: await sha256(utooBin) };
  }
  const entry = await realpath(utooCli);
  const manifestPath = join(dirname(entry), "..", "package.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  if (manifest.name !== "@utoo/lint") {
    throw new Error(`--utoo-cli must point to the installed @utoo/lint CLI, got ${manifest.name}`);
  }
  const requirePackage = createRequire(manifestPath);
  const { resolveBinary } = requirePackage("./lib/binary.cjs");
  return {
    utooMode: "npm-cli",
    utooPackageName: manifest.name,
    utooPackageVersion: manifest.version,
    utooEntrySha256: await sha256(entry),
    utooBinarySha256: await sha256(resolveBinary()),
    utooConfigSha256: await sha256("utlint.config.ts")
  };
}

async function sha256(path) {
  return createHash("sha256").update(await readFile(path)).digest("hex");
}

async function bunPackageProvenance() {
  const entry = await realpath(bunBin);
  const manifestPath = join(dirname(entry), "..", "package.json");
  const manifest = existsSync(manifestPath) ? JSON.parse(await readFile(manifestPath, "utf8")) : null;
  return {
    ...(manifest ? { bunPackageName: manifest.name, bunPackageVersion: manifest.version } : {}),
    bunBinarySha256: await sha256(entry)
  };
}

async function artifactHashes() {
  const paths = ["scripts/run-benchmark.mjs", "scripts/generate-corpus.mjs", "scripts/shared-rules.mjs", "scripts/extended-rules.mjs", "scripts/verify-shared-rules.mjs", "eslint.config.js", "biome.json"];
  return Object.fromEntries(await Promise.all(paths.map(async (path) => [path, await sha256(path)])));
}

async function corpusInventory(targetPath) {
  const root = resolve(targetPath);
  const paths = [];
  async function visit(path) {
    if ((await stat(path)).isFile()) {
      paths.push(path);
      return;
    }
    for (const entry of (await readdir(path, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
      const child = join(path, entry.name);
      if (entry.isDirectory()) await visit(child);
      else if (entry.isFile() && /\.(?:[cm]?[jt]sx?)$/.test(entry.name)) paths.push(child);
    }
  }
  await visit(root);
  const hash = createHash("sha256");
  let totalBytes = 0;
  let totalLines = 0;
  for (const path of paths) {
    const content = await readFile(path);
    hash.update(relative(root, path).replaceAll("\\", "/")).update("\0").update(content).update("\0");
    totalBytes += content.length;
    totalLines += content.toString("utf8").split("\n").length - Number(content.at(-1) === 10);
  }
  return { files: paths.length, totalBytes, totalLines, sha256: hash.digest("hex") };
}

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

function runCommand(benchmark) {
  const started = performance.now();
  const result = spawnSync(benchmark.command, benchmark.args, {
    cwd: process.cwd(),
    env: {
      ...process.env,
      CI: "1",
      NO_COLOR: "1"
    },
    encoding: "utf8",
    stdio: "pipe",
    timeout: timeoutMs,
    maxBuffer: 64 * 1024 * 1024
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

async function lintableFiles(path) {
  const pathStat = await stat(path);
  if (pathStat.isFile()) {
    return [path];
  }
  if (!pathStat.isDirectory()) {
    return [];
  }

  const files = [];
  for (const entry of (await readdir(path, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    const child = join(path, entry.name);
    if (entry.isDirectory()) {
      files.push(...await lintableFiles(child));
    } else if (entry.isFile() && /\.(?:[cm]?[jt]sx?)$/.test(entry.name)) {
      files.push(child);
    }
  }
  return files;
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
