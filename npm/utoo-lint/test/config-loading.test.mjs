import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { createRequire } from "node:module";

import { CLIEngine, ESLint, Linter, lintFiles, lintText, resolveBinary, run, runCli } from "../index.js";

const require = createRequire(import.meta.url);
const {
  CLIEngine: CommonJSCLIEngine,
  ESLint: CommonJSESLint,
  Linter: CommonJSLinter,
  run: commonJSRun,
  runCli: commonJSRunCli
} = require("../index.cjs");

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const cliPath = join(packageDirectory, "bin", "utoo-lint.js");
const fishlintPath = join(packageDirectory, "bin", "fishlint.js");
const builtBinary = resolve(
  packageDirectory,
  "..",
  "..",
  "zig-out",
  "bin",
  process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint"
);
const largeDiagnosticCount = 20_000;
const testOutputMaxBuffer = 64 * 1024 * 1024;

function testBinary() {
  if (existsSync(builtBinary)) {
    return builtBinary;
  }
  return resolveBinary();
}

function createProject(t) {
  const project = mkdtempSync(join(tmpdir(), "utoo-lint-config-loading-"));
  t.after(() => rmSync(project, { recursive: true, force: true }));
  return project;
}

function write(path, source = "{}\n") {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, source);
  return path;
}

test("frontend typed, package, and JSON entry points expose the same scope and rule set", () => {
  const jsonPath = join(packageDirectory, "configs", "frontend.json");
  const declarationPath = join(packageDirectory, "configs", "frontend.d.ts");
  const fromJson = JSON.parse(readFileSync(jsonPath, "utf8"));
  const fromPackageExport = require("@utoo/lint/configs/frontend");
  assert.deepEqual(fromPackageExport, fromJson);

  const declaration = readFileSync(declarationPath, "utf8");
  const typedRuleIds = [...declaration.matchAll(/^\s*\|\s*"([^"]+)";?$/gm)].map((match) => match[1]);
  assert.deepEqual(typedRuleIds, Object.keys(fromJson.rules));
  assert.deepEqual(fromJson.files, ["src/**/*.{js,jsx,ts,tsx}"]);
  assert.deepEqual(fromJson.ignores, ["dist", "coverage", "node_modules"]);
  assert.match(declaration, /readonly files: \["src\/\*\*\/\*\.\{js,jsx,ts,tsx\}"\];/);
  assert.match(declaration, /readonly ignores: \["dist", "coverage", "node_modules"\];/);

  const reviewedRules = {
    "react-hooks/rules-of-hooks": "error",
    "react-hooks/exhaustive-deps": "warn",
    "react/jsx-key": "error",
    "react/no-array-index-key": "warn",
    "react/no-children-prop": "error",
    "react/no-danger-with-children": "error",
    "react/void-dom-elements-no-children": "error",
    "react/no-unstable-nested-components": "warn",
    "react/no-forward-ref": "warn",
    "no-script-url": "error",
    "promise/no-nesting": "error",
    "unused-imports/no-unused-imports": "warn",
    "@typescript-eslint/no-unused-vars": "warn",
    "@typescript-eslint/ban-types": "warn"
  };
  for (const [ruleId, severity] of Object.entries(reviewedRules)) {
    assert.equal(fromJson.rules[ruleId], severity, ruleId);
  }
  assert.equal(
    Object.keys(fromJson.rules).some((ruleId) => /prettier|format|indent|quotes|semi/.test(ruleId)),
    false
  );
});

function createLargeDiagnosticProject(t) {
  const project = createProject(t);
  const sourcePath = write(join(project, "fixture.js"), "debugger;\n".repeat(largeDiagnosticCount));
  const configPath = write(
    join(project, "utlint.config.json"),
    `${JSON.stringify({ rules: { "no-debugger": "error" } }, null, 2)}\n`
  );
  return { project, sourcePath, configPath };
}

function assertLargeJsonReport(stdout) {
  const byteLength = Buffer.byteLength(stdout);
  assert.ok(byteLength > 1024 * 1024, `expected more than 1 MiB of JSON, received ${byteLength} bytes`);
  const report = JSON.parse(stdout);
  assert.equal(report.diagnostics.length, largeDiagnosticCount);
  assert.ok(report.diagnostics.every((diagnostic) => diagnostic.ruleId === "no-debugger"));
}

test("ESM and CommonJS run capture diagnostic JSON larger than Node's default spawnSync buffer", (t) => {
  const { project, sourcePath, configPath } = createLargeDiagnosticProject(t);
  const args = [`--config=${configPath}`, "--format=json", sourcePath];
  const result = run(args, { binary: testBinary(), cwd: project });

  assert.equal(result.error, undefined);
  assert.equal(result.status, 1);
  assert.equal(result.stderr, "");
  assertLargeJsonReport(result.stdout);

  const commonJSResult = commonJSRun(args, { binary: testBinary(), cwd: project });
  assert.equal(commonJSResult.error, undefined);
  assert.equal(commonJSResult.status, 1);
  assert.equal(commonJSResult.stderr, "");
  assertLargeJsonReport(commonJSResult.stdout);

  const bufferedOutputArgs = ["--eval", `process.stdout.write("x".repeat(4096))`];
  const capped = run(bufferedOutputArgs, { binary: process.execPath, maxBuffer: 1024 });
  assert.equal(capped.error?.code, "ENOBUFS");

  const envCapped = run(bufferedOutputArgs, {
    binary: process.execPath,
    env: { UTOO_LINT_MAX_BUFFER: "1024" }
  });
  assert.equal(envCapped.error?.code, "ENOBUFS");

  const missing = run([], { binary: join(project, "missing-utoo-lint") });
  assert.equal(missing.error?.code, "ENOENT");
});

test("CLI preserves large JSON and text reports with the correct exit status", (t) => {
  const { project, sourcePath, configPath } = createLargeDiagnosticProject(t);
  const env = { ...process.env, UTOO_LINT_BIN: testBinary() };
  const commonArgs = [`--config=${configPath}`, sourcePath];

  const json = spawnSync(process.execPath, [cliPath, "--format=json", ...commonArgs], {
    cwd: project,
    env,
    encoding: "utf8",
    maxBuffer: testOutputMaxBuffer
  });
  assert.equal(json.error, undefined);
  assert.equal(json.status, 1);
  assert.equal(json.stderr, "");
  assertLargeJsonReport(json.stdout);

  const text = spawnSync(process.execPath, [cliPath, "--no-color", ...commonArgs], {
    cwd: project,
    env,
    encoding: "utf8",
    maxBuffer: testOutputMaxBuffer
  });
  assert.equal(text.error, undefined);
  assert.equal(text.status, 1);
  assert.equal(text.stdout, "");
  assert.ok(Buffer.byteLength(text.stderr) > 1024 * 1024);
  assert.equal(text.stderr.match(/no-debugger/g)?.length, largeDiagnosticCount);
  assert.match(text.stderr, /20000 problems \(20000 errors, 0 warnings\)/);
});

test("frontend preset scopes default and explicit targets to source files", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "src", "index.js"), "debugger;\n");
  const generatedPaths = [
    write(join(project, "dist", "generated.js"), "debugger;\n"),
    write(join(project, "coverage", "generated.js"), "debugger;\n"),
    write(join(project, "node_modules", "example", "generated.js"), "debugger;\n")
  ];
  write(
    join(project, "utlint.config.json"),
    readFileSync(join(packageDirectory, "configs", "frontend.json"), "utf8")
  );

  for (const execute of [runCli, commonJSRunCli]) {
    for (const targets of [[], ["."]]) {
      const result = execute(["--format=json", ...targets], {
        cwd: project,
        binary: testBinary(),
        encoding: "utf8"
      });

      assert.equal(result.status, 1, result.stderr);
      const report = JSON.parse(result.stdout);
      assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.ruleId), ["no-debugger"]);
      assert.equal(resolve(report.diagnostics[0].filePath), resolve(sourcePath));
      assert.equal(report.diagnostics.some((diagnostic) => diagnostic.ruleId === "parse"), false);
      for (const generatedPath of generatedPaths) {
        assert.equal(
          report.diagnostics.some((diagnostic) => resolve(diagnostic.filePath) === resolve(generatedPath)),
          false
        );
      }
      if (targets.length === 0) {
        assert.deepEqual(report.filePaths.map((filePath) => resolve(filePath)), [resolve(sourcePath)]);
      }
    }
  }
});

test("ESLint exposes diagnostics suppressed by utlint-ignore", async () => {
  const eslint = new ESLint({
    binary: testBinary(),
    noConfig: true,
    overrideConfig: { rules: { "no-debugger": "error" } }
  });

  const [result] = await eslint.lintText(
    "// utlint-ignore no-debugger: generated breakpoint\ndebugger;\n",
    { filePath: "suppressed.js" }
  );

  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.equal(result.suppressedMessages[0].ruleId, "no-debugger");
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "generated breakpoint" }
  ]);
});

test("CommonJS ESLint exposes diagnostics suppressed by utlint-ignore", async () => {
  const eslint = new CommonJSESLint({
    binary: testBinary(),
    noConfig: true,
    overrideConfig: { rules: { "no-debugger": "error" } }
  });

  const [result] = await eslint.lintText(
    "// utlint-ignore no-debugger: generated breakpoint\ndebugger;\n",
    { filePath: "suppressed.js" }
  );

  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.equal(result.suppressedMessages[0].ruleId, "no-debugger");
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "generated breakpoint" }
  ]);
});

test("ESM and CommonJS Linter expose suppressed messages", (t) => {
  const previousBinary = process.env.UTOO_LINT_BIN;
  process.env.UTOO_LINT_BIN = testBinary();
  t.after(() => {
    if (previousBinary === undefined) {
      delete process.env.UTOO_LINT_BIN;
    } else {
      process.env.UTOO_LINT_BIN = previousBinary;
    }
  });

  for (const LinterImplementation of [Linter, CommonJSLinter]) {
    const linter = new LinterImplementation();
    const messages = linter.verify(
      "// utlint-ignore no-debugger: generated breakpoint\ndebugger;\n",
      { rules: { "no-debugger": "error" } },
      { filename: "suppressed.js" }
    );

    assert.deepEqual(messages, []);
    assert.equal(linter.getSuppressedMessages().length, 1);
    assert.deepEqual(linter.getSuppressedMessages()[0].suppressions, [
      { kind: "directive", justification: "generated breakpoint" }
    ]);
  }
});

test("ESLint compatibility APIs apply eslint-disable directives to native diagnostics", async (t) => {
  const previousBinary = process.env.UTOO_LINT_BIN;
  process.env.UTOO_LINT_BIN = testBinary();
  t.after(() => {
    if (previousBinary === undefined) {
      delete process.env.UTOO_LINT_BIN;
    } else {
      process.env.UTOO_LINT_BIN = previousBinary;
    }
  });

  const source = [
    "export function update(value) {",
    "  value.count += 1; // eslint-disable-line no-param-reassign -- intentional mutation",
    "}",
    ""
  ].join("\n");
  const overrideConfig = {
    rules: {
      "no-param-reassign": ["error", { props: true }],
      "no-unused-vars": "off"
    }
  };

  for (const ESLintImplementation of [ESLint, CommonJSESLint]) {
    const eslint = new ESLintImplementation({
      binary: testBinary(),
      noConfig: true,
      overrideConfig
    });
    const [result] = await eslint.lintText(source, { filePath: "suppressed.js" });
    assert.deepEqual(result.messages, []);
    assert.equal(result.suppressedMessages.length, 1);
    assert.equal(result.suppressedMessages[0].ruleId, "no-param-reassign");
    assert.deepEqual(result.suppressedMessages[0].suppressions, [
      { kind: "directive", justification: "intentional mutation" }
    ]);
  }

  for (const LinterImplementation of [Linter, CommonJSLinter]) {
    const linter = new LinterImplementation();
    const messages = linter.verify(source, overrideConfig, { filename: "suppressed.js" });
    assert.deepEqual(messages, []);
    assert.equal(linter.getSuppressedMessages().length, 1);
    assert.equal(linter.getSuppressedMessages()[0].ruleId, "no-param-reassign");

    const parseMessages = linter.verify(
      "/* eslint-disable */\nconst value = ;\n",
      {},
      { filename: "broken.js" }
    );
    assert.equal(parseMessages.length, 1);
    assert.equal(parseMessages[0].ruleId, "parse");
    assert.deepEqual(linter.getSuppressedMessages(), []);
  }

  for (const CLIEngineImplementation of [CLIEngine, CommonJSCLIEngine]) {
    const cli = new CLIEngineImplementation({
      binary: testBinary(),
      noConfig: true,
      overrideConfig
    });
    const report = cli.executeOnText(source, "suppressed.js");
    assert.deepEqual(report.results[0].messages, []);
    assert.equal(report.results[0].suppressedMessages.length, 1);
    assert.equal(report.results[0].suppressedMessages[0].ruleId, "no-param-reassign");
  }
});

test("CLIEngine.executeOnFiles applies eslint-disable directives to native diagnostics", (t) => {
  const project = createProject(t);
  const sourcePath = write(
    join(project, "suppressed.js"),
    "export function update(value) {\n  value.count += 1; // eslint-disable-line no-param-reassign\n}\n"
  );
  const cli = new CLIEngine({
    binary: testBinary(),
    cwd: project,
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-param-reassign": ["error", { props: true }],
        "no-unused-vars": "off"
      }
    }
  });

  const report = cli.executeOnFiles([sourcePath]);
  assert.deepEqual(report.results[0].messages, []);
  assert.equal(report.results[0].suppressedMessages.length, 1);
  assert.equal(report.results[0].suppressedMessages[0].ruleId, "no-param-reassign");
});

test("ESLint fix mode does not apply fixes disabled by eslint directives", async () => {
  const source = "const value = 1;; // eslint-disable-line no-extra-semi\nconsole.log(value);\n";
  const eslint = new ESLint({
    binary: testBinary(),
    fix: true,
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-extra-semi": "error",
        "no-console": "off",
        "no-unused-vars": "off"
      }
    }
  });

  const [result] = await eslint.lintText(source, { filePath: "suppressed.js" });
  assert.equal(result.output, undefined);
  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.equal(result.suppressedMessages[0].ruleId, "no-extra-semi");
});

test("ESLint fix mode honors disable ranges with selective enables", async () => {
  const source = [
    "/* eslint-disable -- generated code */",
    "const first = 1;;",
    "/* eslint-enable no-extra-semi */",
    "const second = 2;;",
    "void first;",
    "void second;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    fix: true,
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-extra-semi": "error",
        "no-unused-vars": "off"
      }
    }
  });

  const [result] = await eslint.lintText(source, { filePath: "suppressed.js" });
  assert.equal(result.output, source.replace("const second = 2;;", "const second = 2;"));
  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.equal(result.suppressedMessages[0].ruleId, "no-extra-semi");
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "generated code" }
  ]);
});

