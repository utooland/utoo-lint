import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { stripVTControlCharacters } from "node:util";

import * as esm from "../index.js";

const require = createRequire(import.meta.url);
const commonJS = require("../index.cjs");
const binary = fileURLToPath(new URL(
  `../../../zig-out/bin/utoo-lint${process.platform === "win32" ? ".exe" : ""}`,
  import.meta.url,
));

async function formatters(options = {}, name = "stylish") {
  const formats = [];
  for (const api of [esm, commonJS]) {
    formats.push(new api.CLIEngine(options).getFormatter(name));
    formats.push((await new api.ESLint(options).loadFormatter(name)).format);
  }
  return formats;
}

function result(filePath, messages) {
  return {
    filePath,
    messages,
    errorCount: messages.filter((message) => message.severity === 2).length,
    warningCount: messages.filter((message) => message.severity === 1).length,
    fixableErrorCount: messages.filter((message) => message.severity === 2 && message.fix).length,
    fixableWarningCount: messages.filter((message) => message.severity === 1 && message.fix).length,
  };
}

test("stylish sorts by line and column without changing the input or tied message order", async () => {
  const input = [result("/project/input.tsx", [
    { line: 3, column: 19, severity: 2, message: 'Missing "key" prop for element in iterator', ruleId: "react/jsx-key" },
    { line: 1, column: 8, severity: 1, message: "Second column.", ruleId: "second-column" },
    { line: 1, column: 1, severity: 1, message: "First column.", ruleId: "first-column" },
    { line: 1, column: 8, severity: 1, message: "Tied column.", ruleId: "tied-column" },
  ])];
  const before = structuredClone(input);
  for (const format of await formatters({ color: false })) {
    const rows = format(input).split("\n").filter((line) => /\d+:\d+/.test(line));
    assert.deepEqual(rows.map((line) => line.trim().split(/\s+/).at(-1)), [
      "first-column", "second-column", "tied-column", "react/jsx-key",
    ]);
    assert.deepEqual(input, before);
  }
});

test("stylish aligns columns per file and separates files and the summary without rewriting messages", async () => {
  const input = [
    result("/project/first.js", [
      { line: 1, column: 1, severity: 1, message: "First.", ruleId: "first-rule" },
      { line: 12, column: 23, severity: 2, message: "Second.", ruleId: "second-rule" },
    ]),
    result("/project/clean.js", []),
    result("/project/last.js", [
      { line: 2, column: 4, severity: 2, message: "Last.", ruleId: "last-rule" },
    ]),
  ];
  const expected = [
    "", "/project/first.js",
    "   1:1   warning  First.   first-rule",
    "  12:23  error    Second.  second-rule",
    "", "/project/last.js",
    "  2:4  error  Last.  last-rule",
    "", "✖ 3 problems (2 errors, 1 warning)", "",
  ].join("\n");
  for (const format of await formatters({ color: false })) {
    assert.equal(format(input), expected);
  }
});

test("stylish summarizes fixable errors and warnings, but not suggestions", async () => {
  const fix = { range: [0, 3], text: "let" };
  const input = [
    result("/project/errors.js", [
      { line: 1, column: 1, severity: 2, message: "Use let.", ruleId: "no-var", fix },
      { line: 2, column: 1, severity: 2, message: "Review this.", ruleId: "suggestion", suggestions: [{ desc: "Try let", fix }] },
    ]),
    result("/project/warnings.js", [
      { line: 1, column: 1, severity: 1, message: "Use let.", ruleId: "no-var", fix },
      { line: 2, column: 1, severity: 1, message: "Use let.", ruleId: "no-var", fix },
    ]),
  ];
  for (const format of await formatters({ color: false })) {
    assert.ok(format(input).endsWith([
      "✖ 4 problems (2 errors, 2 warnings)",
      "  1 error and 2 warnings potentially fixable with the `--fix` option.", "",
    ].join("\n")));
    assert.doesNotMatch(format([result("/project/suggestion.js", [input[0].messages[1]])]), /--fix/);
  }
});

