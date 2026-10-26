import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import * as esm from "../index.js";

const cjs = createRequire(import.meta.url)("../index.cjs");
const builtBinary = resolve(dirname(fileURLToPath(import.meta.url)), "../../../zig-out/bin", process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint");
const binary = existsSync(builtBinary) ? builtBinary : esm.resolveBinary();

for (const [filePath, source, output] of [
  ["example.tsx", 'export const x = <a href="https://x" target="_blank" />;', 'export const x = <a href="https://x" target="_blank" rel="noreferrer" />;'],
  ["boxed.ts", "export type A = String;", "export type A = string;"],
  ["interface.ts", "interface A { a: number; } export interface B extends A {}", "interface A { a: number; } export type B = A"],
]) {
  test(`lintText applies and clears safe autofixes for ${filePath}`, async (t) => {
    const cwd = mkdtempSync(join(tmpdir(), "utlint-safe-fixes-"));
    t.after(() => rmSync(cwd, { recursive: true, force: true }));
    for (const api of [esm, cjs]) {
      const engine = new api.ESLint({
        cwd, binary, overrideConfigFile: true, fix: true,
        overrideConfig: [{ files: ["**/*.{ts,tsx}"], rules: {
          "react/jsx-no-target-blank": "error",
          "@typescript-eslint/ban-types": "error",
          "@typescript-eslint/no-empty-interface": "error",
        } }],
      });
      const [result] = await engine.lintText(source, { filePath });
      assert.equal(result.output, output);
      assert.deepEqual(result.messages, []);
      const [second] = await engine.lintText(output, { filePath });
      assert.deepEqual(second.messages, []);
      assert.equal(second.output, undefined);
    }
  });
}