test("ESLint disable ranges treat comma-only rule lists as all rules", async () => {
  const source = [
    "/* eslint-disable , -- generated code */",
    "const first = 1;;",
    "/* eslint-enable , */",
    "const second = 2;;",
    "void first;",
    "void second;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    fix: true,
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-extra-semi": "error",
        "no-unused-vars": "off"
      }
    }
  });

  const [result] = await eslint.lintText(source, { filePath: "comma-only.js" });
  assert.equal(result.output, source.replace("const second = 2;;", "const second = 2;"));
  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "generated code" }
  ]);
});

test("ESLint directives inside template interpolations suppress native diagnostics", async () => {
  const source = [
    "const text = `${",
    "  // eslint-disable-next-line no-console, no-undef",
    "  missingValue",
    "}`;",
    "void text;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-undef": "error",
        "no-unused-vars": "off"
      }
    }
  });

  const [result] = await eslint.lintText(source, { filePath: "template.js" });
  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.equal(result.suppressedMessages[0].ruleId, "no-undef");
});

test("multiline eslint-disable-next-line starts after the block comment", async () => {
  const source = [
    "/* eslint-disable-next-line",
    "   no-extra-semi */",
    "const value = 1;;",
    "void value;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    fix: true,
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-extra-semi": "error",
        "no-unused-vars": "off"
      }
    }
  });

  const [result] = await eslint.lintText(source, { filePath: "multiline.js" });
  assert.equal(result.output, undefined);
  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.equal(result.suppressedMessages[0].ruleId, "no-extra-semi");
});

test("eslint-disable-next-line recognizes every JavaScript line terminator", async (t) => {
  for (const [name, lineTerminator] of [
    ["carriage return", "\r"],
    ["line separator", "\u2028"],
    ["paragraph separator", "\u2029"]
  ]) {
    await t.test(name, async () => {
      const source = [
        "// eslint-disable-next-line no-extra-semi",
        "const value = 1;;",
        "void value;",
        ""
      ].join(lineTerminator);
      const eslint = new ESLint({
        binary: testBinary(),
        fix: true,
        noConfig: true,
        overrideConfig: {
          rules: {
            "no-extra-semi": "error",
            "no-unused-vars": "off"
          }
        }
      });

      const [result] = await eslint.lintText(source, { filePath: `${name}.js` });
      assert.equal(result.output, undefined);
      assert.deepEqual(result.messages, []);
      assert.equal(result.suppressedMessages.length, 1);
      assert.equal(result.suppressedMessages[0].ruleId, "no-extra-semi");
    });
  }
});

test("multiline eslint-disable-line does not suppress diagnostics", async () => {
  const source = [
    "const value = 1;; /* eslint-disable-line",
    "   no-extra-semi */",
    "void value;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    fix: true,
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-extra-semi": "error",
        "no-unused-vars": "off"
      }
    }
  });

  const [result] = await eslint.lintText(source, { filePath: "invalid-directive.js" });
  assert.equal(result.output, source.replace("const value = 1;;", "const value = 1;"));
  assert.deepEqual(result.messages, []);
  assert.deepEqual(result.suppressedMessages, []);

  const lintOnly = new ESLint({
    binary: testBinary(),
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-extra-semi": "error",
        "no-unused-vars": "off"
      }
    }
  });
  const [lintResult] = await lintOnly.lintText(source, { filePath: "invalid-directive.js" });
  assert.equal(lintResult.messages.length, 1);
  assert.equal(lintResult.messages[0].ruleId, "no-extra-semi");
  assert.deepEqual(lintResult.suppressedMessages, []);
});

test("ESLint directives accept ECMAScript whitespace", async () => {
  const source = [
    "/*\feslint-disable-next-line\fno-extra-semi\f--\fintentional\f*/",
    "const value = 1;;",
    "void value;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    fix: true,
    noConfig: true,
    overrideConfig: {
      rules: {
        "no-extra-semi": "error",
        "no-unused-vars": "off"
      }
    }
  });

  const [result] = await eslint.lintText(source, { filePath: "whitespace.js" });
  assert.equal(result.output, undefined);
  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "intentional" }
  ]);
});

test("ESM and CommonJS ESLint report every overlapping disable directive", async () => {
  const source = [
    "/* eslint-disable no-extra-semi -- generated */",
    "const value = 1;; // eslint-disable-line no-extra-semi -- intentional",
    "void value;",
    ""
  ].join("\n");
  for (const ESLintImplementation of [ESLint, CommonJSESLint]) {
    const eslint = new ESLintImplementation({
      binary: testBinary(),
      noConfig: true,
      overrideConfig: {
        rules: {
          "no-extra-semi": "error",
          "no-unused-vars": "off"
        }
      }
    });

    const [result] = await eslint.lintText(source, { filePath: "overlapping-directives.js" });
    assert.deepEqual(result.messages, []);
    assert.equal(result.suppressedMessages.length, 1);
    assert.deepEqual(result.suppressedMessages[0].suppressions, [
      { kind: "directive", justification: "generated" },
      { kind: "directive", justification: "intentional" }
    ]);
  }

  const report = lintText(source, {
    binary: testBinary(),
    noConfig: true,
    filePath: "overlapping-directives.js",
    overrideConfig: { rules: { "no-extra-semi": "error" } }
  });
  assert.equal(report.suppressedDiagnostics[0].suppression.justification, "intentional");
  assert.deepEqual(report.suppressedDiagnostics[0].suppressions, [
    { kind: "directive", justification: "generated" },
    { kind: "directive", justification: "intentional" }
  ]);
});

test("ESLint range suppressions precede earlier same-line suppressions", async () => {
  const source = "/* eslint-disable-line no-undef -- line */ /* eslint-disable no-undef -- range */ foo();\n";
  const eslint = new ESLint({
    binary: testBinary(),
    noConfig: true,
    overrideConfig: { rules: { "no-undef": "error" } }
  });

  const [result] = await eslint.lintText(source, { filePath: "suppression-order.js" });
  assert.deepEqual(result.messages, []);
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "range" },
    { kind: "directive", justification: "line" }
  ]);
});

test("utlint metadata survives an earlier ESLint line suppression", () => {
  const source = "/* eslint-disable-line no-undef -- eslint */ /* utlint-ignore no-undef: utoo */ foo();\n";
  const report = lintText(source, {
    binary: testBinary(),
    noConfig: true,
    filePath: "mixed-line-directives.js",
    overrideConfig: { rules: { "no-undef": "error" } }
  });

  assert.deepEqual(report.diagnostics, []);
  assert.deepEqual(report.suppressedDiagnostics[0].suppressions, [
    { kind: "directive", justification: "eslint" },
    { kind: "directive", justification: "utoo" }
  ]);
});

test("ESLint disable directives accept empty justifications", async () => {
  const source = [
    "/* eslint-disable no-extra-semi -- */",
    "const value = 1;;",
    "void value;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    fix: true,
    noConfig: true,
    overrideConfig: { rules: { "no-extra-semi": "error" } }
  });

  const [result] = await eslint.lintText(source, { filePath: "empty-justification.js" });
  assert.equal(result.output, undefined);
  assert.deepEqual(result.messages, []);
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "" }
  ]);
});

test("ESLint justification separators require trailing whitespace", async () => {
  const source = [
    "/* eslint-disable-next-line no-extra-semi --*/",
    "const value = 1;;",
    "void value;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    fix: true,
    noConfig: true,
    overrideConfig: { rules: { "no-extra-semi": "error" } }
  });

  const [result] = await eslint.lintText(source, { filePath: "invalid-separator.js" });
  assert.notEqual(result.output, undefined);
  assert.deepEqual(result.suppressedMessages, []);
});

test("native reports preserve overlapping utlint and ESLint metadata", () => {
  const source = [
    "/* eslint-disable no-extra-semi -- generated */",
    "// utlint-ignore no-extra-semi: intentional",
    "const value = 1;;",
    "void value;",
    ""
  ].join("\n");
  const report = lintText(source, {
    binary: testBinary(),
    noConfig: true,
    filePath: "mixed-directives.js",
    overrideConfig: { rules: { "no-extra-semi": "error" } }
  });

  assert.deepEqual(report.diagnostics, []);
  assert.equal(report.suppressedDiagnostics[0].suppression.justification, "intentional");
  assert.deepEqual(report.suppressedDiagnostics[0].suppressions, [
    { kind: "directive", justification: "generated" },
    { kind: "directive", justification: "intentional" }
  ]);
});

test("repeated rule targets produce one suppression per ESLint directive", async () => {
  const source = [
    "/* eslint-disable no-extra-semi, no-extra-semi -- generated */",
    "const value = 1;;",
    "void value;",
    ""
  ].join("\n");
  const eslint = new ESLint({
    binary: testBinary(),
    noConfig: true,
    overrideConfig: { rules: { "no-extra-semi": "error" } }
  });

  const [result] = await eslint.lintText(source, { filePath: "repeated-rule-target.js" });
  assert.deepEqual(result.messages, []);
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "generated" }
  ]);
});

test("lintText returns suppressed native diagnostics with the requested file path", () => {
  const report = lintText(
    "// utlint-ignore no-debugger: generated breakpoint\ndebugger;\n",
    {
      binary: testBinary(),
      noConfig: true,
      filePath: "suppressed.js",
      overrideConfig: { rules: { "no-debugger": "error" } }
    }
  );

  assert.deepEqual(report.diagnostics, []);
  assert.equal(report.suppressedDiagnostics.length, 1);
  assert.equal(report.suppressedDiagnostics[0].filePath, "suppressed.js");
  assert.equal(report.suppressedDiagnostics[0].suppression.justification, "generated breakpoint");
});

test("raw native CLI reports utlint-ignore suppressions without failing", (t) => {
  const project = createProject(t);
  const sourcePath = write(
    join(project, "suppressed.js"),
    "// utlint-ignore no-debugger: generated breakpoint\ndebugger;\n"
  );

  const result = spawnSync(
    testBinary(),
    ["--no-config", "--rules=no-debugger", "--format=json", sourcePath],
    { cwd: project, encoding: "utf8" }
  );
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(report.diagnostics, []);
  assert.equal(report.suppressedDiagnostics.length, 1);
  assert.equal(report.suppressedDiagnostics[0].ruleId, "no-debugger");
});

test("utlint-ignore suppresses ESLint-compatible custom rules", async () => {
  const eslint = new ESLint({
    binary: testBinary(),
    noConfig: true,
    overrideConfig: {
      plugins: {
        custom: {
          rules: {
            report: {
              create(context) {
                return {
                  Program(node) {
                    context.report({
                      node,
                      loc: { start: { line: 2, column: 0 }, end: { line: 2, column: 5 } },
                      message: "custom report"
                    });
                  }
                };
              }
            }
          }
        }
      },
      rules: { "custom/report": "error" }
    }
  });

  const [result] = await eslint.lintText(
    "// utlint-ignore custom/report: generated declaration\nvalue;\n",
    { filePath: "suppressed.js" }
  );

  assert.deepEqual(result.messages, []);
  assert.equal(result.suppressedMessages.length, 1);
  assert.deepEqual(result.suppressedMessages[0].suppressions, [
    { kind: "directive", justification: "generated declaration" }
  ]);
});

for (const filename of ["utlint.config.ts", "utlint.config.json"]) {
  test(`ESLint.findConfigFile discovers ${filename}`, async (t) => {
    const project = createProject(t);
    const configPath = write(join(project, filename));

    const eslint = new ESLint({ cwd: project });

    assert.equal(await eslint.findConfigFile(), configPath);
  });
}

test("fishlint applies TypeScript flat config rules per file and keeps CLI overrides highest", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-debugger": "off" } },',
      '  { files: ["test/**/*.ts"], rules: { "no-debugger": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const disabledSource = write(join(project, "src", "index.ts"), "debugger;\n");
  const enabledSource = write(join(project, "test", "index.ts"), "debugger;\n");
  const env = { ...process.env, UTOO_LINT_BIN: testBinary() };

  const configured = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--format=json", disabledSource, enabledSource],
    { cwd: project, env, encoding: "utf8" }
  );

  assert.equal(configured.status, 1, configured.stderr);
  const configuredReport = JSON.parse(configured.stdout);
  assert.deepEqual(
    configuredReport.diagnostics.map((diagnostic) => diagnostic.filePath),
    [enabledSource]
  );
  assert.equal(configuredReport.diagnostics[0].severity, "error");

  const overridden = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--format=json", "--rule", "no-debugger: off", disabledSource, enabledSource],
    { cwd: project, env, encoding: "utf8" }
  );

  assert.equal(overridden.status, 0, overridden.stderr);
  assert.deepEqual(JSON.parse(overridden.stdout).diagnostics, []);
});

test("fishlint --rules overrides flat-config off severities", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-debugger": "off" } },',
      '  { files: ["test/**/*.ts"], rules: { "no-debugger": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const src = write(join(project, "src", "index.ts"), "debugger;\n");
  const testFile = write(join(project, "test", "index.ts"), "debugger;\n");

  const result = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--rules=no-debugger", "--format=json", src, testFile],
    { cwd: project, env: { ...process.env, UTOO_LINT_BIN: testBinary() }, encoding: "utf8" }
  );
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(report.diagnostics.length, 2);
  assert.ok(report.diagnostics.every((diagnostic) => diagnostic.severity === "warning"));
});

test("fishlint enforces --max-warnings when the native binary exits successfully", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.js"), "debugger;\n");
  const env = { ...process.env, UTOO_LINT_BIN: testBinary() };

  const rejected = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--no-config", "--max-warnings=0", sourcePath],
    { cwd: project, env, encoding: "utf8" }
  );
  const accepted = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--no-config", "--max-warnings=1", sourcePath],
    { cwd: project, env, encoding: "utf8" }
  );

  assert.equal(rejected.status, 1, rejected.stderr);
  assert.match(rejected.stderr, /too many warnings/);
  assert.equal(accepted.status, 0, accepted.stderr);
});

test("fishlint counts quiet warnings against --max-warnings", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.js"), "debugger;\n");

  const result = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--no-config", "--quiet", "--max-warnings=0", sourcePath],
    {
      cwd: project,
      env: { ...process.env, UTOO_LINT_BIN: testBinary() },
      encoding: "utf8"
    }
  );

  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /too many warnings/);
  assert.doesNotMatch(result.stdout, /no-debugger/);
});

test("fishlint groups flat config files by complete rule options", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-console": ["error", { allow: ["warn"] }] } },',
      '  { files: ["test/**/*.ts"], rules: { "no-console": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const allowedSource = write(join(project, "src", "index.ts"), 'console.warn("allowed");\n');
  const reportedSource = write(join(project, "test", "index.ts"), 'console.warn("reported");\n');

  const result = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--format=json", allowedSource, reportedSource],
    { cwd: project, env: { ...process.env, UTOO_LINT_BIN: testBinary() }, encoding: "utf8" }
  );

  assert.equal(result.status, 1, result.stderr);
  const report = JSON.parse(result.stdout);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.filePath), [reportedSource]);
  assert.equal(report.diagnostics[0].ruleId, "no-console");
});

