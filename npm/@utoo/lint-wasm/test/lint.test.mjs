import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  createUtooLint,
  lint,
  UtooLintWasmError,
} from "../index.js";

const wasmUrl = new URL("../utoo-lint.wasm", import.meta.url);
const wasmBytesPromise = readFile(wasmUrl);

async function instantiateInstrumented(overrides = {}) {
  const { instance } = await WebAssembly.instantiate(await wasmBytesPromise, {});
  const calls = { alloc: [], free: [], lint: [] };
  const instrumentedExports = {
    ...instance.exports,
    alloc(...args) {
      calls.alloc.push(args);
      return (overrides.alloc ?? instance.exports.alloc)(...args);
    },
    free(...args) {
      calls.free.push(args);
      return (overrides.free ?? instance.exports.free)(...args);
    },
    lint(...args) {
      calls.lint.push(args);
      return (overrides.lint ?? instance.exports.lint)(...args);
    },
    abi_version: overrides.abi_version ?? instance.exports.abi_version,
  };
  const instrumentedInstance = new Proxy(instance, {
    get(target, property) {
      if (property === "exports") return instrumentedExports;
      return Reflect.get(target, property, target);
    },
  });
  return { calls, instance, instrumentedInstance };
}

test("loads the packaged WebAssembly module", async () => {
  const linter = await createUtooLint();
  assert.equal(linter.abiVersion, 1);
  const result = linter.lint("debugger;", {
    filePath: "input.js",
    rules: { "no-debugger": "warn" },
  });
  assert.equal(result.diagnostics[0]?.severity, "warning");
});

test("provides a lazy convenience API", async () => {
  const result = await lint("const value = 1;;;", {
    filePath: "input.js",
    rules: { "no-extra-semi": "error" },
  });
  assert.ok(result.diagnostics.some((item) => item.ruleId === "no-extra-semi"));
});

test("reports strict syntax as parse errors with empty rules", async () => {
  const linter = await createUtooLint();
  for (const source of ["delete x;", "with (obj) {}"]) {
    const result = linter.lint(source, { filePath: "input.js", rules: {} });
    assert.equal(result.diagnostics.length, 1);
    assert.equal(result.diagnostics[0].ruleId, "parse");
    assert.equal(result.diagnostics[0].severity, "error");
    assert.deepEqual(linter.lint(source, { filePath: "input.js", sourceType: "script", rules: {} }).diagnostics, []);
    const strict = linter.lint(`'use strict'; ${source}`, { filePath: "input.cjs", rules: {} });
    assert.equal(strict.diagnostics.length, 1);
    assert.equal(strict.diagnostics[0].ruleId, "parse");
    const unknownDirective = linter.lint(`// eslint-disable-next-line unknown-rule\n${source}`, { filePath: "input.js", rules: {} });
    assert.deepEqual(unknownDirective.diagnostics.map(({ ruleId }) => ruleId), ["parse"]);
  }
  assert.throws(
    () => linter.lint("delete x;", { sourceType: "unknown", rules: {} }),
    (error) => error instanceof UtooLintWasmError && error.code === "INVALID_OPTIONS"
  );
});

test("exposes jest/valid-title diagnostics and autofixes", async () => {
  const linter = await createUtooLint();
  const checked = linter.lint("test(' forbidden ', () => {});", {
    filePath: "input.jsx",
    rules: {
      "jest/valid-title": ["error", { disallowedWords: ["forbidden"] }],
    },
  });
  assert.equal(checked.diagnostics.length, 1);
  assert.equal(checked.diagnostics[0]?.ruleId, "jest/valid-title");

  const fixed = linter.lintAndFix("test('test works ', () => {});", {
    filePath: "input.tsx",
    rules: { "jest/valid-title": "error" },
  });
  assert.equal(fixed.fixed, true);
  assert.equal(fixed.output, "test('works', () => {});");
});

test("loads browser-friendly Response, byte, and compiled module inputs", async () => {
  const bytes = await wasmBytesPromise;
  const response = new Response(bytes, {
    headers: { "content-type": "application/octet-stream" },
  });
  const fromResponse = await createUtooLint({ wasm: response });
  const fromBytes = await createUtooLint({ wasm: new Uint8Array(bytes) });
  const fromModule = await createUtooLint({ wasm: await WebAssembly.compile(bytes) });

  for (const linter of [fromResponse, fromBytes, fromModule]) {
    assert.equal(linter.lint("", { rules: {} }).diagnostics.length, 0);
  }
});

