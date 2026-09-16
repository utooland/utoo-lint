import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const { nativeFlatConfigEntries, nativeRuleConfig, nativeRules } = require("../lib/native-rule-options.cjs");

test("rewrites import/no-cycle maxDepth Infinity to the unlimited spelling", () => {
  assert.deepEqual(
    nativeRuleConfig("import/no-cycle", ["error", { maxDepth: Infinity, ignoreExternal: true }]),
    ["error", { maxDepth: "\u221e", ignoreExternal: true }]
  );
  assert.deepEqual(nativeRuleConfig("import/no-cycle", ["error", { maxDepth: 2 }]), ["error", { maxDepth: 2 }]);
  assert.deepEqual(nativeRuleConfig("import/no-cycle", "error"), "error");
});

test("names the rule and option for non-finite values without a spelling", () => {
  assert.throws(
    () => nativeRules({ "max-depth": ["error", { max: Infinity }] }),
    { name: "TypeError", message: 'Rule "max-depth" option "max" is Infinity, which cannot be written to the native JSON config.' }
  );
  assert.throws(
    () => nativeRules({ "no-restricted-syntax": ["error", { nested: { list: [1, NaN] } }] }),
    { message: /Rule "no-restricted-syntax" option "nested.list\[1\]" is NaN/ }
  );
  assert.throws(
    () => nativeRules({ "max-len": ["error", -Infinity] }),
    { message: /Rule "max-len" option "\[1\]" is -Infinity/ }
  );
});

test("lenient mode turns unrepresentable numbers into null like JSON.stringify", () => {
  assert.deepEqual(
    nativeRules({ "max-depth": ["error", { max: Infinity }], "import/no-cycle": ["warn", { maxDepth: Infinity }] }, { strict: false }),
    { "max-depth": ["error", { max: null }], "import/no-cycle": ["warn", { maxDepth: "\u221e" }] }
  );
});

test("leaves finite options, non-object entries, and cyclic values untouched", () => {
  const cyclic = { self: null, value: 1 };
  cyclic.self = cyclic;
  const rules = { "max-len": ["error", { code: 120 }], "no-console": 2, custom: ["error", cyclic] };

  const result = nativeRules(rules);

  assert.deepEqual(result["max-len"], ["error", { code: 120 }]);
  assert.equal(result["no-console"], 2);
  assert.equal(result.custom[1].self, cyclic);
  assert.deepEqual(nativeFlatConfigEntries([{ files: ["**/*.js"], rules }, "not-an-entry"])[1], "not-an-entry");
  assert.deepEqual(nativeFlatConfigEntries({ rules }), { rules });
});
