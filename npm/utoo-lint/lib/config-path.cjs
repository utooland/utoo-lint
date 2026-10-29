"use strict";

const { realpathSync } = require("node:fs");
const { isAbsolute } = require("node:path");

// Shared by the ESM and CommonJS helpers, including helpers imported by a
// preset. Keep the entry active while its own extends are being expanded.
const activePaths = [];

function isConfigPath(value) {
  return isAbsolute(value);
}

function withConfigPath(configPath, expand) {
  const canonicalPath = realpathSync(configPath);
  if (activePaths.includes(canonicalPath)) {
    throw new TypeError(`Circular config extends: ${[...activePaths, canonicalPath].join(" -> ")}`);
  }
  activePaths.push(canonicalPath);
  try {
    // Load executable presets with the same Node/TypeScript support used by
    // the application config. Do not load jiti for object-only configurations.
    const { readConfigModule } = require("./config-module.cjs");
    const value = readConfigModule(canonicalPath);
    if (value === null || typeof value !== "object") {
      throw new TypeError(`Config file "${configPath}" must export a config object or array, received ${typeof value}.`);
    }
    return expand(value);
  } finally {
    activePaths.pop();
  }
}

module.exports = { isConfigPath, withConfigPath };
