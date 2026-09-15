export interface LintMessage {
  ruleId: string | null;
  severity: 0 | 1 | 2;
  message: string;
  line: number;
  column: number;
  endLine?: number;
  endColumn?: number;
  nodeType?: string | null;
  fix?: LintFix | LintFix[];
  suggestions?: LintSuggestion[];
  suppressions?: LintSuppression[];
}

export interface LintSuppression {
  kind: "directive";
  justification: string;
}

export interface LintDiagnostic extends Omit<LintMessage, "severity"> {
  severity: "warning" | "error";
  suppression?: LintSuppression;
}

export interface LintFix {
  range: [number, number];
  text: string;
}

export interface LintSuggestion {
  desc: string;
  messageId?: string;
  fix?: LintFix | LintFix[];
}

export interface LintResult {
  filePath: string;
  messages: LintMessage[];
  suppressedMessages: LintMessage[];
  errorCount: number;
  warningCount: number;
  fixableErrorCount: number;
  fixableWarningCount: number;
  source?: string;
  output?: string;
}

export interface LintReport {
  files: number;
  filePaths: string[];
  diagnostics: LintDiagnostic[];
  suppressedDiagnostics: LintDiagnostic[];
  outputs?: Array<{ filePath: string; output: string }>;
  exitCode: number;
  stderr?: string;
}

export interface Formatter {
  format(results: LintResult[] | LintReport): string;
}

export type RuleSeverity = "off" | "warn" | "warning" | "error" | 0 | 1 | 2 | false | true;
export type RuleConfig = RuleSeverity | [RuleSeverity, ...unknown[]];

/**
 * An ESLint plugin object. Rules provided by a mounted plugin run in Node.js
 * alongside the native rules; see the "ESLint Plugins" section of the
 * configuration docs.
 */
export interface PluginObject {
  meta?: { name?: string; version?: string; [key: string]: unknown };
  rules?: Record<string, unknown>;
  configs?: Record<string, unknown>;
  [key: string]: unknown;
}

export interface JestPluginSettings {
  version?: string | number;
  globalAliases?: Record<string, string[]>;
  [key: string]: unknown;
}

export interface SharedSettings {
  jest?: JestPluginSettings;
  [key: string]: unknown;
}

export interface ConfigObject {
  name?: string;
  files?: Array<string | string[]>;
  ignores?: string[];
  rules?: Record<string, RuleConfig>;
  plugins?: Record<string, PluginObject>;
  settings?: SharedSettings;
  languageOptions?: {
    parser?: unknown;
    parserOptions?: Record<string, unknown>;
    globals?: Record<string, unknown>;
    [key: string]: unknown;
  };
  parser?: unknown;
  parserOptions?: Record<string, unknown>;
  globals?: Record<string, unknown>;
  env?: Record<string, unknown>;
  extends?: Array<string | ConfigObject | ConfigObject[]>;
  basePath?: string;
  [key: string]: unknown;
}

export interface LintOptions {
  cwd?: string;
  binary?: string;
  env?: Record<string, string | undefined>;
  /** Maximum bytes captured from each native stdout/stderr stream. Defaults to 64 MiB. */
  maxBuffer?: number;
  threads?: number;
  rules?: string[] | string;
  format?: "text" | "json" | string;
  color?: boolean;
  config?: string;
  configFile?: string;
  noConfig?: boolean;
  fix?: boolean;
  useEslintrc?: boolean;
  overrideConfigFile?: string | boolean;
  baseConfig?: ConfigObject | ConfigObject[];
  overrideConfig?: ConfigObject | ConfigObject[];
  ignore?: boolean;
  noIgnore?: boolean;
  ignorePath?: string;
  ignorePatterns?: string[];
  quiet?: boolean;
  warnIgnored?: boolean;
  errorOnUnmatchedPattern?: boolean;
  extraArgs?: string[];
  flags?: string[];
}

export interface TextLintOptions extends LintOptions {
  filePath?: string;
  filename?: string;
}

export interface VerifyOptions {
  filename?: string;
  filePath?: string;
  cwd?: string;
}

export interface VerifyAndFixResult {
  fixed: boolean;
  messages: LintMessage[];
  output: string;
}

export interface SourceLocation {
  line: number;
  column: number;
}

export interface SourceRange {
  range?: [number, number];
  loc?: {
    start: SourceLocation;
    end: SourceLocation;
  };
  [key: string]: unknown;
}

export interface SourceCodeTokenOptions {
  includeComments?: boolean;
  filter?: (token: SourceRange) => boolean;
  skip?: number;
  count?: number;
  beforeCount?: number;
  afterCount?: number;
}

export type SourceCodeTokenCountOrOptions = number | SourceCodeTokenOptions;

