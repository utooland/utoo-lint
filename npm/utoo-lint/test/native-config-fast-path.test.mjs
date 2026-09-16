import assert from "node:assert/strict";
import childProcess from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

import { lintFiles } from "../index.js";

function createProject(t) {
  const project = mkdtempSync(join(tmpdir(), "utoo-lint-config-fast-path-"));
  t.after(() => rmSync(project, { recursive: true, force: true }));
  return project;
}

function write(path, source) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, source);
  return path;
}

function writeConfig(project, config) {
  return write(join(project, "utlint.config.json"), `${JSON.stringify(config)}\n`);
}

function captureNativeRuns(callback, diagnosticsForPath = () => []) {
  const originalSpawnSync = childProcess.spawnSync;
  const calls = [];
  childProcess.spawnSync = (command, args) => {
    const paths = args.filter((arg) => !arg.startsWith("-"));
    const configArgument = args.find((arg) => arg.startsWith("--config="));
    calls.push({
      args,
      command,
      config: configArgument
        ? JSON.parse(readFileSync(configArgument.slice("--config=".length), "utf8"))
        : undefined,
      paths
    });
    const diagnostics = paths.flatMap(diagnosticsForPath);
    const stdout = JSON.stringify({
      files: paths.length,
      filePaths: paths,
      diagnostics,
      suppressedDiagnostics: [],
      outputs: []
    });
    return {
      error: undefined,
      output: [null, stdout, ""],
      status: diagnostics.length > 0 ? 1 : 0,
      stderr: "",
      stdout
    };
  };
  syncBuiltinESMExports();

  try {
    return { calls, value: callback() };
  } finally {
    childProcess.spawnSync = originalSpawnSync;
    syncBuiltinESMExports();
  }
}

test("severity-only config groups use the native --rules fast path", (t) => {
  const cases = [
    ["string severity", { "no-debugger": "warn", "no-console": "off" }, "no-debugger"],
    ["numeric severity", { "no-debugger": 1, "no-console": 0 }, "no-debugger"],
    ["boolean severity", { "no-debugger": true, "no-console": false }, "no-debugger"],
    ["one-item array severity", { "no-debugger": ["error"], "no-console": ["off"] }, "no-debugger"]
  ];

  for (const [name, rules, selectedRule] of cases) {
    const project = join(createProject(t), name.replaceAll(" ", "-"));
    writeConfig(project, { rules });
    const sourcePath = write(join(project, "src", "index.js"), "debugger;\n");
    const { calls } = captureNativeRuns(() =>
      lintFiles([sourcePath], { binary: "mock-utoo-lint", cwd: project })
    );

    assert.equal(calls.length, 1, name);
    assert.ok(calls[0].args.includes("--no-config"), name);
    assert.ok(calls[0].args.includes(`--rules=${selectedRule}`), name);
    assert.equal(calls[0].args.some((arg) => arg.startsWith("--config=")), false, name);
  }
});

test("severity-only config groups preserve native rule defaults", (t) => {
  const project = createProject(t);
  writeConfig(project, [
    {
      files: ["**/*.tsx"],
      rules: { "react/button-has-type": "error" }
    },
    {
      files: ["**/*.ts"],
      rules: {
        "@typescript-eslint/no-namespace": "error",
        "@typescript-eslint/no-use-before-define": "error"
      }
    }
  ]);
  const paths = [
    write(join(project, "src", "button.tsx"), 'const button = <button type="button" />;\n'),
    write(
      join(project, "src", "types.ts"),
      "interface Before { value: After }\ninterface After { value: string }\n"
    ),
    write(
      join(project, "src", "global.d.ts"),
      "declare namespace API { interface Value { value: string } }\n"
    )
  ];

  const report = lintFiles(paths, { cwd: project });

  assert.deepEqual(report.diagnostics, []);
  assert.equal(report.exitCode, 0);
});

test("fast-path diagnostics keep configured severities and exit status", (t) => {
  const project = createProject(t);
  writeConfig(project, [
    { files: ["warn/**"], rules: { "no-debugger": "warn" } },
    { files: ["error/**"], rules: { "no-debugger": "error" } },
    { files: ["off/**"], rules: { "no-debugger": "off" } }
  ]);
  const warningPath = write(join(project, "warn", "index.js"), "debugger;\n");
  const errorPath = write(join(project, "error", "index.js"), "debugger;\n");
  const offPath = write(join(project, "off", "index.js"), "debugger;\n");

  const { calls, value: report } = captureNativeRuns(
    () => lintFiles([warningPath, errorPath, offPath], { binary: "mock-utoo-lint", cwd: project }),
    (filePath) => [{
      column: 1,
      endColumn: 9,
      endLine: 1,
      filePath,
      fixes: [],
      line: 1,
      message: "Unexpected debugger statement.",
      ruleId: "no-debugger",
      severity: "warning",
      suggestions: []
    }]
  );

  assert.equal(calls.filter(({ args }) => args.includes("--rules=no-debugger")).length, 2);
  assert.deepEqual(
    report.diagnostics.map(({ filePath, severity }) => ({ filePath, severity })),
    [
      { filePath: warningPath, severity: "warning" },
      { filePath: errorPath, severity: "error" }
    ]
  );
  assert.equal(report.exitCode, 1);
});

