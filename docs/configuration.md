# Configuration

`utoo-lint` selects one config from the current working directory or its
ancestors, then applies rule-related CLI overrides.

The canonical config names are:

- `utlint.config.ts`: a typed, executable config loaded by the npm/Node CLI.
- `utlint.config.json`: a static JSON config readable by both the npm CLI and
  the raw native binary.

Choose the format based on how the config will be used:

| Config | Best for | npm/Node CLI | Raw native binary |
| --- | --- | --- | --- |
| `utlint.config.ts` | Type checking while authoring, imports, shared presets, and computed values | Yes | No |
| `utlint.config.json` | Static configuration, schema validation, and direct native use | Yes | Yes |

These are alternative representations of the same active config. They are not
implicitly merged. For the npm/Node entry point, discovery is nearest-first:
all supported names are checked in one directory before the parent directory is
considered. In the same directory, the order is:

1. `utlint.config.ts`
2. `utlint.config.json`
3. `utoo.json` (deprecated)
4. `utoo-lint.json` (deprecated)

This means a nearer `utlint.config.json` wins over a more distant
`utlint.config.ts`. The two legacy JSON names remain temporarily supported for
migration, but new projects should use a canonical name.

The npm CLI discovers either canonical format automatically:

```bash
npx utoo-lint src
```

To select a file explicitly, pass either format to `--config`:

```bash
npx utoo-lint --config=utlint.config.ts src
npx utoo-lint --config=utlint.config.json src
```

Use `--no-config` to ignore local config. Rule-related CLI options such as
`--rules` and individual rule toggles are applied after the selected config.
The resolved `rules` map is the complete enabled rule set, matching ESLint's
configuration model: omitted rules are disabled. If no config is selected,
utoo-lint uses its built-in default rules.

Project-config `files` and `ignores` patterns are resolved relative to the
selected config file's directory, including when that config is discovered in
an ancestor directory or selected explicitly.

## TypeScript Config

Use `utlint.config.ts` for typed authoring, TypeScript syntax, imports, or
computed configuration:

```ts
import { defineConfig } from "@utoo/lint/config";

export default defineConfig({
  files: ["src/**/*.{js,jsx,ts,tsx}"],
  ignores: ["dist", "node_modules"],
  rules: {
    "no-debugger": "error",
    "no-console": "warn"
  }
});
```

The packaged frontend preset has a typed export and can be extended directly
without copying its JSON file or asserting its rule types:

```ts
import { defineConfig } from "@utoo/lint/config";
import frontend from "@utoo/lint/configs/frontend";

export default defineConfig({
  ...frontend,
  ignores: [...frontend.ignores, ".next", "storybook-static"],
  rules: {
    ...frontend.rules,
    "no-console": "off",
  },
});
```

### Global and Entry-Scoped Ignores

Use `globalIgnores()` to exclude files or whole directories from every config
entry. The helper returns an ignore-only entry, so pass it as a separate
`defineConfig()` argument or array item:

```ts
import { defineConfig, globalIgnores } from "@utoo/lint/config";

export default defineConfig(
  globalIgnores(["dist/", ".next/", "**/generated/"]),
  {
    files: ["**/*.{js,jsx,ts,tsx}"],
    rules: {
      "no-debugger": "error"
    }
  }
);
```

An entry is global only when it contains `ignores` and, optionally, `name`.
Adding `files`, `rules`, or another config key makes its `ignores` patterns
entry-scoped: they stop that entry from applying to matching files, but do not
exclude those files from other entries. Only global ignores prune matching
directories during file discovery. A trailing slash expresses a directory;
use `dist/` or `.next/` for a directory beside the config and
`**/generated/` for directories with that name at any depth.