for (const fixFlag of ["--fix", "--fix-dry-run"]) {
  test(`fishlint ${fixFlag} does not leak rules or fixes into an unmatched flat config file`, (t) => {
    const project = createProject(t);
    write(
      join(project, "utlint.config.ts"),
      'export default [{ files: ["test/**/*.js"], rules: { "no-extra-semi": "error" } }];\n'
    );
    const untouchedSource = write(join(project, "src", "index.js"), "foo();;\n");
    const fixedSource = write(join(project, "test", "index.js"), "foo();;\n");

    const result = spawnSync(
      process.execPath,
      [fishlintPath, "eslint", "--format=json", fixFlag, untouchedSource, fixedSource],
      { cwd: project, env: { ...process.env, UTOO_LINT_BIN: testBinary() }, encoding: "utf8" }
    );

    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(result.stdout);
    assert.equal(readFileSync(untouchedSource, "utf8"), "foo();;\n");
    assert.equal(
      readFileSync(fixedSource, "utf8"),
      fixFlag === "--fix" ? "foo();\n" : "foo();;\n"
    );
    assert.deepEqual(report.outputs.map((output) => output.filePath), [fixedSource]);
  });
}

for (const fixFlag of ["--fix", "--fix-dry-run"]) {
  test(`fishlint ${fixFlag} does not leak native defaults from an object config`, (t) => {
    const project = createProject(t);
    write(
      join(project, "utlint.config.json"),
      JSON.stringify({ rules: { "no-debugger": "error" } })
    );
    const sourcePath = write(join(project, "index.js"), "foo();;\n");

    const result = spawnSync(
      process.execPath,
      [fishlintPath, "eslint", "--format=json", fixFlag, sourcePath],
      { cwd: project, env: { ...process.env, UTOO_LINT_BIN: testBinary() }, encoding: "utf8" }
    );
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(report.diagnostics, []);
    assert.deepEqual(report.outputs, []);
    assert.equal(readFileSync(sourcePath, "utf8"), "foo();;\n");
  });
}

test("fishlint applies a flat global ignore entry before per-file rule grouping", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { name: "generated", ignores: ["dist/"] },',
      '  { rules: { "no-debugger": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const ignoredSource = write(join(project, "dist", "ignored.ts"), "debugger;\n");
  const reportedSource = write(join(project, "src", "reported.ts"), "debugger;\n");

  const result = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--format=json", ignoredSource, reportedSource],
    { cwd: project, env: { ...process.env, UTOO_LINT_BIN: testBinary() }, encoding: "utf8" }
  );

  assert.equal(result.status, 1, result.stderr);
  const report = JSON.parse(result.stdout);
  assert.deepEqual(report.filePaths, [reportedSource]);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.filePath), [reportedSource]);
});

test("fishlint replaces a split --config argument when materializing TypeScript", (t) => {
  const project = createProject(t);
  const configPath = write(
    join(project, "custom.config.ts"),
    'export default { rules: { "no-debugger": "off" } };\n'
  );
  const sourcePath = write(join(project, "index.ts"), "debugger;\n");

  const result = spawnSync(
    process.execPath,
    [fishlintPath, "eslint", "--config", configPath, sourcePath],
    {
      cwd: project,
      env: { ...process.env, UTOO_LINT_BIN: testBinary() },
      encoding: "utf8"
    }
  );

  assert.equal(result.status, 0, result.stderr);
});

test("migrator defaults to utlint.config.json", (t) => {
  const project = createProject(t);
  const eslintConfig = join(project, "eslint.config.mjs");
  write(
    eslintConfig,
    'export default [{ files: ["src/**/*.ts"], rules: { "no-debugger": "error" } }];\n'
  );

  const result = spawnSync(process.execPath, [cliPath, "migrate", "eslint", `--from=${eslintConfig}`], {
    cwd: project,
    encoding: "utf8"
  });
  const outputPath = join(project, "utlint.config.json");

  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(outputPath), true);
  const config = JSON.parse(readFileSync(outputPath, "utf8"));
  assert.equal(config[0].$schema.endsWith("/schema.json"), true);
  assert.deepEqual(config[1], {
    files: ["src/**/*.ts"],
    rules: { "no-debugger": "error" }
  });
});

test("migrator preserves flat config scopes, global ignores, and override order", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, "eslint.config.mjs"),
    [
      "export default [",
      '  { name: "global ignores", ignores: ["dist/"] },',
      '  { name: "source", files: ["src/**/*.js"], ignores: ["src/generated/**"], rules: { "no-console": "error", "no-debugger": "warn" } },',
      '  { name: "tests", files: ["test/**/*.js"], rules: { "no-console": "off", "no-debugger": "error" } },',
      '  { name: "late source override", files: ["src/special/**/*.js"], rules: { "no-console": "off" } },',
      '  { name: "scoped ignores", ignores: ["fixtures/**"], languageOptions: { ecmaVersion: 2022 } }',
      "];",
      ""
    ].join("\n")
  );
  const outputPath = join(project, "utlint.config.json");

  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, `--output=${outputPath}`],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  const config = JSON.parse(readFileSync(outputPath, "utf8"));
  assert.equal(config[0].$schema.endsWith("/schema.json"), true);
  assert.deepEqual(config.slice(1), [
    { name: "global ignores", ignores: ["dist/"] },
    {
      name: "source",
      files: ["src/**/*.js"],
      ignores: ["src/generated/**"],
      rules: { "no-console": "error", "no-debugger": "warn" }
    },
    {
      name: "tests",
      files: ["test/**/*.js"],
      rules: { "no-console": "off", "no-debugger": "error" }
    },
    {
      name: "late source override",
      files: ["src/special/**/*.js"],
      rules: { "no-console": "off" }
    },
    { name: "scoped ignores", ignores: ["fixtures/**"], rules: {} }
  ]);

  const sourcePath = write(join(project, "src", "index.js"), "console.log('source');\ndebugger;\n");
  const testPath = write(join(project, "test", "index.js"), "console.log('test');\ndebugger;\n");
  const specialPath = write(join(project, "src", "special", "index.js"), "console.log('special');\ndebugger;\n");
  const lint = spawnSync(
    process.execPath,
    [cliPath, `--config=${outputPath}`, "--format=json", sourcePath, testPath, specialPath],
    { cwd: project, env: { ...process.env, UTOO_LINT_BIN: testBinary() }, encoding: "utf8" }
  );

  assert.equal(lint.status, 1, lint.stderr);
  const diagnostics = JSON.parse(lint.stdout).diagnostics;
  assert.deepEqual(
    diagnostics.map(({ filePath, ruleId, severity }) => ({ filePath, ruleId, severity })),
    [
      { filePath: sourcePath, ruleId: "no-debugger", severity: "warning" },
      { filePath: sourcePath, ruleId: "no-console", severity: "error" },
      { filePath: testPath, ruleId: "no-debugger", severity: "error" },
      { filePath: specialPath, ruleId: "no-debugger", severity: "warning" }
    ]
  );
});

test("migrator resolves classic relative package plugin and nested extends in order", (t) => {
  const project = createProject(t);
  const relativeConfig = write(
    join(project, "relative.cjs"),
    'module.exports = { rules: { "no-alert": "warn" } };\n'
  );
  const companyDirectory = join(project, "node_modules", "eslint-config-company");
  const companyConfig = write(
    join(companyDirectory, "index.cjs"),
    [
      "module.exports = {",
      '  extends: "./nested.json",',
      '  ignorePatterns: ["vendor/**"],',
      '  rules: { "no-debugger": "error" },',
      "  overrides: [{",
      '    files: ["test/**/*.js"],',
      '    excludedFiles: ["test/fixtures/**"],',
      '    rules: { "no-console": "off", "example/inherited": "error" }',
      "  }]",
      "};",
      ""
    ].join("\n")
  );
  const nestedConfig = write(
    join(companyDirectory, "nested.json"),
    JSON.stringify({ rules: { "no-console": "warn" } })
  );
  write(
    join(companyDirectory, "package.json"),
    JSON.stringify({ name: "eslint-config-company", main: "index.cjs" })
  );
  const pluginDirectory = join(project, "node_modules", "eslint-plugin-demo");
  const pluginConfig = write(
    join(pluginDirectory, "index.cjs"),
    'module.exports = { configs: { recommended: { rules: { "no-var": "error" } } } };\n'
  );
  write(
    join(pluginDirectory, "package.json"),
    JSON.stringify({ name: "eslint-plugin-demo", main: "index.cjs" })
  );
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      extends: ["./relative.cjs", "company", "plugin:demo/recommended"],
      rules: { "no-debugger": "off" }
    })
  );

  const result = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(result.status, 1, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout).slice(1), [
    { rules: { "no-alert": "warn" } },
    { rules: { "no-console": "warn" } },
    { ignores: ["vendor/**"] },
    { rules: { "no-debugger": "error" } },
    {
      files: ["test/**/*.js"],
      ignores: ["test/fixtures/**"],
      rules: { "no-console": "off" }
    },
    { rules: { "no-var": "error" } },
    { rules: { "no-debugger": "off" } }
  ]);

  const report = JSON.parse(result.stderr);
  assert.deepEqual(report.unsupportedRules, ["example/inherited"]);
  assert.deepEqual(report.inheritedSources, [
    { name: "./nested.json", filePath: realpathSync(nestedConfig) },
    { name: "./relative.cjs", filePath: realpathSync(relativeConfig) },
    { name: "eslint-config-company", filePath: realpathSync(companyConfig) },
    { name: "plugin:demo/recommended", filePath: realpathSync(pluginConfig) }
  ]);
  assert.deepEqual(report.unsupportedInheritedRules, [
    {
      ruleId: "example/inherited",
      sourceName: "eslint-config-company",
      sourcePath: realpathSync(companyConfig)
    }
  ]);
});

test("migrator resolves plugins from the extending shareable config", (t) => {
  const project = createProject(t);
  const configDirectory = join(project, "node_modules", "eslint-config-local-plugin");
  const configPath = write(
    join(configDirectory, "index.cjs"),
    'module.exports = { extends: "plugin:private/recommended" };\n'
  );
  write(
    join(configDirectory, "package.json"),
    JSON.stringify({ name: "eslint-config-local-plugin", main: "index.cjs" })
  );
  const pluginDirectory = join(configDirectory, "node_modules", "eslint-plugin-private");
  const pluginPath = write(
    join(pluginDirectory, "index.cjs"),
    'module.exports = { configs: { recommended: { rules: { "no-alert": "error" } } } };\n'
  );
  write(
    join(pluginDirectory, "package.json"),
    JSON.stringify({ name: "eslint-plugin-private", main: "index.cjs" })
  );
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({ extends: "local-plugin" })
  );

  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  const { $schema, ...migratedConfig } = JSON.parse(migration.stdout);
  assert.equal($schema.endsWith("/schema.json"), true);
  assert.deepEqual(migratedConfig, { rules: { "no-alert": "error" } });
  assert.deepEqual(JSON.parse(migration.stderr).inheritedSources, [
    { name: "eslint-config-local-plugin", filePath: realpathSync(configPath) },
    { name: "plugin:private/recommended", filePath: realpathSync(pluginPath) }
  ]);
});

test("migrator discovers CommonJS eslintrc files and resolves their extends", (t) => {
  const project = createProject(t);
  const baseConfig = write(
    join(project, "base.json"),
    JSON.stringify({ rules: { "no-console": "warn" } })
  );
  write(
    join(project, ".eslintrc.cjs"),
    'module.exports = { extends: "./base.json", rules: { "no-debugger": "error" } };\n'
  );

  const result = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout).slice(1), [
    { rules: { "no-console": "warn" } },
    { rules: { "no-debugger": "error" } }
  ]);
  assert.deepEqual(JSON.parse(result.stderr).inheritedSources, [
    { name: "./base.json", filePath: realpathSync(baseConfig) }
  ]);
});

test("migrator rebases classic selectors to a descendant output directory", (t) => {
  const project = createProject(t);
  write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      overrides: [{
        files: "packages/app/**/*.js",
        excludedFiles: "packages/app/generated/**",
        rules: { "no-console": "error" }
      }]
    })
  );
  const appDirectory = join(project, "packages", "app");
  mkdirSync(appDirectory, { recursive: true });
  const outputPath = join(appDirectory, "utlint.config.json");
  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--output=${outputPath}`],
    { cwd: appDirectory, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  const { $schema, ...migratedConfig } = JSON.parse(readFileSync(outputPath, "utf8"));
  assert.equal($schema.endsWith("/schema.json"), true);
  assert.deepEqual(migratedConfig, {
    files: ["**/*.js"],
    ignores: ["generated/**"],
    rules: { "no-console": "error" }
  });

  const matchingSource = write(join(appDirectory, "src", "index.js"), "console.log('matched');\n");
  write(join(appDirectory, "generated", "invalid.js"), "const = ;\n");
  const options = { cwd: appDirectory, binary: testBinary(), encoding: "utf8" };

  for (const [name, execute] of [["ESM", runCli], ["CommonJS", commonJSRunCli]]) {
    const lint = execute(["--json"], options);
    assert.equal(lint.status, 1, `${name}: ${lint.stderr}\n${lint.stdout}`);
    assert.deepEqual(
      JSON.parse(lint.stdout).diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [{ filePath: matchingSource, ruleId: "no-console" }]
    );
  }
});

test("migrator preserves rebased absolute and negated classic ignores", (t) => {
  const project = createProject(t);
  write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      ignorePatterns: [
        "dist/**",
        "!dist/keep.js",
        "packages/app/build/**",
        "!packages/app/build/keep.js",
        "packages/app/foo*/**",
        "!packages/app/foo[12]/keep.js"
      ],
      rules: { "no-console": "error" }
    })
  );
  const appDirectory = join(project, "packages", "app");
  mkdirSync(appDirectory, { recursive: true });
  const outputPath = join(appDirectory, "utlint.config.json");
  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--output=${outputPath}`],
    { cwd: appDirectory, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  const migratedConfig = JSON.parse(readFileSync(outputPath, "utf8"));
  const ignoreEntry = migratedConfig.find((entry) => entry.ignores);
  assert.deepEqual(ignoreEntry.ignores, [
    join(realpathSync(project), "dist", "**"),
    `!${join(realpathSync(project), "dist", "keep.js")}`,
    "build/**",
    "!build/keep.js",
    "foo*/**",
    "!foo[12]/keep.js"
  ]);

  const ignoredSource = write(join(project, "dist", "drop.js"), "console.log('ignored');\n");
  const keptSource = write(join(project, "dist", "keep.js"), "console.log('kept');\n");
  const canonicalIgnoredSource = realpathSync(ignoredSource);
  const canonicalKeptSource = realpathSync(keptSource);
  write(join(appDirectory, "build", "drop.js"), "console.log('ignored');\n");
  const defaultKeptSource = write(join(appDirectory, "build", "keep.js"), "console.log('kept');\n");
  write(join(appDirectory, "foo1", "drop.js"), "console.log('ignored');\n");
  const globKeptSource = write(join(appDirectory, "foo1", "keep.js"), "console.log('kept');\n");
  const options = { cwd: appDirectory, binary: testBinary(), encoding: "utf8" };

  for (const [name, execute] of [["ESM", runCli], ["CommonJS", commonJSRunCli]]) {
    const lint = execute(["--json", `--config=${outputPath}`, canonicalIgnoredSource, canonicalKeptSource], options);
    assert.equal(lint.status, 1, `${name}: ${lint.stderr}\n${lint.stdout}`);
    assert.deepEqual(
      JSON.parse(lint.stdout).diagnostics
        .filter(({ ruleId }) => ruleId)
        .map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [{ filePath: canonicalKeptSource, ruleId: "no-console" }]
    );

    const defaultLint = execute(["--json", `--config=${outputPath}`], options);
    assert.equal(defaultLint.status, 1, `${name}: ${defaultLint.stderr}\n${defaultLint.stdout}`);
    assert.deepEqual(
      JSON.parse(defaultLint.stdout).diagnostics
        .filter(({ ruleId }) => ruleId)
        .map(({ filePath, ruleId }) => ({ filePath, ruleId }))
        .sort((left, right) => left.filePath.localeCompare(right.filePath)),
      [
        { filePath: defaultKeptSource, ruleId: "no-console" },
        { filePath: globKeptSource, ruleId: "no-console" }
      ].sort((left, right) => left.filePath.localeCompare(right.filePath))
    );
  }
});

