"use strict";

// Runs ESLint plugin rule listeners over an ESTree AST.
//
// Listener keys are esquery selectors (`Identifier`, `CallExpression > Literal`,
// `Program:exit`, ...). This mirrors ESLint's NodeEventGenerator: selectors are
// parsed once, indexed by the node types they can match, and applied in
// specificity order while the AST is traversed with the parser's visitor keys.
//
// CommonJS on purpose: shared by the ESM and CommonJS entry points.

const esquery = require("esquery");

const NON_CHILD_KEYS = new Set(["type", "start", "end", "range", "loc", "parent", "comments", "tokens"]);

function isNode(value) {
  return value !== null && typeof value === "object" && typeof value.type === "string";
}

function fallbackKeys(node) {
  return Object.keys(node).filter((key) => !NON_CHILD_KEYS.has(key));
}

function childKeys(node, visitorKeys) {
  return visitorKeys?.[node.type] ?? fallbackKeys(node);
}

function possibleTypes(selector) {
  switch (selector.type) {
    case "identifier":
      return [selector.value];
    case "matches": {
      const types = [];
      for (const child of selector.selectors) {
        const childTypes = possibleTypes(child);
        if (!childTypes) {
          return null;
        }
        types.push(...childTypes);
      }
      return types;
    }
    case "compound": {
      const typesForComponents = selector.selectors.map(possibleTypes).filter(Boolean);
      return typesForComponents.length === 0 ? null : typesForComponents[0];
    }
    case "child":
    case "descendant":
    case "sibling":
    case "adjacent":
      return possibleTypes(selector.right);
    case "class":
      if (selector.name === "function") {
        return ["FunctionDeclaration", "FunctionExpression", "ArrowFunctionExpression"];
      }
      return null;
    default:
      return null;
  }
}

function countClassAttributes(selector) {
  switch (selector.type) {
    case "child":
    case "descendant":
    case "sibling":
    case "adjacent":
      return countClassAttributes(selector.left) + countClassAttributes(selector.right);
    case "compound":
    case "not":
    case "matches":
      return selector.selectors.reduce((sum, child) => sum + countClassAttributes(child), 0);
    case "attribute":
    case "field":
    case "nth-child":
    case "nth-last-child":
      return 1;
    default:
      return 0;
  }
}

function countIdentifiers(selector) {
  switch (selector.type) {
    case "child":
    case "descendant":
    case "sibling":
    case "adjacent":
      return countIdentifiers(selector.left) + countIdentifiers(selector.right);
    case "compound":
    case "not":
    case "matches":
      return selector.selectors.reduce((sum, child) => sum + countIdentifiers(child), 0);
    case "identifier":
      return 1;
    default:
      return 0;
  }
}

function compareSpecificity(left, right) {
  return left.attributeCount - right.attributeCount
    || left.identifierCount - right.identifierCount
    || (left.rawSelector <= right.rawSelector ? -1 : 1);
}

const selectorCache = new Map();

function parseSelector(rawSelector) {
  if (selectorCache.has(rawSelector)) {
    return selectorCache.get(rawSelector);
  }
  const isExit = rawSelector.endsWith(":exit");
  const source = isExit ? rawSelector.slice(0, -":exit".length) : rawSelector;
  let parsedSelector;
  try {
    parsedSelector = esquery.parse(source.replace(/:exit$/u, ""));
  } catch (error) {
    const wrapped = new SyntaxError(`Syntax error in selector "${source}": ${error.message}`);
    wrapped.cause = error;
    throw wrapped;
  }
  const selector = {
    rawSelector,
    isExit,
    parsedSelector,
    listenerTypes: possibleTypes(parsedSelector),
    attributeCount: countClassAttributes(parsedSelector),
    identifierCount: countIdentifiers(parsedSelector)
  };
  selectorCache.set(rawSelector, selector);
  return selector;
}

function indexSelectors(selectors) {
  const byType = new Map();
  const anyType = [];
  for (const selector of selectors) {
    if (selector.listenerTypes) {
      for (const type of selector.listenerTypes) {
        if (!byType.has(type)) {
          byType.set(type, []);
        }
        byType.get(type).push(selector);
      }
    } else {
      anyType.push(selector);
    }
  }
  for (const list of byType.values()) {
    list.sort(compareSpecificity);
  }
  anyType.sort(compareSpecificity);
  return { byType, anyType };
}

function wrapListenerError(error, entry, node) {
  if (error && typeof error === "object" && !error.utooLintRuleId) {
    const location = node?.loc?.start ? ` at ${node.loc.start.line}:${node.loc.start.column + 1}` : "";
    const wrapped = new Error(`Error while running ESLint plugin rule "${entry.ruleId}"${location}: ${error.message}`);
    wrapped.cause = error;
    wrapped.stack = `${wrapped.message}\n${error.stack ?? ""}`;
    wrapped.utooLintRuleId = entry.ruleId;
    return wrapped;
  }
  return error;
}

