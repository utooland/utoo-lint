import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { ESLint, Linter, RuleTester, lintFiles, lintText, resolveBinary, runCli } from "../index.js";
import { readConfig } from "../lib/config-loader.js";

const require = createRequire(import.meta.url);
const { Linter: CommonJSLinter, runCli: commonJSRunCli } = require("../index.cjs");

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const builtBinary = resolve(
  packageDirectory,
  "..",
  "..",
  "zig-out",
  "bin",
  process.platform === "win32" ? "utoo-lint.exe" : "utoo-lint"
);

function testBinary() {
  return existsSync(builtBinary) ? builtBinary : resolveBinary();
}

function createProject(t) {
  const project = mkdtempSync(join(tmpdir(), "utoo-lint-eslint-plugins-"));
  t.after(() => rmSync(project, { recursive: true, force: true }));
  return project;
}

function write(path, source) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, source);
  return path;
}

// Linter, RuleTester, and lintText resolve the native binary from the
// environment; point them at the freshly built binary like the CLI tests do.
function useTestBinary(t) {
  const previousBinary = process.env.UTOO_LINT_BIN;
  process.env.UTOO_LINT_BIN = testBinary();
  t.after(() => {
    if (previousBinary === undefined) {
      delete process.env.UTOO_LINT_BIN;
    } else {
      process.env.UTOO_LINT_BIN = previousBinary;
    }
  });
}

const PLUGIN_SOURCE = `
const plugin = {
  meta: { name: "example", version: "1.0.0" },
  rules: {
    "no-foo": {
      meta: {
        type: "problem",
        fixable: "code",
        docs: { url: "https://example.test/no-foo" },
        messages: { foo: "Do not use {{name}}" },
        schema: []
      },
      create(context) {
        return {
          "Identifier[name='foo']"(node) {
            context.report({
              node,
              messageId: "foo",
              data: { name: node.name },
              fix: (fixer) => fixer.replaceText(node, "bar")
            });
          }
        };
      }
    },
    "unused-function": {
      meta: {
        messages: { unused: "Function {{name}} is never used" },
        schema: [{ type: "object", properties: { prefix: { type: "string", default: "fn:" } } }]
      },
      create(context) {
        return {
          "Program:exit"(node) {
            const scope = context.sourceCode.getScope(node);
            const variables = [scope, ...scope.childScopes].flatMap((candidate) => candidate.variables);
            for (const variable of variables) {
              const isFunction = variable.defs.some((definition) => definition.type === "FunctionName");
              if (isFunction && variable.references.length === 0) {
                context.report({
                  node: variable.identifiers[0],
                  messageId: "unused",
                  data: { name: ((context.options[0] ?? {}).prefix ?? "") + variable.name }
                });
              }
            }
          }
        };
      }
    },
    "no-empty-element": {
      meta: { hasSuggestions: true },
      create(context) {
        return {
          "JSXElement:has(JSXOpeningElement[selfClosing=false])"(node) {
            if (node.children.length > 0) {
              return;
            }
            const opening = context.sourceCode.getText(node.openingElement);
            context.report({
              node,
              message: "Empty element",
              suggest: [{
                desc: "Self-close the element",
                fix: (fixer) => fixer.replaceText(node, opening.replace(/>$/u, " />"))
              }]
            });
          }
        };
      }
    },
    "no-parens-call": {
      create(context) {
        return {
          CallExpression(node) {
            const token = context.sourceCode.getTokenAfter(node.callee);
            if (token.value === "(" && node.arguments.length === 0) {
              context.report({ node, message: "empty call " + token.type });
            }
          }
        };
      }
    },
    throws: {
      create() {
        return {
          Program() {
            throw new Error("boom");
          }
        };
      }
    },
    "needs-debugger": {
      meta: { fixable: "code" },
      create(context) {
        return {
          Program(node) {
            if (node.body.some((statement) => statement.type === "DebuggerStatement")) {
              return;
            }
            context.report({ node, message: "Add a debugger", fix: (fixer) => fixer.insertTextBeforeRange([0, 0], "debugger;\\n") });
          }
        };
      }
    }
  }
};
plugin.configs = {
  recommended: { plugins: { example: plugin }, rules: { "example/no-foo": "error" } }
};
export default plugin;
`;

