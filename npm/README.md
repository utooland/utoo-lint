# npm packaging

This directory contains the npm CLI wrapper for `@utoo/lint`, the native
platform packages, and the standalone WebAssembly package.

- `@utoo/lint` is the JavaScript CLI package.
- `@utoo/lint-wasm` is the ESM wrapper and freestanding WebAssembly module for
  browser and Node single-file linting.
- `@utoo/lint-darwin-arm64` contains the native Zig binary for macOS arm64.
- `@utoo/lint-darwin-x64` contains the native Zig binary for macOS x64.
- `@utoo/lint-linux-arm64` contains the native Zig binary for Linux arm64.
- `@utoo/lint-linux-x64` contains the native Zig binary for Linux x64.
- `@utoo/lint-win32-x64` contains the native Zig binary for Windows x64.

## WebAssembly Package

`npm/@utoo/lint-wasm` is published independently from the Node CLI because it
does not use a native platform package, WASI, or a real filesystem. The package
contains `index.js`, TypeScript declarations, and `utoo-lint.wasm`.

Build and stage the WebAssembly file before testing or packing the package:

```bash
pnpm package:wasm
pnpm test:wasm
pnpm --dir npm/@utoo/lint-wasm test
pnpm --dir npm/@utoo/lint-wasm test:types
```

See the repository's [WebAssembly guide](../docs/wasm.md) for the public API
and runtime behavior.

## Configuration Files

The canonical project config names are `utlint.config.ts` and
`utlint.config.json`. They are two representations of one active config, not
files that are implicitly merged. The npm/Node entry point searches the nearest
directory first; within one directory, TypeScript wins over JSON. Deprecated
`utoo.json` and `utoo-lint.json` names are checked afterward for temporary
compatibility. Rule-related CLI options such as `--rules`, individual rule
toggles, and fishlint's `--rule` are applied after the selected file.

Project-config `files` and `ignores` patterns are relative to the selected
config file's directory. Flat config entries are matched separately for each
file and combined in array order, with later rule values overriding earlier
ones. The npm CLI, JavaScript API, and fishlint compatibility command use this
per-file rule resolution.

TypeScript config is trusted executable code and its default export must be a
JSON-serializable object or flat config array. For example:

```ts
import { defineConfig } from "@utoo/lint/config";

export default defineConfig({
  files: ["src/**/*.{js,jsx,ts,tsx}"],
  rules: {
    "no-debugger": "error"
  }
});
```

The npm wrapper executes `utlint.config.ts`, materializes its result as JSON,
and invokes the native binary. The raw binary does not execute or discover
TypeScript; it reads `utlint.config.json` (or a deprecated JSON name) directly.
It currently applies only the JSON config's `rules`; config-driven `files` and
`ignores` filtering and default target selection are npm/Node wrapper features.
Pass lint targets explicitly when invoking the raw binary.

The CLI package also exposes a small ESM API:

```js
import { CLIEngine, ESLint, lintFiles, lintText, resolveBinary, run, runFishlint } from "@utoo/lint";

const report = lintFiles(["src", "test"], {
  config: "utlint.config.json",
  rules: ["no-debugger", "@typescript-eslint/no-unused-vars"]
});

console.log(report.diagnostics);
console.log(resolveBinary());
console.log(run(["--help"]).stdout);
console.log(runFishlint(["eslint", "--disable-setup", "--glob", "src"]).status);

const textReport = lintText("debugger;\n", {
  filePath: "inline.js",
  rules: ["no-debugger"]
});
console.log(textReport.diagnostics);

const eslint = new ESLint({
  useEslintrc: false,
  overrideConfig: {
    rules: {
      "no-debugger": "warn"
    }
  }
});
const results = await eslint.lintText("debugger;\n", { filePath: "inline.js" });
console.log(results[0].messages);
console.log(ESLint.version);
console.log(ESLint.getErrorResults(results));

const cli = new CLIEngine({
  useEslintrc: false,
  baseConfig: {
    rules: {
      "no-debugger": "error"
    }
  }
});
console.log(cli.executeOnFiles(["src"]).results);
```

CommonJS scripts can use the same surface through `require()`:

```js
const { ESLint, lintFiles } = require("@utoo/lint");
```

The CommonJS entry is kept behaviorally aligned with the ESM API, including
the fishlint wrapper and per-file flat config handling.

`lintFiles()` and `lintText()` return an object with `files`, `filePaths`,
`diagnostics`, `suppressedDiagnostics`, and `exitCode`. Each diagnostic includes `filePath`, `line`,
`column`, `severity`, `message`, and `ruleId`, with disabled per-file rules
filtered from the diagnostics. `exitCode` is recalculated from the filtered
diagnostics: warnings return 0 and errors return 1. Diagnostics matched by
`utlint-ignore`, `utlint-ignore-all`, or a start/end suppression range appear
in `suppressedDiagnostics`; ESLint-compatible results map them to
`suppressedMessages`. The `ESLint` export is an
alias for `UtooLint`
and supports the common `lintFiles()`, `lintText()`,
`loadFormatter()`, `isPathIgnored()`, and `calculateConfigForFile()` methods for
low-friction replacements. It also provides ESLint-compatible `version`,
`configType`, `defaultConfig`, `fromOptionsModule()`, `outputFixes()`,
`getErrorResults()`, `getRulesMetaForResults()`, `findConfigFile()`, and
`hasFlag()` surfaces. The top-level
`loadESLint()` helper resolves to the compatibility `ESLint` class.
The `Linter` export supports in-memory `verify()` and `verifyAndFix()` calls for
utoo-lint's built-in ESLint-compatible rules, plus `getRules()` and explicit
unsupported custom rule definition methods. The `RuleTester` export can run
basic valid/invalid cases for those built-in rules and supports the
default-config and test-framework static helpers. The `SourceCode` export
provides basic text, location, token, and comment helpers used by
`Linter#getSourceCode()`.
Rule meta includes best-effort `docs.url` values for common ESLint-compatible
rule IDs. `loadFormatter()` and `CLIEngine#getFormatter()` support `json`,
`json-with-metadata`, `compact`, `unix`, and the native text formatter shape.
`lintFiles()` returns absolute `filePaths` and diagnostic `filePath` values,
accepts common glob patterns such as `src/**/*.js` and `src/**/*.{js,ts}`,
supports character classes such as `src/**/*.[jt]s` and negated patterns such
as `!src/generated.js`, includes empty results for checked files with no
messages, and filters inputs with the same ignore rules.
`lintText()` applies those ignore rules to the supplied `filePath` and uses the
same config discovery as file linting unless `noConfig` is set. Raw
`lintText()` reports use the supplied `filePath` for both `filePaths` and
diagnostics.
`isPathIgnored()` reads default `.eslintignore` entries plus `ignorePath`,
`ignorePatterns`, `noIgnore`, and `baseConfig`/`overrideConfig` ignore entries.
`calculateConfigForFile()` and `CLIEngine#getConfigForFile()` combine
`baseConfig`, the selected canonical project config, explicit
`overrideConfigFile`, and `overrideConfig` rules. Project config discovery is
nearest-directory-first. Within a directory, `utlint.config.ts` wins over
`utlint.config.json`; the deprecated `utoo.json` and `utoo-lint.json` names are
checked afterward for temporary compatibility. The project files are
alternative representations of one selected config and are never implicitly
merged with one another. `baseConfig` and
`overrideConfig` may be objects or flat config arrays; when a file path is
provided, flat config `files` and `ignores` entries are applied before merging.
Patterns from the selected project config are resolved relative to that config
file's directory. Matching flat entries are combined in array order, so later
rule values override earlier values.
ESLint-compatible results use those calculated rule severities for `messages`,
`errorCount`, and `warningCount`, including per-file flat config matches. The
JS API filters diagnostics for rules disabled by the matched file config. The
native run keeps rules enabled when any matched flat config entry may need them,
so later `off` entries do not suppress diagnostics for other files. Raw
`diagnostics` use the same per-file severity and disabled-rule filtering. The
`CLIEngine` export
provides a synchronous legacy facade for older ESLint integrations.
`CLIEngine#executeOnText()` accepts a string path or an options object with
`filePath`, `filename`, and text lint options.
It also exposes legacy `getRules()`, `addPlugin()`, and
`resolveFileGlobPatterns()` facade methods for integrations that probe them
during startup.
The `@utoo/lint/config` subpath exposes `defineConfig()` and `globalIgnores()`,
including basic flat config `extends` expansion, and `@utoo/lint/universal`
exposes `Linter` for browser-oriented integrations.
The `@utoo/lint/use-at-your-own-risk` subpath exposes `builtinRules`,
`FlatESLint`, `LegacyESLint`, `shouldUseFlatConfig()`, and `FileEnumerator`
compatibility exports.
The CLI includes a native migration path for projects replacing ESLint config
files:

