import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import * as esm from "../index.js";

const cjs = createRequire(import.meta.url)("../index.cjs");
const builtBinary = resolve(dirname(fileURLToPath(import.meta.url)), "../../../zig-out/bin", process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint");
const binary = existsSync(builtBinary) ? builtBinary : esm.resolveBinary();

function project(t) {
  const cwd = mkdtempSync(join(tmpdir(), "utlint-text-scope-"));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  mkdirSync(join(cwd, "src"));
  return cwd;
}

for (const format of ["json", "ts", "inline"]) {
  for (const [name, extra, source, expectedRules] of [
    ["globals", { languageOptions: { globals: { allowed: "readonly" } } }, "debugger;\n", ["no-debugger"]],
    ["settings", { settings: { jest: { version: 22 } }, rules: { "jest/no-deprecated-functions": "error" } }, "debugger; jest.runTimersToTime(1000);\n", ["jest/no-deprecated-functions", "no-debugger"]],
    ["rule options", { rules: { "no-console": ["warn", { allow: ["warn"] }] } }, "debugger; console.warn('ok'); console.log('report');\n", ["no-console", "no-debugger"]]
  ]) {
    test(`lintText selects scoped ${name} from ${format} config using the logical path`, async (t) => {
      const cwd = project(t);
      const config = { files: ["src/**/*.js"], ...extra, rules: { "no-debugger": "error", ...extra.rules } };
      if (format !== "inline") {
        writeFileSync(join(cwd, `utlint.config.${format}`), format === "json" ? JSON.stringify(config) : `export default [${JSON.stringify(config)}];\n`);
      }
      const options = { cwd, binary, ...(format === "inline" ? { overrideConfigFile: true, overrideConfig: [config] } : {}) };
      const control = join(cwd, "src/control.js");
      writeFileSync(control, source);
      for (const api of [esm, cjs]) {
        const engine = new api.UtooLint(options);
        assert.deepEqual((await engine.calculateConfigForFile("src/control.js")).rules["no-debugger"], [2]);
        const [fileResult] = await engine.lintFiles(["src/control.js"]);
        assert.deepEqual(fileResult.messages.map((message) => message.ruleId).sort(), expectedRules);
        for (const filePath of ["src/control.js", control, "src/unsaved.js"]) {
          const [textResult] = await engine.lintText(source, { filePath });
          assert.equal(textResult.filePath, resolve(cwd, filePath));
          assert.deepEqual(textResult.messages, fileResult.messages);
          const report = api.lintText(source, { ...options, filePath });
          assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.ruleId).sort(), expectedRules);
          assert.ok(report.diagnostics.every((diagnostic) => diagnostic.filePath === filePath));
        }
        const [unmatched] = await engine.lintText(source, { filePath: "test/unsaved.js" });
        assert.deepEqual(unmatched.messages, []);
      }
      assert.equal(existsSync(join(cwd, "src/unsaved.js")), false);
      assert.equal(readFileSync(control, "utf8"), source);
    });
  }
}

test("lintText preserves scoped globals, ignores, overrides, fixes and suppressed diagnostics", async (t) => {
  const cwd = project(t);
  const config = [
    { ignores: ["src/ignored/**"] },
    { files: [["src/**", "**/*.js"]], ignores: ["src/local-ignore/**"], languageOptions: { globals: { allowed: "readonly" } }, rules: { "no-undef": "error", "no-debugger": "error", "no-extra-semi": "error" } },
    { files: ["src/override/**"], rules: { "no-debugger": "off" } }
  ];
  for (const api of [esm, cjs]) {
    const engine = new api.UtooLint({ cwd, binary, overrideConfigFile: true, overrideConfig: config, fix: true });
    const source = "allowed; missing; debugger;;\n";
    const [result] = await engine.lintText(source, { filePath: "src/unsaved.js" });
    assert.deepEqual(result.messages.map((message) => message.ruleId).sort(), ["no-debugger", "no-undef"]);
    assert.match(result.messages.find((message) => message.ruleId === "no-undef").message, /missing/);
    assert.equal(result.output, "allowed; missing; debugger;\n");
    for (const filePath of ["src/local-ignore/file.js", "src/file.ts"]) {
      const [clean] = await engine.lintText(source, { filePath });
      assert.deepEqual(clean.messages, []);
      assert.equal(clean.output, undefined);
    }
    assert.deepEqual((await engine.lintText("debugger;", { filePath: "src/override/file.js" }))[0].messages, []);
    assert.deepEqual(await engine.lintText(source, { filePath: "src/ignored/file.js", warnIgnored: false }), []);
    const [suppressed] = await engine.lintText("// eslint-disable-next-line no-debugger\ndebugger;\n", { filePath: "src/suppressed.js" });
    assert.deepEqual(suppressed.messages, []);
    assert.equal(suppressed.suppressedMessages[0].ruleId, "no-debugger");
    const report = api.lintText("// eslint-disable-next-line no-debugger\ndebugger;\n", { cwd, binary, overrideConfig: config, filePath: "src/suppressed.js" });
    assert.equal(report.suppressedDiagnostics[0].filePath, "src/suppressed.js");
  }
  assert.equal(existsSync(join(cwd, "src/unsaved.js")), false);
});

test("lintText uses its default filename when materializing scoped configuration", async (t) => {
  const cwd = project(t);
  for (const api of [esm, cjs]) {
    const report = api.lintText("debugger;", { cwd, binary, overrideConfig: { files: ["text.js"], languageOptions: { globals: { allowed: "readonly" } }, rules: { "no-debugger": "error" } } });
    assert.deepEqual(report.diagnostics.map(({ ruleId }) => ruleId), ["no-debugger"]);
  }
});