function writePluginProject(t, { rules, extraConfig = "" } = {}) {
  const project = createProject(t);
  write(join(project, "example-plugin.mjs"), PLUGIN_SOURCE);
  const ruleSource = JSON.stringify(rules ?? {
    "example/no-foo": "error",
    "example/unused-function": ["warn", {}],
    "example/no-empty-element": "warn",
    "no-debugger": "error"
  });
  write(
    join(project, "utlint.config.ts"),
    [
      'import example from "./example-plugin.mjs";',
      "export default [",
      `  { files: ["**/*.js", "**/*.jsx", "**/*.ts", "**/*.tsx"], plugins: { example }, rules: ${ruleSource} }${extraConfig}`,
      "];",
      ""
    ].join("\n")
  );
  return project;
}

function cliJson(project, args, cli = runCli) {
  const result = cli(["--format=json", ...args], {
    cwd: project,
    env: { ...process.env, UTOO_LINT_BIN: testBinary() }
  });
  return { status: result.status, report: JSON.parse(result.stdout) };
}

function summarize(diagnostics) {
  return diagnostics.map((diagnostic) => `${diagnostic.ruleId}@${diagnostic.line}:${diagnostic.column}:${diagnostic.severity}`);
}

const [nodeMajor, nodeMinor] = process.versions.node.split(".").map(Number);
const commonJSCanLoadESM = nodeMajor > 22 || (nodeMajor === 22 && nodeMinor >= 12) || (nodeMajor === 20 && nodeMinor >= 19);

test("CLI runs ESLint plugin rules from utlint.config.ts alongside native rules", (t) => {
  const project = writePluginProject(t);
  write(join(project, "src", "index.js"), "function helper() {}\nconst foo = 1;\ndebugger;\n");

  const { status, report } = cliJson(project, ["src"]);

  assert.equal(status, 1);
  assert.deepEqual(summarize(report.diagnostics), [
    "example/unused-function@1:10:warning",
    "example/no-foo@2:7:error",
    "no-debugger@3:1:error"
  ]);
  const unused = report.diagnostics[0];
  assert.equal(unused.message, "Function fn:helper is never used");
  const foo = report.diagnostics[1];
  assert.equal(foo.message, "Do not use foo");
  assert.deepEqual(foo.fixes, [{ range: [27, 30], text: "bar" }]);
  assert.equal(foo.endLine, 2);
  assert.equal(foo.endColumn, 10);

  if (commonJSCanLoadESM) {
    const commonJS = cliJson(project, ["src"], commonJSRunCli);
    assert.equal(commonJS.status, 1);
    assert.deepEqual(summarize(commonJS.report.diagnostics), summarize(report.diagnostics));
  }
});

test("CLI text output lists plugin diagnostics with native diagnostics", (t) => {
  const project = writePluginProject(t);
  write(join(project, "src", "index.js"), "const foo = 1;\ndebugger;\n");

  const result = runCli(["src"], { cwd: project, env: { ...process.env, UTOO_LINT_BIN: testBinary() } });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /1:7\s+error\s+Do not use foo\s+example\/no-foo/u);
  assert.match(result.stderr, /2:1\s+error\s+Unexpected debugger statement\.\s+no-debugger/u);
});

test("plugin rules are never passed to the native binary", (t) => {
  const project = writePluginProject(t, { rules: { "example/no-foo": ["error", { strict: true }], "no-debugger": ["error"] } });
  write(join(project, "src", "index.js"), "const foo = 1;\ndebugger;\n");

  const { status, report } = cliJson(project, ["src"]);

  assert.equal(status, 1);
  assert.deepEqual(summarize(report.diagnostics), ["example/no-foo@1:7:error", "no-debugger@2:1:error"]);
});

test("disable directives suppress plugin diagnostics", (t) => {
  const project = writePluginProject(t, { rules: { "example/no-foo": "error" } });
  write(
    join(project, "src", "index.js"),
    "// eslint-disable-next-line example/no-foo -- legacy\nconst foo = 1;\n/* utlint-ignore example/no-foo */\nconst other = foo;\nconst again = foo;\n"
  );

  const { report } = cliJson(project, ["src"]);

  assert.deepEqual(summarize(report.diagnostics), ["example/no-foo@5:15:error"]);
  assert.equal(report.suppressedDiagnostics.length, 2);
  assert.equal(report.suppressedDiagnostics[0].suppression.justification, "legacy");
});