```bash
utoo-lint migrate eslint --from eslint.config.js --output utlint.config.json
```

The migrator writes a utoo config, reports unsupported rules, skips
formatter-only rules such as `prettier/prettier`, and keeps supported rule
configs without treating ESLint as the long-term runtime API. It currently
flattens ESLint flat-config entries into one object; later duplicate rule values
win, so per-file conflicts need manual review.
The package ships TypeScript declarations for the main entrypoint and
compatibility subpaths, so typed ESLint integrations do not need a separate
`@types` package.
`ESLint` and `CLIEngine` constructor options also accept `quiet: true` to return
only error messages, matching ESLint's warning filtering behavior.
`warnIgnored: false` suppresses warnings for explicit ignored file paths and
skips ignored `lintText()` inputs. `errorOnUnmatchedPattern: false` skips
explicit missing file paths. Set
`UTOO_LINT_BIN=/path/to/utoo-lint` to force the JS API and CLI wrapper to use a
specific native binary during local development.

The package also ships a fishlint compatibility CLI at
`node_modules/@utoo/lint/bin/fishlint.js` for projects that currently run
`fishlint eslint ...`. It is not registered as a `fishlint` bin (only
`utoo-lint` and `utlint` are), so scripts opt into it by path. It supports the
common eslint subcommand
shape, forwards `--config` and `-c`, maps `--glob` values to native lint
targets, expands common `--glob` patterns such as `src/**/*.js` and
`src/**/*.{js,ts}` or `src/**/*.[jt]s`, and normalizes split value flags such
as `--format json`, `-f json`,
`--threads 4`, and `--rules no-debugger`. `--no-eslintrc` maps to native
`--no-config`, and `--no-eslintrc=true` is accepted for compatibility.
`json-with-metadata` emits the native JSON report with a `metadata.rulesMeta`
section. Other non-JSON ESLint formatter names are accepted and use native text
output. `--rule`
accepts JSON objects such as
`{"no-console":"warn"}` and simple `rule: severity` pairs, merging them into the
selected utoo-lint config for the run. Compatibility output and exit status are
normalized from the selected config severity. It ignores fishlint-only setup/debug
flags. `--ext` is accepted for compatibility; native directory traversal already
filters to supported JavaScript and TypeScript extensions. ESLint cache controls and
other cache flags are consumed for compatibility because utoo-lint does not keep
an ESLint-style result cache. The wrapper applies ESLint-style warning exit-code
semantics, including `--max-warnings`. ESLint runtime config flags such as
`--env`, `-E`, `--global`, `--parser`, `--parser-options`, `--plugin`, and
ignore-pattern flags are accepted so existing wrapper scripts do not pass them
as file targets. The wrapper applies simple `.eslintignore`, `--ignore-path`,
and `--ignore-pattern` filters such as `dist/**` to explicit and `--glob`
targets before invoking native lint, including `**/*.js` globstar patterns and
`!pattern` negation entries. Negated `--glob` values such as
`--glob '!src/generated/**'` exclude files from expanded lint targets.
`--no-ignore` and `--no-ignore=true` disable those wrapper-side ignore filters.
`--no-error-on-unmatched-pattern` and `--no-error-on-unmatched-pattern=true` skip
missing explicit and `--glob` targets before invoking native lint. `--quiet`
and `--quiet=true` filter warnings from compatibility output. Explicit ignored
file paths emit ESLint-style warnings unless `--no-warn-ignored` or
`--no-warn-ignored=true` is set.
`--fix` and `--fix-dry-run` apply fixes from supported native rules. The Node
API also composes those fixes with fixes reported by custom rules. `--fix-type`
remains accepted with a warning but is not implemented yet. Native autofix
coverage is tracked per rule in [the rule status](../docs/rule-status.md).
Display and reporting controls such as `--color`, `--no-color`, `--stats`,
`--stats=true`, and `--no-warn-ignored` are accepted for the same reason.
`--output-file` and `-o` write the native output to the requested report file.
`--stdin` reads source from standard input, and `--stdin-filename` controls the
path shown in output.
`--print-config` prints the selected utoo-lint JSON configuration for migration
debugging.

