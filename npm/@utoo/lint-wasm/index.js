const defaultWasmUrl = new URL("./utoo-lint.wasm", import.meta.url);
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const ABI_VERSION = 1;
const MAX_SOURCE_BYTES = 64 * 1024 * 1024;
const MAX_OPTIONS_BYTES = 1024 * 1024;

let defaultLinterPromise;

export class UtooLintWasmError extends Error {
  constructor(message, options = {}) {
    super(message, options.cause === undefined ? undefined : { cause: options.cause });
    this.name = "UtooLintWasmError";
    this.code = options.code ?? "wasm_error";
    this.ruleId = options.ruleId;
  }
}

export async function createUtooLint(options = {}) {
  const instance = await instantiate(options.wasm ?? defaultWasmUrl, options.imports ?? {});
  return createApi(instance);
}

export async function lint(source, options) {
  defaultLinterPromise ??= createUtooLint();
  return (await defaultLinterPromise).lint(source, options);
}

export async function lintAndFix(source, options) {
  defaultLinterPromise ??= createUtooLint();
  return (await defaultLinterPromise).lintAndFix(source, options);
}

function createApi(instance) {
  const exports = instance?.exports;
  if (
    !(exports?.memory instanceof WebAssembly.Memory) ||
    typeof exports.alloc !== "function" ||
    typeof exports.free !== "function" ||
    typeof exports.lint !== "function" ||
    typeof exports.abi_version !== "function"
  ) {
    throw new UtooLintWasmError("Invalid utoo-lint WebAssembly module", {
      code: "invalid_wasm_module"
    });
  }

  const version = exports.abi_version();
  if (version !== ABI_VERSION) {
    throw new UtooLintWasmError(
      `Unsupported utoo-lint WebAssembly ABI version ${version}; expected ${ABI_VERSION}`,
      { code: "unsupported_abi_version" }
    );
  }

  function run(source, options = {}, fix = false) {
    if (typeof source !== "string") {
      throw new TypeError("source must be a string");
    }

    const sourceBytes = encoder.encode(source);
    assertRequestSize(sourceBytes.length, MAX_SOURCE_BYTES, "source", "64 MiB");
    const optionsBytes = encoder.encode(JSON.stringify({
      version: ABI_VERSION,
      filePath: options.filePath ?? options.filename ?? "input.js",
      ...(options.sourceType === undefined ? {} : { sourceType: options.sourceType }),
      fix: fix ? "apply" : "none",
      ...(options.rules === undefined ? {} : { rules: options.rules }),
      ...(options.settings === undefined ? {} : { settings: options.settings })
    }));
    assertRequestSize(optionsBytes.length, MAX_OPTIONS_BYTES, "options", "1 MiB");

    const sourceAllocationLength = sourceBytes.length || 1;
    const optionsAllocationLength = optionsBytes.length || 1;
    const sourcePtr = allocate(exports, sourceBytes.length, "source");
    let optionsPtr = 0;
    let resultPtr = 0;
    let resultAllocationLength = 0;

    try {
      new Uint8Array(exports.memory.buffer, sourcePtr, sourceBytes.length).set(sourceBytes);
      optionsPtr = allocate(exports, optionsBytes.length, "options");
      new Uint8Array(exports.memory.buffer, optionsPtr, optionsBytes.length).set(optionsBytes);

      resultPtr = exports.lint(sourcePtr, sourceBytes.length, optionsPtr, optionsBytes.length);
      if (resultPtr === 0) {
        throw new UtooLintWasmError("utoo-lint WebAssembly execution failed", {
          code: "wasm_execution_failed"
        });
      }

      const memoryByteLength = exports.memory.buffer.byteLength;
      if (!Number.isInteger(resultPtr) || resultPtr < 0 || resultPtr > memoryByteLength - 4) {
        throw new UtooLintWasmError("utoo-lint WebAssembly returned an invalid buffer", {
          code: "invalid_result_buffer"
        });
      }

      const resultLength = new DataView(exports.memory.buffer).getUint32(resultPtr, true);
      resultAllocationLength = 4 + resultLength;
      if (resultAllocationLength > memoryByteLength - resultPtr) {
        resultAllocationLength = 0;
        throw new UtooLintWasmError("utoo-lint WebAssembly returned an invalid buffer", {
          code: "invalid_result_buffer"
        });
      }

      let result;
      try {
        const json = decoder.decode(
          new Uint8Array(exports.memory.buffer, resultPtr + 4, resultLength)
        );
        result = JSON.parse(json);
      } catch (cause) {
        throw new UtooLintWasmError("utoo-lint WebAssembly returned invalid JSON", {
          code: "invalid_result_json",
          cause
        });
      }
      if (!result.ok) {
        throw new UtooLintWasmError(result.error?.message ?? "utoo-lint failed", {
          code: result.error?.code,
          ruleId: result.error?.ruleId
        });
      }
      return result;
    } finally {
      if (resultPtr !== 0 && resultAllocationLength !== 0) {
        exports.free(resultPtr, resultAllocationLength);
      }
      if (optionsPtr !== 0) exports.free(optionsPtr, optionsAllocationLength);
      if (sourcePtr !== 0) exports.free(sourcePtr, sourceAllocationLength);
    }
  }

  return Object.freeze({
    abiVersion: version,
    lint: run,
    lintAndFix(source, options = {}) {
      return run(source, options, true);
    }
  });
}

