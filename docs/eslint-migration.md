# Migrating from ESLint

This guide covers the current migration path from ESLint to `utoo-lint` and how
to estimate the cost before changing CI.

`utoo-lint` is still experimental. Treat the migration as an incremental
replacement for the rule set that is already implemented natively, not as a
drop-in replacement for the whole ESLint ecosystem.

## What Migrates Cleanly

The lowest-cost projects usually have these properties:

- They lint JavaScript, JSX, TypeScript, or TSX source files.
- Their ESLint config can be reduced to JSON-serializable `files`, `ignores`,
  and `rules` entries.
- Most enabled rules are ESLint core rules or supported rules from
  `@typescript-eslint`, `eslint-plugin-react`, `eslint-plugin-import`,
  `eslint-plugin-jsx-a11y`, `eslint-plugin-react-hooks`, or
  `eslint-plugin-eslint-comments`. Rules from other plugins can keep running
  through the [ESLint plugin bridge](configuration.md#eslint-plugins).
- Formatting is already handled by Prettier, Biome, or another formatter
  outside ESLint.
- CI and pre-commit scripts can run ESLint and `utoo-lint` side by side for a
  short validation window.

The built-in compatibility surface currently exposes more than 300
ESLint-compatible rule IDs through the JavaScript API, spanning ESLint core,
TypeScript ESLint, React, imports, JSX accessibility, React Hooks, and
eslint-comments. See [Rule status](rule-status.md) for the exact implemented
list and option coverage.

## Migration Cost

Use this table as a first estimate.

| Project shape | Expected cost | What usually needs work |
| --- | --- | --- |
| Simple app or package with mostly supported rules | Low, often under half a day | Install package, generate `utlint.config.json`, update scripts, compare diagnostics |
| Frontend app with several plugin presets and overrides | Medium, around 1-2 days | Flatten config, mount plugins whose rules have no native implementation, decide which rules stay on ESLint temporarily |
| Monorepo with custom ESLint plugins, processors, typed parser services, or autofix-dependent workflows | High, several days or more | Mount custom plugins in `utlint.config.ts`, keep dual lint jobs for processors and type-aware rules, and audit autofix coverage |

The main cost is not changing file syntax. It is deciding what to do with ESLint
features that do not have a native equivalent yet.

Common low-cost items:

- Rule severities: `"off"`, `"warn"`, `"warning"`, `"error"`, `0`, `1`, `2`,
  booleans, and ESLint-style arrays are accepted.
- Rule names: keep canonical ESLint rule IDs such as `no-debugger`,
  `react/jsx-no-target-blank`, and `@typescript-eslint/no-unused-vars`.
- `files` and `ignores`: simple flat config patterns are copied by the
  migrator and used by the JS wrapper/API.
- Formatter rules: `prettier/prettier` is ignored by the migrator because
  formatting should stay outside `utoo-lint`.

Common medium- or high-cost items:

- Plugin rules without a native implementation can keep running by mounting
  the plugin in `utlint.config.ts`; see
  [ESLint Plugins](configuration.md#eslint-plugins). They run in JavaScript, so
  prefer a native rule where one exists.
- Dynamic JavaScript config values, functions, symbols, parser objects, and
  non-serializable plugin objects are stripped by the migrator. Re-add
  `plugins` by hand in a TypeScript config when you need their rules.
- Processors for non-JS files such as Markdown, Vue SFC, or MDX are not a native
  migration path today.
- Autofix-dependent workflows need an explicit coverage check. `utoo-lint`
  applies safe fixes for supported rules; keep ESLint or another tool for
  transformations that are not marked as fixable in [Rule status](rule-status.md).
- Rules that depend on TypeScript type checker services should be audited
  manually. `utoo-lint` is a native parser/semantic linter, not an ESLint runtime
  around `@typescript-eslint/parser`.

## Step 1: Install

```bash
npm install --save-dev @utoo/lint
```

Run it on explicit targets first:

```bash
npx utoo-lint src test
```

For a focused first pass, run only rules that already exist in both projects:

```bash
npx utoo-lint --rules=no-debugger,no-unused-vars,@typescript-eslint/no-unused-vars src
```

## Step 2: Generate a Native Config

Use the migration command to turn an existing ESLint config into the canonical
static config, `utlint.config.json`:

```bash
npx utoo-lint migrate eslint --from eslint.config.js --output utlint.config.json
```

The generated config is a native `utoo-lint` config, not an ESLint config
executed through a compatibility layer. ESLint flat-config entries remain
separate and in their original order, including their `files`, `ignores`, and
supported rule values. This preserves per-file overrides and keeps ignore-only
entries global while other ignores remain entry-scoped. The migrator also skips
formatter-only rules such as `prettier/prettier` and reports enabled unsupported
rules that still need a native utoo rule or a deliberate replacement. Disabled
unsupported rules are omitted because they have no runtime behavior to migrate.

For a preview without writing a file:

```bash
npx utoo-lint migrate eslint --print --report=json
```

The selected value for each rule is preserved, including arrays such as
`["error", { ...options }]`. Native utoo rules consume the options they support;
enabled unsupported rules are reported instead of being copied. Unsupported
rules configured as `"off"`, `0`, `false`, or an array with one of those
severities do not block migration.

Flat-config output starts with a schema metadata entry, followed by the
migrated entries. Matching entries are applied in array order, so a later value
for the same rule retains ESLint's override behavior.

Classic `.eslintrc`, `.eslintrc.json`, `.eslintrc.js`, and `.eslintrc.cjs`
inputs are expanded with ESLint's classic config resolver before conversion.
Relative paths, shareable config package names, `plugin:name/preset` references,
and arrays of `extends` values retain their ESLint order. Nested inherited
rules and overrides become ordered utoo config entries; `files`,
`excludedFiles`, and `ignorePatterns` become the corresponding scoped selectors
and global ignores. These patterns are rebased to the output config directory,
including when an ancestor `.eslintrc` is discovered. Literal-choice extglobs
such as `**/*.@(js|ts)` are expanded to native selector alternatives. Extglob
forms that cannot be represented safely stop migration with an actionable error
instead of silently changing file coverage. Circular chains and missing configs
likewise stop migration with the extends chain or referring config in the error
instead of producing partial output.

The migrator translates the following reviewed aliases when their behavior has
a native equivalent. These mappings are semantic compatibility decisions, not
string-only renames: each source rule is checked against the target's
implemented behavior and supported options before it is added.

| ESLint rule | utoo-lint rule |
| --- | --- |
| `no-native-reassign` | `no-global-assign` |
| `@typescript-eslint/no-invalid-this` | `no-invalid-this` |
| `@eslint-react/no-array-index-key` | `react/no-array-index-key` |
| `@eslint-react/dom-no-find-dom-node` | `react/no-find-dom-node` |
| `@eslint-react/dom-no-render-return-value` | `react/no-render-return-value` |
| `@eslint-react/dom-no-void-elements-with-children` | `react/void-dom-elements-no-children` |
| `@eslint-react/rules-of-hooks` | `react-hooks/rules-of-hooks` |

Translated aliases are listed separately in the migration report. Other legacy
or plugin rule IDs remain unsupported unless an explicit equivalent is added;
the migrator does not infer mappings from similar names.

Use that JSON report to size the migration:

- `supportedRules`: can move to `utoo-lint` immediately.
- `unsupportedRules`: require a replacement, a new native rule, or temporary
  ESLint coverage.
- `ignoredRules`: intentionally left outside `utoo-lint`, usually formatting.
- `inheritedSources`: the resolved relative, package, plugin, or built-in config
  sources that contributed to classic config migration.
- `unsupportedInheritedRules`: unsupported rules paired with the inherited
  source that introduced them.

The command exits with status `1` when unsupported rules are found. That is a
useful signal for automation; it does not mean the generated config is unusable.

## Step 3: Start From the Frontend Template

Create `utlint.config.json` in the project root, or copy the packaged frontend
template:

```bash
cp node_modules/@utoo/lint/configs/frontend.json utlint.config.json
```

The template includes a `$schema`, source file globs, common build-directory
ignores, and a focused browser/import/React/JSX a11y/TypeScript rule set. Use it
when you want a known baseline before translating the full ESLint config.

Minimal native config:

```json
{
  "$schema": "https://raw.githubusercontent.com/utooland/utoo-lint/main/npm/utoo-lint/schema.json",
  "rules": {
    "no-debugger": "error",
    "no-console": "off",
    "no-unused-vars": "warn",
    "@typescript-eslint/no-unused-vars": ["warn"],
    "react/jsx-no-target-blank": "error",
    "jsx-a11y/aria-props": "error"
  }
}
```

The canonical names are `utlint.config.ts` and `utlint.config.json`. They are
two representations of one active config and are not implicitly merged.
For the npm/Node entry point, discovery checks the nearest directory first;
within the same directory, `utlint.config.ts` wins over
`utlint.config.json`. The old `utoo.json` and `utoo-lint.json` names remain
temporarily supported after the canonical names, but are deprecated. Use
`--config=path/to/utlint.config.json` to select a file explicitly, or
`--no-config` to ignore local config.

Project-config `files` and `ignores` patterns are relative to the selected
config file's directory. For flat config arrays, entries are matched per file
and combined in array order; later matching rule values override earlier ones.
The npm CLI, JavaScript API, and fishlint compatibility command use this
per-file rule resolution.

The npm/Node CLI can also execute a trusted typed config. Its default export
must be a JSON-serializable object or flat config array:

```ts
// utlint.config.ts
import { defineConfig } from "@utoo/lint/config";

export default defineConfig({
  files: ["src/**/*.{js,jsx,ts,tsx}"],
  rules: {
    "no-debugger": "error",
    "@typescript-eslint/no-unused-vars": "warn"
  }
});
```

Loading `utlint.config.ts` executes project code. The npm wrapper materializes
the exported value as JSON for one native process; the raw binary itself does
not execute or discover TypeScript. It searches for `utlint.config.json` and
then the legacy JSON names, so use JSON when invoking it directly. The raw
binary resolves flat-config `files`, global and entry-scoped `ignores`, rule
overrides, and supported settings per file. Omitted rules are disabled,
matching ESLint's configuration model.

## Step 4: Translate Rules Manually When Needed

- `"off"`, `0`, or `false` disable a rule.
- `"warn"`, `"error"`, `1`, `2`, or `true` enable a rule.
- Arrays such as `["error", { ...options }]` use the first item as severity and pass supported options to the native rule implementation.

As in ESLint, warning diagnostics do not fail the command; error diagnostics
return exit status 1. The fishlint-compatible CLI also supports
`--max-warnings` when a warning budget should fail CI.

Rule-related CLI options are applied after the config, so command-line rule
toggles override configured rule values:

```bash
npx utoo-lint --config=utlint.config.json --no-console=off src
```

## Translate ESLint Rules Manually

Move rules from `eslint.config.js` or `.eslintrc` into
`utlint.config.json` by keeping the same canonical rule names:

```js
// eslint.config.js
export default [
  {
    rules: {
      "no-debugger": "error",
      "@typescript-eslint/no-unused-vars": ["warn"],
      "react/jsx-no-target-blank": "error"
    }
  }
];
```

```json
{
  "rules": {
    "no-debugger": "error",
    "@typescript-eslint/no-unused-vars": ["warn"],
    "react/jsx-no-target-blank": "error"
  }
}
```

Use [Rule status](rule-status.md) to confirm which ESLint, TypeScript ESLint,
React, import, React Hooks, eslint-comments, and JSX a11y rules are currently
implemented. If a rule is missing, choose one of these paths:

- Keep ESLint for that rule during the transition.
- Disable it deliberately and document why.
- Implement the native rule in `src/rules`.
- Replace it with a supported rule or a non-lint tool.

## Step 5: Compare Diagnostics

Run ESLint and `utoo-lint` side by side until the selected rule set is stable:

```bash
npx eslint src test
npx utoo-lint --config=utlint.config.json src test
```

Useful comparison workflow:

```bash
npx eslint src test --format json > eslint-report.json
npx utoo-lint --config=utlint.config.json --format=json src test > utoo-report.json
```

Expect some differences during the first pass:

- `utoo-lint` reports only native rules that are enabled in the selected config.
- Unsupported ESLint rules are absent until they are ported.
- Some supported rules intentionally implement the common ESLint behavior first;
  check [Rule status](rule-status.md) for option-level notes.

Once diagnostics match expectations, replace the ESLint job for that rule set or
keep both jobs while expanding rule coverage.

## Replace Package Scripts

Typical script migration:

```json
{
  "scripts": {
    "lint:eslint": "eslint src test",
    "lint:utoo": "utoo-lint --config=utlint.config.json src test",
    "lint": "utoo-lint --config=utlint.config.json src test"
  }
}
```

During rollout, keep both:

```json
{
  "scripts": {
    "lint": "npm run lint:eslint && npm run lint:utoo",
    "lint:eslint": "eslint src test",
    "lint:utoo": "utoo-lint --config=utlint.config.json src test"
  }
}
```

When using the JavaScript API, calling `lintFiles()` without patterns follows
the `files` entries in `utlint.config.json`. For command-line scripts, pass explicit
targets during migration so CI stays easy to reason about.

## ESLint CLI Wrapper

`@utoo/lint` ships an ESLint-flavoured CLI at `bin/eslint.js`, but it does not
register it as an `eslint` bin. Installing `@utoo/lint` next to ESLint therefore
never changes which tool `npx eslint` or an existing `"lint": "eslint src"`
script runs, and the two CLIs can be compared side by side. Opt into the
wrapper per script when a project is ready to switch:

```json
{
  "scripts": {
    "lint": "node node_modules/@utoo/lint/bin/eslint.js src test"
  }
}
```

The wrapper accepts the common ESLint flags (`--config`, `--format`, `--fix`,
`--max-warnings`, `--quiet`, `--rule`, `--no-config`) and forwards to the same
translation layer as `fishlint eslint`, described below.

## Replace Fishlint Commands

`@utoo/lint` ships a fishlint compatibility CLI at `bin/fishlint.js` for scripts
that already call the eslint subcommand. Like the ESLint wrapper above, it is
not registered as a `fishlint` bin, so opt in explicitly:

```bash
node node_modules/@utoo/lint/bin/fishlint.js eslint --disable-setup --config utlint.config.json --ext .js,.ts --glob src
```

`bin/fishlint-lint-staged.js` is the matching lint-staged entry point and can
be referenced the same way.

The wrapper invokes `utoo-lint` after translating common fishlint eslint flags.
It forwards `--config`, maps `--glob` values to lint targets, accepts `--ext`
for compatibility, and ignores fishlint-only setup/debug flags. `--fix` applies
fixes from supported native rules, while `--fix-dry-run` computes fixed output
without writing files. It discovers `utlint.config.ts`, `utlint.config.json`,
the deprecated `utoo.json`/`utoo-lint.json` names, and ESLint migration inputs
such as `eslint.config.js`/`eslint.config.mjs`/`eslint.config.cjs`. Executable
configs are loaded and materialized as temporary JSON before invoking the
native binary.

Fishlint presets often include `prettier/prettier`. `utoo-lint` accepts that
rule in config files for compatibility and ignores it because formatting remains
outside the native linter.

## Replace ESLint API Calls

For scripts that already use ESLint's Node API, import `ESLint` from
`@utoo/lint` and keep the high-level call shape:

```js
import { ESLint } from "@utoo/lint";

const eslint = new ESLint({
  useEslintrc: false,
  overrideConfig: {
    rules: {
      "no-debugger": "warn",
      "no-console": "warn"
    }
  }
});

const results = await eslint.lintFiles(["src"]);
const formatter = await eslint.loadFormatter("stylish");
console.log(formatter.format(results));
```

`ESLint#lintText()` is also supported. It writes the text to a temporary file and
maps diagnostics back to the provided `filePath`, which is useful for editor,
pre-commit, and codemod integrations:

```js
const [result] = await eslint.lintText("debugger;\n", {
  filePath: "inline.js"
});
```

Older integrations that still use ESLint's legacy `CLIEngine` can import a
small synchronous facade:

```js
import { CLIEngine } from "@utoo/lint";

const cli = new CLIEngine({
  useEslintrc: false,
  baseConfig: {
    rules: {
      "no-debugger": "error"
    }
  }
});

const report = cli.executeOnFiles(["src"]);
console.log(cli.getFormatter("stylish")(report.results));
```

## Practical Go/No-Go Checklist

Before removing ESLint from CI, confirm:

- `utoo-lint migrate eslint --report=json` has no unexpected unsupported rules.
- The `utlint.config.json` target and ignore patterns match the old lint scope.
- Side-by-side diagnostics are reviewed for the selected rule set.
- Formatting remains a separate step, and required autofixes have native
  coverage or a documented fallback.
- Custom ESLint plugins are mounted in `utlint.config.ts`, and processors and
  type-aware rules either remain in an ESLint job or have a tracked native
  replacement plan.
