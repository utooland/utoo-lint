import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { cpus, release, tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import { rulesForProfile, utooRuleArgs } from "./shared-rules.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoDir = resolve(scriptDir, "../..");
const options = parseArgs(process.argv.slice(2));
if (options.help) {
  console.log(`Usage: node scripts/run-focused.mjs --before-binary=PATH [options]
  --after-binary=PATH       Default: ../zig-out/bin/utoo-lint
  --before-wrapper=PATH     Required when source-code or plugin scenarios are selected
  --after-wrapper=PATH      Default: ../npm/utoo-lint/index.cjs
  --js-binary=PATH          Shared native binary for BOTH wrappers (default: after)
  --before-ref=REF          Baseline source provenance (for example 7addc3f)
  --after-ref=REF           Candidate source provenance (default: HEAD plus working diff)
  --zig=PATH               Compiler used for both builds (default: zig)
  --build-mode=MODE         Build provenance (default: fast)
  --before-zig=PATH --after-zig=PATH
  --before-build-mode=MODE --after-build-mode=MODE
                           Per-variant overrides for compiler/build provenance
  --runs=20 --warmups=5 --memory-runs=0 --output=results/focused.json
  --scenarios=no-shadow,diagnostics,semantic,control,source-code,plugin
  --shadow-counts=500,2000,8000 --diagnostic-lines=4000
  --semantic-references=8000 --control-files=1000 --control-statements=30
  --js-statements=2000
No compilation is performed. Native timings include text output and process startup.
JS timings exclude module/parser setup for SourceCode and time all of Linter.verify
for plugins. Raw fresh-process wall times are also recorded. Fixtures are temporary.`);
  process.exit(0);
}

const runs = integer(options.runs, 20, "runs", 1);
const warmups = integer(options.warmups, 5, "warmups", 0);
const memoryRuns = integer(options["memory-runs"], 0, "memory-runs", 0);
const shadowCounts = (options["shadow-counts"] ?? "500,2000,8000").split(",").map((value) => integer(value, 0, "shadow-counts", 1));
const diagnosticLines = integer(options["diagnostic-lines"], 4000, "diagnostic-lines", 1);
const semanticReferences = integer(options["semantic-references"], 8000, "semantic-references", 1);
const controlFiles = integer(options["control-files"], 1000, "control-files", 1);
const controlStatements = integer(options["control-statements"], 30, "control-statements", 1);
const jsStatements = integer(options["js-statements"], 2000, "js-statements", 1);
const groups = new Set((options.scenarios ?? "no-shadow,diagnostics,semantic,control,source-code,plugin").split(","));
for (const group of groups) {
  if (!["no-shadow", "diagnostics", "semantic", "control", "source-code", "plugin"].includes(group)) throw new Error(`Unknown scenario: ${group}`);
}
const hasJavaScript = groups.has("source-code") || groups.has("plugin");
for (const required of hasJavaScript ? ["before-binary", "before-wrapper"] : ["before-binary"]) {
  if (!options[required]) throw new Error(`--${required} is required`);
}
const variants = ["before", "after"].map((name) => ({
  name,
  binary: resolve(options[`${name}-binary`] ?? join(repoDir, "zig-out/bin/utoo-lint")),
  ...(hasJavaScript ? { wrapper: resolve(options[`${name}-wrapper`] ?? join(repoDir, "npm/utoo-lint/index.cjs")) } : {}),
  sourceRef: options[`${name}-ref`] ?? (name === "after" ? "HEAD" : null),
  zig: options[`${name}-zig`] ?? options.zig ?? "zig",
  buildMode: options[`${name}-build-mode`] ?? options["build-mode"] ?? "fast"
}));
const jsBinary = hasJavaScript ? resolve(options["js-binary"] ?? variants[1].binary) : null;
for (const file of [...variants.flatMap((variant) => [variant.binary, ...(hasJavaScript ? [variant.wrapper] : [])]), ...(hasJavaScript ? [jsBinary] : [])]) {
  if (!(await stat(file)).isFile()) throw new Error(`Missing benchmark input: ${file}`);
}
const fixtureRoot = await mkdtemp(join(tmpdir(), "utoo-lint-focused-"));
const output = resolve(options.output ?? join(repoDir, "benchmarks/results/focused.json"));
const env = { ...process.env, CI: "1", NO_COLOR: "1", FORCE_COLOR: "0", LC_ALL: "C" };
const hash = (value) => createHash("sha256").update(value).digest("hex");
const scenarios = [];

try {
  if (groups.has("no-shadow")) {
    for (const count of shadowCounts) {
      const file = await fixture(`no-shadow-${count}.js`, Array.from({ length: count }, (_, index) => `export function f${index}(local${index}) { return local${index}; }`).join("\n") + "\n");
      native(`no-shadow/${count}-functions`, file, ["--rules=no-shadow", "--threads=1"], 1, 0);
    }
  }
  if (groups.has("diagnostics")) {
    const file = await fixture("debugger-many.js", "debugger;\n".repeat(diagnosticLines));
    native(`text-diagnostics/${diagnosticLines}-lines`, file, ["--rules=no-debugger", "--threads=1"], 1, diagnosticLines);
    const early = await fixture("debugger-first.js", "debugger;\n" + "0;\n".repeat(diagnosticLines - 1));
    native(`text-diagnostics/first-line-only-${diagnosticLines}-lines`, early, ["--rules=no-debugger", "--threads=1"], 1, 1);
  }
  if (groups.has("semantic")) {
    for (const language of ["js", "ts"]) {
      const annotation = language === "ts" ? ": number" : "";
      const file = await fixture(`semantic.${language}`, `export function compute(input${annotation}) {\nlet value = input;\n` + "value += input;\n".repeat(semanticReferences) + "return value;\n}\n");
      native(`semantic-errors/${language}-${semanticReferences}-references`, file, ["--rules=semantic-errors", "--threads=1"], 1, 0);
    }
  }
  if (groups.has("control")) {
    const target = join(fixtureRoot, "control");
    checkedSpawn(process.execPath, [join(scriptDir, "generate-corpus.mjs"), `--files=${controlFiles}`, `--statements=${controlStatements}`, `--out=${target}`], 0);
    for (const profile of ["shared", "extended"]) {
      native(`control/${profile}-${controlFiles}-files`, target, utooRuleArgs(rulesForProfile(profile)), controlFiles, 0);
    }
  }
  if (groups.has("source-code") || groups.has("plugin")) {
    const file = await fixture("plugin.js", Array.from({ length: jsStatements }, (_, index) => `/* before ${index} */ export const value${index} = ${index}; // after ${index}`).join("\n") + "\n");
    for (const mode of ["tokens", "comments", "locations", "plugin"]) {
      if (mode === "plugin" ? !groups.has("plugin") : !groups.has("source-code")) continue;
      scenarios.push({ name: `${mode === "plugin" ? "plugin" : "source-code"}/${mode}-${jsStatements}-declarations`, kind: "js", mode, target: file, count: jsStatements });
    }
  }

  const variantProvenance = await Promise.all(variants.map(async (variant) => ({
    ...variant,
    zigVersion: commandOutput(variant.zig, ["version"]),
    resolvedSourceRef: variant.sourceRef ? commandOutput("git", ["rev-parse", variant.sourceRef]) : null,
    binarySha256: hash(await readFile(variant.binary)),
    ...(hasJavaScript ? {
      wrapperFiles: await wrapperFiles(variant.wrapper),
      yukuVersion: createRequire(variant.wrapper)("yuku/package.json").version
    } : {})
  })));
  const provenance = {
    generatedAt: new Date().toISOString(), node: process.version, platform: process.platform, arch: process.arch,
    osRelease: release(), cpu: { model: cpus()[0]?.model ?? null, logicalCores: cpus().length },
    zigVersion: variantProvenance[0].zigVersion === variantProvenance[1].zigVersion ? variantProvenance[0].zigVersion : null,
    buildMode: variants[0].buildMode === variants[1].buildMode ? variants[0].buildMode : null,
    git: { head: commandOutput("git", ["rev-parse", "HEAD"]), status: commandOutput("git", ["status", "--porcelain"]), diffSha256: hash(commandOutput("git", ["diff", "HEAD", "--binary"]) ?? ""), changedFiles: await changedSourceFiles() },
    runnerSha256: hash(await readFile(fileURLToPath(import.meta.url))),
    ...(hasJavaScript ? {
      workerSha256: hash(await readFile(join(scriptDir, "focused-js-worker.cjs"))),
      jsBinary: { path: jsBinary, sha256: hash(await readFile(jsBinary)) }
    } : {}),
    variants: variantProvenance,
    fixtures: await fixtureInventory(fixtureRoot),
    configuration: { runs, warmups, memoryRuns, shadowCounts, diagnosticLines, semanticReferences, controlFiles, controlStatements, jsStatements, groups: [...groups] },
    methodology: {
      sampling: "Paired rounds, alternating before/after order; fresh process per sample; warm filesystem cache, cold JS process/JIT",
      nativeTimer: "Wall-clock spawnSync of native text CLI, including startup and captured output",
      jsTimer: "Worker performance.now: SourceCode queries exclude parser/setup; plugin includes all of Linter.verify; process wall time also retained",
      validation: "Before timing: equal complete parsed native JSON and exact text stdout/stderr; JS complete API outputs/messages hashed. Every timing sample must retain matching output",
      memory: "Optional native-only system time RSS measurements, separate from timing; worker nodePeakRssKiB is Node self high-water RSS captured before result hashing and excludes native subprocesses"
    }
  };

  const results = [];
  for (const scenario of scenarios) {
    console.log(`Validate ${scenario.name}`);
    const verified = variants.map((variant) => validate(scenario, variant));
    assert.deepEqual(verified[1], verified[0], `${scenario.name}: before/after output differs`);
    const measurements = variants.map((variant) => ({ variant: variant.name, samplesMs: [], processWallSamplesMs: [], nodePeakRssKiBSamples: [] }));
    for (let round = 0; round < warmups + runs; round += 1) {
      for (let offset = 0; offset < variants.length; offset += 1) {
        const index = (round + offset) % variants.length;
        const sample = measure(scenario, variants[index], verified[index]);
        if (round < warmups) continue;
        measurements[index].samplesMs.push(sample.elapsedMs);
        measurements[index].processWallSamplesMs.push(sample.wallMs);
        if (sample.nodePeakRssKiB !== undefined) measurements[index].nodePeakRssKiBSamples.push(sample.nodePeakRssKiB);
      }
    }
    for (const measurement of measurements) measurement.summary = summarize(measurement.samplesMs);
    const memory = scenario.kind === "native" && memoryRuns > 0 ? measureNativeMemory(scenario, verified[0]) : null;
    const reductionPercent = 100 * (1 - measurements[1].summary.medianMs / measurements[0].summary.medianMs);
    const result = { ...scenario, target: relative(fixtureRoot, scenario.target), validation: verified[0], measurements, reductionPercent, ...(memory ? { memory } : {}) };
    results.push(result);
    await mkdir(dirname(output), { recursive: true });
    await writeFile(output, JSON.stringify({ ...provenance, complete: results.length === scenarios.length, results }, null, 2) + "\n");
    console.log(`${scenario.name}: ${measurements[0].summary.medianMs.toFixed(3)} -> ${measurements[1].summary.medianMs.toFixed(3)} ms (${reductionPercent.toFixed(1)}% reduction)`);
  }
  console.log(`Wrote ${output}`);
} finally {
  await rm(fixtureRoot, { recursive: true, force: true });
}

async function fixture(name, source) {
  const file = join(fixtureRoot, name);
  await writeFile(file, source);
  return file;
}

function native(name, target, args, files, diagnosticCount) {
  // --rules uses the native default warning severity, including no-debugger.
  scenarios.push({ name, kind: "native", target, args: ["--no-config", "--no-color", ...args], files, diagnosticCount, status: 0 });
}

function checkedSpawn(command, args, status, extra = {}) {
  const result = spawnSync(command, args, { cwd: repoDir, env, encoding: "utf8", maxBuffer: 256 * 1024 * 1024, timeout: 120000, ...extra });
  if (result.error || result.status !== status) throw new Error(`${command} ${args.join(" ")} failed: ${result.error?.message ?? result.stderr}\n${result.stdout}`);
  return result;
}

function nativeRun(scenario, variant, json = false) {
  return checkedSpawn(variant.binary, [...scenario.args, ...(json ? ["--format=json"] : []), scenario.target], scenario.status);
}

function jsRun(scenario, variant) {
  return JSON.parse(checkedSpawn(process.execPath, [join(scriptDir, "focused-js-worker.cjs"), variant.wrapper, scenario.mode, scenario.target, String(scenario.count)], 0, { env: { ...env, UTOO_LINT_BIN: jsBinary } }).stdout);
}

function validate(scenario, variant) {
  if (scenario.kind === "js") {
    const sample = jsRun(scenario, variant);
    return { resultSha256: sample.resultSha256, outputCount: sample.outputCount };
  }
  const json = nativeRun(scenario, variant, true);
  const report = JSON.parse(json.stdout);
  assert.equal(report.files, scenario.files);
  assert.equal(report.filePaths.length, scenario.files);
  assert.equal(report.diagnostics.length, scenario.diagnosticCount);
  assert.equal(report.suppressedDiagnostics.length, 0);
  assert.equal(report.outputs.length, 0);
  const text = nativeRun(scenario, variant);
  return { reportSha256: hash(JSON.stringify(report)), files: report.files, diagnosticCount: report.diagnostics.length, stdoutSha256: hash(text.stdout), stderrSha256: hash(text.stderr), stderrLength: text.stderr.length, status: text.status };
}

function measure(scenario, variant, expected) {
  const started = performance.now();
  if (scenario.kind === "js") {
    const result = jsRun(scenario, variant);
    const wallMs = performance.now() - started;
    assert.equal(result.resultSha256, expected.resultSha256);
    assert.equal(result.outputCount, expected.outputCount);
    assert.ok(Number.isFinite(result.elapsedMs) && result.elapsedMs >= 0);
    return { ...result, wallMs };
  }
  const result = nativeRun(scenario, variant);
  const elapsedMs = performance.now() - started;
  assert.equal(hash(result.stdout), expected.stdoutSha256);
  assert.equal(hash(result.stderr), expected.stderrSha256);
  return { elapsedMs, wallMs: elapsedMs };
}

function measureNativeMemory(scenario, expected) {
  if (!["darwin", "linux"].includes(process.platform)) throw new Error("--memory-runs requires macOS or Linux /usr/bin/time");
  const samples = variants.map((variant) => ({ variant: variant.name, samplesBytes: [] }));
  for (let round = 0; round < memoryRuns; round += 1) {
    for (let offset = 0; offset < variants.length; offset += 1) {
      const index = (round + offset) % variants.length;
      const result = checkedSpawn("/usr/bin/time", [process.platform === "darwin" ? "-l" : "-v", variants[index].binary, ...scenario.args, scenario.target], scenario.status);
      assert.equal(hash(result.stdout), expected.stdoutSha256);
      assert.equal(hash(result.stderr.slice(0, expected.stderrLength)), expected.stderrSha256);
      const timeOutput = result.stderr.slice(expected.stderrLength);
      const match = process.platform === "darwin" ? timeOutput.match(/^\s*(\d+)\s+maximum resident set size/m) : timeOutput.match(/Maximum resident set size \(kbytes\):\s*(\d+)/);
      if (!match) throw new Error(`Missing system time RSS: ${result.stderr}`);
      samples[index].samplesBytes.push(Number(match[1]) * (process.platform === "darwin" ? 1 : 1024));
    }
  }
  return { scope: "native CLI process peak resident set size", method: `/usr/bin/time ${process.platform === "darwin" ? "-l" : "-v"}`, samples };
}

async function wrapperFiles(wrapper) {
  const directory = dirname(wrapper);
  const files = [wrapper, join(directory, "package.json")];
  for (const entry of await readdir(join(directory, "lib"), { withFileTypes: true })) {
    if (entry.isFile() && /\.(?:cjs|js|json)$/.test(entry.name)) files.push(join(directory, "lib", entry.name));
  }
  return Object.fromEntries(await Promise.all(files.sort().map(async (file) => [relative(directory, file), hash(await readFile(file))])));
}

async function fixtureInventory(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const file = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await fixtureInventory(file));
    else {
      const bytes = await readFile(file);
      files.push({ path: relative(fixtureRoot, file), bytes: bytes.length, sha256: hash(bytes) });
    }
  }
  return files.sort((left, right) => left.path.localeCompare(right.path));
}