/**
 * Traverse `program` and invoke matching listeners.
 *
 * `listenersBySelector` maps a raw selector string to entries of shape
 * `{ ruleId, listener }`. Listeners for the same selector are invoked in
 * registration order; different selectors are ordered by specificity.
 */
function runRuleListeners(program, listenersBySelector, options = {}) {
  const visitorKeys = options.visitorKeys ?? null;
  const esqueryOptions = {
    visitorKeys: visitorKeys ?? undefined,
    fallback: fallbackKeys
  };
  const selectors = [];
  const entriesBySelector = new Map();
  for (const [rawSelector, entries] of listenersBySelector) {
    const selector = parseSelector(rawSelector);
    selectors.push(selector);
    entriesBySelector.set(selector, entries);
  }
  const enter = indexSelectors(selectors.filter((selector) => !selector.isExit));
  const exit = indexSelectors(selectors.filter((selector) => selector.isExit));
  const ancestry = [];

  function apply(index, node) {
    const typed = index.byType.get(node.type) ?? [];
    const untyped = index.anyType;
    let typedIndex = 0;
    let untypedIndex = 0;
    while (typedIndex < typed.length || untypedIndex < untyped.length) {
      let selector;
      if (untypedIndex >= untyped.length || (typedIndex < typed.length && compareSpecificity(typed[typedIndex], untyped[untypedIndex]) < 0)) {
        selector = typed[typedIndex];
        typedIndex += 1;
      } else {
        selector = untyped[untypedIndex];
        untypedIndex += 1;
      }
      if (!esquery.matches(node, selector.parsedSelector, ancestry, esqueryOptions)) {
        continue;
      }
      for (const entry of entriesBySelector.get(selector)) {
        try {
          entry.listener(node);
        } catch (error) {
          throw wrapListenerError(error, entry, node);
        }
      }
    }
  }

  function visit(node) {
    apply(enter, node);
    ancestry.unshift(node);
    for (const key of childKeys(node, visitorKeys)) {
      const value = node[key];
      if (Array.isArray(value)) {
        for (const item of value) {
          if (isNode(item)) {
            visit(item);
          }
        }
      } else if (isNode(value)) {
        visit(value);
      }
    }
    ancestry.shift();
    apply(exit, node);
  }

  visit(program);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function deepMergeDefaults(defaults, value) {
  if (value === undefined) {
    return structuredCloneSafe(defaults);
  }
  if (isPlainObject(defaults) && isPlainObject(value)) {
    const result = { ...value };
    for (const [key, defaultValue] of Object.entries(defaults)) {
      result[key] = deepMergeDefaults(defaultValue, value[key]);
    }
    return result;
  }
  return value;
}

function structuredCloneSafe(value) {
  if (Array.isArray(value)) {
    return value.map(structuredCloneSafe);
  }
  if (isPlainObject(value)) {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, structuredCloneSafe(item)]));
  }
  return value;
}

function schemaItemAt(schema, index) {
  if (Array.isArray(schema)) {
    return schema[index];
  }
  if (!isPlainObject(schema)) {
    return undefined;
  }
  if (Array.isArray(schema.items)) {
    return schema.items[index];
  }
  if (isPlainObject(schema.items)) {
    return schema.items;
  }
  if (Array.isArray(schema.prefixItems)) {
    return schema.prefixItems[index];
  }
  return undefined;
}

// Applies JSON-schema `default` values the way ESLint's validator does: only
// properties of objects the user actually passed are filled in.
function applySchemaDefaults(schema, value) {
  if (!isPlainObject(schema)) {
    return value;
  }
  if (isPlainObject(value) && isPlainObject(schema.properties)) {
    const result = { ...value };
    for (const [key, propertySchema] of Object.entries(schema.properties)) {
      if (!isPlainObject(propertySchema)) {
        continue;
      }
      if (result[key] === undefined && propertySchema.default !== undefined) {
        result[key] = structuredCloneSafe(propertySchema.default);
      }
      if (result[key] !== undefined) {
        result[key] = applySchemaDefaults(propertySchema, result[key]);
      }
    }
    return result;
  }
  if (Array.isArray(value) && isPlainObject(schema.items)) {
    return value.map((item) => applySchemaDefaults(schema.items, item));
  }
  return value;
}

/**
 * Compute the effective `context.options` for a rule: user options with
 * `meta.defaultOptions` merged in (ESLint >= 9.15) and JSON-schema defaults
 * filled in for the object options that were provided.
 */
function applyRuleOptionDefaults(rule, options = []) {
  const meta = rule?.meta ?? {};
  let result = Array.isArray(options) ? options.slice() : [];
  if (Array.isArray(meta.defaultOptions)) {
    const merged = [];
    const length = Math.max(meta.defaultOptions.length, result.length);
    for (let index = 0; index < length; index += 1) {
      merged.push(deepMergeDefaults(meta.defaultOptions[index], result[index]));
    }
    result = merged;
  }
  if (meta.schema) {
    result = result.map((value, index) => applySchemaDefaults(schemaItemAt(meta.schema, index), value));
  }
  return result;
}

module.exports = {
  applyRuleOptionDefaults,
  parseSelector,
  runRuleListeners
};
