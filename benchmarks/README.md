# utoo-lint benchmark

The CodSpeed workflow measures walltime on the fixed
`codspeed-macro-arm64-graviton-ubuntu-22-04` runner label. Standard GitHub
`ubuntu-latest` jobs can use different CPU models, making their elapsed times
unsuitable as a stable regression baseline. Keep the runner label the same for
the default branch and pull requests; see the
[CodSpeed runner documentation](https://codspeed.io/docs/features/macro-runners).

When changing runner hardware, the first successful default-branch run becomes
the new baseline. Compare subsequent pull requests against that baseline rather
than attributing the hardware transition's timing changes to source code. This
runner change does not change the workload, measurement mode or regression
thresholds. The CodSpeed GitHub App must already have Macro Runner access for
the repository; see the
[GitHub Actions setup](https://codspeed.io/docs/integrations/ci/github-actions/macro-runners).

This directory benchmarks the local `@utoo/lint` native binary or an installed
published npm CLI against Oxlint, Biome, ESLint, and optionally Bun lint on the
same generated TypeScript corpus and shared lint rule set.

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
`--bun` to use `bun` from `PATH`. As checked on October 28, 2026, the Bun 1.4.4
stable npm binary does not include the built-in lint command. This pinned canary
package was verified to support it and can be installed independently:

```bash
# Run from benchmarks/
npm install --prefix .tools/release --no-save --package-lock=false --no-audit --no-fund bun@1.4.4-canary.20261027.1
BUN_BIN="$PWD/.tools/release/node_modules/.bin/bun" UTOO_LINT_BUILD_MODE=fast npm run bench -- --runs=20 --warmups=5
```

The package reports runtime version/revision `1.4.4-canary.1+a0cc096ce`. The isolated
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
BUN_BIN="$PWD/.tools/release/node_modules/.bin/bun" UTOO_LINT_BUILD_MODE=fast npm run bench -- --rule-set=shared --target=fixtures/bun-comparison --runs=20 --warmups=5
BUN_BIN="$PWD/.tools/release/node_modules/.bin/bun" UTOO_LINT_BUILD_MODE=fast npm run bench -- --rule-set=extended --target=fixtures/bun-comparison --runs=20 --warmups=5
```

## Published npm CLI comparison

Use this mode for a release comparison of the CLI users install. Unlike the
default native mode, it includes the npm wrapper's process startup, TypeScript
configuration loading, file selection, native delegation, and reporting. It
uses the installed package's platform binary; no local build is required.

The runner collects the input paths once and passes the same explicit file list
to every tool. Directory discovery is excluded for all tools. This also avoids
VCS-ignore differences: Oxlint 1.90.0 can skip an ignored directory even with
`--no-ignore`, while explicit file arguments are checked. The generated fixture
directory remains ignored by Git; validation confirms every tool checks every
input file.

From the repository root, with Node.js 22.13 or later:

```bash
pnpm install --frozen-lockfile
cd benchmarks
npm install --prefix .tools/release --no-save --package-lock=false --no-audit --no-fund @utoo/lint@0.4.13 bun@1.4.4-canary.20261027.1
npm run generate -- --files=1000 --statements=30 --out=fixtures/release

env -u UTOO_LINT_BIN BUN_BIN="$PWD/.tools/release/node_modules/.bin/bun" \
  npm run bench -- --utoo-cli=.tools/release/node_modules/.bin/utlint \
  --rule-set=shared --target=fixtures/release --warmups=5 --runs=20 \
  --output=results/release-12.json

env -u UTOO_LINT_BIN BUN_BIN="$PWD/.tools/release/node_modules/.bin/bun" \
  npm run bench -- --utoo-cli=.tools/release/node_modules/.bin/utlint \
  --rule-set=extended --target=fixtures/release --warmups=5 --runs=20 \
  --output=results/release-49.json
```

The isolated prefix keeps the published `@utoo/lint` and Bun installations out of
the workspace dependency graph. Oxlint, Biome, ESLint, and the TypeScript parser
are pinned by `benchmarks/package.json` and the root `pnpm-lock.yaml`.
`utlint.config.ts` enables exactly the selected profile. CLI mode rejects
`UTOO_LINT_BIN` so an environment override cannot silently substitute a local
native binary.

Each profile uses the same 1,000 synthetic TypeScript files with 30 statement
blocks per file, five warmups, and 20 measured samples per tool. Every sample
starts a fresh process, with tools interleaved in rotating order. OS file caches
and configuration-loader caches are warmed; no lint-result cache is enabled.
This is not a cold-disk measurement or a benchmark of a running editor daemon.

The 12-rule and 49-rule profiles contain common non-type-aware rules. Before
timing, the runner verifies rule violations, the full-profile execution path,
clean controls, and the actual corpus file count. These probes establish common
case coverage, not complete semantic equivalence. The synthetic corpus does not
represent every project's syntax, plugins, type-aware checks, or diagnostics.
Report measured results with their versions, hardware, workload, and sampling
method; do not present a synthetic speed ratio as a guarantee for all projects.

`--utoo-cli=PATH` selects the published CLI entry or its `.bin/utlint` alias.
`--output=PATH` chooses the raw JSON destination (default
`results/latest.json`). `--timeout-ms=N` bounds each timed process (default
`120000`). The JSON retains every sample, commands, versions, corpus byte/line
counts and digest, configuration/runner hashes, validation results, and the
installed wrapper and native binary digests.

### Release chart

Render a white-background SVG and PNG from both raw result files. From the
repository root:

```bash
python3 -m venv benchmarks/.tools/chart-venv
benchmarks/.tools/chart-venv/bin/python -m pip install -r benchmarks/chart-requirements.txt
benchmarks/.tools/chart-venv/bin/python benchmarks/scripts/render-release-chart.py \
  --input benchmarks/results/release-12.json \
  --input benchmarks/results/release-49.json \
  --output benchmarks/results/release-comparison
```

The chart dependency is pinned to Matplotlib 3.10.7. All five tools remain
visible, including Bun's canary version. Bars show median wall-clock time on a
shared linear scale starting at zero; shorter is better. Relative figures use
each profile's fastest median as the denominator. Archive the raw JSON beside
the chart when publishing a dated result.

## Recorded comparison: 2026-10-28

The release comparison used the published `@utoo/lint@0.4.13` npm CLI on an
Apple M4 Pro (12 logical cores, 48 GiB), macOS arm64, Node.js 22.23.1. The
1,000-file corpus contains 239,000 lines / 4,576,311 bytes. Both profiles used
five warmups followed by 20 rotated, interleaved samples per tool.

| CLI | Version | 12 rules median (ms) | 49 rules median (ms) |
| --- | --- | ---: | ---: |
| utoo-lint | 0.4.13 | 482.667 | 541.272 |
| Bun lint | 1.4.4 canary | 137.746 | 141.381 |
| Oxlint | 1.90.0 | 190.195 | 194.734 |
| Biome | 2.6.3 | 373.972 | 406.116 |
| ESLint | 10.13.0 | 2690.676 | 2801.086 |

ESLint's median elapsed time divided by utoo-lint's was 5.57x for 12 rules and
5.18x for 49 rules. These are ratios for this synthetic common-rule workload.
The local desktop host was shared with other processes; the snapshots retain
every sample, timing ranges, standard deviations, and host load averages.
Directory discovery is excluded equally for all tools; config loading and
fresh process startup are included. No type checking, formatting, fixes, or
lint-result caching is measured.

Bun was installed as `1.4.4-canary.20261027.1+9b8347a`; its binary reports
`1.4.4-canary.1+a0cc096ce` via `--revision`. The stable `1.4.4` binary did not
expose `bun lint` when checked. The TypeScript parser is `typescript-eslint`
8.72.1 with TypeScript 6.0.3. The full-profile fixture directory and isolated
rule controls passed for all five tools; every tool checked all 1,000 corpus
files with zero diagnostics. This validates the selected common cases, without
establishing complete semantic equivalence between rule implementations.

Both raw snapshots were captured at clean benchmark commit `8fa585d`:

- [12-rule samples and provenance](snapshots/2026-10-28-release-cli-12-rules.json)
- [49-rule samples and provenance](snapshots/2026-10-28-release-cli-49-rules.json)
- [PNG chart](../assets/utoo-lint-benchmark-2026-10-28.png) / [SVG chart](../assets/utoo-lint-benchmark-2026-10-28.svg)

Regenerate the published chart from the repository root:

```bash
benchmarks/.tools/chart-venv/bin/python benchmarks/scripts/render-release-chart.py \
  --input benchmarks/snapshots/2026-10-28-release-cli-12-rules.json \
  --input benchmarks/snapshots/2026-10-28-release-cli-49-rules.json \
  --output assets/utoo-lint-benchmark-2026-10-28 --title 'utoo-lint · Lint Performance'
```

## Earlier recorded comparisons

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

The default `utoo-lint` command uses `../zig-out/bin/utoo-lint` with the
explicit input file list collected from `fixtures/src`.
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
- The runner keeps tool comparisons aligned by applying the same explicit input file list to
  every tool and enabling only the shared rules defined in
  `scripts/shared-rules.mjs`.
- Before timing, every tool checks the full profile's clean control and the
  actual target file count with zero corpus diagnostics. The shared profile uses
  a combined violation fixture; the extended profile checks the full profile on
  a directory of violations as well as each rule enabled in isolation. These probes check that the selected
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
  startup and configuration loading. In the default mode, `utoo-lint` uses the
  native binary directly, excluding npm wrapper startup and config discovery;
  `--utoo-cli` instead measures the installed npm CLI and its TS config. Editor daemon behavior,
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

For native-only groups such as `--scenarios=control`, wrapper arguments are
optional and JavaScript dependency metadata is omitted. Compiler and build-mode
provenance is recorded per revision: `--before-zig` / `--after-zig` and
`--before-build-mode` / `--after-build-mode` override the shared `--zig` and
`--build-mode` defaults when comparing revisions that require different toolchains.

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

### Recorded results: 2026-10-23

The [full raw results](snapshots/2026-10-23-yuku-hotpaths.json) compare the
Yuku 0.22.1 upgrade alone (`7addc3f`) with the subsequent hotpath optimizations
(`3f5b271`). The run used an Apple M4, macOS arm64, Node.js 20.19.1, and
Zig 0.17.0 with `-Doptimize=fast`: 20 alternating before/after pairs after five
warmup pairs, with a fresh process per sample. All 13 scenarios passed output
parity checks, and every measured sample reproduced its validated output.

The raw record was captured before the optimization commit, so its recorded
HEAD and candidate source ref still resolve to `7addc3f`. Its working-tree file
hashes, candidate wrapper inventory, and runner hashes were verified against `3f5b271`;
the archived provenance is unchanged.

| Scenario | Before median (ms) | After median (ms) | Time reduction |
| --- | ---: | ---: | ---: |
| `no-shadow`, 500 functions | 3.057 | 2.597 | 15.0% |
| `no-shadow`, 2,000 functions | 10.912 | 3.268 | 70.1% |
| `no-shadow`, 8,000 functions | 133.726 | 6.094 | 95.4% |
| Text output, 4,000 diagnostics | 51.568 | 3.042 | 94.1% |
| Text output, first-line diagnostic in 4,000 lines | 2.213 | 2.212 | 0.0% |
| Semantic errors, JS, 8,000 references | 3.249 | 2.838 | 12.6% |
| Semantic errors, TS, 8,000 references | 3.473 | 3.061 | 11.9% |
| Control, 1,000 files, 12 rules | 73.213 | 72.706 | 0.7% |
| Control, 1,000 files, 49 rules | 75.059 | 74.106 | 1.3% |
| SourceCode tokens, 2,000 declarations | 586.015 | 200.792 | 65.7% |
| SourceCode tokens with comments, 2,000 declarations | 3,027.193 | 489.510 | 83.8% |
| SourceCode locations, 2,000 declarations | 4.003 | 1.105 | 72.4% |
| Plugin verification, 2,000 declarations | 870.686 | 171.808 | 80.3% |

These are targeted synthetic workloads, not general project speedups. The two
ordinary corpus controls were effectively flat: their 0.7% and 1.3% median
reductions were small relative to sample variation. Native timings include
startup and text output; SourceCode timings exclude parsing, while plugin
timings include the whole `Linter.verify` call.

Five separate native RSS measurements per revision showed about 25% lower
median peak RSS for semantic-only checks: 12.828 to 9.578 MiB for JS and 12.875
to 9.609 MiB for TS. The diagnostic position index increased the 4,000-diagnostic
case from 8.641 to 8.766 MiB, a 0.125 MiB tradeoff. The raw JSON also records
JavaScript workers' Node-only peak RSS; it excludes native child processes and
does not measure the whole plugin workload's memory.

### Main-to-candidate control

A separate [same-machine comparison](snapshots/2026-10-23-main-controls.json)
measures the complete upgrade and optimization against main (`957d528`). Main
was built from unchanged sources with its declared Zig
`0.17.0-dev.224+c166c49b1` and `ReleaseFast`; the candidate (`3f5b271`) uses
Zig 0.17.0 and `fast`. The [baseline build record](snapshots/2026-10-23-main-build.json)
includes source, binary, and compiler hashes plus official signature verification.
This comparison includes the toolchain change, so it does not isolate Yuku alone.

Both profiles passed complete JSON and text output parity checks over 20
alternating pairs after five warmup pairs on the same Apple M4:

| Native control | Main median (ms) | Candidate median (ms) | Time reduction | Main / candidate peak RSS (MiB) |
| --- | ---: | ---: | ---: | ---: |
| 1,000 files, 12 rules | 81.438 | 74.954 | 8.0% | 63.469 / 57.359 |
| 1,000 files, 49 rules | 83.251 | 75.675 | 9.1% | 63.797 / 57.516 |

RSS values are medians of five separate measurements. Reproduce this native-only
comparison with `--scenarios=control`, the two binaries and source refs, and
`--before-zig`, `--after-zig`, `--before-build-mode=ReleaseFast`, and
`--after-build-mode=fast` pointing to the corresponding toolchains.

The [upgrade-only CodSpeed report](https://github.com/utooland/utoo-lint/pull/1295#issuecomment-6345348918)
flagged slower Linux wall times, but also warns that the two runs used different
runner types. Unchanged configuration-discovery cases were slower as well.
The local native controls did not reproduce that regression; they do not resolve
the Linux alert or establish performance for every workload. Keep the CI report
separate from these controlled macOS measurements.

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
