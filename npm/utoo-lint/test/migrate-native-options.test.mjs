import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { resolveBinary } from "../index.js";

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const cliPath = join(packageDirectory, "bin", "utoo-lint.js");
const builtBinary = resolve(packageDirectory, "..", "..", "zig-out", "bin", process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint");
const binary = process.env.UTOO_LINT_BIN ?? (existsSync(builtBinary) ? builtBinary : resolveBinary());

function write(path, source) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, source);
  return path;
}

function createProject(t) {
  const project = mkdtempSync(join(tmpdir(), "utoo-lint-migrate-options-"));
  t.after(() => rmSync(project, { recursive: true, force: true }));
  return project;
}

const configFormats = {
  legacy(project, rules) {
    return write(join(project, ".eslintrc.cjs"), `module.exports = { rules: ${rules} };\n`);
  },
  flat(project, rules) {
    return write(join(project, "eslint.config.mjs"), `export default [{ rules: ${rules} }];\n`);
  },
  object(project, rules) {
    return write(join(project, "eslint.config.cjs"), `module.exports = { rules: ${rules} };\n`);
  },
  override(project, rules) {
    return write(join(project, ".eslintrc.cjs"), `module.exports = { overrides: [{ files: ["src/**/*.js"], rules: ${rules} }] };\n`);
  },
  inherited(project, rules) {
    write(join(project, "shared.cjs"), `module.exports = { rules: ${rules} };\n`);
    return write(join(project, ".eslintrc.cjs"), 'module.exports = { extends: ["./shared.cjs"] };\n');
  },
  plugin(project, rules) {
    const pluginDirectory = join(project, "node_modules", "eslint-plugin-unlimited");
    write(join(pluginDirectory, "package.json"), '{ "name": "eslint-plugin-unlimited", "main": "index.cjs" }\n');
    write(join(pluginDirectory, "index.cjs"), `module.exports = { configs: { recommended: { rules: ${rules} } } };\n`);
    return write(join(project, ".eslintrc.cjs"), 'module.exports = { extends: ["plugin:unlimited/recommended"] };\n');
  }
};

function migrate(project, sourcePath) {
  return spawnSync(process.execPath, [cliPath, "migrate", "eslint", `--from=${sourcePath}`, "--report=json"], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: binary },
    encoding: "utf8"
  });
}

for (const [format, writeConfig] of Object.entries(configFormats)) {
  for (const maxDepth of ["Infinity", "2"]) {
    test(`migrated ${format} config keeps import/no-cycle maxDepth ${maxDepth} executable`, (t) => {
      const project = createProject(t);
      const configPath = writeConfig(project, `{ "import/no-cycle": ["error", { maxDepth: ${maxDepth}, ignoreExternal: true }] }`);
      write(join(project, "src", "a.js"), "import { b } from './b.js';\nexport const a = b;\n");
      write(join(project, "src", "b.js"), "import { a } from './a.js';\nexport const b = a;\n");

      const migration = migrate(project, configPath);

      assert.equal(migration.status, 0, migration.stderr);
      const outputPath = join(project, "utlint.config.json");
      const config = JSON.parse(readFileSync(outputPath, "utf8"));
      const entries = Array.isArray(config) ? config : [config];
      const migratedRules = entries.filter((entry) => entry.rules?.["import/no-cycle"]);
      assert.equal(migratedRules.length, 1);
      assert.deepEqual(migratedRules[0].rules["import/no-cycle"], [
        "error",
        { maxDepth: maxDepth === "Infinity" ? "∞" : 2, ignoreExternal: true }
      ]);

      // Execute the emitted JSON directly so the JS wrapper cannot repair it.
      const lint = spawnSync(binary, [`--config=${outputPath}`, "--format=json", "src/a.js", "src/b.js"], {
        cwd: project,
        encoding: "utf8"
      });
      assert.equal(lint.status, 1, lint.stderr);
      assert.equal(lint.stderr, "");
      const report = JSON.parse(lint.stdout);
      assert.equal(report.files, 2);
      assert.equal(report.diagnostics.length, 2);
      assert.ok(report.diagnostics.every((diagnostic) => diagnostic.ruleId === "import/no-cycle"));
    });
  }
}

for (const format of ["legacy", "flat", "inherited"]) {
  for (const { rules, message } of [
    { rules: '{ "max-depth": ["error", { max: Infinity }] }', message: 'Rule "max-depth" option "max" is Infinity' },
    { rules: '{ "import/no-cycle": ["error", { maxDepth: -Infinity }] }', message: 'Rule "import/no-cycle" option "maxDepth" is -Infinity' },
    { rules: '{ "import/no-cycle": ["error", { maxDepth: NaN }] }', message: 'Rule "import/no-cycle" option "maxDepth" is NaN' }
  ]) {
    test(`migrator rejects an unrepresentable native option in ${format}: ${message}`, (t) => {
      const project = createProject(t);
      const configPath = configFormats[format](project, rules);

      const migration = migrate(project, configPath);

      assert.equal(migration.status, 2, migration.stderr);
      assert.ok(migration.stderr.includes(message), migration.stderr);
      assert.equal(existsSync(join(project, "utlint.config.json")), false);
    });
  }
}

test("non-finite options in ignored and unsupported plugin rules retain migration reporting", (t) => {
  const project = createProject(t);
  const configPath = write(join(project, "eslint.config.mjs"), `export default [{
    plugins: { example: { configs: { unused: { rules: { "max-depth": ["error", { max: Infinity }] } } } } },
    rules: {
      "import/no-cycle": ["error", { maxDepth: Infinity }],
      "prettier/prettier": ["error", { printWidth: Infinity }],
      "example/unsupported": ["error", { limit: NaN }]
    }
  }];\n`);

  const migration = migrate(project, configPath);

  assert.equal(migration.status, 1, migration.stderr);
  const report = JSON.parse(migration.stdout);
  assert.deepEqual(report.unsupportedRules, ["example/unsupported"]);
  assert.deepEqual(report.ignoredRules.map(({ ruleId }) => ruleId), ["prettier/prettier"]);
  const config = JSON.parse(readFileSync(join(project, "utlint.config.json"), "utf8"));
  assert.deepEqual(config[1].rules, { "import/no-cycle": ["error", { maxDepth: "∞" }] });
});
