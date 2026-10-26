# `@utoo/lint-wasm`

Browser-ready WebAssembly build of utoo-lint. It runs JavaScript, TypeScript,
JSX, and TSX lint rules entirely in memory and is suitable for playgrounds and
Web Workers.

```sh
pnpm add @utoo/lint-wasm
```

```js
import { createUtooLint } from "@utoo/lint-wasm";

const linter = await createUtooLint();
const result = linter.lint(`const value = console.log("hello");`, {
  filePath: "playground.ts",
  rules: {
    "no-console": "warn",
    "no-unused-vars": "error"
  }
});

console.log(result.diagnostics);
```

Use `lintAndFix()` to preview safe fixes without changing any files:

```js
const fixed = linter.lintAndFix("const value = 1;;;", {
  filePath: "playground.js",
  rules: { "no-extra-semi": "error" }
});

console.log(fixed.output);
```

Diagnostic and fix ranges are UTF-16 offsets, so they can be passed directly
to JavaScript string APIs and browser editors. Run the linter in a Web Worker
for interactive editors so large inputs do not block the main thread.

Rules that need a real project filesystem cannot run in the freestanding
module. Enabled rules in that category are returned in `skippedRules`; this
currently covers dependency-aware import rules and project-config-aware Alipay
rules. All parser, basic, and in-memory semantic rules remain available.

Omit `rules` to use utoo-lint's default rule set. Pass `rules: {}` when the
playground should start with every rule disabled and then enable individual
rules from its UI.

Set `sourceType: "script"` or `"commonjs"` to parse sloppy scripts. The default
follows `filePath`: `.cjs` and `.cts` use CommonJS, and other extensions use
modules. Modules and explicit `"use strict"` contexts report invalid strict
syntax as parse errors even with `rules: {}`.

`createUtooLint()` also accepts a URL, `Response`, bytes, compiled
`WebAssembly.Module`, or `WebAssembly.Instance` through its `wasm` option for
custom hosting and testing:

```js
const linter = await createUtooLint({
  wasm: new URL("/assets/utoo-lint.wasm", location.href)
});
```

Serve the file with `Content-Type: application/wasm` to enable streaming
compilation. The loader automatically falls back to buffered compilation when
that MIME type is unavailable. Production hosting should also enable Brotli or
gzip compression for the `.wasm` asset.
