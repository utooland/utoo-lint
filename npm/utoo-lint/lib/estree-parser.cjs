"use strict";

// ESLint-compatible parser adapter used to run community ESLint plugin rules.
//
// The native lint engine keeps its own AST in Zig. Plugin rules are JavaScript
// and expect the ESTree shape that ESLint hands to `create(context)`, so this
// module parses the file a second time with yuku-parser (the same parser the
// engine is built on), then decorates the tree with `range`, `loc`, `parent`,
// a token stream, comments, and a lazily computed scope manager.
//
// This file is CommonJS on purpose: it is shared by the ESM (`index.js`) and
// CommonJS (`index.cjs`) entry points.

const { extname } = require("node:path");
const { visitorKeys: TS_VISITOR_KEYS } = require("@typescript-eslint/visitor-keys");

const VISITOR_KEYS = Object.freeze({ ...TS_VISITOR_KEYS });

const NON_CHILD_KEYS = new Set(["type", "start", "end", "range", "loc", "parent", "comments", "tokens"]);

const JS_KEYWORDS = new Set([
  "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do",
  "else", "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof",
  "let", "new", "return", "static", "super", "switch", "this", "throw", "try", "typeof", "var",
  "void", "while", "with", "yield"
]);

const TS_KEYWORDS = new Set([
  "abstract", "any", "as", "asserts", "async", "await", "bigint", "boolean", "declare", "enum",
  "from", "get", "global", "implements", "infer", "interface", "is", "keyof", "module", "namespace",
  "never", "number", "object", "of", "out", "override", "private", "protected", "public", "readonly",
  "require", "satisfies", "set", "string", "symbol", "type", "undefined", "unique", "unknown"
]);

const PUNCTUATORS = [
  ">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=",
  "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=", "*=", "/=",
  "%=", "&=", "|=", "^=", "**", "<<", ">>"
];

const ECMASCRIPT_GLOBALS = [
  "AggregateError", "Array", "ArrayBuffer", "Atomics", "BigInt", "BigInt64Array", "BigUint64Array",
  "Boolean", "DataView", "Date", "decodeURI", "decodeURIComponent", "encodeURI", "encodeURIComponent",
  "Error", "escape", "eval", "EvalError", "FinalizationRegistry", "Float16Array", "Float32Array",
  "Float64Array", "Function", "globalThis", "Infinity", "Int16Array", "Int32Array", "Int8Array",
  "Intl", "isFinite", "isNaN", "Iterator", "JSON", "Map", "Math", "NaN", "Number", "Object",
  "parseFloat", "parseInt", "Promise", "Proxy", "RangeError", "ReferenceError", "Reflect", "RegExp",
  "Set", "SharedArrayBuffer", "String", "Symbol", "SyntaxError", "TypeError", "Uint16Array",
  "Uint32Array", "Uint8Array", "Uint8ClampedArray", "undefined", "unescape", "URIError", "WeakMap",
  "WeakRef", "WeakSet"
];

const COMMONJS_GLOBALS = {
  exports: "writable",
  global: "readonly",
  module: "readonly",
  require: "readonly",
  __dirname: "readonly",
  __filename: "readonly"
};

let yukuModule = null;
let yukuLoadError = null;

function loadYuku() {
  if (yukuModule) {
    return yukuModule;
  }
  if (yukuLoadError) {
    throw yukuLoadError;
  }
  try {
    // yuku-parser is an ES module. Loading it synchronously from CommonJS
    // relies on require(esm), which Node.js 20.19+ and 22.12+ support.
    yukuModule = require("yuku-parser");
  } catch (error) {
    yukuLoadError = new Error(
      "utoo-lint: unable to load yuku-parser, which is required to run ESLint plugin rules. " +
        "Plugin rules need Node.js 20.19 or newer (or 22.12 or newer). " +
        `Underlying error: ${error?.message ?? error}`
    );
    yukuLoadError.cause = error;
    throw yukuLoadError;
  }
  return yukuModule;
}

function isNativeParserAvailable() {
  try {
    loadYuku();
    return true;
  } catch {
    return false;
  }
}

function languageForFile(filePath, ecmaFeatures) {
  const lower = String(filePath ?? "").toLowerCase();
  if (lower.endsWith(".d.ts") || lower.endsWith(".d.mts") || lower.endsWith(".d.cts")) {
    return "dts";
  }
  const extension = extname(lower);
  if (extension === ".tsx") {
    return "tsx";
  }
  if (extension === ".ts" || extension === ".mts" || extension === ".cts") {
    return "ts";
  }
  if (extension === ".jsx") {
    return "jsx";
  }
  return ecmaFeatures?.jsx === false ? "js" : "jsx";
}

