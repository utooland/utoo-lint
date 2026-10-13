// Keep the original 12-rule profile stable. These additions use core ESLint
// rules with corresponding native implementations in the other benchmark tools.
// Validation snippets exercise a common case; they do not establish complete
// behavioral equivalence for every language feature and option.
export const extendedRuleAdditions = [
  rule("no-async-promise-executor", "suspicious", "noAsyncPromiseExecutor", `
new Promise(async (resolve) => { resolve(1); });
`),
  rule("no-class-assign", "suspicious", "noClassAssign", `
class Example { run() { return 1; } }
Example = 1;
`),
  rule("no-compare-neg-zero", "suspicious", "noCompareNegZero", `
export function compare(value: number) { return value === -0; }
`),
  rule("no-control-regex", "suspicious", "noControlCharactersInRegex", String.raw`
export const pattern = /\u0000/;
`),
  rule("no-dupe-else-if", "suspicious", "noDuplicateElseIf", `
export function branch(value: number) {
  if (value === 1) { return 1; }
  else if (value === 1) { return 2; }
  return 3;
}
`),
  rule("no-dupe-keys", "suspicious", "noDuplicateObjectKeys", `
export const object = { value: 1, value: 2 };
`),
  rule("no-ex-assign", "suspicious", "noCatchAssign", `
try { work(); } catch (error) { error = 1; work(error); }
`),
  rule("no-func-assign", "suspicious", "noFunctionAssign", `
function example() { return 1; }
example = 2;
`),
  rule("no-loss-of-precision", "correctness", "noPrecisionLoss", `
export const value = 9007199254740993;
`),
  rule("no-prototype-builtins", "suspicious", "noPrototypeBuiltins", `
export function hasValue(object: object) { return object.hasOwnProperty("value"); }
`),
  rule("no-self-assign", "correctness", "noSelfAssign", `
export function assign(value: number) { value = value; return value; }
`),
  rule("no-self-compare", "suspicious", "noSelfCompare", `
export function compare(value: number) { return value === value; }
`),
  rule("no-sparse-arrays", "suspicious", "noSparseArray", `
export const values = [1, , 3];
`),
  rule("no-template-curly-in-string", "suspicious", "noTemplateCurlyInString", `
export const value = "\${name}";
`),
  rule("no-unreachable", "correctness", "noUnreachable", `
export function unreachable() { return 1; work(); }
`),
  rule("no-unsafe-optional-chaining", "correctness", "noUnsafeOptionalChaining", `
export function call(value: object) { (value?.method)(); }
`),
  rule("no-useless-catch", "complexity", "noUselessCatch", `
try { work(); } catch (error) { throw error; }
`),
  rule("no-useless-rename", "complexity", "noUselessRename", `
export const { value: value } = object;
`),
  rule("no-useless-concat", "complexity", "noUselessStringConcat", `
export const value = "left" + "right";
`),
  rule("no-unneeded-ternary", "complexity", "noUselessTernary", `
export function booleanValue(value: unknown) { return value ? true : false; }
`),
  rule("no-extra-boolean-cast", "complexity", "noExtraBooleanCast", `
export function branch(value: unknown) { if (!!value) { work(); } }
`),
  rule("no-regex-spaces", "complexity", "noAdjacentSpacesInRegex", `
export const pattern = /a  b/;
`),
  rule("no-shadow-restricted-names", "suspicious", "noShadowRestrictedNames", `
export function shadow(undefined: number) { return undefined; }
`),
  rule("no-unused-labels", "correctness", "noUnusedLabels", `
unused: for (let index = 0; index < 2; index++) { work(index); }
`),
  rule("no-extra-label", "complexity", "noUselessLabel", `
label: for (let index = 0; index < 2; index++) { if (check(index)) { break label; } }
`),
  rule("no-var", "suspicious", "noVar", `
export var value = 1;
`),
  rule("no-constructor-return", "correctness", "noConstructorReturn", `
export class Example { constructor() { return {}; } }
`),
  rule("default-param-last", "style", "useDefaultParameterLast", `
export function parameters(first = 1, second: number) { return first + second; }
`),
  rule("default-case-last", "suspicious", "useDefaultSwitchClauseLast", `
switch (value) { default: break; case 1: break; }
`),
  rule("no-array-constructor", "style", "useArrayLiterals", `
export const values = new Array(1, 2);
`),
  rule("prefer-numeric-literals", "complexity", "useNumericLiterals", `
export const value = parseInt("10", 2);
`),
  rule("prefer-template", "style", "useTemplate", `
export function render(value: unknown) { return "value: " + value; }
`),
  rule("prefer-exponentiation-operator", "style", "useExponentiationOperator", `
export function square(value: number) { return Math.pow(value, 2); }
`),
  rule("no-useless-constructor", "complexity", "noUselessConstructor", `
export class Example { constructor() {} }
`),
  rule("no-constant-binary-expression", "suspicious", "noConstantBinaryExpressions", `
export const result = {} === {};
`),
  rule("no-case-declarations", "correctness", "noSwitchDeclarations", `
switch (value) { case 1: const local = 1; work(local); break; }
`),
  rule("for-direction", "correctness", "useValidForDirection", `
for (let index = 0; index < 10; index--) { work(index); }
`)
];

function rule(name, biomeGroup, biome, validation) {
  return {
    name,
    utooOption: name.replaceAll("-", "_"),
    eslint: name,
    oxlint: name,
    biomeGroup,
    biome,
    validation
  };
}