The package also ships an ESLint CLI wrapper at
`node_modules/@utoo/lint/bin/eslint.js` that routes directly through the same
wrapper, so package scripts such as `eslint src -f json` can be tested without
adding the `fishlint eslint` prefix. It is not registered as an `eslint` bin
either, so an installed ESLint keeps owning that command.

```bash
node node_modules/@utoo/lint/bin/fishlint.js eslint --disable-setup --config utlint.config.json --ext .js,.ts --glob src
node node_modules/@utoo/lint/bin/eslint.js --config utlint.config.json --ext .js,.ts src
```

For programmatic replacements, `runFishlint()` invokes the same compatibility
wrapper as `bin/fishlint.js`, including wrapper-side ignore filtering, quiet
output, max-warning exit semantics, stdin handling through `options.input`, and
delegated commands.

For non-eslint fishlint commands, the compatibility command delegates to
project-local tools when they are installed: `fishlint format` runs `prettier`,
`fishlint stylelint` runs `stylelint`, `fishlint commitlint` runs `commitlint`,
and `fishlint projectlint` runs `projectlint`. This keeps existing scripts
working without treating those tools as native `utoo-lint` checks. Delegated
commands also consume fishlint-only setup and verbose flags, including
`--disable-setup=true` and similar value forms.
`fishlint format` defaults to `prettier --write`, but keeps explicit prettier
mode flags such as `--check`, `--list-different`, and `--debug-check` instead
of adding `--write`.
`fishlint commitlint -E=GIT_PARAMS` is normalized like `--env GIT_PARAMS`,
falling back to `--edit` when the environment variable is not set.
Default delegated targets are still added when the command only contains
configuration value flags such as `fishlint format --config .prettierrc`.
`fishlint setup` and `fishlint setuplint` are accepted as no-ops so existing
install hooks do not fail after replacing the package.

`node_modules/@utoo/lint/bin/fishlint-lint-staged.js` is also provided for
generated fishlint pre-commit hooks; reference it by path as well.
If a project has its own `lint-staged` install, the wrapper delegates to it.
Otherwise it lints staged JavaScript and TypeScript files directly with
the same `fishlint eslint` compatibility wrapper, preserving flags such as
`--config`, `--rules`, and `--quiet`.

Use the packaged frontend config in an app:

```bash
cp node_modules/@utoo/lint/configs/frontend.json utlint.config.json
pnpm exec utoo-lint src
```

The package also ships `schema.json`, which the frontend config references through
its `$schema` field for editor validation.

Build and stage the local native package for the current host:

```bash
./scripts/package-npm.sh
```

Test the wrapper from source:

```bash
node npm/utoo-lint/bin/utoo-lint.js test/fixtures/bad.ts
```

For local global testing:

```bash
pnpm add -g ./npm/@utoo/lint-darwin-arm64 # replace with the current host package
pnpm add -g ./npm/utoo-lint
utoo-lint test/fixtures/bad.ts
```

Publishing is orchestrated by `scripts/publish-npm-packages.mjs`:

```bash
NPM_TAG=latest node scripts/publish-npm-packages.mjs
```

GitHub Actions stages the native package directories from the release matrix,
copies their binaries into the workspace packages, updates package versions from
the release tag, and publishes with pnpm in `.github/workflows/release.yml`.
Exact versions that already exist are skipped so interrupted releases can be
retried. All packages publish through npm Trusted Publishing/OIDC; new packages
must be initialized and authorize `release.yml` before they are added to a
release. The WebAssembly package is attempted first and the root `@utoo/lint`
package last.
