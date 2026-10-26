import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import * as esm from "../index.js";

const commonJS = createRequire(import.meta.url)("../index.cjs");
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const builtBinary = join(root, "zig-out/bin/utoo-lint");
const binary = existsSync(builtBinary) ? builtBinary : esm.resolveBinary();
const source = "// eslint-disable-next-line unknown-rule\ndebugger;";

function project(t) {
  const path = mkdtempSync(join(tmpdir(), "utoo-lint-unknown-disable-"));
  t.after(() => rmSync(path, { recursive: true, force: true }));
  return path;
}

function withBinary(t) {
  const previous = process.env.UTOO_LINT_BIN;
  process.env.UTOO_LINT_BIN = binary;
  t.after(() => {
    if (previous === undefined) delete process.env.UTOO_LINT_BIN;
    else process.env.UTOO_LINT_BIN = previous;
  });
}

function assertUnknown(diagnostic, ruleId = "unknown-rule") {
  assert.equal(diagnostic.ruleId, ruleId);
  assert.equal(diagnostic.message, `Definition for rule '${ruleId}' was not found.`);
  assert.equal(diagnostic.line, 1);
  assert.equal(diagnostic.column, 1);
  assert.equal(diagnostic.endLine, 1);
  assert.equal(diagnostic.endColumn, 41);
}

for (const [name, api] of [["ESM", esm], ["CommonJS", commonJS]]) {
  test(`${name} CLI and lintText validate disable names with configured and empty rules`, (t) => {
    const cwd = project(t);
    writeFileSync(join(cwd, "case.js"), source);
    for (const rules of [{ "no-debugger": "error" }, {}]) {
      writeFileSync(join(cwd, "utlint.config.json"), JSON.stringify({ files: ["**/*.js"], rules }));
      const cli = api.run(["--config=utlint.config.json", "--format=json", "case.js"], { binary, cwd });
      assert.equal(cli.status, 1);
      const reports = [JSON.parse(cli.stdout), api.lintText(source, { binary, cwd, filePath: "case.js", overrideConfig: { rules } })];
      for (const report of reports) {
        assert.equal(report.diagnostics.length, Object.keys(rules).length + 1);
        assert.equal(report.exitCode ?? cli.status, 1);
        assertUnknown(report.diagnostics.find((item) => item.ruleId === "unknown-rule"));
        assert.deepEqual(report.suppressedDiagnostics, []);
      }
    }
  });

  test(`${name} Linter keeps definition errors unsuppressible and accepts registered custom rules`, (t) => {
    withBinary(t);
    const linter = new api.Linter();
    linter.defineRule("example/registered", { create() { return {}; } });
    assert.deepEqual(linter.verify("/* eslint-disable example/registered */", { rules: {} }), []);
    const messages = linter.verify("/* eslint-disable */\n" + source, { rules: {} });
    assert.equal(messages.length, 1);
    assert.equal(messages[0].ruleId, "unknown-rule");
    assert.equal(messages[0].severity, 2);
    assert.deepEqual(linter.getSuppressedMessages(), []);
    assert.deepEqual(linter.verify("// utlint-ignore unknown-rule\nvoid 0;", { rules: {} }), []);
  });

  test(`${name} mounted JS plugin rules stay known when disabled or silent and remain file scoped`, async (t) => {
    withBinary(t);
    const cwd = project(t);
    mkdirSync(join(cwd, "src"));
    mkdirSync(join(cwd, "other"));
    const config = [
      { rules: {} },
      { files: ["src/**"], plugins: { example: { rules: { silent: { create() { return {}; } } } } }, rules: { "example/silent": "off" } }
    ];
    const code = "// eslint-disable-next-line example/silent\nvoid 0;";
    for (const filePath of ["src/case.js", "other/case.js"]) {
      const report = api.lintText(code, { binary, cwd, noConfig: true, filePath, overrideConfig: config });
      assert.equal(report.diagnostics.length, filePath.startsWith("src/") ? 0 : 1);
      assert.equal(report.exitCode, filePath.startsWith("src/") ? 0 : 1);
    }
    const eslint = new api.ESLint({ binary, cwd, noConfig: true, overrideConfig: config });
    const [result] = await eslint.lintText(code, { filePath: "src/case.js" });
    assert.deepEqual(result.messages, []);
    assert.equal(result.errorCount, 0);
  });
}