function isTypeScriptLanguage(lang) {
  return lang === "ts" || lang === "tsx" || lang === "dts";
}

function sourceTypeForFile(filePath, requested) {
  if (requested === "script" || requested === "module" || requested === "commonjs") {
    return requested;
  }
  const extension = extname(String(filePath ?? "").toLowerCase());
  return extension === ".cjs" || extension === ".cts" ? "commonjs" : "module";
}

function lineStartIndices(text) {
  const indices = [0];
  for (let index = 0; index < text.length; index += 1) {
    if (text[index] === "\n") {
      indices.push(index + 1);
    }
  }
  return indices;
}

function createLocator(text) {
  const lineStarts = lineStartIndices(text);
  return (index) => {
    let low = 0;
    let high = lineStarts.length - 1;
    while (low < high) {
      const middle = (low + high + 1) >> 1;
      if (lineStarts[middle] <= index) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return { line: low + 1, column: index - lineStarts[low] };
  };
}

function isNode(value) {
  return value !== null && typeof value === "object" && typeof value.type === "string";
}

function childKeys(node) {
  const keys = VISITOR_KEYS[node.type];
  if (keys) {
    return keys;
  }
  return Object.keys(node).filter((key) => !NON_CHILD_KEYS.has(key));
}

function forEachChild(node, callback) {
  for (const key of childKeys(node)) {
    const value = node[key];
    if (Array.isArray(value)) {
      for (const item of value) {
        if (isNode(item)) {
          callback(item);
        }
      }
    } else if (isNode(value)) {
      callback(value);
    }
  }
}

const JSX_ENTITIES = {
  amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: "\u00a0", copy: "\u00a9", reg: "\u00ae",
  trade: "\u2122", hellip: "\u2026", mdash: "\u2014", ndash: "\u2013", laquo: "\u00ab", raquo: "\u00bb",
  lsquo: "\u2018", rsquo: "\u2019", ldquo: "\u201c", rdquo: "\u201d", times: "\u00d7", divide: "\u00f7",
  euro: "\u20ac", pound: "\u00a3", yen: "\u00a5", cent: "\u00a2", deg: "\u00b0", plusmn: "\u00b1",
  middot: "\u00b7", bull: "\u2022", larr: "\u2190", rarr: "\u2192", uarr: "\u2191", darr: "\u2193",
  hearts: "\u2665", sect: "\u00a7", para: "\u00b6", iexcl: "\u00a1", iquest: "\u00bf", frac12: "\u00bd",
  frac14: "\u00bc", frac34: "\u00be", micro: "\u00b5", ensp: "\u2002", emsp: "\u2003", thinsp: "\u2009",
  zwnj: "\u200c", zwj: "\u200d", shy: "\u00ad", infin: "\u221e", ne: "\u2260", le: "\u2264", ge: "\u2265"
};

// ESLint's parsers expose entity-decoded JSX text and attribute values while
// keeping `raw` intact; mirror that for the common entities.
function decodeJsxEntities(value) {
  if (typeof value !== "string" || !value.includes("&")) {
    return value;
  }
  return value.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);/gu, (match, entity) => {
    if (entity[0] === "#") {
      const codePoint = entity[1] === "x" || entity[1] === "X" ? Number.parseInt(entity.slice(2), 16) : Number.parseInt(entity.slice(1), 10);
      return Number.isFinite(codePoint) && codePoint <= 0x10ffff ? String.fromCodePoint(codePoint) : match;
    }
    return Object.hasOwn(JSX_ENTITIES, entity) ? JSX_ENTITIES[entity] : match;
  });
}

function setParent(node, parent) {
  Object.defineProperty(node, "parent", {
    value: parent,
    writable: true,
    configurable: true,
    enumerable: false
  });
}

function decorateNode(node, locate) {
  node.range = [node.start, node.end];
  node.loc = { start: locate(node.start), end: locate(node.end) };
}

function normalizeTree(program, text, locate) {
  const stack = [[program, null]];
  while (stack.length > 0) {
    const [node, parent] = stack.pop();
    if (node.type === "TemplateElement") {
      // ESLint's parsers include the surrounding backticks and `${`/`}`
      // delimiters in a template element's range.
      node.start -= 1;
      node.end += node.tail ? 1 : 2;
    }
    decorateNode(node, locate);
    setParent(node, parent);
    if (node.type === "JSXText" || (node.type === "Literal" && parent?.type === "JSXAttribute")) {
      node.value = decodeJsxEntities(node.value);
    }
    forEachChild(node, (child) => stack.push([child, node]));
  }
  program.start = 0;
  program.end = text.length;
  decorateNode(program, locate);
}

