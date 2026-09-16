import assert from "node:assert/strict";
import childProcess, { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { lintFiles } from "../index.js";

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const builtBinary = resolve(
  packageDirectory,
  "..",
  "..",
  "zig-out",
  "bin",
  process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint"
);

function createProject(t) {
  const project = mkdtempSync(join(tmpdir(), "utoo-lint-native-flat-config-"));
  t.after(() => rmSync(project, { recursive: true, force: true }));
  return project;
}

function write(path, source) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, source);
  return path;
}

function writeConfig(project, config) {
  return write(join(project, "utlint.config.json"), `${JSON.stringify(config, null, 2)}\n`);
}

function runNative(project, args = []) {
  assert.equal(existsSync(builtBinary), true, `missing test binary at ${builtBinary}`);
  return spawnSync(builtBinary, ["--format=json", ...args], { cwd: project, encoding: "utf8" });
}

function diagnosticSummary(result) {
  return JSON.parse(result.stdout).diagnostics
    .filter(({ ruleId }) => ruleId !== "parse" && ruleId !== "io")
    .map(({ filePath, ruleId, severity }) => ({ filePath, ruleId, severity }))
    .sort((left, right) => `${left.filePath}:${left.ruleId}`.localeCompare(`${right.filePath}:${right.ruleId}`));
}

test("raw native binary resolves flat files, ignores, and later overrides per file", (t) => {
  const project = createProject(t);
  const configPath = writeConfig(project, [
    { name: "global ignores", ignores: ["dist/**"] },
    {
      files: ["src/**/*.js"],
      ignores: ["src/generated/**"],
      rules: { "no-console": "error", "no-debugger": "warn" }
    },
    { files: ["test/**/*.js"], rules: { "no-console": "off", "no-debugger": "error" } },
    { files: ["src/special/**/*.js"], rules: { "no-console": "off" } }
  ]);
  const sourcePath = write(join(project, "src", "index.js"), "console.log('source');\ndebugger;\n");
  const testPath = write(join(project, "test", "index.js"), "console.log('test');\ndebugger;\n");
  const specialPath = write(join(project, "src", "special", "index.js"), "console.log('special');\ndebugger;\n");
  const generatedPath = write(join(project, "src", "generated", "index.js"), "console.log('generated');\ndebugger;\n");
  const distPath = write(join(project, "dist", "index.js"), "console.log('dist');\ndebugger;\n");

  const result = runNative(project, [
    `--config=${configPath}`,
    sourcePath,
    testPath,
    specialPath,
    generatedPath,
    distPath
  ]);

  assert.equal(result.status, 1, `${result.stderr}\n${result.stdout}`);
  const report = JSON.parse(result.stdout);
  assert.equal(report.files, 4);
  assert.equal(report.filePaths.includes(distPath), false);
  assert.deepEqual(diagnosticSummary(result), [
    { filePath: sourcePath, ruleId: "no-console", severity: "error" },
    { filePath: sourcePath, ruleId: "no-debugger", severity: "warning" },
    { filePath: specialPath, ruleId: "no-debugger", severity: "warning" },
    { filePath: testPath, ruleId: "no-debugger", severity: "error" }
  ].sort((left, right) => `${left.filePath}:${left.ruleId}`.localeCompare(`${right.filePath}:${right.ruleId}`)));
});

test("raw native default discovery honors selectors, braces, and global ignores", (t) => {
  const project = createProject(t);
  writeConfig(project, [
    { ignores: ["src/generated/**"] },
    { files: ["src/**/*.{js,ts}"], rules: { "no-debugger": "error" } }
  ]);
  const selectedPath = write(join(project, "src", "index.ts"), "debugger;\n");
  write(join(project, "src", "generated", "index.ts"), "debugger;\n");
  write(join(project, "test", "index.ts"), "debugger;\n");

  const result = runNative(project);

  assert.equal(result.status, 1, `${result.stderr}\n${result.stdout}`);
  const report = JSON.parse(result.stdout);
  assert.deepEqual(report.filePaths.map((path) => resolve(project, path)), [selectedPath]);
  assert.deepEqual(
    diagnosticSummary(result).map((diagnostic) => ({
      ...diagnostic,
      filePath: resolve(project, diagnostic.filePath)
    })),
    [{ filePath: selectedPath, ruleId: "no-debugger", severity: "error" }]
  );
  assert.equal(report.files, 1);
});

