import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const { parseForESLint } = require("../lib/estree-parser.cjs");

for (const extension of ["jsx", "tsx"]) {
  test(`${extension} values decode JSX entities once and preserve raw text`, () => {
    const raw = "&amp;amp; &#x1f430; &lt;";
    const text = `<div title="${raw}">${raw}</div>`;
    const { ast, diagnostics } = parseForESLint(text, { filePath: `input.${extension}` });
    const element = ast.body[0].expression;
    const attribute = element.openingElement.attributes[0].value;
    const child = element.children[0];

    assert.deepEqual(diagnostics, []);
    assert.equal(attribute.value, "&amp; 🐰 <");
    assert.equal(attribute.raw, `"${raw}"`);
    assert.equal(child.value, "&amp; 🐰 <");
    assert.equal(child.raw, raw);
    assert.equal(text.slice(...attribute.range), attribute.raw);
    assert.equal(text.slice(...child.range), raw);
    assert.equal(ast.tokens.find((token) => token.start === child.start).value, child.value);
  });
}

test("TypeScript enum and mapped type bindings reach ESLint scope analysis", () => {
  const text = "enum Status { Active }; type Mapping<T> = { [K in keyof T]: T[K] };";
  const { ast, diagnostics, scopeManager } = parseForESLint(text, { filePath: "input.ts" });
  const enumeration = ast.body[0];
  const mappedType = ast.body[2].typeAnnotation;
  const scopes = scopeManager().scopes;

  assert.deepEqual(diagnostics, []);
  assert.equal(enumeration.body.members[0].id.parent, enumeration.body.members[0]);
  assert.equal(mappedType.key.parent, mappedType);
  assert.equal(mappedType.constraint.typeAnnotation.typeName.parent.type, "TSTypeReference");
  assert.deepEqual(scopes.find((scope) => scope.type === "tsEnum").variables.map(({ name }) => name), ["Active"]);
  const mappedScope = scopes.find((scope) => scope.type === "mappedType");
  assert.equal(mappedScope.set.get("K").references.length, 1);
  assert.equal(mappedScope.through.every(({ resolved }) => resolved?.name === "T"), true);
});

test("template tokens preserve delimiters and UTF-16 ranges", () => {
  const text = "const 前缀 = '🐰';\nconst result = `hello ${前缀}!`;";
  const { ast, diagnostics } = parseForESLint(text, { filePath: "input.js" });
  const template = ast.body[1].declarations[0].init;
  const tokens = ast.tokens.filter(({ type }) => type === "Template");

  assert.deepEqual(diagnostics, []);
  assert.deepEqual(tokens.map(({ value }) => value), ["`hello ${", "}!`"]);
  assert.deepEqual(template.quasis.map(({ range }) => text.slice(...range)), ["`hello ${", "}!`"]);
  assert.equal(template.expressions[0].range[0], text.lastIndexOf("前缀"));
  assert.equal(template.loc.start.line, 2);
});