test("stylish color highlights paths, locations, severities, rules and the summary without changing alignment", async () => {
  const input = [result("/project/input.js", [
    { line: 1, column: 1, severity: 1, message: "Warning.", ruleId: "warning-rule" },
    { line: 12, column: 34, severity: 2, message: "Error.", ruleId: "error-rule" },
  ])];
  const plain = (await formatters({ color: false }))[0](input);
  for (const format of await formatters({ color: true })) {
    const output = format(input);
    assert.equal(stripVTControlCharacters(output), plain);
    assert.match(output, /\u001b\[4m\/project\/input.js\u001b\[24m/);
    assert.match(output, /\u001b\[2m1:1\u001b\[22m/);
    assert.match(output, /\u001b\[31merror\u001b\[39m/);
    assert.match(output, /\u001b\[33mwarning\u001b\[39m/);
    assert.match(output, /\u001b\[2merror-rule\u001b\[22m/);
    assert.match(output, /\u001b\[31m\u001b\[1m✖ 2 problems/);
  }
  for (const format of await formatters({ color: false, env: { FORCE_COLOR: "1" } })) {
    assert.equal(format(input), plain);
  }
});

test("stylish detects stdout color support and honors explicit options and environment overrides", () => {
  const input = [result("/project/warning.js", [
    { line: 1, column: 1, severity: 1, message: "Warning.", ruleId: "warning-rule" },
  ])];
  const script = `
    import * as esm from ${JSON.stringify(new URL("../index.js", import.meta.url).href)};
    import cjs from ${JSON.stringify(new URL("../index.cjs", import.meta.url).href)};
    const { input, tty, options } = JSON.parse(process.argv[1]);
    Object.defineProperty(process.stdout, "isTTY", { value: tty });
    Object.defineProperty(process.stderr, "isTTY", { value: !tty });
    const output = [];
    for (const api of [esm, cjs]) {
      output.push(new api.CLIEngine(options).getFormatter()(input));
      output.push((await new api.ESLint(options).loadFormatter()).format(input));
    }
    process.stdout.write(JSON.stringify(output));
  `;
  const baseEnv = { ...process.env };
  for (const name of ["NO_COLOR", "NODE_DISABLE_COLORS", "FORCE_COLOR", "CLICOLOR_FORCE", "TERM"]) {
    delete baseEnv[name];
  }
  const cases = [
    { tty: false, color: false },
    { tty: true, color: true },
    { tty: false, env: { FORCE_COLOR: "1" }, color: true },
    { tty: false, env: { FORCE_COLOR: "" }, color: true },
    { tty: true, env: { FORCE_COLOR: "0" }, color: false },
    { tty: true, env: { NO_COLOR: "" }, color: false },
    { tty: true, env: { NODE_DISABLE_COLORS: "1" }, color: false },
    { tty: true, env: { NO_COLOR: "1", FORCE_COLOR: "1" }, color: false },
    { tty: false, env: { CLICOLOR_FORCE: "1" }, color: true },
    { tty: true, env: { TERM: "dumb" }, color: false },
    { tty: false, options: { color: true }, env: { NO_COLOR: "1" }, color: true },
    { tty: true, options: { color: false }, env: { FORCE_COLOR: "1" }, color: false },
    { tty: false, options: { env: { FORCE_COLOR: "1" } }, color: true },
    { tty: true, options: { env: { NO_COLOR: "1" } }, color: false },
  ];
  for (const { tty, env = {}, options = {}, color } of cases) {
    const child = spawnSync(process.execPath, ["--input-type=module", "-e", script, JSON.stringify({ input, tty, options })], {
      encoding: "utf8", env: { ...baseEnv, ...env },
    });
    assert.equal(child.status, 0, child.stderr);
    for (const output of JSON.parse(child.stdout)) {
      assert.equal(output.includes("\u001b["), color, JSON.stringify({ tty, env, options }));
      if (color) assert.match(output, /\u001b\[33m\u001b\[1m✖ 1 problem/);
    }
  }
});

test("stylish handles fatal errors without rule IDs or locations and stays silent for clean results", async () => {
  const input = [{
    ...result("/project/broken.js", [
      { fatal: true, severity: 1, message: "Parsing error: bad token.", ruleId: null },
    ]),
    errorCount: 1, warningCount: 0,
  }];
  const expected = "\n/project/broken.js\n  0:0  error  Parsing error: bad token.\n\n✖ 1 problem (1 error, 0 warnings)\n";
  for (const color of [false, true]) {
    for (const format of await formatters({ color })) {
      assert.equal(stripVTControlCharacters(format(input)), expected);
      assert.equal(format([]), "");
      assert.equal(format([result("/project/clean.js", [])]), "");
    }
  }
});

test("stylish ignores ANSI escape codes when measuring message columns", async () => {
  const input = [result("/project/input.js", [
    { line: 1, column: 1, severity: 2, message: "\u001b[31mRed\u001b[39m", ruleId: "first-rule" },
    { line: 2, column: 1, severity: 2, message: "Plain", ruleId: "second-rule" },
  ])];
  for (const format of await formatters({ color: true })) {
    assert.equal(stripVTControlCharacters(format(input)), [
      "", "/project/input.js",
      "  1:1  error  Red    first-rule",
      "  2:1  error  Plain  second-rule",
      "", "✖ 2 problems (2 errors, 0 warnings)", "",
    ].join("\n"));
  }
});

test("stylish does not alter JSON, metadata, compact or unix formatter results", async () => {
  const input = [result("/project/input.js", [
    { line: 3, column: 2, severity: 2, message: "Error.", ruleId: "no-var" },
    { line: 1, column: 1, severity: 1, message: "Warning.", ruleId: "no-debugger" },
  ])];
  const before = structuredClone(input);
  for (const format of await formatters({ color: true })) format(input);
  for (const format of await formatters({ color: true }, "json")) {
    assert.equal(format(input), JSON.stringify(before));
  }
  for (const format of await formatters({ color: true }, "json-with-metadata")) {
    const output = JSON.parse(format(input));
    assert.deepEqual(output.results, before);
    assert.deepEqual(Object.keys(output.metadata.rulesMeta), ["no-var", "no-debugger"]);
  }
  for (const format of await formatters({ color: true }, "compact")) {
    assert.equal(format(input), "/project/input.js: line 3, col 2, Error - Error. (no-var)\n/project/input.js: line 1, col 1, Warning - Warning. (no-debugger)");
  }
  for (const format of await formatters({ color: true }, "unix")) {
    assert.equal(format(input), "/project/input.js:3:2: Error. [Error/no-var]\n/project/input.js:1:1: Warning. [Warning/no-debugger]");
  }
  assert.deepEqual(input, before);
});

test("stylish renders real mixed-rule diagnostics and only counts safe native fixes", async () => {
  const source = "debugger;\nvar value = 1;\nitems.map(item => <Tag />);\n";
  const rules = { "no-debugger": "warn", "no-var": "error", "react/jsx-key": "error" };
  for (const api of [esm, commonJS]) {
    const options = { binary, color: false, useEslintrc: false, baseConfig: { rules } };
    const engine = new api.CLIEngine(options);
    const report = engine.executeOnText(source, "mixed.tsx");
    const before = structuredClone(report);
    const output = engine.getFormatter()(report.results);
    assert.equal(output, [
      "", report.results[0].filePath,
      "  1:1   warning  Unexpected debugger statement.              no-debugger",
      "  2:1   error    Use 'let' or 'const' instead of 'var'.      no-var",
      '  3:19  error    Missing "key" prop for element in iterator  react/jsx-key',
      "", "✖ 3 problems (2 errors, 1 warning)",
      "  1 error and 0 warnings potentially fixable with the `--fix` option.", "",
    ].join("\n"));
    assert.equal(report.errorCount, 2);
    assert.equal(report.warningCount, 1);
    assert.equal(report.fixableErrorCount, 1);
    assert.equal(report.results[0].messages.find((message) => message.ruleId === "react/jsx-key").fix, undefined);
    assert.equal(engine.getFormatter()(report), output);
    const eslint = new api.ESLint(options);
    assert.equal((await eslint.loadFormatter()).format(await eslint.lintText(source, { filePath: "mixed.tsx" })), output);
    assert.deepEqual(report, before);

    const native = api.lintText(source, { binary, noConfig: true, filePath: "mixed.tsx", overrideConfig: { rules } });
    const originalNative = structuredClone(native);
    assert.equal(native.exitCode, 1);
    assert.equal(engine.getFormatter()(native), output);
    assert.deepEqual(native, originalNative);
  }
});