test("raw native resolves explicit ancestor configs relative to the config directory", (t) => {
  const project = createProject(t);
  const configPath = writeConfig(project, [
    { files: [["packages/**/*.js", "**/*.test.js"]], rules: { "no-debugger": "error" } }
  ]);
  const selectedPath = write(join(project, "packages", "app", "src", "index.test.js"), "debugger;\n");
  const unmatchedPath = write(join(project, "packages", "app", "src", "index.js"), "debugger;\n");

  const result = runNative(join(project, "packages", "app"), [
    `--config=${configPath}`,
    selectedPath,
    unmatchedPath
  ]);

  assert.equal(result.status, 1, result.stderr);
  assert.deepEqual(diagnosticSummary(result), [
    { filePath: selectedPath, ruleId: "no-debugger", severity: "error" }
  ]);
});

test("later severity-only entries retain earlier rule options", (t) => {
  const project = createProject(t);
  writeConfig(project, [
    { files: ["src/**/*.js"], rules: { "no-console": ["error", { allow: ["warn"] }] } },
    { files: ["src/**/*.js"], rules: { "no-console": "warn" } }
  ]);
  const sourcePath = write(join(project, "src", "index.js"), "console.warn('allowed');\n");

  const result = runNative(project, [sourcePath]);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(diagnosticSummary(result), []);
});

test("raw native rule flags keep CLI precedence over flat config", (t) => {
  const project = createProject(t);
  writeConfig(project, [
    { files: ["src/**/*.js"], rules: { "no-debugger": "off" } },
    { files: ["test/**/*.js"], rules: { "no-debugger": "error" } }
  ]);
  const sourcePath = write(join(project, "src", "index.js"), "debugger;\n");
  const testPath = write(join(project, "test", "index.js"), "debugger;\n");

  const result = runNative(project, ["--no-debugger=off", sourcePath, testPath]);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(diagnosticSummary(result), []);
});

test("Node wrapper serializes TypeScript flat config into one native process", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-debugger": "warn" }, settings: { jest: { version: 29 } } },',
      '  { files: ["test/**/*.ts"], rules: { "no-debugger": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const sourcePath = write(join(project, "src", "index.ts"), "debugger;\n");
  const testPath = write(join(project, "test", "index.ts"), "debugger;\n");
  const originalSpawnSync = childProcess.spawnSync;
  const calls = [];
  childProcess.spawnSync = (command, args, spawnOptions) => {
    if (command !== "mock-utoo-lint") {
      return originalSpawnSync(command, args, spawnOptions);
    }
    const configArg = args.find((arg) => arg.startsWith("--config="));
    calls.push({
      args,
      command,
      config: JSON.parse(readFileSync(configArg.slice("--config=".length), "utf8"))
    });
    const stdout = JSON.stringify({
      files: 2,
      filePaths: [sourcePath, testPath],
      diagnostics: [],
      suppressedDiagnostics: [],
      outputs: []
    });
    return { error: undefined, status: 0, stdout, stderr: "", output: [null, stdout, ""] };
  };
  syncBuiltinESMExports();
  t.after(() => {
    childProcess.spawnSync = originalSpawnSync;
    syncBuiltinESMExports();
  });

  const report = lintFiles([sourcePath, testPath], { binary: "mock-utoo-lint", cwd: project });

  assert.equal(report.files, 2);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, "mock-utoo-lint");
  assert.deepEqual(calls[0].config.map(({ files, rules }) => ({ files, rules })), [
    { files: ["src/**/*.ts"], rules: { "no-debugger": "warn" } },
    { files: ["test/**/*.ts"], rules: { "no-debugger": "error" } }
  ]);
  assert.ok(calls[0].args.includes(`--config-root=${project}`));
});