test("--fix writes plugin fixes and --fix-dry-run reports them as outputs", (t) => {
  const project = writePluginProject(t, { rules: { "example/no-foo": "error", "no-extra-semi": "error" } });
  const source = write(join(project, "src", "index.js"), "const foo = 1;;\nfoo();\n");

  const dryRun = cliJson(project, ["--fix-dry-run", "src"]);
  assert.deepEqual(dryRun.report.diagnostics, []);
  assert.deepEqual(dryRun.report.outputs, [{ filePath: source, output: "const bar = 1;\nbar();\n" }]);
  assert.equal(readFileSync(source, "utf8"), "const foo = 1;;\nfoo();\n");

  const fixed = cliJson(project, ["--fix", "src"]);
  assert.equal(fixed.status, 0);
  assert.deepEqual(fixed.report.diagnostics, []);
  assert.equal(readFileSync(source, "utf8"), "const bar = 1;\nbar();\n");
});

test("--rules selects plugin rules the same way it selects native rules", (t) => {
  const project = writePluginProject(t, { rules: { "example/no-foo": "error", "example/unused-function": "off", "no-debugger": "error" } });
  write(join(project, "src", "index.js"), "function helper() {}\nconst foo = 1;\ndebugger;\n");

  const onlyPlugin = cliJson(project, ["--rules=example/no-foo", "src"]);
  assert.deepEqual(summarize(onlyPlugin.report.diagnostics), ["example/no-foo@2:7:warning"]);

  const onlyNative = cliJson(project, ["--rules=no-debugger", "src"]);
  assert.deepEqual(summarize(onlyNative.report.diagnostics), ["no-debugger@3:1:warning"]);

  const enabledByFlag = cliJson(project, ["--rules=example/unused-function", "src"]);
  assert.deepEqual(summarize(enabledByFlag.report.diagnostics), ["example/unused-function@1:10:warning"]);
});

test("native rules are re-run on text changed by plugin fixes", async (t) => {
  const project = writePluginProject(t, { rules: { "example/needs-debugger": "error", "no-debugger": "error" } });
  const source = write(join(project, "src", "index.js"), "const value = 1;\n");

  const dryRun = cliJson(project, ["--fix-dry-run", "src"]);
  assert.deepEqual(summarize(dryRun.report.diagnostics), ["no-debugger@1:1:error"]);
  assert.deepEqual(dryRun.report.outputs, [{ filePath: source, output: "debugger;\nconst value = 1;\n" }]);
  assert.equal(readFileSync(source, "utf8"), "const value = 1;\n");

  const written = cliJson(project, ["--fix", "src"]);
  assert.equal(written.status, 1);
  assert.deepEqual(summarize(written.report.diagnostics), ["no-debugger@1:1:error"]);
  assert.equal(readFileSync(source, "utf8"), "debugger;\nconst value = 1;\n");

  write(source, "const value = 1;\n");
  const eslint = new ESLint({
    cwd: project,
    fix: true,
    overrideConfigFile: true,
    overrideConfig: [{
      files: ["**/*.js"],
      plugins: { inline: { rules: { "needs-debugger": { meta: { fixable: "code" }, create: (context) => ({ Program(node) { if (!node.body.some((statement) => statement.type === "DebuggerStatement")) context.report({ node, message: "Add a debugger", fix: (fixer) => fixer.insertTextBeforeRange([0, 0], "debugger;\n") }); } }) } } } },
      rules: { "inline/needs-debugger": "error", "no-debugger": "error" }
    }]
  });
  const results = await eslint.lintFiles(["src"]);
  assert.deepEqual(results[0].messages.map((message) => [message.ruleId, message.line, message.severity]), [["no-debugger", 1, 2]]);
  assert.equal(results[0].output, "debugger;\nconst value = 1;\n");
});

test("TypeScript and TSX files get scope analysis and suggestions", (t) => {
  const project = writePluginProject(t);
  write(join(project, "src", "types.ts"), "interface Shape { size: number }\nfunction unused(shape: Shape): Shape { return shape; }\nfunction used(): Shape { return { size: 1 }; }\nused();\n");
  write(join(project, "src", "view.tsx"), "export const view = <div className=\"x\"></div>;\n");

  const { report } = cliJson(project, ["src"]);

  const byFile = new Map();
  for (const diagnostic of report.diagnostics) {
    byFile.set(diagnostic.filePath.split("/").pop(), [...(byFile.get(diagnostic.filePath.split("/").pop()) ?? []), diagnostic]);
  }
  assert.deepEqual(summarize(byFile.get("types.ts")), ["example/unused-function@2:10:warning"]);
  const empty = byFile.get("view.tsx")[0];
  assert.equal(empty.ruleId, "example/no-empty-element");
  assert.equal(empty.suggestions[0].desc, "Self-close the element");
  assert.equal(empty.suggestions[0].fix[0].text, "<div className=\"x\" />");
});