export class SourceCode {
  static splitLines(text: string): string[];
  constructor(text: string, ast?: SourceRange | null);
  constructor(config: {
    text: string;
    ast?: SourceRange | null;
    hasBOM?: boolean;
    parserServices?: unknown;
    scopeManager?: unknown;
    visitorKeys?: unknown;
  });
  text: string;
  ast: SourceRange | null;
  lines: string[];
  comments: SourceRange[];
  tokens: SourceRange[];
  parserServices: unknown;
  /** Scope manager from `eslint-scope` (JavaScript) or `@typescript-eslint/scope-manager` (TypeScript). */
  scopeManager: unknown;
  visitorKeys: Record<string, readonly string[]> | null;
  getText(node?: SourceRange, beforeCount?: number, afterCount?: number): string;
  getLines(): string[];
  getAllComments(): SourceRange[];
  getIndexFromLoc(loc: SourceLocation): number;
  getLocFromIndex(index: number): SourceLocation;
  getRange(node?: SourceRange): [number, number];
  getLoc(node?: SourceRange): { start: SourceLocation; end: SourceLocation };
  getAllTokens(): SourceRange[];
  getTokens(node?: SourceRange, beforeCount?: number, afterCount?: number): SourceRange[];
  getTokens(node?: SourceRange, options?: SourceCodeTokenOptions): SourceRange[];
  getFirstToken(node?: SourceRange, skipOrOptions?: SourceCodeTokenCountOrOptions): SourceRange | null;
  getFirstTokens(node?: SourceRange, countOrOptions?: SourceCodeTokenCountOrOptions): SourceRange[];
  getLastToken(node?: SourceRange, skipOrOptions?: SourceCodeTokenCountOrOptions): SourceRange | null;
  getLastTokens(node?: SourceRange, countOrOptions?: SourceCodeTokenCountOrOptions): SourceRange[];
  getTokenBefore(nodeOrToken: SourceRange, skipOrOptions?: SourceCodeTokenCountOrOptions): SourceRange | null;
  getTokensBefore(nodeOrToken: SourceRange, countOrOptions?: SourceCodeTokenCountOrOptions): SourceRange[];
  getTokenAfter(nodeOrToken: SourceRange, skipOrOptions?: SourceCodeTokenCountOrOptions): SourceRange | null;
  getTokensAfter(nodeOrToken: SourceRange, countOrOptions?: SourceCodeTokenCountOrOptions): SourceRange[];
  getTokensBetween(left: SourceRange, right: SourceRange, countOrOptions?: SourceCodeTokenCountOrOptions): SourceRange[];
  getFirstTokenBetween(left: SourceRange, right: SourceRange, skipOrOptions?: SourceCodeTokenCountOrOptions): SourceRange | null;
  getFirstTokensBetween(left: SourceRange, right: SourceRange, countOrOptions?: SourceCodeTokenCountOrOptions): SourceRange[];
  getLastTokenBetween(left: SourceRange, right: SourceRange, skipOrOptions?: SourceCodeTokenCountOrOptions): SourceRange | null;
  getLastTokensBetween(left: SourceRange, right: SourceRange, countOrOptions?: SourceCodeTokenCountOrOptions): SourceRange[];
  getTokenByRangeStart(index: number, options?: Pick<SourceCodeTokenOptions, "includeComments">): SourceRange | null;
  getTokenOrCommentBefore(nodeOrToken: SourceRange): SourceRange | null;
  getTokenOrCommentAfter(nodeOrToken: SourceRange): SourceRange | null;
  getCommentsBefore(nodeOrToken: SourceRange): SourceRange[];
  getCommentsAfter(nodeOrToken: SourceRange): SourceRange[];
  getCommentsInside(node: SourceRange): SourceRange[];
  getComments(node: SourceRange): { before: SourceRange[]; after: SourceRange[]; inside: SourceRange[] };
  getJSDocComment(node: SourceRange): SourceRange | null;
  commentsExistBetween(left: SourceRange, right: SourceRange): boolean;
  isSpaceBetween(left: SourceRange, right: SourceRange): boolean;
  isSpaceBetweenTokens(left: SourceRange, right: SourceRange): boolean;
  getNodeByRangeIndex(index: number): SourceRange | null;
  getAncestors(node?: SourceRange): SourceRange[];
  getDeclaredVariables(node?: SourceRange): unknown[];
  getScope(node?: SourceRange): unknown;
  markVariableAsUsed(name: string, node?: SourceRange): boolean;
  getDisableDirectives(): unknown[];
  getInlineConfigNodes(): unknown[];
  applyInlineConfig(): undefined;
  applyLanguageOptions(): undefined;
  finalize(): undefined;
  traverse(): unknown[];
  isGlobalReference(): boolean;
}