When no lint target is passed, the npm/Node wrapper discovers targets from the
config's `files` patterns, or scans the current directory if there are none.
Global ignores filter that discovery and prevent traversal into ignored
directories. Entry-scoped ignores are evaluated later, while resolving the
matching config for each discovered file. This shape intentionally follows
[ESLint flat config's global and non-global ignore semantics](https://eslint.org/docs/latest/use/configure/ignore).

`defineConfig()` accepts config objects and flat config arrays and returns a
flat array. It also provides editor completion and compile-time checking from
the exported configuration types. A TypeScript config is trusted executable
code: loading it can run arbitrary code with the permissions of the Node
process. Its default export must be a JSON-serializable config object or flat
config array. The loader transpiles and executes TypeScript syntax; it does not
run `tsc` or perform type checking when linting starts.

For a flat config array, each entry's `files` and `ignores` select the files to
which that entry applies. Matching entries are combined in array order, so a
later matching rule value overrides an earlier value for the same rule. The npm
CLI, JavaScript API, and fishlint compatibility command apply this rule
resolution separately for each linted file.

The npm wrapper executes the TypeScript file, materializes its result as JSON,
and passes that flat config to one native process. The raw native binary does
not execute or discover TypeScript; it searches for `utlint.config.json` and
then the legacy JSON names. Use the npm CLI for `utlint.config.ts`; when
invoking the raw binary directly, use `utlint.config.json`.

The raw binary resolves static flat-config `files`, global and entry-scoped
`ignores`, ordered rule overrides, and supported shared `settings` for each
file. With no explicit lint target, config selectors and global ignores also
control native file discovery. Patterns are relative to the selected config's
directory.

## JSON Config

Use `utlint.config.json` for a static, runtime-independent config:

```json
{
  "$schema": "https://raw.githubusercontent.com/utooland/utoo-lint/main/npm/utoo-lint/schema.json",
  "files": ["src/**/*.{js,jsx,ts,tsx}"],
  "ignores": ["dist", "node_modules"],
  "rules": {
    "no-debugger": "error",
    "no-console": "warn"
  }
}
```

The optional `$schema` property enables completion and validation in editors
that support JSON Schema. JSON config cannot contain imports or computed
values; use `utlint.config.ts` when those are required.

Version-aware Jest rules detect the closest installed `jest` package by
default and fall back to the latest supported major when no installation can
be found. Set `settings.jest.version` when a repository uses multiple Jest
versions or needs to pin the version used for linting:

```json
{
  "settings": {
    "jest": {
      "version": "29.7.0",
      "globalAliases": { "describe": ["context"] }
    }
  },
  "rules": {
    "jest/no-deprecated-functions": "error",
    "jest/no-focused-tests": "error"
  }
}
```

Use `settings.jest.globalAliases` to map canonical Jest functions to
project-specific global names. For example, the configuration above treats
`context` as an alias for `describe`.

ESLint config files are a migration input, not the recommended long-term
configuration format. Generate a native config with:

```bash
npx utoo-lint migrate eslint --from eslint.config.js --output utlint.config.json
```

## Frontend Project Config

For a React or TypeScript frontend project, start by copying the packaged frontend template into the project root:

```bash
cp node_modules/@utoo/lint/configs/frontend.json utlint.config.json
npx utoo-lint
```

The template includes a `$schema` entry for editor validation and a focused set of browser, import, React, JSX a11y, and TypeScript rules:

```json
{
  "$schema": "https://raw.githubusercontent.com/utooland/utoo-lint/main/npm/utoo-lint/schema.json",
  "files": ["src/**/*.{js,jsx,ts,tsx}"],
  "ignores": ["dist", "coverage", "node_modules"],
  "rules": {
    "no-debugger": "error",
    "no-console": "warn",
    "react/jsx-no-target-blank": "error",
    "jsx-a11y/aria-props": "error",
    "@typescript-eslint/no-unused-vars": "warn"
  }
}
```

With no target argument, the copied preset scans JavaScript and TypeScript
under `src`. Its rules do not apply to `dist`, `coverage`, or `node_modules`,
including when `.` is passed explicitly. Add framework-specific generated
directories such as `.next`, `storybook-static`, or `build` to the copied
`ignores` array. Typed configs can append to `frontend.ignores` as shown in the
TypeScript example above.

`utoo-lint` treats config severities like ESLint. `off`, `0`, and `false`
disable a rule; `warn`, `warning`, `on`, and `1` report warnings; `error`, `2`,
and `true` report errors. ESLint-style arrays are accepted; the first item
controls severity, and supported option objects are passed to the native rule
implementation. Warnings leave the process exit status at 0, while errors
return status 1.

## Rule Names

Use canonical ESLint rule names in `rules`:

```json
{
  "rules": {
    "no-debugger": "error",
    "import/no-duplicates": "error",
    "react/jsx-no-duplicate-props": "error",
    "jsx-a11y/iframe-has-title": "error",
    "@typescript-eslint/no-require-imports": "error"
  }
}
```

Unknown rule names are rejected so typos do not silently pass. See [Rule status](rule-status.md) for the implemented rule list.

## CLI Precedence

Rule-related CLI options are applied after the config file:

```bash
npx utoo-lint --config=utlint.config.json --no-console=off src
```

For one-off focused runs, `--rules` disables every rule first, then enables only the listed rules:

```bash
npx utoo-lint --rules=no-debugger,react/jsx-no-target-blank src
```

## React Compiler-related checks

Enable the native React Compiler-related checks explicitly in `utlint.config.json`:

```json
{
  "rules": {
    "react-hooks/use-memo": "error",
    "react-hooks/void-use-memo": "error"
  }
}
```

These rules are disabled by default and are not added to the `frontend` preset.
They run in both native and WebAssembly builds without installing React Compiler.
They cover a documented subset of the upstream rules; enabling them does not prove
that a component can be compiled. See [rule status](rule-status.md#react-hooks-rules)
for supported patterns and limitations.

Rule names follow React main at `e92bda78750136493cb324e98df1726f62ba8e92`: `use-memo`
checks callback signatures and captured assignments; `void-use-memo` checks missing
returns and unused results and is in upstream `recommended-latest`. The selected
upstream fixtures and their coverage boundaries are recorded in each rule’s
`tests/snapshots/specs/react-hooks/<rule>/UPSTREAM.md`.