function normalizeComments(program, comments, text, locate) {
  const result = [];
  if (program.hashbang && typeof program.hashbang === "object") {
    const { start, end } = program.hashbang;
    result.push({ type: "Hashbang", value: text.slice(start + 2, end), start, end, range: [start, end], loc: { start: locate(start), end: locate(end) } });
  }
  delete program.hashbang;
  for (const comment of comments) {
    result.push({
      type: comment.type,
      value: comment.value,
      start: comment.start,
      end: comment.end,
      range: [comment.start, comment.end],
      loc: { start: locate(comment.start), end: locate(comment.end) }
    });
  }
  result.sort((left, right) => left.start - right.start);
  return result;
}

function token(type, text, start, end, locate) {
  return {
    type,
    value: text.slice(start, end),
    start,
    end,
    range: [start, end],
    loc: { start: locate(start), end: locate(end) }
  };
}

function identifierRange(node, text) {
  const name = node.name;
  if (typeof name !== "string" || name.length === 0) {
    return [node.start, node.end];
  }
  if (text.startsWith(name, node.start)) {
    return [node.start, node.start + name.length];
  }
  const index = text.indexOf(name, node.start);
  if (index !== -1 && index + name.length <= node.end) {
    return [index, index + name.length];
  }
  return [node.start, node.end];
}

function literalTokenType(node) {
  if (node.regex && typeof node.regex === "object") {
    return "RegularExpression";
  }
  if (typeof node.value === "string") {
    return node.parent?.type === "JSXAttribute" ? "JSXText" : "String";
  }
  if (typeof node.value === "boolean") {
    return "Boolean";
  }
  if (node.value === null && node.raw === "null") {
    return "Null";
  }
  return "Numeric";
}

function collectLeafTokens(program, text, locate) {
  const leaves = [];
  const singleCharPositions = new Set();
  const stack = [program];
  while (stack.length > 0) {
    const node = stack.pop();
    switch (node.type) {
      case "Identifier": {
        const [start, end] = identifierRange(node, text);
        const isMeta = node.parent?.type === "MetaProperty" && node.parent.meta === node;
        leaves.push(token(isMeta ? "Keyword" : "Identifier", text, start, end, locate));
        break;
      }
      case "PrivateIdentifier": {
        const leaf = token("PrivateIdentifier", text, node.start, node.end, locate);
        leaf.value = node.name;
        leaves.push(leaf);
        break;
      }
      case "JSXIdentifier":
        leaves.push(token("JSXIdentifier", text, node.start, node.end, locate));
        break;
      case "JSXText":
        if (node.end > node.start) {
          const leaf = token("JSXText", text, node.start, node.end, locate);
          if (typeof node.value === "string") {
            leaf.value = node.value;
          }
          leaves.push(leaf);
        }
        break;
      case "Literal":
        leaves.push(token(literalTokenType(node), text, node.start, node.end, locate));
        break;
      case "TemplateElement":
        leaves.push(token("Template", text, node.start, node.end, locate));
        break;
      case "TSTypeParameterInstantiation":
      case "TSTypeParameterDeclaration":
        singleCharPositions.add(node.start);
        singleCharPositions.add(node.end - 1);
        break;
      default:
        break;
    }
    forEachChild(node, (child) => stack.push(child));
  }
  leaves.sort((left, right) => left.start - right.start);
  return { leaves, singleCharPositions };
}

function isWhitespace(code) {
  return code === 0x20 || code === 0x09 || code === 0x0a || code === 0x0d || code === 0x0b || code === 0x0c
    || code === 0xa0 || code === 0xfeff || code === 0x2028 || code === 0x2029
    || (code >= 0x1680 && /\s/u.test(String.fromCharCode(code)));
}

const IDENTIFIER_START = /[$_\p{ID_Start}]/u;
const IDENTIFIER_PART = /[$_‌‍\p{ID_Continue}]/u;

function readWord(text, index, limit) {
  let end = index;
  while (end < limit) {
    const char = text[end];
    if (char === "\\" && text[end + 1] === "u") {
      end += 2;
      continue;
    }
    const codePoint = text.codePointAt(end);
    const chars = String.fromCodePoint(codePoint);
    if (!(end === index ? IDENTIFIER_START : IDENTIFIER_PART).test(chars)) {
      break;
    }
    end += chars.length;
  }
  return end;
}

