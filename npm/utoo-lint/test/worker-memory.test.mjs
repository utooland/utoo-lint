import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

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
  const project = mkdtempSync(join(tmpdir(), "utoo-lint-worker-memory-"));
  t.after(() => rmSync(project, { recursive: true, force: true }));
  return project;
}

function write(project, filename, source) {
  const path = join(project, filename);
  writeFileSync(path, source);
  return path;
}

function runNative(project, threads, args) {
  assert.equal(existsSync(builtBinary), true, `missing test binary at ${builtBinary}`);
  return spawnSync(
    builtBinary,
    ["--format=text", "--no-color", `--threads=${threads}`, ...args],
    {
      cwd: project,
      encoding: "utf8",
      env: { ...process.env, CI: "1", NO_COLOR: "1" },
      maxBuffer: 8 * 1024 * 1024,
      timeout: 20000
    }
  );
}

function textDiagnosticsByFile(stderr, paths) {
  const knownPaths = new Set(paths);
  const groups = new Map();
  let currentPath;
  for (const line of stderr.split("\n")) {
    if (knownPaths.has(line)) {
      assert.equal(groups.has(line), false, `duplicate diagnostic heading: ${line}`);
      currentPath = line;
      groups.set(line, []);
      continue;
    }
    const diagnostic = line.match(/^\s+(\d+):(\d+)\s+(error|warning)\s+(.+?)\s{2}(\S+)$/);
    if (!diagnostic) continue;
    assert.ok(currentPath, `diagnostic without a file heading: ${line}`);
    groups.get(currentPath).push({
      line: Number(diagnostic[1]),
      column: Number(diagnostic[2]),
      severity: diagnostic[3],
      message: diagnostic[4],
      ruleId: diagnostic[5]
    });
  }
  return groups;
}

function sourcePadding(repetitions) {
  return `/* ${"source owned by this file ".repeat(repetitions)} */\n`;
}

function createFixFixtures(project) {
  const definitions = [
    { name: "large-first", padding: sourcePadding(4096), value: "first large value", extraSemicolons: 1 },
    { name: "tiny", padding: "", value: "x", extraSemicolons: 2 },
    { name: "medium", padding: sourcePadding(512), value: "a replacement with a different length", extraSemicolons: 1 },
    { name: "small", padding: "", value: "distinct small value", extraSemicolons: 3 },
    { name: "large-last", padding: sourcePadding(3072), value: "last large value", extraSemicolons: 2 },
    { name: "last", padding: "", value: "the last replacement", extraSemicolons: 1 }
  ];
  return definitions.map(({ name, padding, value, extraSemicolons }, index) => {
    const identifier = `value${index}`;
    const tail = `export { ${identifier} };\n`;
    const initializer = JSON.stringify(value);
    const source = `${padding}let ${identifier} = ${initializer};${";".repeat(extraSemicolons)}\n${tail}`;
    const fixed = `${padding}const ${identifier} = ${initializer};\n${tail}`;
    const path = write(project, `${name}.js`, source);
    return { path, source, fixed };
  });
}

for (const threads of [1, 2]) {
  test(`raw native text keeps per-file diagnostics and flat config settings with ${threads} worker(s)`, { skip: !existsSync(builtBinary) }, (t) => {
    const project = createProject(t);
    write(project, "utlint.config.json", JSON.stringify([
      { files: ["warning-*.js"], rules: { "no-debugger": "warn", "no-console": "off" } },
      {
        files: ["error-*.js"],
        rules: { "no-debugger": "off", "no-console": ["error", { allow: ["warn"] }] }
      }
    ]));

    const definitions = [
      {
        filename: "warning-first.js",
        source: `${sourcePadding(4096)}console.log("disabled first");\ndebugger;\n`,
        line: 3,
        severity: "warning",
        ruleId: "no-debugger",
        message: "Unexpected debugger statement."
      },
      {
        filename: "error-first.js",
        source: 'console.warn("allowed first");\nconsole.log("blocked first");\ndebugger;\n',
        line: 2,
        severity: "error",
        ruleId: "no-console",
        message: "Unexpected console statement."
      },
      {
        filename: "warning-second.js",
        source: 'debugger;\nconsole.error("disabled second");\n',
        line: 1,
        severity: "warning",
        ruleId: "no-debugger",
        message: "Unexpected debugger statement."
      },
      {
        filename: "error-second.js",
        source: `${sourcePadding(512)}console.log("blocked second");\nconsole.warn("allowed second");\ndebugger;\n`,
        line: 2,
        severity: "error",
        ruleId: "no-console",
        message: "Unexpected console statement."
      },
      {
        filename: "warning-last.js",
        source: "\n\ndebugger;\n",
        line: 3,
        severity: "warning",
        ruleId: "no-debugger",
        message: "Unexpected debugger statement."
      },
      {
        filename: "error-last.js",
        source: `${sourcePadding(3072)}\nconsole.warn("allowed last");\nconsole.error("blocked last");\n`,
        line: 4,
        severity: "error",
        ruleId: "no-console",
        message: "Unexpected console statement."
      }
    ];
    const fixtures = definitions.map(({ filename, source, ...diagnostic }) => ({
      path: write(project, filename, source),
      diagnostic: { ...diagnostic, column: 1 }
    }));
    const paths = fixtures.map(({ path }) => path);
    const result = runNative(project, threads, paths);

    assert.equal(result.error, undefined);
    assert.equal(result.status, 1, result.stderr);
    assert.equal(result.stdout, "");
    assert.doesNotMatch(result.stderr, /\u001b\[/);
    const groups = textDiagnosticsByFile(result.stderr, paths);
    assert.deepEqual([...groups.keys()].sort(), [...paths].sort());
    for (const { path, diagnostic } of fixtures) {
      assert.deepEqual(groups.get(path), [diagnostic], path);
    }
    assert.match(result.stderr, /✖ 6 problems \(3 errors, 3 warnings\)/);
    assert.match(result.stderr, /6 files checked/);
  });

  for (const fixFlag of ["--fix", "--fix-dry-run"]) {
    test(`raw native text ${fixFlag} keeps distinct outputs across large and small files with ${threads} worker(s)`, { skip: !existsSync(builtBinary) }, (t) => {
      const project = createProject(t);
      write(project, "utlint.config.json", JSON.stringify([
        { files: ["*.js"], rules: { "prefer-const": "error", "no-extra-semi": "warn" } }
      ]));
      const fixtures = createFixFixtures(project);
      const result = runNative(project, threads, [fixFlag, ...fixtures.map(({ path }) => path)]);

      assert.equal(result.error, undefined);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout, "");
      assert.match(result.stderr, /^✓ 6 files checked, no problems found\n/);
      assert.match(result.stderr, /\d+ problems fixed\./);
      assert.doesNotMatch(result.stderr, /prefer-const|no-extra-semi|\u001b\[/);
      for (const { path, source, fixed } of fixtures) {
        assert.equal(readFileSync(path, "utf8"), fixFlag === "--fix" ? fixed : source, path);
      }
    });
  }
}