test("migrator preserves AND semantics for nested classic override extends", (t) => {
  const project = createProject(t);
  const packageDirectory = join(project, "node_modules", "eslint-config-scoped");
  write(
    join(packageDirectory, "index.json"),
    JSON.stringify({
      overrides: [{
        files: ["**/*.js", "**/*.cjs"],
        excludedFiles: "**/generated/**",
        rules: { "no-console": "error" }
      }]
    })
  );
  write(
    join(packageDirectory, "package.json"),
    JSON.stringify({ name: "eslint-config-scoped", main: "index.json" })
  );
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      overrides: [{
        files: ["src/**", "lib/**"],
        extends: "scoped"
      }]
    })
  );

  const result = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(result.status, 0, result.stderr);
  const { $schema, ...config } = JSON.parse(result.stdout);
  assert.equal($schema.endsWith("/schema.json"), true);
  assert.deepEqual(config, {
    files: [
      ["src/**", "**/*.js"],
      ["src/**", "**/*.cjs"],
      ["lib/**", "**/*.js"],
      ["lib/**", "**/*.cjs"]
    ],
    ignores: ["**/generated/**"],
    rules: { "no-console": "error" }
  });

  write(join(project, "utlint.config.json"), result.stdout);
  const matchingSource = write(join(project, "src", "index.js"), "console.log('matched');\n");
  write(join(project, "src", "invalid.ts"), "const = ;\n");
  write(join(project, "src", "generated", "invalid.js"), "const = ;\n");
  write(join(project, "test", "invalid.js"), "const = ;\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const [name, execute] of [["ESM", runCli], ["CommonJS", commonJSRunCli]]) {
    const lint = execute(["--json"], options);
    assert.equal(lint.status, 1, `${name}: ${lint.stderr}\n${lint.stdout}`);
    const report = JSON.parse(lint.stdout);
    assert.deepEqual(report.filePaths, [matchingSource]);
    assert.deepEqual(
      report.diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [{ filePath: matchingSource, ruleId: "no-console" }]
    );
  }
});

test("migrator preserves inherited rule options and classic basename override globs", (t) => {
  const project = createProject(t);
  write(
    join(project, "base.json"),
    JSON.stringify({ rules: { "no-console": ["error", { allow: ["warn"] }] } })
  );
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      extends: "./base.json",
      rules: { "no-console": "warn" },
      overrides: [
        { files: "*.js", rules: { "no-debugger": "warn" } },
        { files: "./*.cjs", rules: { "no-alert": "warn" } },
        { files: "**/*.js", excludedFiles: "test/*.js", rules: { "no-alert": "error" } }
      ]
    })
  );
  const outputPath = join(project, "utlint.config.json");

  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, `--output=${outputPath}`],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  assert.deepEqual(JSON.parse(readFileSync(outputPath, "utf8")).slice(1), [
    { rules: { "no-console": ["error", { allow: ["warn"] }] } },
    { rules: { "no-console": "warn" } },
    { files: ["**/*.js"], rules: { "no-debugger": "warn" } },
    { files: ["*.cjs"], rules: { "no-alert": "warn" } },
    { files: ["**/*.js"], ignores: ["test/*.js"], rules: { "no-alert": "error" } }
  ]);

  const nestedJavaScript = write(join(project, "src", "index.js"), "console.warn('ok');\ndebugger;\n");
  const rootCommonJS = write(join(project, "index.cjs"), "alert('root');\n");
  const nestedCommonJS = write(join(project, "src", "index.cjs"), "alert('nested');\n");
  const rootTest = write(join(project, "test", "example.js"), "alert('excluded');\n");
  const nestedTest = write(join(project, "src", "test", "example.js"), "alert('included');\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const lint = execute(["--json", nestedJavaScript, rootCommonJS, nestedCommonJS, rootTest, nestedTest], options);
    assert.equal(lint.status, 1, lint.stderr);
    const diagnostics = JSON.parse(lint.stdout).diagnostics
      .map(({ filePath, ruleId, severity }) => ({ filePath, ruleId, severity }))
      .sort((left, right) => left.filePath.localeCompare(right.filePath));
    assert.deepEqual(
      diagnostics,
      [
        { filePath: nestedJavaScript, ruleId: "no-debugger", severity: "warning" },
        { filePath: rootCommonJS, ruleId: "no-alert", severity: "warning" },
        { filePath: nestedTest, ruleId: "no-alert", severity: "error" }
      ].sort((left, right) => left.filePath.localeCompare(right.filePath))
    );
  }
});