test("rule options, settings, and all-off groups keep the materialized config path", (t) => {
  const cases = [
    {
      name: "enabled rule options",
      config: { rules: { "no-console": ["error", { allow: ["warn"] }] } }
    },
    {
      name: "shared settings",
      config: { rules: { "no-debugger": "error" }, settings: { jest: { version: 21 } } }
    },
    {
      name: "all rules disabled",
      config: { rules: { "no-debugger": "off", "no-console": false } }
    },
    {
      name: "invalid nested severity array",
      config: { rules: { "no-debugger": [["error"]] } }
    },
    {
      name: "invalid numeric severity",
      config: { rules: { "no-debugger": 3 } }
    }
  ];

  for (const { name, config } of cases) {
    const project = join(createProject(t), name.replaceAll(" ", "-"));
    writeConfig(project, config);
    const sourcePath = write(join(project, "index.js"), "debugger;\n");
    const { calls } = captureNativeRuns(() =>
      lintFiles([sourcePath], { binary: "mock-utoo-lint", cwd: project })
    );

    assert.equal(calls.length, 1, name);
    assert.equal(calls[0].args.includes("--no-config"), false, name);
    assert.equal(calls[0].args.some((arg) => arg.startsWith("--rules=")), false, name);
    assert.ok(calls[0].config, name);
  }
});

test("empty settings and options on disabled rules remain fast-path eligible", (t) => {
  const project = createProject(t);
  writeConfig(project, {
    rules: {
      "no-console": ["off", { allow: ["warn"] }],
      "no-debugger": "error"
    },
    settings: {}
  });
  const sourcePath = write(join(project, "index.js"), "debugger;\n");
  const { calls } = captureNativeRuns(() =>
    lintFiles([sourcePath], { binary: "mock-utoo-lint", cwd: project })
  );

  assert.equal(calls.length, 1);
  assert.ok(calls[0].args.includes("--no-config"));
  assert.ok(calls[0].args.includes("--rules=no-debugger"));
  assert.equal(calls[0].args.some((arg) => arg.startsWith("--config=")), false);
});

test("configured globals keep the materialized config path and reach the native config", (t) => {
  const project = createProject(t);
  writeConfig(project, {
    languageOptions: { globals: { APP_VERSION: "readonly" } },
    rules: { "no-undef": "error" }
  });
  const sourcePath = write(join(project, "index.js"), "console.log(APP_VERSION);\n");

  const { calls } = captureNativeRuns(() =>
    lintFiles([sourcePath], { binary: "mock-utoo-lint", cwd: project })
  );

  assert.equal(calls.length, 1);
  assert.equal(calls[0].args.includes("--no-config"), false);
  assert.equal(calls[0].args.some((arg) => arg.startsWith("--rules=")), false);
  assert.deepEqual(calls[0].config, [
    { languageOptions: { globals: { APP_VERSION: "readonly" } }, rules: { "no-undef": "error" } }
  ]);
});

test("eslintrc-style globals in an inline config override reach the per-file native config", (t) => {
  const project = createProject(t);
  writeConfig(project, { rules: { "no-debugger": "error" } });
  const sourcePath = write(join(project, "index.js"), "console.log(APP_VERSION);\n");

  const { calls } = captureNativeRuns(() =>
    lintFiles([sourcePath], {
      binary: "mock-utoo-lint",
      cwd: project,
      overrideConfig: { globals: { APP_VERSION: "readonly", __DEV__: true }, rules: { "no-undef": "error" } }
    })
  );

  assert.equal(calls.length, 1);
  assert.equal(calls[0].args.some((arg) => arg.startsWith("--rules=")), false);
  assert.deepEqual(calls[0].config.languageOptions, { globals: { APP_VERSION: "readonly", __DEV__: true } });
  assert.equal(calls[0].config.rules["no-undef"], "error");
  assert.equal(calls[0].config.rules["no-debugger"], "error");
});

test("languageOptions.globals from a file config and an inline override merge per name", (t) => {
  const project = createProject(t);
  writeConfig(project, [
    { languageOptions: { globals: { FROM_FILE: "readonly", SHARED: "readonly" } }, rules: { "no-undef": "error" } },
    { files: ["src/**"], languageOptions: { globals: { FROM_ENTRY: "writable" } } }
  ]);
  const sourcePath = write(join(project, "src", "index.js"), "console.log(FROM_FILE, SHARED, FROM_ENTRY, FROM_OVERRIDE);\n");

  const { calls } = captureNativeRuns(() =>
    lintFiles([sourcePath], {
      binary: "mock-utoo-lint",
      cwd: project,
      overrideConfig: { languageOptions: { globals: { FROM_OVERRIDE: "readonly", SHARED: "off" } } }
    })
  );

  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].config.languageOptions, {
    globals: { FROM_FILE: "readonly", SHARED: "off", FROM_ENTRY: "writable", FROM_OVERRIDE: "readonly" }
  });
});