function skipLineComment(text, index, limit) {
  while (index < limit) {
    const code = text.charCodeAt(index);
    if (code === 0x0a || code === 0x0d || code === 0x2028 || code === 0x2029) {
      break;
    }
    index += 1;
  }
  return index;
}

function readNumber(text, index, limit) {
  let end = index;
  while (end < limit && /[0-9a-zA-Z_.]/u.test(text[end])) {
    end += 1;
  }
  return end;
}

function readQuoted(text, index, limit) {
  const quote = text[index];
  let end = index + 1;
  while (end < limit) {
    if (text[end] === "\\") {
      end += 2;
      continue;
    }
    if (text[end] === quote) {
      return end + 1;
    }
    end += 1;
  }
  return limit;
}

function lexGap(text, from, to, tokens, locate, keywords, singleCharPositions) {
  let index = from;
  while (index < to) {
    const code = text.charCodeAt(index);
    if (isWhitespace(code)) {
      index += 1;
      continue;
    }
    const char = text[index];
    const next = text[index + 1];
    if (char === "/" && next === "/") {
      index = skipLineComment(text, index + 2, to);
      continue;
    }
    if (char === "/" && next === "*") {
      const close = text.indexOf("*/", index + 2);
      index = close === -1 || close + 2 > to ? to : close + 2;
      continue;
    }
    if (char === "#" && next === "!" && index === 0) {
      index = skipLineComment(text, index + 2, to);
      continue;
    }
    if (char === "#" && index + 1 < to && IDENTIFIER_START.test(String.fromCodePoint(text.codePointAt(index + 1)))) {
      const end = readWord(text, index + 1, to);
      const leaf = token("PrivateIdentifier", text, index, end, locate);
      leaf.value = text.slice(index + 1, end);
      tokens.push(leaf);
      index = end;
      continue;
    }
    if (IDENTIFIER_START.test(String.fromCodePoint(text.codePointAt(index))) || (char === "\\" && next === "u")) {
      const end = readWord(text, index, to);
      const word = text.slice(index, end);
      let type = "Identifier";
      if (word === "null") {
        type = "Null";
      } else if (word === "true" || word === "false") {
        type = "Boolean";
      } else if (keywords.has(word)) {
        type = "Keyword";
      }
      tokens.push(token(type, text, index, end, locate));
      index = end;
      continue;
    }
    if (/[0-9]/u.test(char) || (char === "." && /[0-9]/u.test(next ?? ""))) {
      const end = readNumber(text, index + 1, to);
      tokens.push(token("Numeric", text, index, end, locate));
      index = end;
      continue;
    }
    if (char === "\"" || char === "'") {
      const end = readQuoted(text, index, to);
      tokens.push(token("String", text, index, end, locate));
      index = end;
      continue;
    }
    if (char === "`") {
      const end = readQuoted(text, index, to);
      tokens.push(token("Template", text, index, end, locate));
      index = end;
      continue;
    }
    let length = 1;
    if (!singleCharPositions.has(index)) {
      const punctuator = PUNCTUATORS.find((candidate) => text.startsWith(candidate, index) && index + candidate.length <= to);
      if (punctuator && !(punctuator === "?." && /[0-9]/u.test(text[index + 2] ?? ""))) {
        length = punctuator.length;
      }
    }
    tokens.push(token("Punctuator", text, index, index + length, locate));
    index += length;
  }
}

function buildTokens(program, text, locate, lang) {
  const { leaves, singleCharPositions } = collectLeafTokens(program, text, locate);
  const keywords = isTypeScriptLanguage(lang) ? new Set([...JS_KEYWORDS, ...TS_KEYWORDS]) : JS_KEYWORDS;
  const tokens = [];
  let position = 0;
  for (const leaf of leaves) {
    if (leaf.start < position) {
      continue;
    }
    lexGap(text, position, leaf.start, tokens, locate, keywords, singleCharPositions);
    tokens.push(leaf);
    position = leaf.end;
  }
  lexGap(text, position, text.length, tokens, locate, keywords, singleCharPositions);
  return tokens;
}

function normalizeGlobalAccess(value) {
  if (value === "off") {
    return "off";
  }
  if (value === true || value === "writable" || value === "writeable" || value === "write") {
    return "writable";
  }
  return "readonly";
}