function allocate(exports, length, name) {
  let pointer;
  try {
    pointer = exports.alloc(length);
  } catch (cause) {
    throw new UtooLintWasmError(`utoo-lint could not allocate the ${name} buffer`, {
      code: "wasm_allocation_failed",
      cause
    });
  }
  if (pointer === 0) {
    throw new UtooLintWasmError(`utoo-lint could not allocate the ${name} buffer`, {
      code: "wasm_out_of_memory"
    });
  }
  const allocationLength = length || 1;
  if (
    !Number.isInteger(pointer) ||
    pointer < 0 ||
    pointer > exports.memory.buffer.byteLength - allocationLength
  ) {
    throw new UtooLintWasmError(`utoo-lint returned an invalid ${name} allocation`, {
      code: "invalid_allocation"
    });
  }
  return pointer;
}

function assertRequestSize(actual, maximum, name, displayMaximum) {
  if (actual > maximum) {
    throw new UtooLintWasmError(`${name} exceeds the ${displayMaximum} WebAssembly limit`, {
      code: "REQUEST_TOO_LARGE"
    });
  }
}

async function instantiate(input, imports) {
  if (input instanceof WebAssembly.Instance) return input;
  if (input instanceof WebAssembly.Module) {
    return WebAssembly.instantiate(input, imports);
  }
  if (typeof Response !== "undefined" && input instanceof Response) {
    return instantiateResponse(input, imports);
  }
  if (input instanceof ArrayBuffer || ArrayBuffer.isView(input)) {
    return normalizeInstance(await WebAssembly.instantiate(input, imports));
  }

  const url = input instanceof URL ? input : new URL(input, import.meta.url);
  if (url.protocol === "file:") {
    // Keep the Node-only module specifier opaque to browser bundlers. This
    // branch is only reachable for file: URLs, including the default URL when
    // the package is used directly from Node.js.
    const nodeFsPromises = "node:fs/promises";
    const { readFile } = await import(nodeFsPromises);
    return normalizeInstance(await WebAssembly.instantiate(await readFile(url), imports));
  }
  return instantiateResponse(await fetch(url), imports);
}

async function instantiateResponse(response, imports) {
  if (!response.ok) {
    throw new UtooLintWasmError(
      `Unable to load utoo-lint WebAssembly: ${response.status} ${response.statusText}`,
      { code: "wasm_fetch_failed" }
    );
  }
  try {
    return normalizeInstance(await WebAssembly.instantiateStreaming(response.clone(), imports));
  } catch {
    return normalizeInstance(
      await WebAssembly.instantiate(await response.arrayBuffer(), imports)
    );
  }
}

function normalizeInstance(result) {
  return result instanceof WebAssembly.Instance ? result : result.instance;
}