test("migrator expands representable classic extglobs and rejects unsupported forms", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      overrides: [{ files: "**/*.@(js|ts)", rules: { "no-console": "error" } }]
    })
  );
  const outputPath = join(project, "utlint.config.json");
  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, `--output=${outputPath}`],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  const { $schema, ...migratedConfig } = JSON.parse(readFileSync(outputPath, "utf8"));
  assert.equal($schema.endsWith("/schema.json"), true);
  assert.deepEqual(migratedConfig, {
    files: ["**/*.js", "**/*.ts"],
    rules: { "no-console": "error" }
  });

  const javaScript = write(join(project, "src", "example.js"), "console.log('js');\n");
  const typeScript = write(join(project, "src", "example.ts"), "console.log('ts');\n");
  const jsx = write(join(project, "src", "example.jsx"), "console.log('jsx');\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };
  for (const [name, execute] of [["ESM", runCli], ["CommonJS", commonJSRunCli]]) {
    const lint = execute(["--json", javaScript, typeScript, jsx], options);
    assert.equal(lint.status, 1, `${name}: ${lint.stderr}\n${lint.stdout}`);
    assert.deepEqual(
      JSON.parse(lint.stdout).diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [
        { filePath: javaScript, ruleId: "no-console" },
        { filePath: typeScript, ruleId: "no-console" }
      ]
    );
  }

  const unsupportedConfig = write(
    join(project, "unsupported.eslintrc.json"),
    JSON.stringify({
      overrides: [{ files: "**/*.!(test).js", rules: { "no-console": "error" } }]
    })
  );
  const unsupported = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${unsupportedConfig}`, "--print"],
    { cwd: project, encoding: "utf8" }
  );
  assert.equal(unsupported.status, 2, unsupported.stderr);
  assert.equal(unsupported.stdout, "");
  assert.match(unsupported.stderr, /cannot migrate classic selector pattern .*only literal @\(one\|two\)/u);
});

test("migrated unscoped rules keep project-wide default lint coverage", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      rules: { "no-console": "error" },
      overrides: [{ files: "tests/**/*.js", rules: { "no-alert": "error" } }]
    })
  );
  const outputPath = join(project, "utlint.config.json");
  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, `--output=${outputPath}`],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  const sourcePath = write(join(project, "src", "app.ts"), "console.log('covered');\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const [name, execute] of [["ESM", runCli], ["CommonJS", commonJSRunCli]]) {
    const lint = execute(["--json"], options);
    assert.equal(lint.status, 1, `${name}: ${lint.stderr}\n${lint.stdout}`);
    assert.deepEqual(
      JSON.parse(lint.stdout).diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [{ filePath: sourcePath, ruleId: "no-console" }]
    );
  }
});

test("migrator propagates inherited scoped ignores to child override rules", (t) => {
  const project = createProject(t);
  const packageDirectory = join(project, "node_modules", "eslint-config-ignore-generated");
  write(
    join(packageDirectory, "index.json"),
    JSON.stringify({
      ignorePatterns: ["generated.js"],
      rules: { "no-console": "error" }
    })
  );
  write(
    join(packageDirectory, "package.json"),
    JSON.stringify({ name: "eslint-config-ignore-generated", main: "index.json" })
  );
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      overrides: [
        {
          files: "src/**/*.js",
          extends: "ignore-generated",
          rules: { "no-debugger": "error" }
        },
        {
          files: "src/**/*.js",
          rules: { "no-alert": "error" }
        }
      ]
    })
  );

  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  assert.deepEqual(JSON.parse(migration.stdout).slice(1), [
    {
      files: ["src/**/*.js"],
      ignores: ["generated.js"],
      rules: { "no-console": "error" }
    },
    {
      files: ["src/**/*.js"],
      ignores: ["generated.js"],
      rules: { "no-debugger": "error" }
    },
    {
      files: ["src/**/*.js"],
      rules: { "no-alert": "error" }
    }
  ]);

  write(join(project, "utlint.config.json"), migration.stdout);
  const generatedSource = write(
    join(project, "src", "generated.js"),
    "console.log('ignored in first chain');\ndebugger;\nalert('active sibling');\n"
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };
  for (const [name, execute] of [["ESM", runCli], ["CommonJS", commonJSRunCli]]) {
    const lint = execute(["--json", generatedSource], options);
    assert.equal(lint.status, 1, `${name}: ${lint.stderr}\n${lint.stdout}`);
    assert.deepEqual(
      JSON.parse(lint.stdout).diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [{ filePath: generatedSource, ruleId: "no-alert" }]
    );
  }
});

test("migrator isolates ignores between nested sibling override chains", (t) => {
  const project = createProject(t);
  const ignoredPackageDirectory = join(project, "node_modules", "eslint-config-nested-ignore");
  write(
    join(ignoredPackageDirectory, "index.json"),
    JSON.stringify({ ignorePatterns: ["generated.js"], rules: { "no-console": "error" } })
  );
  write(
    join(ignoredPackageDirectory, "package.json"),
    JSON.stringify({ name: "eslint-config-nested-ignore", main: "index.json" })
  );
  const nestedPackageDirectory = join(project, "node_modules", "eslint-config-nested-overrides");
  write(
    join(nestedPackageDirectory, "index.json"),
    JSON.stringify({
      overrides: [
        {
          files: "**/*.test.js",
          extends: "nested-ignore",
          rules: { "no-debugger": "error" }
        },
        {
          files: "**/*.js",
          rules: { "no-alert": "error" }
        }
      ]
    })
  );
  write(
    join(nestedPackageDirectory, "package.json"),
    JSON.stringify({ name: "eslint-config-nested-overrides", main: "index.json" })
  );
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      overrides: [{ files: "src/**", extends: "nested-overrides" }]
    })
  );
  const outputPath = join(project, "utlint.config.json");
  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, `--output=${outputPath}`],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 0, migration.stderr);
  const generatedSource = write(join(project, "src", "generated.js"), "alert('active sibling');\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };
  for (const [name, execute] of [["ESM", runCli], ["CommonJS", commonJSRunCli]]) {
    const lint = execute(["--json", generatedSource], options);
    assert.equal(lint.status, 1, `${name}: ${lint.stderr}\n${lint.stdout}`);
    assert.deepEqual(
      JSON.parse(lint.stdout).diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [{ filePath: generatedSource, ruleId: "no-alert" }]
    );
  }
});

test("migrator does not report inherited unsupported rules disabled by the child", (t) => {
  const project = createProject(t);
  const baseConfig = write(
    join(project, "base.json"),
    JSON.stringify({
      rules: {
        "example/disabled-by-child": "error",
        "example/still-enabled": "error"
      }
    })
  );
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      extends: "./base.json",
      rules: { "example/disabled-by-child": "off" }
    })
  );

  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 1, migration.stderr);
  const report = JSON.parse(migration.stderr);
  assert.deepEqual(report.unsupportedRules, ["example/still-enabled"]);
  assert.deepEqual(report.unsupportedInheritedRules, [{
    ruleId: "example/still-enabled",
    sourceName: "./base.json",
    sourcePath: realpathSync(baseConfig)
  }]);
});

test("migrator applies scoped unsupported-rule disables by coverage", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      overrides: [
        { files: "src/**/*.js", rules: { "example/disabled-broadly": "error" } },
        { files: "**/*.ts", rules: { "example/still-enabled": "error" } },
        {
          files: ["src/**/*.jsx", "test/**/*.jsx"],
          rules: { "example/disabled-in-parts": "error" }
        },
        { files: "**/*.js", rules: { "example/disabled-broadly": "off" } },
        { files: "src/**/*.ts", rules: { "example/still-enabled": "off" } },
        { files: "src/**/*.jsx", rules: { "example/disabled-in-parts": "off" } },
        { files: "test/**/*.jsx", rules: { "example/disabled-in-parts": "off" } }
      ]
    })
  );

  const migration = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(migration.status, 1, migration.stderr);
  const report = JSON.parse(migration.stderr);
  assert.deepEqual(report.unsupportedRules, ["example/still-enabled"]);
  assert.deepEqual(report.unsupportedInheritedRules, []);
});

test("migrator reports circular and unresolvable classic extends", (t) => {
  const cycleProject = createProject(t);
  const cycleConfig = write(
    join(cycleProject, ".eslintrc.json"),
    JSON.stringify({ extends: "./cycle-a.json" })
  );
  write(
    join(cycleProject, "cycle-a.json"),
    JSON.stringify({ extends: "./cycle-b.json" })
  );
  write(
    join(cycleProject, "cycle-b.json"),
    JSON.stringify({ extends: "./cycle-a.json" })
  );

  const cycle = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${cycleConfig}`, "--print"],
    { cwd: cycleProject, encoding: "utf8" }
  );
  assert.equal(cycle.status, 2, cycle.stderr);
  assert.equal(cycle.stdout, "");
  assert.match(cycle.stderr, /Circular ESLint extends chain detected: \.\/cycle-a\.json -> \.\/cycle-b\.json -> \.\/cycle-a\.json/u);

  const missingProject = createProject(t);
  const missingConfig = write(
    join(missingProject, ".eslintrc.json"),
    JSON.stringify({ extends: "missing-shareable" })
  );
  const missing = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${missingConfig}`, "--print"],
    { cwd: missingProject, encoding: "utf8" }
  );
  assert.equal(missing.status, 2, missing.stderr);
  assert.equal(missing.stdout, "");
  assert.match(missing.stderr, /Failed to load config "missing-shareable" to extend from/u);
  assert.match(missing.stderr, /Referenced from:/u);
});

test("migrator config stdout does not corrupt its serialized input", (t) => {
  const project = createProject(t);
  write(
    join(project, "eslint.config.mjs"),
    'console.log("migrate notice");\nexport default [{ rules: { "no-debugger": "error" } }];\n'
  );

  const result = spawnSync(process.execPath, [cliPath, "migrate", "eslint", "--print"], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout)[1].rules["no-debugger"], "error");
});

test("migrator omits disabled unsupported rules from the blocking report", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, "eslint.config.json"),
    JSON.stringify({
      rules: {
        "example/off-string": "off",
        "example/off-number": 0,
        "example/off-boolean": false,
        "example/off-string-array": ["off", { reason: "disabled" }],
        "example/off-number-array": [0, { reason: "disabled" }],
        "example/off-boolean-array": [false, { reason: "disabled" }],
        "no-debugger": "error"
      }
    })
  );

  const result = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout).rules, { "no-debugger": "error" });
  assert.deepEqual(JSON.parse(result.stderr).unsupportedRules, []);
});

test("migrator still blocks on enabled unsupported rules", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, "eslint.config.json"),
    JSON.stringify({
      rules: {
        "example/disabled": "off",
        "example/enabled": ["warn", { reason: "still active" }]
      }
    })
  );

  const result = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(result.status, 1, result.stderr);
  assert.deepEqual(JSON.parse(result.stderr).unsupportedRules, ["example/enabled"]);
});

test("migrator translates reviewed @eslint-react aliases", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      rules: {
        "@eslint-react/no-array-index-key": ["warn"],
        "@eslint-react/dom-no-find-dom-node": 2,
        "@eslint-react/dom-no-render-return-value": false,
        "@eslint-react/dom-no-void-elements-with-children": ["error"],
        "@eslint-react/rules-of-hooks": "error"
      }
    })
  );

  const result = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout).rules, {
    "react-hooks/rules-of-hooks": "error",
    "react/no-array-index-key": ["warn"],
    "react/no-find-dom-node": 2,
    "react/no-render-return-value": false,
    "react/void-dom-elements-no-children": ["error"]
  });
  const report = JSON.parse(result.stderr);
  assert.deepEqual(report.unsupportedRules, []);
  assert.deepEqual(report.translatedRules, [
    { sourceRuleId: "@eslint-react/dom-no-find-dom-node", targetRuleId: "react/no-find-dom-node" },
    { sourceRuleId: "@eslint-react/dom-no-render-return-value", targetRuleId: "react/no-render-return-value" },
    { sourceRuleId: "@eslint-react/dom-no-void-elements-with-children", targetRuleId: "react/void-dom-elements-no-children" },
    { sourceRuleId: "@eslint-react/no-array-index-key", targetRuleId: "react/no-array-index-key" },
    { sourceRuleId: "@eslint-react/rules-of-hooks", targetRuleId: "react-hooks/rules-of-hooks" }
  ]);
});

test("migrator preserves enabled disabled and option-bearing reviewed aliases", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, "eslint.config.mjs"),
    [
      "export default [",
      "  { rules: {",
      '    "no-native-reassign": ["warn", { exceptions: ["Object"] }],',
      '    "@typescript-eslint/no-invalid-this": ["error", { capIsConstructor: false }]',
      "  } },",
      '  { files: ["test/**/*.ts"], rules: {',
      '    "no-native-reassign": 0,',
      '    "@typescript-eslint/no-invalid-this": "off"',
      "  } }",
      "];",
      ""
    ].join("\n")
  );

  const result = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(result.status, 0, result.stderr);
  const config = JSON.parse(result.stdout);
  assert.deepEqual(config.slice(1), [
    {
      rules: {
        "no-global-assign": ["warn", { exceptions: ["Object"] }],
        "no-invalid-this": ["error", { capIsConstructor: false }]
      }
    },
    {
      files: ["test/**/*.ts"],
      rules: {
        "no-global-assign": 0,
        "no-invalid-this": "off"
      }
    }
  ]);
  const report = JSON.parse(result.stderr);
  assert.deepEqual(report.supportedRules, ["no-global-assign", "no-invalid-this"]);
  assert.deepEqual(report.unsupportedRules, []);
  assert.deepEqual(report.translatedRules, [
    { sourceRuleId: "@typescript-eslint/no-invalid-this", targetRuleId: "no-invalid-this" },
    { sourceRuleId: "no-native-reassign", targetRuleId: "no-global-assign" }
  ]);
});

test("migrator does not infer unreviewed aliases without equivalent rules", (t) => {
  const project = createProject(t);
  const eslintConfig = write(
    join(project, ".eslintrc.json"),
    JSON.stringify({
      rules: {
        "@eslint-react/no-missing-key": "error",
        "@eslint-react/dom-no-render": "warn",
        "@typescript-eslint/no-invalid-this-extra": "error",
        "no-native-reassignment": "warn"
      }
    })
  );

  const result = spawnSync(
    process.execPath,
    [cliPath, "migrate", "eslint", `--from=${eslintConfig}`, "--print", "--report=json"],
    { cwd: project, encoding: "utf8" }
  );

  assert.equal(result.status, 1, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout).rules, {});
  const report = JSON.parse(result.stderr);
  assert.deepEqual(report.translatedRules, []);
  assert.deepEqual(report.unsupportedRules, [
    "@eslint-react/dom-no-render",
    "@eslint-react/no-missing-key",
    "@typescript-eslint/no-invalid-this-extra",
    "no-native-reassignment"
  ]);
});

test("ESLint.findConfigFile prefers utlint.config.ts over utlint.config.json in the same directory", async (t) => {
  const project = createProject(t);
  const typescriptConfig = write(join(project, "utlint.config.ts"));
  write(join(project, "utlint.config.json"));

  const eslint = new ESLint({ cwd: project });

  assert.equal(await eslint.findConfigFile(), typescriptConfig);
});

test("ESLint.findConfigFile searches ancestors from a file path", async (t) => {
  const project = createProject(t);
  const configPath = write(join(project, "utlint.config.json"));
  const sourcePath = write(join(project, "packages", "app", "src", "index.ts"), "export {};\n");

  const eslint = new ESLint({ cwd: join(project, "packages", "app") });

  assert.equal(await eslint.findConfigFile(sourcePath), configPath);
});

test("ESLint.findConfigFile prefers the nearest config directory before filename priority", async (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.ts"));
  const nearestConfig = write(join(project, "packages", "app", "utlint.config.json"));
  const sourcePath = write(join(project, "packages", "app", "src", "index.ts"), "export {};\n");

  const eslint = new ESLint({ cwd: project });

  assert.equal(await eslint.findConfigFile(sourcePath), nearestConfig);
});

test("CLI loads utlint.config.ts and --no-config bypasses it", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "src", "index.ts"), "debugger;\n");
  write(
    join(project, "utlint.config.ts"),
    [
      "type UtlintConfig = { rules: Record<string, \"off\" | \"error\"> };",
      "const config: UtlintConfig = { rules: { \"no-debugger\": \"off\" } };",
      "export default config;",
      ""
    ].join("\n")
  );

  const env = {
    ...process.env,
    UTOO_LINT_BIN: testBinary()
  };
  const configured = spawnSync(process.execPath, [cliPath, sourcePath], {
    cwd: project,
    env,
    encoding: "utf8"
  });
  const unconfigured = spawnSync(process.execPath, [cliPath, "--no-config", sourcePath], {
    cwd: project,
    env,
    encoding: "utf8"
  });

  assert.equal(configured.error, undefined);
  assert.equal(configured.status, 0, configured.stderr);
  assert.equal(unconfigured.error, undefined);
  assert.equal(unconfigured.status, 0, unconfigured.stderr);
  assert.match(unconfigured.stderr, /no-debugger/);
});

test("ESM and CommonJS CLI evaluate a TypeScript config once per lint invocation", (t) => {
  const project = createProject(t);
  const counterPath = write(join(project, "config-load-count.txt"), "0");
  write(
    join(project, "utlint.config.ts"),
    [
      'import { readFileSync, writeFileSync } from "node:fs";',
      `const counterPath = ${JSON.stringify(counterPath)};`,
      'writeFileSync(counterPath, String(Number(readFileSync(counterPath, "utf8")) + 1));',
      'export default { rules: { "no-debugger": "off" } };',
      ""
    ].join("\n")
  );
  const firstSource = write(join(project, "src", "first.ts"), "debugger;\n");
  const secondSource = write(join(project, "src", "second.ts"), "debugger;\n");

  const options = {
    cwd: project,
    binary: testBinary()
  };
  const firstResult = runCli([firstSource, secondSource], options);
  const secondResult = commonJSRunCli([firstSource, secondSource], options);

  assert.equal(firstResult.status, 0, firstResult.stderr);
  assert.equal(secondResult.status, 0, secondResult.stderr);
  assert.equal(readFileSync(counterPath, "utf8"), "2");
});

test("CommonJS API discovers and loads utlint.config.ts", async (t) => {
  const project = createProject(t);
  const configPath = write(
    join(project, "utlint.config.ts"),
    "export default { rules: { \"no-debugger\": \"off\" } };\n"
  );
  const sourcePath = write(join(project, "src", "index.ts"), "debugger;\n");
  const eslint = new CommonJSESLint({ cwd: project, binary: testBinary() });

  assert.equal(await eslint.findConfigFile(sourcePath), configPath);
  const results = await eslint.lintFiles([sourcePath]);
  assert.equal(results[0].messages.length, 0);
});

test("legacy config names remain discoverable after the canonical names", async (t) => {
  for (const filename of ["utoo.json", "utoo-lint.json"]) {
    const project = createProject(t);
    const configPath = write(join(project, filename));
    const eslint = new ESLint({ cwd: project });
    assert.equal(await eslint.findConfigFile(), configPath);
  }
});

test("explicit config and --no-config keep last-argument-wins semantics", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.ts"), "debugger;\n");
  const configPath = write(
    join(project, "custom.config.ts"),
    "export default { rules: { \"no-debugger\": \"off\" } };\n"
  );
  const env = { ...process.env, UTOO_LINT_BIN: testBinary() };

  const configLast = spawnSync(
    process.execPath,
    [cliPath, "--no-config", `--config=${configPath}`, sourcePath],
    { cwd: project, env, encoding: "utf8" }
  );
  const noConfigLast = spawnSync(
    process.execPath,
    [cliPath, `--config=${configPath}`, "--no-config", sourcePath],
    { cwd: project, env, encoding: "utf8" }
  );

  assert.equal(configLast.status, 0, configLast.stderr);
  assert.equal(noConfigLast.status, 0, noConfigLast.stderr);
});

test("split -c loads an explicit TypeScript config", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.ts"), "debugger;\n");
  const configPath = write(
    join(project, "custom.config.ts"),
    'export default { rules: { "no-debugger": "off" } };\n'
  );
  const result = spawnSync(process.execPath, [cliPath, "-c", configPath, sourcePath], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
});

test("invalid TypeScript config failures name the selected file", (t) => {
  const project = createProject(t);
  const configPath = write(join(project, "utlint.config.ts"), "throw new Error(\"config exploded\");\n");
  const sourcePath = write(join(project, "index.ts"), "export {};\n");
  const result = spawnSync(process.execPath, [cliPath, sourcePath], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, new RegExp(configPath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(result.stderr, /config exploded/);
});

test("TypeScript config stdout does not corrupt the serialized config", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    'console.log("config notice");\nexport default { rules: { "no-debugger": "off" } };\n'
  );
  const sourcePath = write(join(project, "index.ts"), "debugger;\n");

  const result = spawnSync(process.execPath, [cliPath, sourcePath], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stderr, /unable to read config|Unexpected token/);
});

test("a broken higher-priority TypeScript config does not fall through to JSON", (t) => {
  const project = createProject(t);
  const configPath = write(join(project, "utlint.config.ts"), "throw new Error(\"selected ts failed\");\n");
  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "off" } }\n');
  const sourcePath = write(join(project, "index.ts"), "debugger;\n");

  const result = spawnSync(process.execPath, [cliPath, sourcePath], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, new RegExp(configPath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(result.stderr, /selected ts failed/);
});

test("raw native binary discovers utlint.config.json in an ancestor", (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "off" } }\n');
  const packageDirectory = join(project, "packages", "app");
  const sourcePath = write(join(packageDirectory, "index.ts"), "debugger;\n");
  const result = spawnSync(testBinary(), [sourcePath], {
    cwd: packageDirectory,
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
});

test("raw native binary treats configured rules as the complete rule set", (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "error" } }\n');
  const sourcePath = write(join(project, "index.js"), "debugger;\nconst unused = 1;\n");

  const result = spawnSync(testBinary(), ["--format=json", sourcePath], {
    cwd: project,
    encoding: "utf8"
  });
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 1, result.stderr);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.ruleId), ["no-debugger"]);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.severity), ["error"]);
});

test("raw native binary reports configured warnings without failing", (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "warn" } }\n');
  const sourcePath = write(join(project, "index.js"), "debugger;\n");

  const result = spawnSync(testBinary(), ["--format=json", sourcePath], {
    cwd: project,
    encoding: "utf8"
  });
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.ruleId), ["no-debugger"]);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.severity), ["warning"]);
});

test("raw native binary groups text diagnostics and supports color overrides", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.js"), 'debugger;\nconsole.log("x");\n');

  const plain = spawnSync(
    testBinary(),
    ["--no-color", "--no-config", "--rules=no-debugger,no-console", sourcePath],
    { cwd: project, encoding: "utf8" }
  );
  assert.equal(plain.status, 0, plain.stderr);
  assert.doesNotMatch(plain.stderr, /\u001b\[/);
  assert.equal(plain.stderr.match(new RegExp(sourcePath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g"))?.length, 1);
  assert.match(plain.stderr, /^\s+1:1\s+warning\s+Unexpected debugger statement\.\s+no-debugger$/m);
  assert.match(plain.stderr, /^\s+2:1\s+warning\s+Unexpected console statement\.\s+no-console$/m);
  assert.match(plain.stderr, /✖ 2 problems \(0 errors, 2 warnings\)/);

  const colored = spawnSync(
    testBinary(),
    ["--color", "--no-config", "--rules=no-debugger", sourcePath],
    { cwd: project, encoding: "utf8", env: { ...process.env, NO_COLOR: "1" } }
  );
  assert.equal(colored.status, 0, colored.stderr);
  assert.match(colored.stderr, /\u001b\[1m/);
  assert.match(colored.stderr, /\u001b\[33mwarning/);

  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "error", "no-console": "warn" } }\n');
  const mixed = spawnSync(testBinary(), ["--no-color", sourcePath], {
    cwd: project,
    encoding: "utf8"
  });
  assert.equal(mixed.status, 1, mixed.stderr);
  assert.match(mixed.stderr, /✖ 2 problems \(1 error, 1 warning\)/);
});

test("raw native binary gives clean and fixable text summaries", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.js"), "const value = 1;\n");

  const clean = spawnSync(testBinary(), ["--no-color", "--no-config", "--rules=no-debugger", sourcePath], {
    cwd: project,
    encoding: "utf8"
  });
  assert.equal(clean.status, 0, clean.stderr);
  assert.equal(clean.stderr, "✓ 1 file checked, no problems found\n");

  writeFileSync(sourcePath, "const value = 1;;\n");
  const fixable = spawnSync(testBinary(), ["--no-color", "--no-config", "--rules=no-extra-semi", sourcePath], {
    cwd: project,
    encoding: "utf8"
  });
  assert.equal(fixable.status, 0, fixable.stderr);
  assert.match(fixable.stderr, /1 problem potentially fixable with the `--fix` option\./);
});

test("raw native binary applies array and numeric config severities", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.js"), "debugger;\n");

  for (const [config, expectedSeverity, expectedStatus] of [
    ['["warn"]', "warning", 0],
    ["1", "warning", 0],
    ['["error"]', "error", 1],
    ["2", "error", 1]
  ]) {
    write(join(project, "utlint.config.json"), `{ "rules": { "no-debugger": ${config} } }\n`);
    const result = spawnSync(testBinary(), ["--format=json", sourcePath], {
      cwd: project,
      encoding: "utf8"
    });
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, expectedStatus, result.stderr);
    assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.severity), [expectedSeverity]);
  }
});

test("raw native binary accepts duplicate names in --rules without changing severity", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.js"), "debugger;\n");

  const result = spawnSync(
    testBinary(),
    ["--no-config", "--rules=no-debugger,no-debugger", "--format=json", sourcePath],
    { cwd: project, encoding: "utf8" }
  );
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.ruleId), ["no-debugger"]);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.severity), ["warning"]);
});

test("raw native binary counts JSX tags as uses for isolated unused-variable rules", (t) => {
  const project = createProject(t);
  const sourcePath = write(
    join(project, "fixture.tsx"),
    [
      "function Header() {",
      "  return <header>Utoo</header>;",
      "}",
      "",
      "export function App() {",
      "  return <Header />;",
      "}",
      ""
    ].join("\n")
  );

  for (const rule of ["no-unused-vars", "@typescript-eslint/no-unused-vars"]) {
    const result = spawnSync(
      testBinary(),
      ["--no-config", `--rules=${rule}`, "--format=json", sourcePath],
      { cwd: project, encoding: "utf8" }
    );
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(report.diagnostics, [], rule);
  }
});

test("raw native binary counts JSX member roots as uses for isolated unused-variable rules", (t) => {
  const project = createProject(t);
  const sourcePath = write(
    join(project, "fixture.tsx"),
    [
      'import { motion } from "framer-motion";',
      "",
      "export function App() {",
      "  return <motion.div>Utoo</motion.div>;",
      "}",
      ""
    ].join("\n")
  );

  for (const rule of ["no-unused-vars", "@typescript-eslint/no-unused-vars"]) {
    const result = spawnSync(
      testBinary(),
      ["--no-config", `--rules=${rule}`, "--format=json", sourcePath],
      { cwd: project, encoding: "utf8" }
    );
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(report.diagnostics, [], rule);
  }
});

test("raw native binary keeps parse errors fatal with an empty rules config", (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.json"));
  const sourcePath = write(join(project, "index.js"), "const = ;\n");

  const result = spawnSync(testBinary(), ["--format=json", sourcePath], {
    cwd: project,
    encoding: "utf8"
  });
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 1, result.stderr);
  assert.ok(report.diagnostics.some((diagnostic) => diagnostic.ruleId === "parse" && diagnostic.severity === "error"));
});

test("raw native binary enables no rules for an empty config", (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.json"));
  const sourcePath = write(join(project, "index.js"), "debugger;\nconst unused = 1;\n");

  const result = spawnSync(testBinary(), ["--format=json", sourcePath], {
    cwd: project,
    encoding: "utf8"
  });
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(report.diagnostics, []);
});

test("raw native binary keeps default rules when config discovery is disabled", (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.json"));
  const sourcePath = write(join(project, "index.js"), "debugger;\n");

  const result = spawnSync(testBinary(), ["--no-config", "--format=json", sourcePath], {
    cwd: project,
    encoding: "utf8"
  });
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.ruleId), ["no-debugger"]);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.severity), ["warning"]);
});

test("ESM API loads an ancestor utlint.config.json", async (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "off" } }\n');
  const appDirectory = join(project, "packages", "app");
  const sourcePath = write(join(appDirectory, "index.ts"), "debugger;\n");
  const eslint = new ESLint({ cwd: appDirectory, binary: testBinary() });

  const results = await eslint.lintFiles([sourcePath]);

  assert.equal(results[0].messages.length, 0);
});

test("ancestor config patterns are relative to the config directory", async (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({
      files: ["packages/app/src/**/*.ts"],
      rules: { "no-debugger": "off" }
    })
  );
  const appDirectory = join(project, "packages", "app");
  const sourcePath = write(join(appDirectory, "src", "index.ts"), "debugger;\n");
  const eslint = new ESLint({ cwd: appDirectory, binary: testBinary() });

  const config = await eslint.calculateConfigForFile(sourcePath);

  assert.deepEqual(config.rules["no-debugger"], [0]);
});

test("CLI resolves ancestor files and ignores from the config directory", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [{",
      '  files: ["packages/app/src/**/*.ts"],',
      '  ignores: ["packages/app/src/ignored.ts"],',
      '  rules: { "no-debugger": "error" }',
      "}];",
      ""
    ].join("\n")
  );
  const appDirectory = join(project, "packages", "app");
  write(join(appDirectory, "src", "index.ts"), "debugger;\n");
  write(join(appDirectory, "src", "ignored.ts"), "debugger;\n");

  const result = spawnSync(process.execPath, [cliPath], {
    cwd: appDirectory,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /src\/index\.ts/);
  assert.doesNotMatch(result.stderr, /src\/ignored\.ts/);
});

test("same-directory utlint.config.ts behavior wins over utlint.config.json", async (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.ts"), 'export default { rules: { "no-debugger": "off" } };\n');
  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "error" } }\n');
  const sourcePath = write(join(project, "index.ts"), "debugger;\n");
  const eslint = new ESLint({ cwd: project, binary: testBinary() });

  const results = await eslint.lintFiles([sourcePath]);

  assert.equal(results[0].messages.length, 0);
});

test("a nearer legacy config owns the file before a parent canonical config", async (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.ts"), 'export default { rules: { "no-debugger": "error" } };\n');
  const appDirectory = join(project, "packages", "app");
  write(join(appDirectory, "utoo.json"), '{ "rules": { "no-debugger": "off" } }\n');
  const sourcePath = write(join(appDirectory, "index.ts"), "debugger;\n");
  const eslint = new ESLint({ cwd: appDirectory, binary: testBinary() });

  const results = await eslint.lintFiles([sourcePath]);

  assert.equal(results[0].messages.length, 0);
});

test("utlint.config.ts can import defineConfig and provide default files", (t) => {
  const project = createProject(t);
  const packageLinkDirectory = join(project, "node_modules", "@utoo");
  mkdirSync(packageLinkDirectory, { recursive: true });
  symlinkSync(packageDirectory, join(packageLinkDirectory, "lint"), "dir");
  write(join(project, "src", "index.ts"), "debugger;\n");
  write(
    join(project, "utlint.config.ts"),
    [
      'import { defineConfig } from "@utoo/lint/config";',
      "type Severity = \"off\" | \"error\";",
      "const severity: Severity = \"off\";",
      "export default defineConfig({",
      '  files: ["src/**/*.ts"],',
      '  rules: { "no-debugger": severity }',
      "});",
      ""
    ].join("\n")
  );

  const result = spawnSync(process.execPath, [cliPath], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
});

test("globalIgnores prunes default targets while config-entry ignores stay scoped", (t) => {
  const project = createProject(t);
  const packageLinkDirectory = join(project, "node_modules", "@utoo");
  mkdirSync(packageLinkDirectory, { recursive: true });
  symlinkSync(packageDirectory, join(packageLinkDirectory, "lint"), "dir");
  write(join(project, "dist", "index.ts"), "debugger;\n");
  write(join(project, ".next", "index.ts"), "debugger;\n");
  write(join(project, "packages", "app", "generated", "index.ts"), "debugger;\n");
  write(join(project, "src", "scoped", "index.ts"), "debugger;\n");
  write(
    join(project, "utlint.config.ts"),
    [
      'import { defineConfig, globalIgnores } from "@utoo/lint/config";',
      "export default defineConfig(",
      '  globalIgnores(["dist/", ".next/", "**/generated/"]),',
      '  { ignores: ["src/scoped/"], rules: { "no-debugger": "off" } },',
      '  { files: ["**/*.ts"], rules: { "no-debugger": "error" } },',
      ");",
      ""
    ].join("\n")
  );

  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute([], {
      cwd: project,
      binary: testBinary(),
      encoding: "utf8"
    });

    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /src\/scoped\/index\.ts/);
    assert.doesNotMatch(result.stderr, /dist\/index\.ts/);
    assert.doesNotMatch(result.stderr, /\.next\/index\.ts/);
    assert.doesNotMatch(result.stderr, /generated\/index\.ts/);
  }
});

test("--rules overrides the selected project config", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.ts"), "debugger;\n");
  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "off" } }\n');

  const result = spawnSync(process.execPath, [cliPath, "--rules=no-debugger", sourcePath], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /no-debugger/);
});

test("utoo-lint text output groups diagnostics by file and summarizes severities", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "src", "index.js"), 'debugger;\nconsole.log("x");\n');

  const result = runCli(
    ["--no-color", "--no-config", "--rules=no-debugger,no-console", sourcePath],
    { cwd: project, binary: testBinary(), encoding: "utf8" }
  );

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "");
  assert.doesNotMatch(result.stderr, /\u001b\[/);
  assert.equal(result.stderr.match(new RegExp(sourcePath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g"))?.length, 1);
  assert.match(result.stderr, /^\s+1:1\s+warning\s+Unexpected debugger statement\.\s+no-debugger$/m);
  assert.match(result.stderr, /^\s+2:1\s+warning\s+Unexpected console statement\.\s+no-console$/m);
  assert.match(result.stderr, /✖ 2 problems \(0 errors, 2 warnings\)/);
  assert.match(result.stderr, /1 file checked/);

  write(join(project, "utlint.config.json"), '{ "rules": { "no-debugger": "error", "no-console": "warn" } }\n');
  const mixed = runCli(["--no-color", sourcePath], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8"
  });
  assert.equal(mixed.status, 1, mixed.stderr);
  assert.match(mixed.stderr, /✖ 2 problems \(1 error, 1 warning\)/);
});

test("utoo-lint text output reports clean runs and supports forced color", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.js"), "const value = 1;\n");

  const clean = runCli(["--no-color", "--no-config", "--rules=no-debugger", sourcePath], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8"
  });
  assert.equal(clean.status, 0, clean.stderr);
  assert.equal(clean.stderr, "✓ 1 file checked, no problems found\n");

  writeFileSync(sourcePath, "debugger;\n");
  const colored = runCli(["--color", "--no-config", "--rules=no-debugger", sourcePath], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8",
    env: { NO_COLOR: "1" }
  });
  assert.equal(colored.status, 0, colored.stderr);
  assert.match(colored.stderr, /\u001b\[1m/);
  assert.match(colored.stderr, /\u001b\[33mwarning/);
});

test("utoo-lint text output points out autofixable problems", (t) => {
  const project = createProject(t);
  const sourcePath = write(join(project, "index.js"), "const value = 1;;\n");

  const result = runCli(["--no-color", "--no-config", "--rules=no-extra-semi", sourcePath], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /1 problem potentially fixable with the `--fix` option\./);
});

test("later flat config entries can turn a rule back on", async (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { rules: { "no-debugger": "error" } },',
      '  { files: ["src/**/*.ts"], rules: { "no-debugger": "off" } }',
      "];",
      ""
    ].join("\n")
  );
  const disabledSource = write(join(project, "src", "index.ts"), "debugger;\n");
  const enabledSource = write(join(project, "test", "index.ts"), "debugger;\n");
  const eslint = new ESLint({ cwd: project, binary: testBinary() });

  const results = await eslint.lintFiles([disabledSource, enabledSource]);
  const resultByPath = new Map(results.map((result) => [result.filePath, result]));

  assert.equal(resultByPath.get(disabledSource).messages.length, 0);
  assert.match(resultByPath.get(enabledSource).messages[0].ruleId, /no-debugger/);
});

test("flat config rules remain active when the last matching entry disables another file", async (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      'export default [{ files: ["test/**/*.ts"], rules: { "no-debugger": "error" } },',
      '  { files: ["src/**/*.ts"], rules: { "no-debugger": "off" } }];',
      ""
    ].join("\n")
  );
  const disabledSource = write(join(project, "src", "index.ts"), "debugger;\n");
  const enabledSource = write(join(project, "test", "index.ts"), "debugger;\n");
  const eslint = new ESLint({ cwd: project, binary: testBinary() });

  const results = await eslint.lintFiles([disabledSource, enabledSource]);
  const resultByPath = new Map(results.map((result) => [result.filePath, result]));

  assert.equal(resultByPath.get(disabledSource).messages.length, 0);
  assert.match(resultByPath.get(enabledSource).messages[0].ruleId, /no-debugger/);
});

test("a flat config does not leak native default rules that it never enables", async (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify([{ rules: { "no-console": "error" } }])
  );
  const sourcePath = write(join(project, "index.ts"), "debugger;\n");
  const eslint = new ESLint({ cwd: project, binary: testBinary() });

  const results = await eslint.lintFiles([sourcePath]);

  assert.equal(results[0].messages.length, 0);
});

test("ESM and CommonJS register and disable unselected react/no-direct-mutation-state", async (t) => {
  const ruleId = "react/no-direct-mutation-state";
  for (const LinterImplementation of [Linter, CommonJSLinter]) {
    assert.equal(new LinterImplementation().getRules().has(ruleId), true);
  }

  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "no-console": "error" } })
  );
  const sourcePath = write(
    join(project, "index.js"),
    "class View extends React.Component { update() { this.state.count = 1; } }\n"
  );

  for (const ESLintImplementation of [ESLint, CommonJSESLint]) {
    const eslint = new ESLintImplementation({ cwd: project, binary: testBinary() });
    const [result] = await eslint.lintFiles([sourcePath]);
    assert.equal(result.messages.length, 0);
  }
});

test("flat config rule options are applied to the matching files", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-console": ["error", { allow: ["warn"] }] } },',
      '  { files: ["test/**/*.ts"], rules: { "no-console": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const allowedSource = write(join(project, "src", "index.ts"), 'console.warn("x");\n');
  const reportedSource = write(join(project, "test", "index.ts"), 'console.warn("x");\n');

  const result = runCli([allowedSource, reportedSource], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8"
  });

  assert.equal(result.status, 1, result.stderr);
  assert.doesNotMatch(result.stderr, /src\/index\.ts/);
  assert.match(result.stderr, /test\/index\.ts/);
});

test("ESM and CommonJS flat config nested file selectors use AND semantics", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify([
      { rules: { "no-console": "off" } },
      { files: [["src/**", "**/*.js"]], rules: { "no-console": "error" } }
    ])
  );
  const matchingSource = write(join(project, "src", "index.js"), "console.log(1);\n");
  const wrongExtension = write(join(project, "src", "index.ts"), "console.log(1);\n");
  const wrongDirectory = write(join(project, "test", "index.js"), "console.log(1);\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute(["--json", matchingSource, wrongExtension, wrongDirectory], options);
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, 1, result.stderr);
    assert.deepEqual(
      report.diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [{ filePath: matchingSource, ruleId: "no-console" }]
    );
  }
});

test("flat config autofixes only files whose matched config enables the rule", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify([
      { files: ["src/**/*.ts"], rules: { "no-extra-semi": "off" } },
      { files: ["test/**/*.ts"], rules: { "no-extra-semi": "error" } }
    ])
  );
  const untouchedSource = write(join(project, "src", "index.ts"), "const value = 1;;\n");
  const fixedSource = write(join(project, "test", "index.ts"), "const value = 1;;\n");

  const result = runCli(["--fix", untouchedSource, fixedSource], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(untouchedSource, "utf8"), "const value = 1;;\n");
  assert.equal(readFileSync(fixedSource, "utf8"), "const value = 1;\n");
});

test("ESM and CommonJS runCli honor object configs across multiple config roots", (t) => {
  const project = createProject(t);
  const appSource = write(join(project, "packages", "app", "index.js"), "debugger;\n");
  const toolingSource = write(join(project, "packages", "tooling", "index.js"), "console.log(1);\n");
  write(
    join(project, "packages", "app", "utlint.config.json"),
    JSON.stringify({ rules: { "no-debugger": "error" } })
  );
  write(
    join(project, "packages", "tooling", "utlint.config.json"),
    JSON.stringify({ rules: { "no-console": "error" } })
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute(["--json", appSource, toolingSource], options);
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, 1, result.stderr);
    assert.deepEqual(
      report.diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })),
      [
        { filePath: appSource, ruleId: "no-debugger" },
        { filePath: toolingSource, ruleId: "no-console" }
      ]
    );
  }
});

for (const [name, targets] of [
  ["directory", ["src", "test"]],
  ["glob", ["src/**/*.js", "test/**/*.js"]]
]) {
  test(`flat config autofix grouping expands ${name} targets before matching`, (t) => {
    const project = createProject(t);
    write(
      join(project, "utlint.config.json"),
      JSON.stringify([
        { files: ["src/**/*.js"], rules: { "no-extra-semi": "off" } },
        { files: ["test/**/*.js"], rules: { "no-extra-semi": "error" } }
      ])
    );
    const untouchedSource = write(join(project, "src", "index.js"), "foo();;\n");
    const fixedSource = write(join(project, "test", "index.js"), "foo();;\n");

    const result = runCli(["--fix", ...targets], {
      cwd: project,
      binary: testBinary(),
      encoding: "utf8"
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(untouchedSource, "utf8"), "foo();;\n");
    assert.equal(readFileSync(fixedSource, "utf8"), "foo();\n");
  });
}

test("an unmatched flat config entry means no rules instead of native defaults", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify([{ files: ["test/**/*.js"], rules: { "no-extra-semi": "error" } }])
  );
  const sourcePath = write(join(project, "src", "index.js"), "foo();;\n");

  const result = runCli(["--fix-dry-run", "--json", sourcePath], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8"
  });
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(report.diagnostics, []);
  assert.deepEqual(report.outputs, []);
  assert.equal(readFileSync(sourcePath, "utf8"), "foo();;\n");
});

test("ESM and CommonJS object configs do not leak native default dry-run fixes", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "no-debugger": "error" } })
  );
  const sourcePath = write(join(project, "index.js"), "foo();;\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute(["--fix-dry-run", "--json", sourcePath], options);
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(report.diagnostics, []);
    assert.deepEqual(report.outputs, []);
    assert.equal(readFileSync(sourcePath, "utf8"), "foo();;\n");
  }
});

test("CLI --rules enables exactly the requested rules after project config", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "no-debugger": "off", "no-console": "error" } })
  );
  const sourcePath = write(join(project, "index.js"), "debugger;\nconsole.log(1);\nfoo();;\n");

  const result = spawnSync(
    process.execPath,
    [cliPath, "--rules=no-debugger", "--fix-dry-run", "--json", sourcePath],
    {
      cwd: project,
      env: { ...process.env, UTOO_LINT_BIN: testBinary() },
      encoding: "utf8"
    }
  );
  const report = JSON.parse(result.stdout);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.ruleId), ["no-debugger"]);
  assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.severity), ["warning"]);
  assert.deepEqual(report.outputs, []);
  assert.equal(readFileSync(sourcePath, "utf8"), "debugger;\nconsole.log(1);\nfoo();;\n");
});

test("project config and CLI --rules enable jest/no-conditional-expect", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "jest/no-conditional-expect": "error" } })
  );
  const sourcePath = write(
    join(project, "conditional.test.js"),
    "test('conditional', () => { if (enabled) expect(value).toBeDefined(); });\n"
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-conditional-expect", severity: "error" }
    ]);

    const isolated = execute(
      ["--no-config", "--rules=jest/no-conditional-expect", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.deepEqual(isolatedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-conditional-expect", severity: "warning" }
    ]);
  }
});

test("jest/no-deprecated-functions uses project settings, auto detection, and fixes", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({
      settings: { jest: { version: "21.4.0" } },
      rules: { "jest/no-deprecated-functions": "error" }
    })
  );
  write(join(project, "node_modules", "jest", "package.json"), JSON.stringify({ version: "22.2.0" }));
  const source = [
    'require.requireActual("module");',
    "jest.runTimersToTime(1000);",
    'jest.genMockFromModule("module");',
    ""
  ].join("\n");
  const sourcePath = write(join(project, "deprecated.test.js"), source);
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-deprecated-functions", severity: "error" }
    ]);

    const selected = execute(["--rules=jest/no-deprecated-functions", "--json", sourcePath], options);
    const selectedReport = JSON.parse(selected.stdout);
    assert.equal(selected.status, 0, selected.stderr);
    assert.deepEqual(selectedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-deprecated-functions", severity: "warning" }
    ]);

    const isolated = execute(
      ["--no-config", "--rules=jest/no-deprecated-functions", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.equal(isolatedReport.diagnostics.length, 2);
    assert.ok(isolatedReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/no-deprecated-functions" && severity === "warning"
    ));

    const dryRun = execute(["--fix-dry-run", "--json", sourcePath], options);
    const dryRunReport = JSON.parse(dryRun.stdout);
    assert.equal(dryRun.status, 0, dryRun.stderr);
    assert.equal(dryRunReport.outputs.length, 1);
    assert.match(dryRunReport.outputs[0].output, /jest\.requireActual\("module"\)/);
    assert.equal(readFileSync(sourcePath, "utf8"), source);

    const fixed = execute(["--fix", "--json", sourcePath], options);
    assert.equal(fixed.status, 0, fixed.stderr);
    assert.match(readFileSync(sourcePath, "utf8"), /jest\.requireActual\("module"\)/);
    writeFileSync(sourcePath, source);
  }
});

test("project config and CLI --rules enable jest/no-export", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "jest/no-export": "error" } })
  );
  const sourcePath = write(
    join(project, "export.test.js"),
    "export const helper = 1; test('export', () => expect(helper).toBe(1));\n"
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-export", severity: "error" }
    ]);

    const isolated = execute(
      ["--no-config", "--rules=jest/no-export", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.deepEqual(isolatedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-export", severity: "warning" }
    ]);
  }
});

test("jest/no-focused-tests preserves project settings and editor suggestions", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({
      settings: { jest: { globalAliases: { describe: ["context"] } } },
      rules: { "jest/no-focused-tests": "error" }
    })
  );
  const source = "context.only('suite', () => {});\n";
  const sourcePath = write(join(project, "focused.test.js"), source);
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-focused-tests", severity: "error" }
    ]);
    assert.equal(configuredReport.diagnostics[0].fixes.length, 0);
    assert.equal(configuredReport.diagnostics[0].suggestions[0].desc, "Remove focus from test");
    assert.deepEqual(configuredReport.diagnostics[0].suggestions[0].fix, [
      { range: [7, 12], text: "" }
    ]);

    const selected = execute(["--rules=jest/no-focused-tests", "--json", sourcePath], options);
    const selectedReport = JSON.parse(selected.stdout);
    assert.equal(selected.status, 0, selected.stderr);
    assert.deepEqual(selectedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-focused-tests", severity: "warning" }
    ]);

    const fixed = execute(["--fix", "--json", sourcePath], options);
    assert.equal(fixed.status, 1, fixed.stderr);
    assert.equal(readFileSync(sourcePath, "utf8"), source);
  }

  const previousBinary = process.env.UTOO_LINT_BIN;
  process.env.UTOO_LINT_BIN = testBinary();
  t.after(() => {
    if (previousBinary === undefined) delete process.env.UTOO_LINT_BIN;
    else process.env.UTOO_LINT_BIN = previousBinary;
  });

  const importedSource = [
    'import { describe as suite } from "@jest/globals";',
    "suite.only('suite', () => {});",
    ""
  ].join("\n");
  for (const LinterImplementation of [Linter, CommonJSLinter]) {
    const linter = new LinterImplementation();
    const messages = linter.verify(
      importedSource,
      { rules: { "jest/no-focused-tests": "error" } },
      { filename: "focused.test.js" }
    );
    assert.equal(messages.length, 1);
    assert.equal(messages[0].fix, undefined);
    assert.equal(messages[0].suggestions[0].desc, "Remove focus from test");
    assert.deepEqual(messages[0].suggestions[0].fix, { range: [56, 61], text: "" });
    assert.equal(linter.getRules().get("jest/no-focused-tests").meta.hasSuggestions, true);
  }
});

test("project config and CLI --rules enable jest/no-identical-title", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "jest/no-identical-title": "error" } })
  );
  const sourcePath = write(
    join(project, "titles.test.js"),
    "it('same', () => {}); test('same', () => {});\n"
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-identical-title", severity: "error" }
    ]);

    const isolated = execute(
      ["--no-config", "--rules=jest/no-identical-title", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.deepEqual(isolatedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-identical-title", severity: "warning" }
    ]);
  }
});

test("project config and CLI --rules enable jest/no-interpolation-in-snapshots", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "jest/no-interpolation-in-snapshots": "error" } })
  );
  const sourcePath = write(
    join(project, "inline-snapshot.test.js"),
    "expect(value).toMatchInlineSnapshot(`${value}`);\n"
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-interpolation-in-snapshots", severity: "error" }
    ]);

    const isolated = execute(
      ["--no-config", "--rules=jest/no-interpolation-in-snapshots", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.deepEqual(isolatedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-interpolation-in-snapshots", severity: "warning" }
    ]);
  }
});

test("jest/no-jasmine-globals supports config, --rules, and safe fixes", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "jest/no-jasmine-globals": "error" } })
  );
  const source = [
    "jasmine.any(String);",
    "jasmine.DEFAULT_TIMEOUT_INTERVAL = 5000;",
    ""
  ].join("\n");
  const expected = [
    "expect.any(String);",
    "jest.setTimeout(5000);",
    ""
  ].join("\n");
  const sourcePath = write(join(project, "jasmine.test.js"), source);
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.equal(configuredReport.diagnostics.length, 2);
    assert.ok(configuredReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/no-jasmine-globals" && severity === "error"
    ));

    const isolated = execute(
      ["--no-config", "--rules=jest/no-jasmine-globals", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.equal(isolatedReport.diagnostics.length, 2);
    assert.ok(isolatedReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/no-jasmine-globals" && severity === "warning"
    ));

    const dryRun = execute(["--fix-dry-run", "--json", sourcePath], options);
    const dryRunReport = JSON.parse(dryRun.stdout);
    assert.equal(dryRun.status, 0, dryRun.stderr);
    assert.equal(dryRunReport.outputs.length, 1);
    assert.equal(dryRunReport.outputs[0].output, expected);
    assert.equal(readFileSync(sourcePath, "utf8"), source);

    const fixed = execute(["--fix", "--json", sourcePath], options);
    assert.equal(fixed.status, 0, fixed.stderr);
    assert.equal(readFileSync(sourcePath, "utf8"), expected);
    writeFileSync(sourcePath, source);
  }
});

test("project config and CLI --rules enable jest/no-mocks-import", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "jest/no-mocks-import": "error" } })
  );
  const sourcePath = write(
    join(project, "mocks.test.js"),
    [
      "import mock from './__mocks__/mock.js';",
      "import('./nested/__mocks__/dynamic.js');",
      "require('./__mocks__/commonjs.js');",
      ""
    ].join("\n")
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.equal(configuredReport.diagnostics.length, 3);
    assert.ok(configuredReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/no-mocks-import" && severity === "error"
    ));

    const isolated = execute(
      ["--no-config", "--rules=jest/no-mocks-import", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.equal(isolatedReport.diagnostics.length, 3);
    assert.ok(isolatedReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/no-mocks-import" && severity === "warning"
    ));
  }
});

test("jest/no-standalone-expect preserves custom test-block options", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({
      rules: {
        "jest/no-standalone-expect": [
          "error",
          { additionalTestBlockFunctions: ["customTest"] }
        ]
      }
    })
  );
  const sourcePath = write(
    join(project, "standalone.test.js"),
    [
      "customTest('works', () => expect(true).toBe(true));",
      "describe('suite', () => expect(true).toBe(true));",
      ""
    ].join("\n")
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-standalone-expect", severity: "error" }
    ]);

    const selected = execute(["--rules=jest/no-standalone-expect", "--json", sourcePath], options);
    const selectedReport = JSON.parse(selected.stdout);
    assert.equal(selected.status, 0, selected.stderr);
    assert.deepEqual(selectedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/no-standalone-expect", severity: "warning" }
    ]);

    const isolated = execute(
      ["--no-config", "--rules=jest/no-standalone-expect", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.equal(isolatedReport.diagnostics.length, 2);
    assert.ok(isolatedReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/no-standalone-expect" && severity === "warning"
    ));
  }
});

test("project config and CLI --rules enable jest/valid-describe-callback", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "jest/valid-describe-callback": "error" } })
  );
  const sourcePath = write(
    join(project, "describe.test.js"),
    [
      "describe('valid', () => {});",
      "describe('invalid', async () => {});",
      ""
    ].join("\n")
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity, message }) => ({ ruleId, severity, message })), [
      {
        ruleId: "jest/valid-describe-callback",
        severity: "error",
        message: "No async describe callback"
      }
    ]);

    const selected = execute(["--rules=jest/valid-describe-callback", "--json", sourcePath], options);
    const selectedReport = JSON.parse(selected.stdout);
    assert.equal(selected.status, 0, selected.stderr);
    assert.deepEqual(selectedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/valid-describe-callback", severity: "warning" }
    ]);
  }
});

test("project config and CLI --rules enable jest/valid-expect-in-promise", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "jest/valid-expect-in-promise": "error" } })
  );
  const sourcePath = write(
    join(project, "promise.test.js"),
    [
      "it('floating', () => { load().then(value => expect(value).toBeDefined()); });",
      "it('returned', () => load().then(value => expect(value).toBeDefined()));",
      ""
    ].join("\n")
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/valid-expect-in-promise", severity: "error" }
    ]);

    const selected = execute(["--rules=jest/valid-expect-in-promise", "--json", sourcePath], options);
    const selectedReport = JSON.parse(selected.stdout);
    assert.equal(selected.status, 0, selected.stderr);
    assert.deepEqual(selectedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/valid-expect-in-promise", severity: "warning" }
    ]);

    const isolated = execute(
      ["--no-config", "--rules=jest/valid-expect-in-promise", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.deepEqual(isolatedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/valid-expect-in-promise", severity: "warning" }
    ]);
  }
});

test("jest/valid-expect preserves argument and async matcher options", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({
      rules: {
        "jest/valid-expect": [
          "error",
          { minArgs: 0, maxArgs: 2, asyncMatchers: ["toSettle"] }
        ]
      }
    })
  );
  const sourcePath = write(
    join(project, "valid-expect.test.js"),
    [
      "expect().pass();",
      "expect(1, 'message').toBe(1);",
      "expect(Promise.resolve(1)).toSettle();",
      "expect(Promise.resolve(1)).toResolve();",
      ""
    ].join("\n")
  );
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.deepEqual(configuredReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/valid-expect", severity: "error" }
    ]);

    const selected = execute(["--rules=jest/valid-expect", "--json", sourcePath], options);
    const selectedReport = JSON.parse(selected.stdout);
    assert.equal(selected.status, 0, selected.stderr);
    assert.deepEqual(selectedReport.diagnostics.map(({ ruleId, severity }) => ({ ruleId, severity })), [
      { ruleId: "jest/valid-expect", severity: "warning" }
    ]);

    const isolated = execute(
      ["--no-config", "--rules=jest/valid-expect", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.equal(isolatedReport.diagnostics.length, 3);
    assert.ok(isolatedReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/valid-expect" && severity === "warning"
    ));
  }
});

test("jest/valid-title preserves options, CLI selection, and safe fixes", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({
      rules: {
        "jest/valid-title": [
          "error",
          {
            ignoreTypeOfDescribeName: true,
            disallowedWords: ["forbidden"],
            mustMatch: { test: "^that" }
          }
        ]
      }
    })
  );
  const source = [
    "describe(makeName(), () => {});",
    "test('contains forbidden', () => {});",
    "test('wrong title', () => {});",
    "it('it works ', () => {});",
    ""
  ].join("\n");
  const expected = [
    "describe(makeName(), () => {});",
    "test('contains forbidden', () => {});",
    "test('wrong title', () => {});",
    "it('works', () => {});",
    ""
  ].join("\n");
  const sourcePath = write(join(project, "title.test.js"), source);
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const configured = execute(["--json", sourcePath], options);
    const configuredReport = JSON.parse(configured.stdout);
    assert.equal(configured.status, 1, configured.stderr);
    assert.equal(configuredReport.diagnostics.length, 4);
    assert.ok(configuredReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/valid-title" && severity === "error"
    ));

    const selected = execute(["--rules=jest/valid-title", "--json", sourcePath], options);
    const selectedReport = JSON.parse(selected.stdout);
    assert.equal(selected.status, 0, selected.stderr);
    assert.equal(selectedReport.diagnostics.length, 4);
    assert.ok(selectedReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/valid-title" && severity === "warning"
    ));

    const isolated = execute(
      ["--no-config", "--rules=jest/valid-title", "--json", sourcePath],
      options
    );
    const isolatedReport = JSON.parse(isolated.stdout);
    assert.equal(isolated.status, 0, isolated.stderr);
    assert.equal(isolatedReport.diagnostics.length, 3);
    assert.ok(isolatedReport.diagnostics.every(({ ruleId, severity }) =>
      ruleId === "jest/valid-title" && severity === "warning"
    ));

    const dryRun = execute(["--fix-dry-run", "--json", sourcePath], options);
    const dryRunReport = JSON.parse(dryRun.stdout);
    assert.equal(dryRun.status, 1, dryRun.stderr);
    assert.equal(dryRunReport.outputs.length, 1);
    assert.equal(dryRunReport.outputs[0].output, expected);
    assert.equal(readFileSync(sourcePath, "utf8"), source);
  }
});

test("flat config keeps Jest version settings scoped per file", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["old/**/*.js"], settings: { jest: { version: 21 } }, rules: { "jest/no-deprecated-functions": "error" } },',
      '  { files: ["new/**/*.js"], settings: { jest: { version: 22 } }, rules: { "jest/no-deprecated-functions": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const oldSource = write(join(project, "old", "fixture.js"), "jest.runTimersToTime(1000);\n");
  const newSource = write(join(project, "new", "fixture.js"), "jest.runTimersToTime(1000);\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute(["--json", oldSource, newSource], options);
    const report = JSON.parse(result.stdout);
    assert.equal(result.status, 1, result.stderr);
    assert.deepEqual(report.diagnostics.map(({ filePath, ruleId }) => ({ filePath, ruleId })), [
      { filePath: newSource, ruleId: "jest/no-deprecated-functions" }
    ]);
  }
});

test("CLI --rules preserves per-file options for the selected flat-config rule", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-console": ["error", { allow: ["warn"] }] } },',
      '  { files: ["test/**/*.ts"], rules: { "no-console": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const allowedSource = write(join(project, "src", "index.ts"), 'console.warn("x");\n');
  const reportedSource = write(join(project, "test", "index.ts"), 'console.warn("x");\n');

  const result = runCli(["--rules=no-console", allowedSource, reportedSource], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stderr, /src\/index\.ts/);
  assert.match(result.stderr, /test\/index\.ts/);
});

test("CLI applies flat config rules per file", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-debugger": "off" } },',
      '  { files: ["test/**/*.ts"], rules: { "no-debugger": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const disabledSource = write(join(project, "src", "index.ts"), "debugger;\n");
  const enabledSource = write(join(project, "test", "index.ts"), "debugger;\n");

  const result = spawnSync(process.execPath, [cliPath, disabledSource, enabledSource], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() },
    encoding: "utf8"
  });

  assert.equal(result.status, 1, result.stderr);
  assert.doesNotMatch(result.stderr, new RegExp(disabledSource.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(result.stderr, new RegExp(enabledSource.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
});

test("ESM and CommonJS runCli apply flat config rules per file", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-debugger": "off" } },',
      '  { files: ["test/**/*.ts"], rules: { "no-debugger": "error" } }',
      "];",
      ""
    ].join("\n")
  );
  const disabledSource = write(join(project, "src", "index.ts"), "debugger;\n");
  const enabledSource = write(join(project, "test", "index.ts"), "debugger;\n");
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };

  for (const execute of [runCli, require("../index.cjs").runCli]) {
    const result = execute([disabledSource, enabledSource], options);
    assert.equal(result.status, 1, result.stderr);
    assert.doesNotMatch(result.stderr, /src\/index\.ts/);
    assert.match(result.stderr, /test\/index\.ts/);
  }
});

test("ESM and CommonJS apply flat overrideConfig rules per file with project config disabled", async (t) => {
  const project = createProject(t);
  const allowedSource = write(join(project, "src", "index.ts"), 'console.warn("x");\n');
  const reportedSource = write(join(project, "test", "index.ts"), 'console.warn("x");\n');
  const overrideConfig = [
    { files: ["src/**/*.ts"], rules: { "no-console": ["error", { allow: ["warn"] }] } },
    { files: ["test/**/*.ts"], rules: { "no-console": "error" } }
  ];

  for (const ESLintConstructor of [ESLint, require("../index.cjs").ESLint]) {
    const eslint = new ESLintConstructor({
      cwd: project,
      binary: testBinary(),
      overrideConfigFile: true,
      overrideConfig
    });
    const results = await eslint.lintFiles([allowedSource, reportedSource]);
    const resultByPath = new Map(results.map((result) => [result.filePath, result]));
    assert.equal(resultByPath.get(allowedSource).messages.length, 0);
    assert.match(resultByPath.get(reportedSource).messages[0].ruleId, /no-console/);
  }
});

test("ESM and CommonJS runCli preserve warning JSON output without failing", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.ts"),
    [
      "export default [",
      '  { files: ["src/**/*.ts"], rules: { "no-debugger": "off" } },',
      '  { files: ["test/**/*.ts"], rules: { "no-debugger": "warn" } }',
      "];",
      ""
    ].join("\n")
  );
  const disabledSource = write(join(project, "src", "index.ts"), "debugger;\n");
  const enabledSource = write(join(project, "test", "index.ts"), "debugger;\n");

  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute(["--json", disabledSource, enabledSource], {
      cwd: project,
      binary: testBinary(),
      encoding: "utf8"
    });
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, 0, result.stderr);
    assert.equal(report.diagnostics.length, 1);
    assert.equal(report.diagnostics[0].severity, "warning");
    assert.match(report.diagnostics[0].filePath, /test\/index\.ts$/);
  }
});

test("ESM and CommonJS keep parse errors fatal when rules are configured", (t) => {
  const project = createProject(t);
  write(join(project, "utlint.config.json"));
  const sourcePath = write(join(project, "index.js"), "const = ;\n");

  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute(["--json", sourcePath], {
      cwd: project,
      binary: testBinary(),
      encoding: "utf8"
    });
    const report = JSON.parse(result.stdout);

    assert.equal(result.status, 1, result.stderr);
    assert.ok(report.diagnostics.some((diagnostic) => diagnostic.ruleId === "parse" && diagnostic.severity === "error"));
  }
});

test("ignored-file warnings do not fail lintFiles or lintText", (t) => {
  const project = createProject(t);
  const ignoredSource = write(join(project, "ignored.js"), "debugger;\n");
  const options = {
    cwd: project,
    binary: testBinary(),
    noConfig: true,
    ignorePatterns: ["ignored.js"]
  };

  for (const execute of [lintFiles, require("../index.cjs").lintFiles]) {
    const report = execute([ignoredSource], options);
    assert.equal(report.exitCode, 0);
    assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.severity), ["warning"]);
  }
  for (const execute of [lintText, require("../index.cjs").lintText]) {
    const report = execute("debugger;\n", { ...options, filePath: ignoredSource });
    assert.equal(report.exitCode, 0);
    assert.deepEqual(report.diagnostics.map((diagnostic) => diagnostic.severity), ["warning"]);
  }
});

test("runCli keeps --fix writes while filtering project config diagnostics", (t) => {
  const project = createProject(t);
  write(
    join(project, "utlint.config.json"),
    JSON.stringify({ rules: { "no-extra-semi": "error" } })
  );
  const sourcePath = write(join(project, "index.ts"), "const value = 1;;\n");

  const result = runCli(["--fix", sourcePath], {
    cwd: project,
    binary: testBinary(),
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(sourcePath, "utf8"), "const value = 1;\n");
});

for (const filename of ["utlint.config.ts", "utlint.config.json"]) {
  test(`fishlint loads ancestor ${filename}`, (t) => {
    const project = createProject(t);
    write(join(project, filename),
      filename.endsWith(".ts")
        ? 'export default { rules: { "no-debugger": "off" } };\n'
        : '{ "rules": { "no-debugger": "off" } }\n');
    const appDirectory = join(project, "packages", "app");
    const sourcePath = write(join(appDirectory, "index.ts"), "debugger;\n");

    const result = spawnSync(process.execPath, [fishlintPath, "eslint", sourcePath], {
      cwd: appDirectory,
      env: { ...process.env, UTOO_LINT_BIN: testBinary() },
      encoding: "utf8"
    });

    assert.equal(result.status, 0, result.stderr);
  });
}

test("React Compiler use-memo supports ESM/CommonJS configuration and suppression", (t) => {
  const project = createProject(t);
  const ruleId = "react-hooks/use-memo";
  write(join(project, "utlint.config.json"), JSON.stringify({ rules: { [ruleId]: "error" } }));
  const source = "import {useMemo as calculate} from 'react'; function Component() { return calculate(async (value) => value, []); }";
  const options = { cwd: project, binary: testBinary(), encoding: "utf8" };
  for (const extension of ["js", "jsx", "ts", "tsx"]) {
    const sourcePath = write(join(project, `component.${extension}`), source);
    for (const execute of [runCli, commonJSRunCli]) {
      const result = execute(["--json", sourcePath], options);
      assert.equal(result.status, 1, result.stderr);
      const diagnostics = JSON.parse(result.stdout).diagnostics;
      assert.equal(diagnostics.length, 2);
      assert.ok(diagnostics.every((item) => item.ruleId === ruleId && item.severity === "error" && item.fixes.length === 0));
    }
  }
  const sourcePath = write(join(project, "suppressed.js"), `// utlint-ignore-all ${ruleId}: fixture\n${source}`);
  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute(["--json", sourcePath], options);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout).diagnostics, []);
  }
});

