"use strict";

// Loads a `utlint.config.{ts,js,mjs,cjs,mts,cts}` module in-process so that
// live plugin objects (with their `create()` functions) are available to the
// ESLint plugin runner. The native engine keeps receiving the serialized JSON
// form of the same config through `config-loader`.
//
// CommonJS on purpose: shared by the ESM and CommonJS entry points.

const { statSync } = require("node:fs");
const { resolve: resolvePath } = require("node:path");

const cache = new Map();

function configModuleValue(loaded) {
  if (loaded && typeof loaded === "object" && !Array.isArray(loaded) && "default" in loaded) {
    return loaded.default;
  }
  return loaded;
}

function readConfigModule(path, cwd) {
  const configPath = resolvePath(cwd ?? process.cwd(), path);
  let mtimeMs = 0;
  try {
    mtimeMs = statSync(configPath).mtimeMs;
  } catch {
    // Let jiti surface the actual filesystem error below.
  }
  const cached = cache.get(configPath);
  if (cached && cached.mtimeMs === mtimeMs) {
    return cached.value;
  }

  const { createJiti } = require("jiti");
  const jiti = createJiti(configPath, { interopDefault: true });
  let value;
  try {
    value = configModuleValue(jiti(configPath));
  } catch (error) {
    throw new Error(`utoo-lint unable to load config ${configPath}: ${error?.message ?? error}`, { cause: error });
  }
  cache.set(configPath, { mtimeMs, value });
  return value;
}

function clearConfigModuleCache() {
  cache.clear();
}

module.exports = {
  clearConfigModuleCache,
  readConfigModule
};
