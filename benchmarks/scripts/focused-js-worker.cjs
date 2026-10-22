const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { dirname, join } = require("node:path");
const { performance } = require("node:perf_hooks");

const [wrapper, mode, fixturePath, rawCount] = process.argv.slice(2);
const count = Number(rawCount);
const api = require(wrapper);
const text = readFileSync(fixturePath, "utf8");
const digest = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
let started;
let elapsedMs;
let result;

if (mode === "plugin") {
  const linter = new api.Linter();
  let visited = 0;
  linter.defineRule("focused/token-boundary", {
    create(context) {
      return {
        VariableDeclarator(node) {
          const token = context.sourceCode.getTokenAfter(node.id, { includeComments: true });
          visited += 1;
          if (token?.value === "=") {
            context.report({ node: node.id, message: "Initializer follows this binding." });
          }
        }
      };
    }
  });
  started = performance.now();
  const messages = linter.verify(text, {
    parserOptions: { ecmaVersion: 2022, sourceType: "module" },
    rules: { "focused/token-boundary": "error" }
  }, { filename: fixturePath });
  elapsedMs = performance.now() - started;
  assert.equal(visited, count);
  assert.equal(messages.length, count);
  assert.ok(messages.every((message) => message.ruleId === "focused/token-boundary"));
  result = { visited, messages };
} else {
  // Setup is deliberately outside the focused API timer. Every worker is a
  // fresh process, so this measures cold-JIT queries on an already parsed file.
  const parser = require(join(dirname(wrapper), "lib", "estree-parser.cjs"));
  const parsed = parser.parseForESLint(text, { filePath: fixturePath });
  assert.deepEqual(parsed.diagnostics, []);
  const source = new api.SourceCode({ text, ast: parsed.ast, visitorKeys: parsed.visitorKeys });
  const nodes = parsed.ast.body.map((statement) => statement.declaration.declarations[0]);
  assert.equal(nodes.length, count);
  const outputs = [];
  const options = { includeComments: mode === "comments" };
  started = performance.now();
  for (const node of nodes) {
    if (mode === "locations") {
      outputs.push(source.getLocFromIndex(node.range[0]), source.getLocFromIndex(node.range[1]));
    } else {
      for (const token of [
        source.getFirstToken(node, options),
        source.getLastToken(node, options),
        source.getTokenBefore(node, options),
        source.getTokenAfter(node, options)
      ]) {
        outputs.push(token);
      }
    }
  }
  elapsedMs = performance.now() - started;
  result = outputs;
}

const nodePeakRssKiB = process.resourceUsage().maxRSS;
process.stdout.write(JSON.stringify({
  elapsedMs,
  resultSha256: digest(result),
  outputCount: Array.isArray(result) ? result.length : result.messages.length,
  nodePeakRssKiB
}) + "\n");
