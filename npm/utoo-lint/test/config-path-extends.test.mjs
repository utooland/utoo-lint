import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

import { defineConfig as defineEsmConfig } from "../config.js";

const require = createRequire(import.meta.url);
const { defineConfig: defineCjsConfig } = require("../config.cjs");

function project(t) {
  const directory = mkdtempSync(join(tmpdir(), "utoo-config-path-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return directory;
}

function write(path, source) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, source);
  return path;
}

function withoutNames(configuration) {
  return configuration.map(({ name, ...entry }) => entry);
}

for (const [entryPoint, defineConfig] of [["ESM", defineEsmConfig], ["CommonJS", defineCjsConfig]]) {
  test(`${entryPoint}: require.resolve inherits a shared config array and preserves project overrides`, (t) => {
    const directory = project(t);
    const shared = [
      { ignores: ["**/generated/**"] },
      {
        files: ["**/*.ts"],
        rules: { "no-debugger": "error", "no-console": "warn" },
        languageOptions: { globals: { SharedGlobal: "readonly" } }
      }
    ];
    const presetPath = write(join(directory, "preset.cjs"), `module.exports = ${JSON.stringify(shared)};\n`);
    const application = {
      files: ["src/**"],
      rules: { "no-console": "off" },
      languageOptions: { globals: { ApplicationGlobal: "readonly" } }
    };

    const actual = defineConfig({ ...application, extends: require.resolve(presetPath) });
    const inline = defineConfig({ ...application, extends: [shared] });

    assert.deepEqual(withoutNames(actual), withoutNames(inline));
    assert.deepEqual(actual[0].ignores, ["**/generated/**"]);
    assert.equal(actual[0].files, undefined, "global ignores must remain global");
    assert.deepEqual(actual[1].files, [["src/**", "**/*.ts"]]);
    assert.deepEqual(actual.at(-1).rules, { "no-console": "off" });
    assert.deepEqual(actual.at(-1).languageOptions.globals, { ApplicationGlobal: "readonly" });
  });

  test(`${entryPoint}: path configs support CJS, ESM, JSON and TypeScript exports`, (t) => {
    const directory = project(t);
    const fixtures = [
      ["preset.cjs", 'module.exports = { rules: { "no-debugger": "error" } };\n'],
      ["preset.mjs", 'export default [{ rules: { "no-debugger": "error" } }];\n'],
      ["preset.json", '{ "rules": { "no-debugger": "error" } }\n'],
      ["preset.ts", 'const severity: "error" = "error"; export default { rules: { "no-debugger": severity } };\n'],
      ["wrapped.cjs", 'module.exports = { default: { rules: { "no-debugger": "error" } } };\n']
    ];
    for (const [name, source] of fixtures) {
      const presetPath = write(join(directory, name), source);
      const result = defineConfig({ extends: [require.resolve(presetPath)] });
      assert.equal(result.find((entry) => entry.rules)?.rules["no-debugger"], "error", name);
    }
  });

  test(`${entryPoint}: inherited paths keep nested scope and rule precedence`, (t) => {
    const directory = project(t);
    const basePath = write(join(directory, "base.cjs"), 'module.exports = { files: ["**/*.ts"], rules: { "no-debugger": "error" } };\n');
    const sharedPath = write(join(directory, "shared.cjs"), `module.exports = { extends: ${JSON.stringify(basePath)}, files: ["src/**"], rules: { "no-debugger": "warn" } };\n`);
    const result = defineConfig({
      extends: require.resolve(sharedPath),
      files: ["src/application/**"],
      rules: { "no-debugger": "off" }
    });

    assert.deepEqual(result.filter((entry) => entry.rules).map((entry) => entry.rules["no-debugger"]), ["error", "warn", "off"]);
    assert.deepEqual(result[0].files, [["src/application/**", "src/**", "**/*.ts"]]);
    assert.deepEqual(result[1].files, [["src/application/**", "src/**"]]);
    assert.deepEqual(result[2].files, ["src/application/**"]);
    assert.ok(result.every((entry) => !("extends" in entry)));
  });

  test(`${entryPoint}: shared modules can use defineConfig with further resolved paths`, (t) => {
    const directory = project(t);
    const basePath = write(join(directory, "base.cjs"), 'module.exports = { rules: { "no-debugger": "error" } };\n');
    const helperPath = require.resolve("../config.cjs");
    const sharedPath = write(join(directory, "shared.cjs"), [
      `const { defineConfig } = require(${JSON.stringify(helperPath)});`,
      `module.exports = defineConfig({ extends: ${JSON.stringify(basePath)}, rules: { "no-console": "warn" } });`,
      ""
    ].join("\n"));

    const result = defineConfig({ extends: sharedPath, rules: { "no-console": "off" } });

    assert.deepEqual(result.filter((entry) => entry.rules).map((entry) => entry.rules), [
      { "no-debugger": "error" },
      { "no-console": "warn" },
      { "no-console": "off" }
    ]);
  });

  test(`${entryPoint}: paths can be combined with existing plugin and object configs`, (t) => {
    const directory = project(t);
    const presetPath = write(join(directory, "preset.cjs"), 'module.exports = { rules: { "no-debugger": "error" } };\n');
    const plugins = { demo: { configs: { recommended: { rules: { "no-console": "warn" } } } } };
    const result = defineConfig({
      plugins,
      extends: [require.resolve(presetPath), "demo/recommended", { rules: { eqeqeq: "error" } }],
      rules: { "no-console": "off" }
    });

    assert.deepEqual(result.filter((entry) => entry.rules).map((entry) => entry.rules), [
      { "no-debugger": "error" },
      { "no-console": "warn" },
      { eqeqeq: "error" },
      { "no-console": "off" }
    ]);
    assert.deepEqual(defineConfig({ plugins, extends: ["demo/recommended"] })[0].rules, { "no-console": "warn" });
    assert.deepEqual(defineConfig({ plugins, extends: "demo/recommended" })[0].rules, { "no-console": "warn" });
    assert.throws(() => defineConfig({ extends: ["missing/recommended"] }), /Plugin "missing" not found/);

    const withGlobalIgnores = defineConfig({
      files: ["src/**"],
      plugins: { demo: { configs: { recommended: [{ ignores: ["**/generated/**"] }, { rules: { "no-console": "warn" } }] } } },
      extends: ["demo/recommended"]
    });
    assert.deepEqual(withGlobalIgnores[0].ignores, ["**/generated/**"]);
    assert.equal(withGlobalIgnores[0].files, undefined, "plugin config names must not change global ignores");
  });

  test(`${entryPoint}: circular shared paths fail without poisoning later loads`, (t) => {
    const directory = project(t);
    const firstPath = join(directory, "first.cjs");
    const secondPath = join(directory, "second.cjs");
    write(firstPath, `module.exports = { extends: ${JSON.stringify(secondPath)} };\n`);
    write(secondPath, `module.exports = { extends: ${JSON.stringify(firstPath)} };\n`);

    assert.throws(() => defineConfig({ extends: firstPath }), /circular|cycle/i);

    const helperPath = require.resolve("../config.cjs");
    const helperFirstPath = join(directory, "helper-first.cjs");
    const helperSecondPath = join(directory, "helper-second.cjs");
    write(helperFirstPath, `const { defineConfig } = require(${JSON.stringify(helperPath)}); module.exports = defineConfig({ extends: ${JSON.stringify(helperSecondPath)} });\n`);
    write(helperSecondPath, `const { defineConfig } = require(${JSON.stringify(helperPath)}); module.exports = defineConfig({ extends: ${JSON.stringify(helperFirstPath)} });\n`);
    assert.throws(() => defineConfig({ extends: helperFirstPath }), /circular|cycle/i);

    const validPath = write(join(directory, "valid.cjs"), 'module.exports = { rules: { "no-debugger": "error" } };\n');
    const result = defineConfig({ extends: [validPath, validPath] });
    assert.equal(result.filter((entry) => entry.rules?.["no-debugger"] === "error").length, 2);
  });

  test(`${entryPoint}: missing, invalid and factory exports report errors without invoking factories`, (t) => {
    const directory = project(t);
    const sentinel = join(directory, "factory-invoked");
    const factoryPath = write(join(directory, "factory.cjs"), `module.exports = () => { require("node:fs").writeFileSync(${JSON.stringify(sentinel)}, "called"); return {}; };\n`);
    const invalidPath = write(join(directory, "invalid.cjs"), 'module.exports = "not a configuration";\n');
    const nullPath = write(join(directory, "null.cjs"), "module.exports = null;\n");
    const failedPath = write(join(directory, "failed.cjs"), 'throw new Error("shared-config-load-failed");\n');

    assert.throws(() => defineConfig({ extends: factoryPath }), /config|object|function/i);
    assert.equal(existsSync(sentinel), false);
    assert.throws(() => defineConfig({ extends: invalidPath }), /config|object/i);
    assert.throws(() => defineConfig({ extends: nullPath }), /config|object/i);
    assert.throws(() => defineConfig({ extends: join(directory, "missing.cjs") }), /missing\.cjs/);
    assert.throws(() => defineConfig({ extends: failedPath }), /shared-config-load-failed/);
  });
}
