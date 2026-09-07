# @utoo/lint

![utoo-lint logo](assets/utoo-lint-logo.svg)

[![npm version](https://img.shields.io/npm/v/%40utoo%2Flint?logo=npm)](https://www.npmjs.com/package/@utoo/lint)
[![Node.js 20+](https://img.shields.io/badge/Node.js-%3E%3D20-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![CI](https://github.com/utooland/utoo-lint/actions/workflows/ci.yml/badge.svg)](https://github.com/utooland/utoo-lint/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/utooland/utoo-lint)](https://github.com/utooland/utoo-lint/blob/main/LICENSE)

A high-performance linter for JavaScript and TypeScript, written in Zig and
powered by [Yuku](https://github.com/yuku-toolchain/yuku).

`@utoo/lint` combines a native lint engine with familiar configuration, CLI,
and JavaScript APIs.

[Installation](#installation) · [Quick start](#quick-start) ·
[Rules](https://github.com/utooland/utoo-lint/blob/main/docs/rule-status.md) ·
[Configuration](https://github.com/utooland/utoo-lint/blob/main/docs/configuration.md) ·
[GitHub](https://github.com/utooland/utoo-lint)

## Why utoo-lint?

- **Native performance** — Zig and Yuku power parsing, semantic analysis, and
  parallel file linting.
- **Broad rule coverage** — More than 300 rules cover JavaScript, TypeScript,
  React, JSX accessibility, and imports.
- **Familiar configuration** — Use typed `utlint.config.ts` or static
  `utlint.config.json`, with ESLint-style rule names and severities.
- **Practical workflows** — Safe autofix, suppression comments, JSON output,
  and ESM/CommonJS APIs are included.
- **Portable installation** — Prebuilt binaries are available for macOS,
  Linux, and Windows on supported architectures.

## Installation

`@utoo/lint` requires Node.js 20 or later.

### utoo

[utoo](https://utoo.land/en/docs/utoo) is a fast, npm-compatible package
manager written in Rust. Install it once if it is not already available:

```bash
npm install -g utoo
```

Add `@utoo/lint` as a development dependency:

```bash
ut install @utoo/lint -D
```

In an existing project, run `ut install` without a package name to install all
dependencies declared in `package.json`.

### Other package managers

```bash
pnpm add -D @utoo/lint
npm install --save-dev @utoo/lint
```

The package selects the native binary for the current platform. No Zig
toolchain is required.

## Quick start

### Run with the default rules

```bash
utx @utoo/lint src
```

Without a config file, `utoo-lint` uses its built-in default rules. It supports
`.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs`, `.mts`, and `.cts` files.

### Add a typed config

Create `utlint.config.ts`:

```ts
import { defineConfig } from "@utoo/lint/config";
import frontend from "@utoo/lint/configs/frontend";

export default defineConfig({
  ...frontend,
  ignores: [...frontend.ignores, ".next", "storybook-static"],
  rules: {
    ...frontend.rules,
    "no-console": "off",
    "react/no-forward-ref": "off"
  }
});
```

The frontend preset uses `error` for correctness and safety checks that should
fail CI, and `warn` for migration or maintainability checks that should remain
visible without blocking adoption:

| Severity | Added frontend guardrails |
| --- | --- |
| `error` | `react-hooks/rules-of-hooks`, `react/jsx-key`, `react/no-children-prop`, `react/no-danger-with-children`, `react/void-dom-elements-no-children`, `no-script-url`, `promise/no-nesting` |
| `warn` | `react-hooks/exhaustive-deps`, `react/no-array-index-key`, `react/no-unstable-nested-components`, `react/no-forward-ref`, `unused-imports/no-unused-imports`, `@typescript-eslint/no-unused-vars`, `@typescript-eslint/ban-types` |

Override project-specific rules after spreading `frontend.rules`, and append
framework-generated directories to `frontend.ignores`, as shown above.

The preset intentionally enables no formatter or type-checker integration.
Keep Prettier (or another formatter) and `tsc` as independent project steps.

The CLI discovers the config and uses its `files` patterns:

```bash
utx @utoo/lint
```

See the
[configuration guide](https://github.com/utooland/utoo-lint/blob/main/docs/configuration.md)
for flat config arrays, global ignores, rule options, and config precedence.

### Add package scripts

```json
{
  "scripts": {
    "lint": "utoo-lint src",
    "lint:fix": "utoo-lint --fix src"
  }
}
```

With utoo, run these scripts as `ut lint` and `ut lint:fix`.

## Common commands

| Task | Command |
| --- | --- |
| Lint files | `utx @utoo/lint src` |
| Apply safe fixes | `utx @utoo/lint --fix src` |
| Preview fixes as JSON | `utx @utoo/lint --fix-dry-run --format=json src` |
| Select rules for one run | `utx @utoo/lint --rules=no-debugger,no-unused-vars src` |
| Use an explicit config | `utx @utoo/lint --config=utlint.config.json src` |

Run `utx @utoo/lint --help` for all CLI options.

## Configuration

`utoo-lint` supports two canonical config formats. They are alternative
representations of one active config and are not merged together.

| Config | Best for | Raw native binary |
| --- | --- | --- |
| `utlint.config.ts` | Typed authoring, imports, presets, and computed values | No |
| `utlint.config.json` | Static configuration and JSON Schema validation | Yes |

Rule severities follow ESLint conventions: `off`, `warn`, `error`, `0`, `1`,
and `2`. A selected config enables only the rules present in its resolved
`rules` map.

The npm CLI and JavaScript API load both formats. The raw native binary loads
JSON only. See the
[configuration guide](https://github.com/utooland/utoo-lint/blob/main/docs/configuration.md)
for the complete behavior.

## Autofix

Apply safe fixes in place:

```bash
utx @utoo/lint --fix src
```

Preview fixes without writing files:

```bash
utx @utoo/lint --fix-dry-run --format=json src
```

Fixes run until the source is stable, subject to a safety pass limit. The
[rule status](https://github.com/utooland/utoo-lint/blob/main/docs/rule-status.md)
documents autofix support for each rule.

## Suppression comments

Use suppression comments for intentional exceptions without disabling a rule
in project configuration:

```js
// utlint-ignore no-debugger: generated breakpoint
debugger;
```

| Directive | Scope |
| --- | --- |
| `utlint-ignore [rule]` | The next line of code |
| `utlint-ignore-all [rule]` | The entire file when placed before any code |
| `utlint-ignore-start [rule]` | The start of a suppressed range |
| `utlint-ignore-end [rule]` | The end of a suppressed range |

A directive may target one rule ID. Omitting it creates or closes an all-rules
suppression. Parse errors are never suppressed, and suppressed fixes are not
applied.

See the
[suppression comments guide](https://github.com/utooland/utoo-lint/blob/main/docs/suppressions.md)
for range examples and API behavior.

## Migrating from ESLint

Convert an existing ESLint config into a native utoo-lint config:

```bash
utx @utoo/lint migrate eslint \
  --from eslint.config.js \
  --output utlint.config.json
```

The package also exposes `eslint` and `fishlint` compatibility commands for
incremental replacement workflows. See the
[migration guide](https://github.com/utooland/utoo-lint/blob/main/docs/eslint-migration.md)
for supported mappings and known differences.

## JavaScript API

The package provides ESM and CommonJS entry points:

```js
import { lintFiles } from "@utoo/lint";

const report = lintFiles(["src"], {
  config: "utlint.config.ts"
});

console.log(report.diagnostics);
```

An ESLint-style API is also available:

```js
import { ESLint } from "@utoo/lint";

const eslint = new ESLint({ fix: true });
const results = await eslint.lintFiles(["src"]);
await ESLint.outputFixes(results);
```

`await eslint.loadFormatter()` and `cliEngine.getFormatter()` default to an
ESLint-style `stylish` report: aligned columns, blank lines between files,
diagnostics sorted by line and column, and a summary of fixable errors and
warnings. Rule messages (including punctuation), result arrays, and exit codes
are unchanged. Only actual autofixes count toward the `--fix` hint, not editor
suggestions; missing JSX keys still need a manually chosen stable, unique key.

The stylish formatter detects color support on stdout. Pass `color: true` or
`color: false` to the `ESLint` or `CLIEngine` constructor to override detection.
Otherwise, `NO_COLOR` or `NODE_DISABLE_COLORS` disables color; `FORCE_COLOR`
forces it (`0` disables), followed by `CLICOLOR_FORCE` and stdout TTY detection
(`TERM=dumb` disables automatic color). Constructor `env` overrides also apply.
JSON, JSON-with-metadata, compact, unix, and native CLI text formats are unchanged.

Raw reports include active diagnostics, suppressed diagnostics, fixed outputs,
and an exit code. The compatibility layer also exports `Linter`, `CLIEngine`,
`RuleTester`, and `SourceCode` APIs.

Native JSON diagnostics and ESLint-compatible messages include one-based `line`,
`column`, `endLine`, and `endColumn` positions for source spans. Columns count
UTF-16 code units, and the end position is exclusive. Suppressed diagnostics keep
the same range. I/O errors without a source span omit the end positions; messages
from older native binaries may also omit them.

`ESLint` and `CLIEngine` also discover classic `.eslintrc.*` files (or
`eslintConfig` in `package.json`) when no native config applies. Legacy
`extends`, directory cascades, `root`, `overrides`, and ignore patterns are
resolved per source filename. Precedence is `baseConfig`, project config,
then `overrideConfig`; `useEslintrc: false` disables discovery. Native config
files still take priority. The lower-level `lintFiles`, `lintText`, and native
CLI keep their native-only discovery behavior.

Legacy configuration resolution uses `@eslint/eslintrc`. If the project has
ESLint 8 installed, its configuration resolver is used instead to support
shared configs that patch ESLint's module resolution. Neither path uses ESLint
to parse or lint source files: rules still run in utoo-lint. Enabled rules that
utoo-lint does not support remain errors, not silently skipped checks.

The Node wrapper captures up to 64 MiB from each native stdout and stderr
stream by default. Programmatic `run`, `runCli`, and `runFishlint` calls can set
`maxBuffer` to another positive byte count. Set `UTOO_LINT_MAX_BUFFER` to apply
the same limit to CLI invocations; output beyond the configured bound reports
`ENOBUFS` instead of being truncated.

## WebAssembly

For browser playgrounds and in-memory Node ESM usage, install the independent
`@utoo/lint-wasm` package. It ships a freestanding WebAssembly module rather
than selecting one of the native platform packages used by `@utoo/lint`.

See the
[WebAssembly guide](https://github.com/utooland/utoo-lint/blob/main/docs/wasm.md)
for its API, runtime boundaries, and Web Worker recommendation.

## Supported platforms

The package installs a platform-specific optional dependency containing the
native binary.

| Operating system | Architectures |
| --- | --- |
| macOS | arm64, x64 |
| Linux | arm64, x64 |
| Windows | x64 |

Set `UTOO_LINT_BIN=/path/to/utoo-lint` to use a custom binary during local
development.

## Documentation

- [Rule status](https://github.com/utooland/utoo-lint/blob/main/docs/rule-status.md)
- [Configuration](https://github.com/utooland/utoo-lint/blob/main/docs/configuration.md)
- [Suppression comments](https://github.com/utooland/utoo-lint/blob/main/docs/suppressions.md)
- [WebAssembly](https://github.com/utooland/utoo-lint/blob/main/docs/wasm.md)
- [Migrating from ESLint](https://github.com/utooland/utoo-lint/blob/main/docs/eslint-migration.md)
- [Benchmarks](https://github.com/utooland/utoo-lint/tree/main/benchmarks)
- [Security policy](https://github.com/utooland/utoo-lint/blob/main/SECURITY.md)

## License

[MIT](https://github.com/utooland/utoo-lint/blob/main/LICENSE)