function declareGlobals(scopeManager, globals, createVariable) {
  const globalScope = scopeManager.globalScope ?? scopeManager.scopes?.[0];
  if (!globalScope || !(globalScope.set instanceof Map)) {
    return;
  }
  for (const [name, rawAccess] of Object.entries(globals)) {
    const access = normalizeGlobalAccess(rawAccess);
    if (access === "off") {
      continue;
    }
    let variable = globalScope.set.get(name);
    if (!variable) {
      variable = createVariable(globalScope, name, access);
      globalScope.set.set(name, variable);
      globalScope.variables.push(variable);
    }
    variable.eslintImplicitGlobalSetting = access;
    variable.eslintExplicitGlobal = true;
    variable.writeable = access === "writable";
  }
  if (Array.isArray(globalScope.through)) {
    globalScope.through = globalScope.through.filter((reference) => {
      const variable = globalScope.set.get(reference.identifier?.name);
      if (!variable) {
        return true;
      }
      reference.resolved = variable;
      variable.references.push(reference);
      return false;
    });
  }
}

function collectGlobals(options, sourceType) {
  const globals = {};
  for (const name of ECMASCRIPT_GLOBALS) {
    globals[name] = "readonly";
  }
  if (sourceType === "commonjs") {
    Object.assign(globals, COMMONJS_GLOBALS);
  }
  for (const [name, access] of Object.entries(options.globals ?? {})) {
    globals[name] = access;
  }
  return globals;
}

function createScopeManagerFactory(program, options) {
  let cached = null;
  let computed = false;
  return () => {
    if (computed) {
      return cached;
    }
    computed = true;
    cached = analyzeScopes(program, options);
    return cached;
  };
}

function analyzeScopes(program, options) {
  const { lang, sourceType, ecmaFeatures } = options;
  const globalReturn = ecmaFeatures?.globalReturn === true || sourceType === "commonjs";
  const impliedStrict = ecmaFeatures?.impliedStrict === true;
  const globals = collectGlobals(options, sourceType);

  if (isTypeScriptLanguage(lang)) {
    const tsScope = require("@typescript-eslint/scope-manager");
    const scopeManager = tsScope.analyze(program, {
      sourceType: sourceType === "commonjs" ? "script" : sourceType,
      globalReturn,
      impliedStrict,
      jsxPragma: options.jsxPragma ?? "React",
      jsxFragmentName: options.jsxFragmentName ?? null,
      lib: ["esnext"],
      childVisitorKeys: VISITOR_KEYS
    });
    declareGlobals(scopeManager, globals, (globalScope, name, access) => new tsScope.ImplicitLibVariable(globalScope, name, {
      isTypeVariable: false,
      isValueVariable: true,
      writeable: access === "writable",
      eslintImplicitGlobalSetting: access
    }));
    return scopeManager;
  }

  const eslintScope = require("eslint-scope");
  const scopeManager = eslintScope.analyze(program, {
    ignoreEval: true,
    nodejsScope: globalReturn,
    impliedStrict,
    ecmaVersion: typeof options.ecmaVersion === "number" ? Math.max(options.ecmaVersion, 6) : 2026,
    sourceType,
    jsx: lang === "jsx",
    childVisitorKeys: VISITOR_KEYS,
    fallback: "iteration"
  });
  declareGlobals(scopeManager, globals, (globalScope, name) => new eslintScope.Variable(name, globalScope));
  return scopeManager;
}

/**
 * Parse `text` and return `{ ast, scopeManager, visitorKeys, services }` in
 * the shape ESLint expects from a parser's `parseForESLint`.
 *
 * `scopeManager` is a function so scope analysis only runs when a rule asks
 * for it; `SourceCode` in the entry points turns it into a lazy getter.
 */
function parseForESLint(text, options = {}) {
  if (typeof text !== "string") {
    throw new TypeError("parseForESLint requires source text");
  }
  const { parse } = loadYuku();
  const filePath = options.filePath ?? options.filename ?? "input.js";
  const ecmaFeatures = options.ecmaFeatures ?? {};
  const lang = languageForFile(filePath, ecmaFeatures);
  const sourceType = sourceTypeForFile(filePath, options.sourceType);
  const result = parse(text, { lang, sourceType, preserveParens: false });
  const program = result.program;
  const locate = createLocator(text);

  normalizeTree(program, text, locate);
  program.comments = normalizeComments(program, result.comments ?? [], text, locate);
  program.tokens = buildTokens(program, text, locate, lang);

  return {
    ast: program,
    scopeManager: createScopeManagerFactory(program, { ...options, lang, sourceType, ecmaFeatures }),
    visitorKeys: VISITOR_KEYS,
    services: {},
    diagnostics: result.diagnostics ?? []
  };
}

module.exports = {
  ECMASCRIPT_GLOBALS,
  VISITOR_KEYS,
  isNativeParserAvailable,
  languageForFile,
  parseForESLint
};
