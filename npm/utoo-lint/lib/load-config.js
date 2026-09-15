import { dirname } from "node:path";
import { writeFileSync } from "node:fs";
import { createJiti } from "jiti";

const configPath = process.argv[2];

// Config modules may mount live ESLint plugin objects, which contain functions
// and frequently reference themselves (`plugin.configs.recommended.plugins`).
// Serialize them down to the rule names the wrapper needs to route rules; the
// plugin objects themselves are re-imported in-process when rules run.
function serializablePlugins(plugins, seen) {
  const result = {};
  for (const [name, plugin] of Object.entries(plugins)) {
    if (!plugin || typeof plugin !== "object") {
      continue;
    }
    const rules = {};
    for (const [ruleName, rule] of Object.entries(plugin.rules ?? {})) {
      rules[ruleName] = { meta: serializable(rule?.meta ?? {}, seen) ?? {} };
    }
    result[name] = {
      ...(plugin.meta && typeof plugin.meta === "object" ? { meta: serializable(plugin.meta, seen) ?? {} } : {}),
      rules
    };
  }
  return result;
}

function serializable(value, seen = new WeakSet()) {
  if (value === null || typeof value === "string" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === "bigint") {
    return value.toString();
  }
  if (typeof value !== "object") {
    return undefined;
  }
  if (typeof value.toJSON === "function") {
    return serializable(value.toJSON(), seen);
  }
  if (seen.has(value)) {
    return undefined;
  }
  seen.add(value);
  try {
    if (Array.isArray(value)) {
      return value.map((item) => {
        const item2 = serializable(item, seen);
        return item2 === undefined ? null : item2;
      });
    }
    const result = {};
    for (const [key, item] of Object.entries(value)) {
      if (key === "plugins" && item && typeof item === "object" && !Array.isArray(item)) {
        result.plugins = serializablePlugins(item, seen);
        continue;
      }
      const serialized = serializable(item, seen);
      if (serialized !== undefined) {
        result[key] = serialized;
      }
    }
    return result;
  } finally {
    seen.delete(value);
  }
}

try {
  if (!configPath) {
    throw new TypeError("missing config path");
  }
  const jiti = createJiti(dirname(configPath));
  const value = await jiti.import(configPath, { default: true });
  const json = JSON.stringify(serializable(value));
  if (json === undefined) {
    throw new TypeError("config did not export a JSON-serializable value");
  }
  // fd 3 is a private serialization channel created by config-loader. Config
  // code may write to stdout without corrupting the JSON payload.
  writeFileSync(3, json);
} catch (error) {
  console.error(error?.stack ?? error?.message ?? String(error));
  process.exitCode = 1;
}