test("native rules take precedence over plugin rules with the same id", (t) => {
  const project = createProject(t);
  write(join(project, "react-plugin.mjs"), `
export default {
  rules: {
    "jsx-key": { create(context) { return { JSXElement(node) { context.report({ node, message: "PLUGIN jsx-key" }); } }; } },
    "no-div": { create(context) { return { "JSXOpeningElement[name.name='div']"(node) { context.report({ node, message: "PLUGIN no-div" }); } }; } }
  }
};
`);
  write(
    join(project, "utlint.config.ts"),
    'import react from "./react-plugin.mjs";\nexport default [{ files: ["**/*.jsx"], plugins: { react }, rules: { "react/jsx-key": "error", "react/no-div": "warn" } }];\n'
  );
  write(join(project, "src", "list.jsx"), "const list = [1].map((item) => <div>{item}</div>);\n");

  const { report } = cliJson(project, ["src"]);

  assert.deepEqual(
    report.diagnostics.map((diagnostic) => `${diagnostic.ruleId}: ${diagnostic.message}`),
    ['react/jsx-key: Missing "key" prop for element in iterator', "react/no-div: PLUGIN no-div"]
  );
});

test("config loader serializes circular plugin objects for the native engine", (t) => {
  const project = writePluginProject(t);

  const config = readConfig(join(project, "utlint.config.ts"), project);

  assert.equal(Array.isArray(config), true);
  assert.deepEqual(Object.keys(config[0].plugins.example.rules).sort(), ["needs-debugger", "no-empty-element", "no-foo", "no-parens-call", "throws", "unused-function"]);
  assert.equal(config[0].plugins.example.rules["no-foo"].meta.docs.url, "https://example.test/no-foo");
  assert.equal("create" in config[0].plugins.example.rules["no-foo"], false);
});

test("ESLint API and lintText include plugin messages from the config file", async (t) => {
  const project = writePluginProject(t, { rules: { "example/no-foo": "error", "no-debugger": "warn" } });
  write(join(project, "src", "index.js"), "const foo = 1;\ndebugger;\n");

  const eslint = new ESLint({ cwd: project, fix: true });
  const results = await eslint.lintFiles(["src"]);

  assert.equal(results.length, 1);
  assert.deepEqual(
    results[0].messages.map((message) => [message.ruleId, message.line, message.column, message.severity]),
    [["no-debugger", 2, 1, 1]]
  );
  assert.equal(results[0].output, "const bar = 1;\ndebugger;\n");

  const textResults = await new ESLint({ cwd: project }).lintText("const foo = 1;\n", { filePath: "src/text.js" });
  assert.deepEqual(textResults[0].messages.map((message) => [message.ruleId, message.endLine, message.endColumn]), [["example/no-foo", 1, 10]]);
  assert.equal(textResults[0].messages[0].fix.text, "bar");

  const formatter = await eslint.loadFormatter("json");
  assert.equal(typeof formatter.format(results), "string");

  const report = lintText("const foo = 1;\n", { cwd: project, filePath: "src/report.js" });
  assert.deepEqual(summarize(report.diagnostics), ["example/no-foo@1:7:error"]);

  const fileReport = lintFiles(["src"], { cwd: project });
  assert.deepEqual(summarize(fileReport.diagnostics), ["example/no-foo@1:7:error", "no-debugger@2:1:warning"]);
});