test("migrator recognizes React Compiler use-memo", (t) => {
  const project = createProject(t);
  const ruleId = "react-hooks/use-memo";
  const config = write(join(project, ".eslintrc.json"), JSON.stringify({ rules: { [ruleId]: "error", "react-hooks/refs": "error" } }));
  const result = spawnSync(process.execPath, [cliPath, "migrate", "eslint", `--from=${config}`, "--print", "--report=json"], { cwd: project, encoding: "utf8" });
  assert.equal(result.status, 1, result.stderr);
  const report = JSON.parse(result.stderr);
  assert.deepEqual(report.supportedRules, [ruleId]);
  assert.deepEqual(report.unsupportedRules, ["react-hooks/refs"]);
});

test("React Compiler use-memo resolves CommonJS and indirect values through both wrappers", (t) => {
  const project = createProject(t);
  const ruleId = "react-hooks/use-memo";
  write(join(project, "utlint.config.json"), JSON.stringify({ rules: { [ruleId]: "error" } }));
  const sourcePath = write(join(project, "component.tsx"), "const {useMemo: memo} = require('react'); const calc = async value => value; function Component() { return memo(calc, []); }");
  for (const execute of [runCli, commonJSRunCli]) {
    const result = execute(["--json", sourcePath], { cwd: project, binary: testBinary(), encoding: "utf8" });
    assert.equal(result.status, 1, result.stderr);
    const diagnostics = JSON.parse(result.stdout).diagnostics;
    assert.equal(diagnostics.length, 2);
    assert.ok(diagnostics.every((item) => item.ruleId === ruleId));
  }
});
