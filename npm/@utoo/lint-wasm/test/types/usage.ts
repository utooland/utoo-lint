import {
  createUtooLint,
  lint,
  lintAndFix,
  type LintDiagnostic,
  type LintFixResult,
  type LintOnlyResult,
  type LintResult,
} from "@utoo/lint-wasm";

const linter = await createUtooLint();
const direct: LintResult = linter.lint("debugger;", {
  filePath: "input.js",
  sourceType: "script",
  rules: { "no-debugger": "error" },
});
const diagnostic: LintDiagnostic | undefined = direct.diagnostics[0];
void diagnostic?.range;
const suppressedDiagnostic: LintDiagnostic | undefined = direct.suppressedDiagnostics[0];
void suppressedDiagnostic?.suppressions?.[0]?.justification;

const lintOnly: LintOnlyResult = await lint("console.log('x');", {
  rules: { "no-console": "warn" },
});
// @ts-expect-error lint-only results deliberately have no output buffer.
void lintOnly.output;

const fixed: LintFixResult = await lintAndFix("const value = 1;;;", {
  rules: { "no-extra-semi": 2 },
});
fixed.output.toUpperCase();

function consume(result: LintResult) {
  if (result.mode === "fix") {
    result.output.toUpperCase();
  } else {
    result.fixed satisfies false;
  }
}
void consume;
