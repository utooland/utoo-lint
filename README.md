![utoo-lint banner](assets/utoo-lint-banner.png)

# utoo-lint

[![npm version](https://img.shields.io/npm/v/%40utoo%2Flint?logo=npm)](https://www.npmjs.com/package/@utoo/lint)
[![Node.js 20+](https://img.shields.io/badge/Node.js-%3E%3D20-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![CI](https://github.com/utooland/utoo-lint/actions/workflows/ci.yml/badge.svg)](https://github.com/utooland/utoo-lint/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/utooland/utoo-lint)](LICENSE)

A high-performance linter for JavaScript and TypeScript, written in Zig and
powered by [Yuku](https://github.com/yuku-toolchain/yuku).

`utoo-lint` is published on npm as
[`@utoo/lint`](https://www.npmjs.com/package/@utoo/lint). It combines a native
lint engine with familiar configuration, CLI, and JavaScript APIs.

[Website](https://utlint.umijs.org/) · [Installation](#installation) ·
[Quick start](#quick-start) ·
[Rules](docs/rule-status.md) · [Configuration](docs/configuration.md) ·
[WebAssembly](docs/wasm.md) · [Playground](https://utlint.umijs.org/playground/) ·
[ESLint migration](docs/eslint-migration.md)

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
- **Browser-ready engine** — The separate `@utoo/lint-wasm` package runs
  single-file linting and autofix entirely in memory.

## Performance

The benchmark suite compares fresh CLI runs of utoo-lint, Oxlint, Biome, and
ESLint on the same generated TypeScript corpus and shared rule set.

![utoo-lint benchmark](assets/utoo-lint-benchmark.png)

See the [benchmark methodology](benchmarks/README.md) to reproduce the results
and understand what is included in the comparison.

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

The npm package selects the native binary for the current platform. No Zig
toolchain is required when using the published package.

## Quick start

### Run with the default rules

Point `utoo-lint` at a file or directory:

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

React Compiler-related `react-hooks/use-memo`, `react-hooks/void-use-memo`, `react-hooks/purity`, `react-hooks/set-state-in-render`
checks are also available as opt-in rules. See
[configuration and coverage](docs/configuration.md#react-compiler-related-checks).

Override project-specific rules after spreading `frontend.rules`, and append
framework-generated directories to `frontend.ignores`, as shown above.

The preset intentionally enables no formatter or type-checker integration.
Keep Prettier (or another formatter) and `tsc` as independent project steps.

Run the linter again without repeating the target:

```bash
utx @utoo/lint
```

The CLI discovers the nearest `utlint.config.ts` or `utlint.config.json` and
uses its `files` patterns. See the [configuration guide](docs/configuration.md)
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

The npm CLI and JavaScript API load both config formats. The raw native binary
loads JSON only. See the [configuration guide](docs/configuration.md) for the
complete behavior.

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
[rule status](docs/rule-status.md) documents autofix support for each rule.

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

See the [suppression comments guide](docs/suppressions.md) for range examples
and API behavior.

## Migrating from ESLint

Convert an existing ESLint config into a native utoo-lint config:

```bash
utx @utoo/lint migrate eslint \
  --from eslint.config.js \
  --output utlint.config.json
```

The package also exposes `eslint` and `fishlint` compatibility commands for
incremental replacement workflows. See [Migrating from ESLint](docs/eslint-migration.md)
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

The Node wrapper captures up to 64 MiB from each native stdout and stderr
stream by default. Programmatic `run`, `runCli`, and `runFishlint` calls can set
`maxBuffer` to another positive byte count. Set `UTOO_LINT_MAX_BUFFER` to apply
the same limit to CLI invocations; output beyond the configured bound reports
`ENOBUFS` instead of being truncated.

## WebAssembly

Use the separate `@utoo/lint-wasm` package for browser playgrounds, Web
Workers, and other ESM runtimes that support WebAssembly:

```bash
pnpm add @utoo/lint-wasm
```

```js
import { createUtooLint } from "@utoo/lint-wasm";

const linter = await createUtooLint();
const report = linter.lint("debugger;", {
  filePath: "playground.js",
  rules: { "no-debugger": "error" }
});

console.log(report.diagnostics);
```

The WebAssembly build has no WASI or real-filesystem dependency. It lints one
in-memory source at a time; enabled rules that require project I/O are not run
and are reported in `skippedRules`. For an interactive playground, keep the
linter instance in a Web Worker so synchronous lint calls do not block the UI.

See the [WebAssembly guide](docs/wasm.md) for the Node ESM API, autofix,
configuration semantics, Worker setup, and local build commands.

This repository also includes an [EVJS + Utoopack Playground](apps/playground/README.md)
that bundles Monaco Editor and runs the WASM engine in a Web Worker. Its
production output is a server-free static site suitable for public hosting.

## Documentation

- [Rule status](docs/rule-status.md) — implemented rules and autofix coverage
- [Configuration](docs/configuration.md) — config discovery, matching, and rule
  values
- [Suppression comments](docs/suppressions.md) — line, file, and range
  suppressions
- [WebAssembly](docs/wasm.md) — browser and Node ESM usage, runtime boundaries,
  and Playground integration
- [Migrating from ESLint](docs/eslint-migration.md) — migration workflow and
  compatibility notes
- [Contributing](CONTRIBUTING.md) — local development, rule work, and releases
- [Security policy](SECURITY.md) — privately report a vulnerability

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before
opening a pull request. The native engine is built with Zig, and Yuku is pinned
as a git submodule for reproducible parser behavior.

## License

[MIT](LICENSE)