test("keeps working after memory growth and releases every owned buffer", async () => {
  const { calls, instance, instrumentedInstance } = await instantiateInstrumented();
  const linter = await createUtooLint({ wasm: instrumentedInstance });
  const initialMemory = instance.exports.memory.buffer.byteLength;
  const source = `${"// padding\n".repeat(10_000)}debugger;`;

  for (let iteration = 0; iteration < 3; iteration += 1) {
    const result = linter.lint(source, {
      rules: { "no-debugger": "error" },
    });
    assert.equal(result.diagnostics[0]?.ruleId, "no-debugger");
  }

  assert.ok(instance.exports.memory.buffer.byteLength > initialMemory);
  assert.equal(calls.alloc.length, 6);
  assert.equal(calls.lint.length, 3);
  assert.equal(calls.free.length, 9);
});

test("exposes structured lint failures and still releases the ABI buffers", async () => {
  const { calls, instrumentedInstance } = await instantiateInstrumented();
  const linter = await createUtooLint({ wasm: instrumentedInstance });

  assert.throws(
    () => linter.lint("", { rules: { "unknown/rule": "error" } }),
    (error) => {
      assert.ok(error instanceof UtooLintWasmError);
      assert.equal(error.code, "UNKNOWN_RULE");
      assert.equal(error.ruleId, "unknown/rule");
      return true;
    },
  );
  assert.equal(calls.free.length, 3);
});

test("normalizes malformed ABI responses and releases their result allocation", async () => {
  let memory;
  let nativeAlloc;
  const setup = await instantiateInstrumented({
    lint() {
      const pointer = nativeAlloc(5);
      const view = new DataView(memory.buffer);
      view.setUint32(pointer, 1, true);
      view.setUint8(pointer + 4, "{".charCodeAt(0));
      return pointer;
    },
  });
  memory = setup.instance.exports.memory;
  nativeAlloc = setup.instance.exports.alloc;
  const linter = await createUtooLint({ wasm: setup.instrumentedInstance });

  assert.throws(
    () => linter.lint("", { rules: {} }),
    (error) => {
      assert.ok(error instanceof UtooLintWasmError);
      assert.equal(error.code, "invalid_result_json");
      assert.ok(error.cause instanceof SyntaxError);
      return true;
    },
  );
  assert.equal(setup.calls.free.length, 3);
});

test("rejects unsupported ABI versions before allocating", async () => {
  const setup = await instantiateInstrumented({ abi_version: () => 2 });
  await assert.rejects(
    createUtooLint({ wasm: setup.instrumentedInstance }),
    (error) => error instanceof UtooLintWasmError && error.code === "unsupported_abi_version",
  );
  assert.equal(setup.calls.alloc.length, 0);
});

test("rejects oversized options before allocating WebAssembly memory", async () => {
  const setup = await instantiateInstrumented();
  const linter = await createUtooLint({ wasm: setup.instrumentedInstance });

  assert.throws(
    () => linter.lint("", { filePath: "x".repeat(1024 * 1024), rules: {} }),
    (error) => error instanceof UtooLintWasmError && error.code === "REQUEST_TOO_LARGE",
  );
  assert.equal(setup.calls.alloc.length, 0);
});

test("rejects failed allocations without writing to or freeing address zero", async () => {
  let allocation = 0;
  let nativeAlloc;
  const setup = await instantiateInstrumented({
    alloc(length) {
      allocation += 1;
      return allocation === 2 ? 0 : nativeAlloc(length);
    },
  });
  nativeAlloc = setup.instance.exports.alloc;
  const linter = await createUtooLint({ wasm: setup.instrumentedInstance });

  assert.throws(
    () => linter.lint("debugger;", { rules: { "no-debugger": "error" } }),
    (error) => error instanceof UtooLintWasmError && error.code === "wasm_out_of_memory",
  );
  assert.equal(setup.calls.free.length, 1);
  assert.notEqual(setup.calls.free[0][0], 0);
});

test("validates the result header before reading across memory", async () => {
  const setup = await instantiateInstrumented({
    lint() {
      return 0xffff_ffff;
    },
  });
  const linter = await createUtooLint({ wasm: setup.instrumentedInstance });

  assert.throws(
    () => linter.lint("", { rules: {} }),
    (error) => error instanceof UtooLintWasmError && error.code === "invalid_result_buffer",
  );
  assert.equal(setup.calls.free.length, 2);
});
