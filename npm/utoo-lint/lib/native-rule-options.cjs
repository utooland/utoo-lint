"use strict";

// JSON has no representation for Infinity or NaN, so JSON.stringify turns them
// into null and the native binary rejects the rule option with an opaque
// UnsupportedRuleConfigValue error. Options with a documented unlimited
// spelling are rewritten to it. Anything else fails with a message that names
// the rule and option, or becomes null again in lenient mode (used by the
// config loader subprocess, which cannot tell native rules from plugin rules).
const UNLIMITED = "∞";
const INFINITE_OPTION_SPELLINGS = {
  "import/no-cycle": { maxDepth: UNLIMITED }
};

function nativeRuleConfig(ruleId, ruleConfig, options = {}) {
  if (!Array.isArray(ruleConfig)) {
    return ruleConfig;
  }
  const strict = options.strict !== false;
  const spellings = INFINITE_OPTION_SPELLINGS[ruleId] ?? {};
  return ruleConfig.map((item, index) => {
    if (index === 0) {
      return item;
    }
    if (!isPlainObject(item)) {
      return nativeRuleOptionValue(ruleId, item, `[${index}]`, strict);
    }
    const seen = new WeakSet([item]);
    return Object.fromEntries(
      Object.entries(item).map(([key, value]) => [
        key,
        value === Infinity && Object.hasOwn(spellings, key)
          ? spellings[key]
          : nativeRuleOptionValue(ruleId, value, key, strict, seen)
      ])
    );
  });
}

function nativeRuleOptionValue(ruleId, value, path, strict, seen = new WeakSet()) {
  if (typeof value === "number") {
    if (Number.isFinite(value)) {
      return value;
    }
    if (!strict) {
      return null;
    }
    throw new TypeError(
      `Rule "${ruleId}" option "${path}" is ${String(value)}, which cannot be written to the native JSON config.`
    );
  }
  if (value === null || typeof value !== "object" || seen.has(value)) {
    return value;
  }
  seen.add(value);
  try {
    if (Array.isArray(value)) {
      return value.map((item, index) => nativeRuleOptionValue(ruleId, item, `${path}[${index}]`, strict, seen));
    }
    if (!isPlainObject(value)) {
      return value;
    }
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [
        key,
        nativeRuleOptionValue(ruleId, item, `${path}.${key}`, strict, seen)
      ])
    );
  } finally {
    seen.delete(value);
  }
}

function nativeRules(rules, options = {}) {
  if (!isPlainObject(rules)) {
    return rules;
  }
  return Object.fromEntries(
    Object.entries(rules).map(([ruleId, ruleConfig]) => [ruleId, nativeRuleConfig(ruleId, ruleConfig, options)])
  );
}

function nativeFlatConfigEntries(entries, options = {}) {
  if (!Array.isArray(entries)) {
    return entries;
  }
  return entries.map((entry) =>
    isPlainObject(entry) && entry.rules ? { ...entry, rules: nativeRules(entry.rules, options) } : entry
  );
}

function isPlainObject(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

module.exports = { nativeFlatConfigEntries, nativeRuleConfig, nativeRules };