async function changedSourceFiles() {
  const tracked = commandOutput("git", ["diff", "--name-only", "-z", "HEAD"]) ?? "";
  const untracked = commandOutput("git", ["ls-files", "--others", "--exclude-standard", "-z"]) ?? "";
  const files = [...new Set([...tracked.split("\0"), ...untracked.split("\0")].filter(Boolean))].sort();
  return Object.fromEntries(await Promise.all(files.map(async (file) => {
    const absolute = join(repoDir, file);
    const info = await stat(absolute).catch(() => null);
    if (!info) return [file, { deleted: true }];
    if (info.isDirectory()) return [file, { gitlink: commandOutput("git", ["-C", absolute, "rev-parse", "HEAD"]) }];
    return [file, { sha256: hash(await readFile(absolute)) }];
  })));
}

function commandOutput(command, args) {
  const result = spawnSync(command, args, { cwd: repoDir, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, timeout: 10000 });
  return result.status === 0 ? result.stdout.trim() : null;
}

function summarize(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  const meanMs = sorted.reduce((sum, value) => sum + value, 0) / sorted.length;
  return { minMs: sorted[0], maxMs: sorted.at(-1), medianMs: sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2, meanMs, standardDeviationMs: Math.sqrt(sorted.reduce((sum, value) => sum + (value - meanMs) ** 2, 0) / sorted.length) };
}

function integer(value, fallback, name, minimum) {
  const parsed = value === undefined ? fallback : Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum) throw new Error(`--${name} must be an integer >= ${minimum}`);
  return parsed;
}

function parseArgs(argv) {
  const allowed = new Set(["help", "before-binary", "before-wrapper", "after-binary", "after-wrapper", "js-binary", "before-ref", "after-ref", "zig", "build-mode", "before-zig", "after-zig", "before-build-mode", "after-build-mode", "runs", "warmups", "memory-runs", "output", "scenarios", "shadow-counts", "diagnostic-lines", "semantic-references", "control-files", "control-statements", "js-statements"]);
  const parsed = {};
  for (const arg of argv) {
    const match = /^--([^=]+)(?:=(.*))?$/.exec(arg);
    if (!match || !allowed.has(match[1]) || (match[1] !== "help" && match[2] === undefined)) throw new Error(`Unknown or incomplete argument: ${arg}`);
    parsed[match[1]] = match[2] ?? true;
  }
  return parsed;
}