test("Node wrapper preserves selectors from a single config object", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    'export default { files: ["test/**/*.ts"], rules: { "no-debugger": "error" } };\n'
  );
  const sourcePath = write(join(project, "src", "index.ts"), "debugger;\n");
  const testPath = write(join(project, "test", "index.ts"), "debugger;\n");

  const report = lintFiles([sourcePath, testPath], { binary: builtBinary, cwd: project });

  assert.deepEqual(report.diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })), [
    { filePath: testPath, ruleId: "no-debugger" }
  ]);
});

test("raw native binary honours languageOptions.globals from every matching entry", (t) => {
  const project = createProject(t);
  const configPath = writeConfig(project, [
    {
      languageOptions: { globals: { APP_VERSION: "readonly", __DEV__: "writable" } },
      rules: { "no-undef": "error", "no-global-assign": "error" }
    },
    { files: ["legacy/**"], languageOptions: { globals: { APP_VERSION: "writable", window: "off" } } }
  ]);
  const source = "console.log(APP_VERSION, __DEV__, window);\nAPP_VERSION = '2';\n__DEV__ = true;\nmissing();\n";
  const appPath = write(join(project, "src", "index.js"), source);
  const legacyPath = write(join(project, "legacy", "index.js"), source);

  const result = runNative(project, [`--config=${configPath}`, appPath, legacyPath]);

  assert.equal(result.status, 1, `${result.stderr}\n${result.stdout}`);
  const diagnostics = JSON.parse(result.stdout).diagnostics
    .filter(({ ruleId }) => ruleId !== "parse" && ruleId !== "io")
    .map(({ filePath, line, ruleId, message }) => ({ filePath, line, ruleId, message }))
    .sort((left, right) => left.filePath.localeCompare(right.filePath) || left.line - right.line);
  assert.deepEqual(diagnostics, [
    { filePath: legacyPath, line: 1, ruleId: "no-undef", message: "'window' is not defined." },
    { filePath: legacyPath, line: 4, ruleId: "no-undef", message: "'missing' is not defined." },
    { filePath: appPath, line: 2, ruleId: "no-global-assign", message: "Read-only global 'APP_VERSION' should not be modified." },
    { filePath: appPath, line: 4, ruleId: "no-undef", message: "'missing' is not defined." }
  ]);
});

test("raw native binary rejects invalid languageOptions.globals values", (t) => {
  const project = createProject(t);
  const configPath = writeConfig(project, [
    { languageOptions: { globals: { APP_VERSION: "sometimes" } }, rules: { "no-undef": "error" } }
  ]);
  const sourcePath = write(join(project, "index.js"), "console.log(APP_VERSION);\n");

  const result = runNative(project, [`--config=${configPath}`, sourcePath]);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /invalid flat config .*InvalidGlobalValue/);
});

test("raw native binary keeps languageOptions.globals from an object config alive for the whole run", (t) => {
  const project = createProject(t);
  const configPath = writeConfig(project, {
    languageOptions: { globals: { APP_VERSION: "readonly", __DEV__: "writable" } },
    rules: { "no-undef": "error", "no-global-assign": "error" }
  });
  const source = "console.log(APP_VERSION, __DEV__);\nAPP_VERSION = '2';\n__DEV__ = true;\nmissing();\n";
  const paths = Array.from({ length: 6 }, (_, index) => write(join(project, "src", `file-${index}.js`), source));

  const result = runNative(project, [`--config=${configPath}`, ...paths]);

  assert.equal(result.status, 1, `${result.stderr}\n${result.stdout}`);
  const diagnostics = JSON.parse(result.stdout).diagnostics
    .filter(({ ruleId }) => ruleId !== "parse" && ruleId !== "io")
    .map(({ ruleId, message }) => `${ruleId}: ${message}`)
    .sort();
  assert.deepEqual(diagnostics, [
    ...paths.map(() => "no-global-assign: Read-only global 'APP_VERSION' should not be modified."),
    ...paths.map(() => "no-undef: 'missing' is not defined.")
  ]);
});
