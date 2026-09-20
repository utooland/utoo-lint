# Contributing

This guide covers local development, rule implementation, packaging, benchmark
charts, and publishing for `utoo-lint`.

## Reporting Issues

Every `utoo-lint` issue must include a minimal reproduction URL from the
[Playground](https://utlint.umijs.org/playground/).

1. Search existing issues to avoid duplicates.
2. Reduce the example to the smallest relevant code sample in the Playground.
   Choose the correct file extension and configure the relevant rules and options.
3. Select a concrete **Version** instead of `latest` so the reproduction stays
   tied to the engine version you tested.
4. Click **Share** and copy the full URL, including `?version=...` and
   `#playground=...`. Reopen it to verify that the code and rule configuration
   are restored. A link to the Playground homepage is not a reproduction.
5. Open an issue using the issue form. Include the reproduction URL, steps to
   reproduce, expected behavior, and actual behavior. For rule requests, use
   the Playground example to demonstrate the desired diagnostic or fix.

For CLI, configuration discovery, or filesystem issues that cannot be fully
reproduced in the browser, still include a Playground link with the relevant
code and explain its limitations. Add a minimal repository, exact commands,
configuration, and environment details needed to reproduce the full issue.

Issues without a valid Playground reproduction will be asked to provide one
before investigation proceeds. After a fix is released, verify the same example
with the fixed version and record the result before closing the issue.

Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Prerequisites

Yuku currently tracks Zig nightly. Use a Zig version compatible with the
vendored Yuku commit:

```bash
zig version
```

The vendored Yuku `build.zig.zon` currently asks for
`0.16.0` or newer. The repository is currently tested with
`0.17.0-dev.224+c166c49b1`.

Initialize submodules before building:

```bash
git submodule update --init --recursive
```

Install JavaScript workspace dependencies with pnpm:

```bash
corepack enable
pnpm install
```

## Development

Run the test suite:

```bash
zig build test -Doptimize=ReleaseFast -j1
```

Build the CLI:

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/utoo-lint src test
```

Run the CLI against the fixture:

```bash
zig build run -Doptimize=ReleaseFast -j1 -- test/fixtures/bad.ts
```

## Adding a Rule

Add a new file under `src/rules`, then register it in `src/rules/root.zig`.

For a structural rule, add a check function in the rule file and call it from
the matching visitor hook in `BasicVisitor`.

For a scope or symbol rule, add a `run` function in the rule file and call it
from `runSemantic`.

Add focused tests under `tests/rules`, then include the test module from
`tests/all.zig`.

For a rule's externally visible diagnostic contract, add a fixture under
`tests/snapshots/specs/<category>/<rule>`. The category maps filesystem-safe
names to rule namespaces, for example:

```text
tests/snapshots/specs/core/no-debugger/multiple.js
tests/snapshots/specs/typescript-eslint/no-invalid-void-type/invalid.ts
tests/snapshots/specs/react/no-unescaped-entities/default.jsx
```

Every fixture has a `<case>.options.json` sidecar whose expectations are
independent from its snapshot. Use `"expect": "clean"` with a zero count for a
valid fixture. `required`, `forbidden`, and `any` make fix availability part of
the test contract. The sidecar can also set `rule_options` to the same JSON
value accepted by a lint rule:

```json
{
  "expect": "diagnostics",
  "diagnostic_count": 1,
  "fixes": "forbidden",
  "rule_options": ["error", { "allow": ["warn"] }]
}
```

Run only the snapshot suite in verification mode:

```bash
zig build test-snapshots -j1
```

Snapshots record ordered diagnostics with their rule, severity, message, byte
span, line and column, covered source, and every original fix span and
replacement. Fixable cases also record the first fix pass and its remaining
diagnostics.

After an intentional rule behavior change, update snapshots explicitly:

```bash
zig build update-snapshots -j1
git diff -- tests/snapshots
```

Verification never replaces an accepted `.snap`; a missing or mismatched
snapshot is written as `.snap.new` and the test fails. Review the candidate,
then run the update command to accept it. Orphan snapshots and stale
`.snap.new` files fail verification. The regular `zig build test` step also
runs this suite, so CI rejects unreviewed changes.

## Benchmarks

The benchmark workspace compares the local `utoo-lint` binary with Oxlint,
Biome, and ESLint on a generated TypeScript corpus using a shared rule set.

```bash
zig build -Doptimize=ReleaseFast
pnpm --dir benchmarks generate
pnpm --dir benchmarks bench
```

The benchmark runner writes machine-readable results to
`benchmarks/results/latest.json`.

Render a shareable chart from the latest benchmark results:

```bash
pnpm --dir benchmarks chart
```

`benchmarks/results` is ignored by git, so generated charts do not need to be
cleaned up before committing.

## Packaging

Build and stage the npm CLI packages:

```bash
./scripts/package-npm.sh
node npm/utoo-lint/bin/utoo-lint.js test/fixtures/bad.ts
```

Local pnpm install test:

```bash
pnpm add -g ./npm/@utoo/lint-darwin-arm64
pnpm add -g ./npm/utoo-lint
utoo-lint test/fixtures/bad.ts
```

Build, stage, and validate the browser WebAssembly package:

```bash
pnpm package:wasm
pnpm test:wasm
pnpm --dir npm/@utoo/lint-wasm test
pnpm --dir npm/@utoo/lint-wasm test:types
```

The npm package layout is:

- `npm/utoo-lint` is the public CLI wrapper published as `@utoo/lint`.
- `npm/@utoo/lint-wasm` is the browser-ready package published as
  `@utoo/lint-wasm`.
- `npm/@utoo/lint-darwin-arm64` is published as
  `@utoo/lint-darwin-arm64`.
- `npm/@utoo/lint-darwin-x64` is published as `@utoo/lint-darwin-x64`.
- `npm/@utoo/lint-linux-arm64` is published as `@utoo/lint-linux-arm64`.
- `npm/@utoo/lint-linux-x64` is published as `@utoo/lint-linux-x64`.
- `npm/@utoo/lint-win32-x64` is published as `@utoo/lint-win32-x64`.

## Publishing

GitHub Releases publish binary archives for:

- `utoo-lint-darwin-arm64.tar.gz`
- `utoo-lint-darwin-x64.tar.gz`
- `utoo-lint-linux-arm64.tar.gz`
- `utoo-lint-linux-x64.tar.gz`
- `utoo-lint-windows-x64.zip`
- `utoo-lint.wasm`
- `utoo-lint.wasm.gz`
- `utoo-lint.wasm.sha256`

Each native archive is uploaded with a matching `.sha256` file. The
WebAssembly checksum covers the raw `utoo-lint.wasm` artifact.

The release workflow builds all native and WebAssembly assets, stages the npm
packages from the same artifacts, uploads the release assets to GitHub, and
publishes the scoped packages before the CLI wrapper.

Every npm package must already exist and authorize this repository through npm
Trusted Publishing with these GitHub Actions settings:

```text
Organization: utooland
Repository: utoo-lint
Workflow: release.yml
Allowed action: npm publish
```

The release job uses OIDC exclusively and does not receive an npm publishing
token. Before adding a new package to the release workflow, initialize it on
npm and configure the Trusted Publisher above.

Publishing is idempotent. The workflow checks every exact package version
before publishing, skips versions already present on npm, rejects uninitialized
packages before publishing anything, publishes `@utoo/lint-wasm` first to catch
Trusted Publisher configuration errors early, and publishes the root
`@utoo/lint` package last.

Publish from GitHub:

1. Create a new GitHub Release whose tag starts with `v`, for example `v0.1.0`.
2. Publish the release.

The release workflow updates npm package versions from the release tag, builds
the native binaries, and publishes the npm packages with pnpm.

For a manual run, open the `Release` workflow in GitHub Actions and set
`release_tag` to a `v`-prefixed tag. Enable `publish_npm` when the npm packages
should be published.

After the workflow succeeds:

```bash
pnpm add -g @utoo/lint
utoo-lint test/fixtures/bad.ts
```