for (const [format, LinterClass] of [["ESM", Linter], ["CommonJS", CommonJSLinter]]) {
  test(`${format} Linter runs inline plugins with scope analysis, tokens, and fixes`, { skip: format === "CommonJS" && !commonJSCanLoadESM }, (t) => {
    useTestBinary(t);
    const plugin = {
      rules: {
        "no-unused-local": {
          create(context) {
            return {
              FunctionDeclaration(node) {
                const scope = context.sourceCode.getScope(node);
                for (const variable of scope.variables) {
                  if (variable.references.length === 0 && variable.defs.length > 0) {
                    context.report({ node: variable.identifiers[0], message: `${variable.name} unused` });
                  }
                }
              },
              "CallExpression > Identifier.callee[name=/^fo+$/]"(node) {
                const after = context.sourceCode.getTokenAfter(node);
                context.report({ node, message: `call ${after.value}`, fix: (fixer) => fixer.replaceText(node, "bar") });
              }
            };
          }
        }
      }
    };
    const config = [{
      files: ["**/*.{js,ts}"],
      plugins: { ex: plugin },
      languageOptions: { globals: { external: "readonly" } },
      rules: { "ex/no-unused-local": "error", "no-debugger": "error" }
    }];
    const linter = new LinterClass();

    const messages = linter.verify("function f(a, b) { debugger; return a + external; }\nfoo();\n", config, { filename: "input.js" });
    assert.deepEqual(
      messages.map((message) => `${message.ruleId}@${message.line}:${message.column} ${message.message}`),
      ["ex/no-unused-local@1:15 b unused", "no-debugger@1:20 Unexpected debugger statement.", "ex/no-unused-local@2:1 call ("]
    );
    assert.equal(linter.getSourceCode().ast.type, "Program");
    assert.deepEqual(linter.getSourceCode().scopeManager.globalScope.through.map((reference) => reference.identifier.name), ["foo"]);

    const typescript = linter.verify("function g(p: number, q: string): number { return p; }\n", config, { filename: "input.ts" });
    assert.deepEqual(typescript.map((message) => message.message), ["q unused"]);

    const fixed = linter.verifyAndFix("foo(); foo();\n", config, { filename: "input.js" });
    assert.equal(fixed.output, "bar(); bar();\n");
    assert.equal(fixed.fixed, true);
  });
}

test("rule options merge meta.defaultOptions and JSON schema defaults", (t) => {
  useTestBinary(t);
  const seen = [];
  const plugin = {
    rules: {
      options: {
        meta: {
          defaultOptions: [{ mode: "loose", nested: { depth: 1, keep: true } }],
          schema: [{ type: "object", properties: { extra: { type: "string", default: "schema" } } }]
        },
        create(context) {
          seen.push(context.options);
          return {};
        }
      }
    }
  };
  const linter = new Linter();

  linter.verify("x;\n", [{ plugins: { p: plugin }, rules: { "p/options": ["error", { nested: { depth: 2 } }] } }], { filename: "a.js" });
  linter.verify("x;\n", [{ plugins: { p: plugin }, rules: { "p/options": "error" } }], { filename: "a.js" });

  assert.deepEqual(seen, [
    [{ nested: { depth: 2, keep: true }, mode: "loose", extra: "schema" }],
    [{ mode: "loose", nested: { depth: 1, keep: true }, extra: "schema" }]
  ]);
});

test("plugin rule failures name the rule", (t) => {
  useTestBinary(t);
  const plugin = { rules: { throws: { create() { return { Program() { throw new Error("boom"); } }; } } } };
  const linter = new Linter();

  assert.throws(
    () => linter.verify("x;\n", [{ plugins: { p: plugin }, rules: { "p/throws": "error" } }], { filename: "a.js" }),
    /Error while running ESLint plugin rule "p\/throws" at 1:1: boom/u
  );
});

test("RuleTester exercises a plugin rule against the real AST", (t) => {
  useTestBinary(t);
  const rule = {
    meta: { fixable: "code", messages: { foo: "Do not use foo" } },
    create(context) {
      return {
        "VariableDeclarator > Identifier.id[name='foo']"(node) {
          context.report({ node, messageId: "foo", fix: (fixer) => fixer.replaceText(node, "bar") });
        }
      };
    }
  };
  const describe = RuleTester.describe;
  const it = RuleTester.it;
  RuleTester.describe = (_name, fn) => fn();
  RuleTester.it = (_name, fn) => fn();
  try {
    new RuleTester().run("no-foo", rule, {
      valid: ["const bar = 1;", "foo();"],
      invalid: [{ code: "const foo = 1;", errors: [{ messageId: "foo", line: 1, column: 7 }], output: "const bar = 1;" }]
    });
  } finally {
    RuleTester.describe = describe;
    RuleTester.it = it;
  }
});
