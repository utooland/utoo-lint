# utoo-lint Playground

The Playground runs utoo-lint entirely in the browser. It uses the public
EVJS packages, Utoopack, Monaco Editor, a Web Worker, and the workspace
`@utoo/lint-wasm` package. Its AST inspector uses the public
`@yuku-parser/wasm` 0.10.1 package, matching the Yuku revision vendored by
utoo-lint.

No `@alipay/*` package, private registry, internal runtime, or server process
is required. EVJS mounts the root `src/pages/page.tsx` as a CSR SPA at
`/playground`, and the static deployment adapter emits a complete site under
`dist/client`.

## Develop

From the repository root, install dependencies with Node.js 20 or newer and
pnpm 10:

```bash
pnpm install --frozen-lockfile
```

The available WebAssembly versions are discovered from stable GitHub releases
that contain `utoo-lint.wasm` and intentionally are not checked into Git. The
staging script downloads the latest ten versions, verifies their release
SHA-256 digests, and generates the version manifest before starting the
Playground. If GitHub is temporarily unavailable during local development, a
previously verified local manifest and its cached assets are reused:

```bash
pnpm playground:dev
```

The `latest` channel is selected by default and follows the newest stable
version. Selecting a concrete version adds `?version=<version>` to the
Playground URL so the same engine can be reopened or shared even after a newer
release. The Utoopack development URL is printed in the terminal. Open the
`/playground` route rather than the server root.

## Verify and build

```bash
pnpm playground:typecheck
pnpm --filter @utoo/lint-playground inspect
pnpm playground:build
```

The production build runs a deployment audit after `ev build`. It checks that
the output is a complete static deployment, contains valid lint and parser
WASM assets,
requires no server, loads no remote runtime assets, and contains no known
internal registry or release-chain markers.

The production HTML and its initial assets are prepared for the `/playground/`
subpath. The repository-level `site:build` command builds the dumi docs, copies
this output into `dist/site/playground`, and writes the Cloudflare Pages control
files at the unified site root.

The production Playground is deployed to
[`utlint.umijs.org/playground/`](https://utlint.umijs.org/playground/).

## Runtime boundaries

- Linting and autofix run in a long-lived Web Worker.
- The worker loads the freestanding WASM module once and reuses it.
- AST parsing runs in a separate Worker and starts only after opening the AST
  inspector.
- Both WASM modules are bundled locally; the page makes no parser CDN request.
- The Playground lints one in-memory JavaScript, TypeScript, JSX, or TSX file.
- Rules that require filesystem access are reported as skipped.
- Monaco is bundled locally; the page does not depend on a CDN.
