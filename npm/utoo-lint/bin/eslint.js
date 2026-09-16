#!/usr/bin/env node
// ESLint CLI compatibility wrapper. It is deliberately not registered as an
// `eslint` bin: installing @utoo/lint must never change which tool an
// existing `eslint` script runs. Scripts opt in explicitly, for example
// `node node_modules/@utoo/lint/bin/eslint.js src`.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const fishlint = fileURLToPath(new URL("./fishlint.js", import.meta.url));
const result = spawnSync(process.execPath, [fishlint, "eslint", ...process.argv.slice(2)], {
  stdio: "inherit"
});

if (result.error) {
  console.error(`utoo-lint: failed to run eslint compatibility wrapper: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status ?? 1);
