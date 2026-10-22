# utoo-lint benchmark

This directory benchmarks the current local `@utoo/lint` binary against Oxlint,
Biome, ESLint, and optionally Bun lint on the same generated TypeScript corpus
and the same shared lint rule set.

The runner, corpus generator, and rule configurations live in the repository
so they can evolve with the linter and be reviewed together. Generated fixtures,
local tool installations, and run results are ignored. Published results are
separate, dated snapshots with their source data checked in.

## Setup

From the repository root:

```bash
zig build -Doptimize=fast
cd benchmarks
npm install
npm run generate
UTOO_LINT_BUILD_MODE=fast npm run bench -- --runs=20 --warmups=5
```

The benchmark runner writes machine-readable output to `results/latest.json`,
including raw timing samples, commands, the target file count, and the shared
rule list. It also records CLI and dependency versions, the CPU model and thread
count, OS release, and the repository commit and dirty state. The native
`utoo-lint` binary has no `--version` command, so its provenance comes from the
repository commit, the supplied `UTOO_LINT_BUILD_MODE`, and its SHA-256 digest.

## Bun lint

Bun is opt-in: set `BUN_BIN` to a binary that supports `bun lint`, or pass
`--bun` to use `bun` from `PATH`. The Bun 1.4.3 stable npm binary does not include
the built-in lint command. This pinned canary package was verified to support
it and can be installed independently:

```bash
# Run from benchmarks/
npm install --prefix .tools/bun-canary-20261012.1 --no-save --package-lock=false --no-audit --no-fund bun@1.4.3-canary.20261012.1
BUN_BIN="$PWD/.tools/bun-canary-20261012.1/node_modules/.bin/bun" UTOO_LINT_BUILD_MODE=fast npm run bench -- --runs=20 --warmups=5
```

The package reports runtime version `1.4.4-canary.1+b92e2f470`. The isolated
installation leaves the system Bun unchanged. `--skip-bun` takes precedence over
both `BUN_BIN` and `--bun`.

## Rule profiles

`--rule-set=shared` is the default and preserves the original 12-rule comparison.
`--rule-set=extended` enables 49 rules: the original 12 plus 37 non-type-aware
core ESLint rules with corresponding
mappings for the other tools in `scripts/extended-rules.mjs`. The runner selects
the same profile for every tool, including Bun and ESLint's shared configuration.
Rules with differing defaults or TypeScript skips are excluded; for example,
Oxlint skips `getter-return` on TypeScript files.

Compare both profiles on the same 1,000-file corpus:

```bash
npm run generate -- --files=1000 --statements=30 --out=fixtures/bun-comparison
BUN_BIN="$PWD/.tools/bun-canary-20261012.1/node_modules/.bin/bun" UTOO_LINT_BUILD_MODE=fast npm run bench -- --rule-set=shared --target=fixtures/bun-comparison --runs=20 --warmups=5
BUN_BIN="$PWD/.tools/bun-canary-20261012.1/node_modules/.bin/bun" UTOO_LINT_BUILD_MODE=fast npm run bench -- --rule-set=extended --target=fixtures/bun-comparison --runs=20 --warmups=5
```

## Recorded comparisons

The October 13, 2026 local runs used an Apple M4 Pro, 1,000 generated TypeScript
files with 30 statement blocks each, 5 warmups, and 20 measured runs per tool.
The dated snapshots preserve every sample, command, version, and validation result:

- [12 shared rules](snapshots/2026-10-13-bun-12-rules.json)
- [49 shared rules](snapshots/2026-10-13-bun-49-rules.json)

These runs precede the worker-memory and reference-index optimizations. They
measure this generated workload, including CLI startup and configuration loading.

## Commands

```bash
npm run generate -- --files=2000 --statements=40
npm run bench -- --runs=10 --warmups=3
npm run bench:config-discovery -- --time=1000 --warmup-time=500
```

The config-discovery benchmark models 1,000 lint inputs spread across 100
package directories. It reports both uncached upward searches and the
per-invocation directory cache used by the npm wrapper.

The default `utoo-lint` command is `../zig-out/bin/utoo-lint fixtures/src`.
Override it with:

```bash
UTOO_LINT_BIN=/path/to/utoo-lint npm run bench
```

Skip ESLint when you only want the native linter comparison:

```bash
npm run bench -- --skip-eslint
```

Force the original four tools even when `BUN_BIN` is set:

```bash
npm run bench -- --skip-bun
```

## Notes

- The generated corpus is designed to be valid TypeScript with no intentional
  diagnostics. This keeps benchmark time focused on traversal and rule
  execution instead of terminal output.
- The runner keeps tool comparisons aligned by applying the same target path to
  every tool and enabling only the shared rules defined in
  `scripts/shared-rules.mjs`.
- Before timing, every tool checks the full profile's clean control and the
  actual target file count with zero corpus diagnostics. The shared profile uses
  a combined violation fixture; the extended profile checks a separate violation
  with each rule enabled in isolation. These probes check that the selected
  rules run on common cases; they do not establish complete semantic equivalence.
- Bun uses `lint --flavor=eslint --config=eslint.config.js --no-ignore --silent target`,
  reusing the same configuration as ESLint. That configuration
  enables exactly the selected rule profile from `scripts/shared-rules.mjs`,
  with no default rules. Ignore processing is disabled and successful runs produce no
  diagnostic output.
