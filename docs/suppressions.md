# Suppression comments

`utoo-lint` supports Biome-style suppression comments using the
`utlint-ignore` prefix. A suppression may target one rule or all lint rules.
Adding an explanation after `:` is recommended; APIs preserve it with the
suppressed diagnostic.

## Next line of code

Use `utlint-ignore` before the code that should be exempt:

```js
// utlint-ignore no-debugger: generated breakpoint
debugger;
```

Blank lines and other comments may appear between the directive and the code.
An intervening line of code consumes the directive. Omit the rule ID to
suppress every lint rule for that line of code:

```js
// utlint-ignore: generated statement
debugger; console.log("generated");
```

## Entire file

Use `utlint-ignore-all` before any code in the file:

```js
// utlint-ignore-all no-debugger: generated file
```

Leading comments, a UTF-8 byte-order mark, and a script shebang may precede
the directive. An `utlint-ignore-all` placed after code has no effect.

## Range

Use matching `utlint-ignore-start` and `utlint-ignore-end` directives:

```js
// utlint-ignore-start no-debugger: generated section
debugger;
debugger;
// utlint-ignore-end no-debugger: generated section
```

Ranges may overlap or nest. A named end closes a range for the same rule; an
end without a rule ID closes an all-rules range.

All four directives work in line or block comments. Rule IDs use the same
names as configuration, including namespaced IDs such as
`@typescript-eslint/no-unused-vars`.

## Diagnostics and autofix

Suppression applies to lint-rule diagnostics, including diagnostics from
ESLint-compatible custom rules. Parse errors are never suppressed. A
suppressed diagnostic's fix is not applied by `--fix` or `--fix-dry-run`.

Native JSON and the `lintFiles()` / `lintText()` APIs expose suppressed items
in `suppressedDiagnostics`. The ESLint-compatible API exposes them in
`suppressedMessages`, including the directive explanation in `suppressions`.

ESLint disable/enable directives validate named rules even when `rules: {}` is
configured or no lint rule reports a problem. Unknown names produce an error at
the comment span: `Definition for rule 'unknown-rule' was not found.` This error
cannot be suppressed. Registered native rules and JS plugin rules mounted for
the file remain known even when disabled. This validation does not apply to
`utlint-ignore` directives.