export class Linter {
  static readonly version: string;
  constructor(options?: { flags?: string[] });
  verify(code: string, config?: ConfigObject, options?: VerifyOptions | string): LintMessage[];
  verifyAndFix(code: string, config?: ConfigObject, options?: VerifyOptions | string): VerifyAndFixResult;
  getSourceCode(): SourceCode | null;
  getSuppressedMessages(): LintMessage[];
  getTimes(): { passes: unknown[] };
  getFixPassCount(): number;
  hasFlag(flag: string): boolean;
  getRules(): Map<string, unknown>;
  defineRule(ruleId: string, rule: unknown): void;
  defineRules(rules: Record<string, unknown>): void;
  defineParser(parserId: string, parser: unknown): void;
}

export interface RuleTesterValidCase extends ConfigObject {
  code: string;
  name?: string;
  filename?: string;
  filePath?: string;
  options?: unknown[];
  only?: boolean;
}

export interface RuleTesterInvalidCase extends RuleTesterValidCase {
  errors?: number | Array<number | Partial<LintMessage> & {
    messageId?: string;
    data?: Record<string, unknown>;
    type?: string | null;
    suggestions?: number | null | Array<Partial<LintSuggestion> & { data?: Record<string, unknown>; output?: string | null }>;
  }>;
  output?: string | null;
}

export class RuleTester {
  static readonly version: string;
  static setDefaultConfig(config: ConfigObject): void;
  static getDefaultConfig(): ConfigObject;
  static resetDefaultConfig(): void;
  static describe: ((name: string, fn: () => void) => unknown) | null;
  static it: ((name: string, fn: () => void) => unknown) | null;
  static itOnly: ((name: string, fn: () => void) => unknown) | null;
  static only<T extends string | RuleTesterValidCase | RuleTesterInvalidCase>(item: T): T extends string ? RuleTesterValidCase : T & { only: true };
  constructor(config?: ConfigObject);
  run(ruleName: string, rule: unknown, tests?: {
    valid?: Array<string | RuleTesterValidCase>;
    invalid?: RuleTesterInvalidCase[];
  }): void;
}

export class UtooLint {
  static readonly version: string;
  static readonly configType: "flat";
  static readonly defaultConfig: ConfigObject[];
  static fromOptionsModule(optionsURL: URL): Promise<UtooLint>;
  static outputFixes(results: LintResult[]): Promise<void>;
  static getErrorResults(results: LintResult[]): LintResult[];
  constructor(options?: LintOptions);
  lintFiles(patterns?: string | string[], options?: LintOptions): Promise<LintResult[]>;
  lintText(code: string, options?: TextLintOptions): Promise<LintResult[]>;
  isPathIgnored(filePath: string): Promise<boolean>;
  calculateConfigForFile(filePath: string): Promise<ConfigObject>;
  findConfigFile(filePath?: string): Promise<string | undefined>;
  getRulesMetaForResults(results: LintResult[]): Record<string, unknown>;
  hasFlag(flag: string): boolean;
  loadFormatter(name?: string): Promise<Formatter>;
}

export { UtooLint as ESLint };

export class CLIEngine {
  static readonly version: string;
  static outputFixes(report: { results?: LintResult[] } | LintResult[]): void;
  static getErrorResults(results: LintResult[]): LintResult[];
  constructor(options?: LintOptions);
  executeOnFiles(patterns: string | string[]): {
    results: LintResult[];
    errorCount: number;
    warningCount: number;
    fixableErrorCount: number;
    fixableWarningCount: number;
  };
  executeOnText(code: string, filePathOrOptions?: string | TextLintOptions): {
    results: LintResult[];
    errorCount: number;
    warningCount: number;
    fixableErrorCount: number;
    fixableWarningCount: number;
  };
  getFormatter(name?: string): (results: LintResult[]) => string;
  getRules(): Map<string, unknown>;
  addPlugin(name: string, pluginObject: unknown): void;
  resolveFileGlobPatterns(patterns: string | string[]): string[];
  isPathIgnored(filePath: string): boolean;
  getConfigForFile(filePath: string): ConfigObject;
}

export function loadESLint(options?: { useFlatConfig?: boolean; cwd?: string }): Promise<typeof UtooLint>;
export function lintFiles(patterns?: string | string[], options?: LintOptions): LintReport;
export function lintText(code: string, options?: TextLintOptions): LintReport;
export function run(args?: string[], options?: LintOptions): unknown;
export function runCli(args?: string[], options?: LintOptions): unknown;
export function runFishlint(args?: string[], options?: LintOptions): unknown;
export function translateFishlintArgs(args?: string[], options?: { command?: string; warn?: (message: string) => void }): string[];
export function resolveBinary(options?: { env?: Record<string, string | undefined>; platform?: string; arch?: string }): string;
export function platformPackageName(platform?: string, arch?: string): string | undefined;

export const version: string;
export default UtooLint;
