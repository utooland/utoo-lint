import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import * as esm from "../index.js";

const cjs = createRequire(import.meta.url)("../index.cjs");
const builtBinary = resolve(dirname(fileURLToPath(import.meta.url)), "../../../zig-out/bin", process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint");
const binary = existsSync(builtBinary) ? builtBinary : esm.resolveBinary();
const rule = "@typescript-eslint/no-namespace";
const declared = "declare namespace API { const value: number; }";
const external = "export {}; declare module 'foo' { export const value: number; } declare module 'hast' { interface Element { extra?: string; } }";

for (const [format, api] of [["ESM", esm], ["CJS", cjs]]) {
  test(`${format} no-namespace reports declarations by default and preserves explicit allowances`, async (t) => {
    const cwd = mkdtempSync(join(tmpdir(), "utlint-namespace-default-"));
    t.after(() => rmSync(cwd, { recursive: true, force: true }));
    for (const [setting, count, definitionCount] of [
      [2, 1, 0],
      ["error", 1, 0],
      [true, 1, 0],
      [[2], 1, 0],
      [[2, {}], 1, 0],
      [[2, { allowDeclarations: false }], 1, 0],
      [[2, { allowDefinitionFiles: false }], 1, 1],
      [[2, { allowDeclarations: true, allowDefinitionFiles: false }], 0, 0],
    ]) {
      const engine = new api.ESLint({
        cwd, binary, overrideConfigFile: true,
        overrideConfig: [{ files: ["**/*.ts"], rules: { [rule]: setting } }],
      });
      const [runtime] = await engine.lintText("namespace Runtime { export const value = 1; }", { filePath: "runtime.ts" });
      assert.deepEqual(runtime.messages.map((message) => message.ruleId), [rule]);
      for (const [filePath, expected] of [["case.ts", count], ["case.d.ts", definitionCount]]) {
        const [result] = await engine.lintText(declared, { filePath });
        assert.equal(result.messages.length, expected, `${JSON.stringify(setting)}: ${filePath}`);
        assert.ok(result.messages.every((message) => message.ruleId === rule && message.severity === 2));
        const [allowed] = await engine.lintText(external, { filePath });
        assert.deepEqual(allowed.messages, []);
      }
    }
  });

  test(`${format} no-namespace file config severity matches explicit false`, (t) => {
    const cwd = mkdtempSync(join(tmpdir(), "utlint-namespace-files-"));
    t.after(() => rmSync(cwd, { recursive: true, force: true }));
    const filePath = join(cwd, "case.ts");
    writeFileSync(filePath, `${declared}\n`);
    for (const setting of [2, [2, { allowDeclarations: false }]]) {
      writeFileSync(join(cwd, "utlint.config.json"), JSON.stringify({ rules: { [rule]: setting } }));
      const report = api.lintFiles([filePath], { cwd, binary });
      assert.deepEqual(report.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [{ ruleId: rule, severity: "error" }]);
      assert.equal(report.exitCode, 1);
    }
  });
}