- The default shared rule set is: `no-const-assign`,
  `no-empty-character-class`, `no-empty-pattern`, `no-unsafe-finally`,
  `use-isnan`, `valid-typeof`, `no-debugger`, `no-duplicate-case`,
  `no-fallthrough`, `no-global-assign`, `no-import-assign`, and
  `no-unsafe-negation`.
- The runner measures wall-clock time for fresh CLI processes, including process
  startup and configuration loading. `utoo-lint` uses the native binary directly,
  so the npm wrapper's
  startup and config discovery costs are excluded. Editor daemon behavior,
  type-aware rules, formatting, and automatic fixes are out of scope. Warmups
  prime the OS file cache; this is not a cold-disk benchmark.
- Warmups and measured runs interleave the tools in rounds, rotating the first
  tool in each round to reduce timing bias from execution order.

## Node API severity-config benchmark

CodSpeed also runs a `CLIEngine` workload modeled after Umi: 1,000 TypeScript
files across 100 package directories with a large flat config containing only
rule severities. Run a smaller local sample with:

```bash
pnpm codspeed:severity-config -- --files=100 --runs=3 --warmups=1
```

## Native flat-config benchmark

CodSpeed also exercises the npm wrapper with 1,000 TypeScript files split
across source and test flat-config groups. The wrapper serializes the config
once and delegates per-file selector resolution to one native process.

Run a smaller local sample with:

```bash
pnpm codspeed:native-flat-config -- --files=100 --time=100 --warmup-time=0
```

## Focused before/after comparison

`bench:focused` compares two explicitly supplied native binaries and npm
wrappers. Build both revisions before running it; the runner never compiles.
To isolate local optimizations from the Yuku upgrade, use the upgrade-only
commit as the baseline and build both binaries with the same Zig version and
`-Doptimize=fast`.

```bash
# Run from benchmarks/. Paths may point to separate checkouts or saved artifacts.
pnpm bench:focused --before-binary=/path/to/baseline/utoo-lint --before-wrapper=/path/to/baseline/npm/utoo-lint/index.cjs --before-ref=7addc3f --after-binary=../zig-out/bin/utoo-lint --after-wrapper=../npm/utoo-lint/index.cjs --runs=20 --warmups=5 --output=results/focused.json
```

The baseline wrapper needs its matching `lib/`, `package.json`, and installed
dependencies. Both wrappers use the same native binary (the candidate by
default) to isolate JavaScript changes; `--js-binary=PATH` selects another shared
binary. Native scenarios use each revision's own binary.

The default scenarios are:

- `no-shadow`: 500, 2,000, and 8,000 exported functions with distinct parameter
  bindings, using one thread and only `no-shadow`.
- `diagnostics`: 4,000 `debugger` lines, plus a 4,000-line control with just one
  diagnostic on the first line. Text output exercises diagnostic position lookup.
- `semantic`: JavaScript and TypeScript files containing 8,000 repeated updates,
  enabling only `semantic-errors`.
- `control`: the existing clean 1,000-file corpus under both the 12-rule and
  49-rule profiles, using the default thread count.
- `source-code`: separate ordinary-token, token-with-comments, and source-location
  queries over 2,000 declarations. Parsing and `SourceCode` setup are excluded.
- `plugin`: `Linter.verify` with a custom rule that checks each declaration's next
  token and reports a message. This includes native lint, parsing, AST traversal,
  rule execution, and the final report.

Before timing, native results must match in every JSON field, text stdout,
stderr, and exit code. The runner also checks expected file/diagnostic counts.
JavaScript runs hash every returned API value or plugin message and check equal
counts. Timed samples must reproduce those outputs. All fixtures are generated
in an isolated temporary directory and removed afterward.

Each paired round alternates which revision runs first. Every sample starts a
fresh process: warmups prime filesystem caches, while JavaScript query timings
still include cold-JIT behavior. JSON output contains raw operation times and
process wall times, output hashes, source hashes, wrapper and binary hashes,
Node/CPU/OS/Zig metadata, source refs, working-tree status, and a diff digest.
Results are saved after each completed scenario; `complete: false` marks a
partial run. Tiny smoke runs validate the runner, not performance:

```bash
pnpm bench:focused --before-binary=/path/to/baseline/utoo-lint --before-wrapper=/path/to/baseline/npm/utoo-lint/index.cjs --runs=1 --warmups=0 --shadow-counts=3 --diagnostic-lines=6 --semantic-references=8 --control-files=2 --control-statements=1 --js-statements=4 --output=results/focused-smoke.json
```

Use `--scenarios=no-shadow,semantic` to select groups, or `--help` for all size
options. Optional `--memory-runs=5` performs separate native peak-RSS samples
with `/usr/bin/time -l` on macOS or `-v` on Linux and normalizes values to bytes.
JavaScript workers separately report Node's own peak RSS in KiB, captured before
result hashing; that value excludes the native child and must not be presented as
the whole workload's memory. These focused synthetic cases explain targeted changes; the normal
corpus controls check broader throughput and small-change regressions.

## Published website chart

The website uses the archived 2026-08-30 run in
[`public/benchmarks/2026-08-30.json`](../public/benchmarks/2026-08-30.json).
It uses the original 12-rule profile and contains the samples and commands,
but not exact tool versions or the CPU model. It is a dated snapshot, not a
benchmark of the latest release.

Regenerate its English and Chinese SVG images from the repository root:

```bash
node scripts/render-site-benchmark.mjs
```

The published chart uses a linear zero-based scale. New local runs continue to
write to `results/latest.json`; they do not silently replace the published data.
