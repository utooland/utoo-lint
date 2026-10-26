export type RuleSeverity = "off" | "warn" | "warning" | "error" | 0 | 1 | 2 | false | true;
export type RuleConfig = RuleSeverity | [RuleSeverity, ...unknown[]];

export interface JestPluginSettings {
  version?: string | number;
  globalAliases?: Record<string, string[]>;
  [key: string]: unknown;
}

export interface SharedSettings {
  jest?: JestPluginSettings;
  [key: string]: unknown;
}

export interface LintFix {
  range: [number, number];
  text: string;
}

export interface LintSuggestion {
  desc: string;
  fix: LintFix[];
}

export interface LintSuppression {
  kind: "directive";
  justification: string;
}

export interface LintDiagnostic {
  ruleId: string;
  severity: "warning" | "error";
  message: string;
  /** UTF-16 offsets suitable for JavaScript strings and browser editors. */
  range: [number, number];
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
  fixes: LintFix[];
  suggestions: LintSuggestion[];
  suppression?: LintSuppression;
  suppressions?: LintSuppression[];
}

export interface LintOptions {
  filePath?: string;
  filename?: string;
  sourceType?: "module" | "script" | "commonjs";
  rules?: Record<string, RuleConfig>;
  settings?: SharedSettings;
}

export interface LintResultBase {
  version: 1;
  ok: true;
  offsetEncoding: "utf-16";
  filePath: string;
  diagnostics: LintDiagnostic[];
  suppressedDiagnostics: LintDiagnostic[];
  /** Enabled rules that need a real project filesystem and were not run. */
  skippedRules: string[];
}

export interface LintOnlyResult extends LintResultBase {
  mode: "lint";
  diagnosticsSource: "input";
  fixed: false;
  passes: 0;
  appliedDiagnostics: 0;
}

export interface LintFixResult extends LintResultBase {
  mode: "fix";
  diagnosticsSource: "output";
  fixed: boolean;
  passes: number;
  appliedDiagnostics: number;
  output: string;
}

export type LintResult = LintOnlyResult | LintFixResult;

export type WasmSource =
  | string
  | URL
  | Response
  | ArrayBuffer
  | ArrayBufferView
  | WebAssembly.Module
  | WebAssembly.Instance;

export interface CreateUtooLintOptions {
  wasm?: WasmSource;
  imports?: WebAssembly.Imports;
}

export interface UtooLintWasm {
  readonly abiVersion: number;
  lint(source: string, options?: LintOptions): LintOnlyResult;
  lintAndFix(source: string, options?: LintOptions): LintFixResult;
}

export class UtooLintWasmError extends Error {
  readonly code: string;
  readonly ruleId?: string;
  readonly cause?: unknown;
}

export function createUtooLint(options?: CreateUtooLintOptions): Promise<UtooLintWasm>;
export function lint(source: string, options?: LintOptions): Promise<LintOnlyResult>;
export function lintAndFix(source: string, options?: LintOptions): Promise<LintFixResult>;
