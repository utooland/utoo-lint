# Rule status

This document tracks the ESLint-compatible rules currently implemented by `utoo-lint`.
Each rule links to the corresponding ESLint rule reference.
Autofix is called out where it is available; unsafe code shapes remain diagnostics
instead of being rewritten.

| Rule | Status |
| --- | --- |
| [`accessor-pairs`](https://eslint.org/docs/latest/rules/accessor-pairs) | Supports `setWithoutGet`, `getWithoutSet`, and `enforceForClassMembers` configuration |
| [`array-callback-return`](https://eslint.org/docs/latest/rules/array-callback-return) | Implemented for optional `allowImplicit`, `checkForEach`, and `allowVoid` behavior |
| [`arrow-body-style`](https://eslint.org/docs/latest/rules/arrow-body-style) | Supports `always`, `as-needed`, `never`, and `requireReturnForObjectLiteral` with comment-, precedence-, and ASI-safe autofix |
| [`block-scoped-var`](https://eslint.org/docs/latest/rules/block-scoped-var) | Implemented |
| [`camelcase`](https://eslint.org/docs/latest/rules/camelcase) | Supports declarations, imports, optional property checks, `ignoreDestructuring`, `ignoreImports`, lightweight `allow` patterns, and parses `ignoreGlobals` for migration compatibility |
| [`capitalized-comments`](https://eslint.org/docs/latest/rules/capitalized-comments) | Supports `always`, `never`, `ignoreInlineComments`, and `ignoreConsecutiveComments` configuration with autofix |
| [`class-methods-use-this`](https://eslint.org/docs/latest/rules/class-methods-use-this) | Supports methods, accessors, function-valued class fields, `exceptMethods`, `enforceForClassFields`, `ignoreOverrideMethods`, and `ignoreClassesWithImplements` |
| [`complexity`](https://eslint.org/docs/latest/rules/complexity) | Supports `max`, deprecated `maximum`, `classic` and `modified` variants, functions, arrow functions, and static blocks |
| [`consistent-return`](https://eslint.org/docs/latest/rules/consistent-return) | Implemented for mixed explicit value/bare returns and value-returning functions that can fall through |
| [`consistent-this`](https://eslint.org/docs/latest/rules/consistent-this) | Supports configured aliases for direct `this` captures and same-scope deferred assignment checks |
| [`constructor-super`](https://eslint.org/docs/latest/rules/constructor-super) | Implemented |
| [`curly`](https://eslint.org/docs/latest/rules/curly) | Supports `all`, `multi-line`, `multi`, and `multi-or-nest` configuration; autofixes stable block additions/removals while preserving comments and refusing ASI or dangling-`else` hazards |
| [`default-case`](https://eslint.org/docs/latest/rules/default-case) | Implemented with common `commentPattern` behavior |
| [`default-case-last`](https://eslint.org/docs/latest/rules/default-case-last) | Implemented |
| [`default-param-last`](https://eslint.org/docs/latest/rules/default-param-last) | Implemented |
| [`dot-notation`](https://eslint.org/docs/latest/rules/dot-notation) | Supports autofix plus `allowKeywords` and common `allowPattern` configuration |
| [`eol-last`](https://eslint.org/docs/latest/rules/eol-last) | Supports `always`, `never`, `unix`, and `windows` configuration with autofix |
| [`eqeqeq`](https://eslint.org/docs/latest/rules/eqeqeq) | Supports `always`, `allow-null`, and `smart` configuration with safe autofix |
| [`for-direction`](https://eslint.org/docs/latest/rules/for-direction) | Implemented |
| [`func-name-matching`](https://eslint.org/docs/latest/rules/func-name-matching) | Supports `always`, `never`, `includeCommonJSModuleExports`, and `considerPropertyDescriptor` configuration |
| [`func-names`](https://eslint.org/docs/latest/rules/func-names) | Supports `always`, `as-needed`, `never`, and `generators` configuration |
| [`func-style`](https://eslint.org/docs/latest/rules/func-style) | Supports declaration/expression styles, `allowArrowFunctions`, and `overrides.namedExports` |
| [`getter-return`](https://eslint.org/docs/latest/rules/getter-return) | Supports optional `allowImplicit` behavior |
| [`grouped-accessor-pairs`](https://eslint.org/docs/latest/rules/grouped-accessor-pairs) | Implemented for `anyOrder`, `getBeforeSet`, and `setBeforeGet` options |
| [`guard-for-in`](https://eslint.org/docs/latest/rules/guard-for-in) | Implemented |
| [`id-denylist`](https://eslint.org/docs/latest/rules/id-denylist) | Supports configured restricted identifiers, private identifiers, member-write checks, and renamed import/export skips |
| [`id-length`](https://eslint.org/docs/latest/rules/id-length) | Supports `min`, `max`, `exceptions`, common `exceptionPatterns`, and `properties` for bindings, imports, functions, and class/object properties |
| [`id-match`](https://eslint.org/docs/latest/rules/id-match) | Supports lightweight pattern matching for declarations and import aliases, with `properties`, `classFields`, `onlyDeclarations`, and `ignoreDestructuring` configuration |
| [`init-declarations`](https://eslint.org/docs/latest/rules/init-declarations) | Supports `always`, `never`, and `ignoreForLoopInit` |
| [`linebreak-style`](https://eslint.org/docs/latest/rules/linebreak-style) | Supports `unix` and `windows` configuration with autofix |
| [`logical-assignment-operators`](https://eslint.org/docs/latest/rules/logical-assignment-operators) | Implemented for `always`, optional `never`, and optional `enforceForIfStatements: true` behavior with comment-, precedence-, and evaluation-safe autofix |
| [`max-classes-per-file`](https://eslint.org/docs/latest/rules/max-classes-per-file) | Supports `max` and `ignoreExpressions` configuration |
| [`max-depth`](https://eslint.org/docs/latest/rules/max-depth) | Supports `max`, deprecated `maximum`, function scopes, static blocks, and `else if` chains |
| [`max-lines`](https://eslint.org/docs/latest/rules/max-lines) | Supports `max`, `skipBlankLines`, and `skipComments` configuration |
| [`max-lines-per-function`](https://eslint.org/docs/latest/rules/max-lines-per-function) | Supports function and arrow-function line counts plus `max`, `skipBlankLines`, `skipComments`, and `IIFEs` configuration |
| [`max-nested-callbacks`](https://eslint.org/docs/latest/rules/max-nested-callbacks) | Supports `max`, deprecated `maximum`, and call-argument callback detection |
| [`max-params`](https://eslint.org/docs/latest/rules/max-params) | Supports `max`, deprecated `maximum`, and `countThis` configuration |
| [`max-statements`](https://eslint.org/docs/latest/rules/max-statements) | Supports `max`, deprecated `maximum`, `ignoreTopLevelFunctions`, and static block isolation |
| [`new-cap`](https://eslint.org/docs/latest/rules/new-cap) | Supports `newIsCap`, `capIsNew`, `properties`, exception names, and exception patterns |
| [`new-parens`](https://eslint.org/docs/latest/rules/new-parens) | Implemented with nested-expression-safe autofix |
| [`no-alert`](https://eslint.org/docs/latest/rules/no-alert) | Implemented with global `this`, `window`, and `globalThis` detection |
| [`no-array-constructor`](https://eslint.org/docs/latest/rules/no-array-constructor) | Implemented with argument-preserving, ASI-safe autofix |
| [`no-async-promise-executor`](https://eslint.org/docs/latest/rules/no-async-promise-executor) | Implemented |
| [`no-await-in-loop`](https://eslint.org/docs/latest/rules/no-await-in-loop) | Implemented |
| [`no-bitwise`](https://eslint.org/docs/latest/rules/no-bitwise) | Implemented |
| [`no-buffer-constructor`](https://eslint.org/docs/latest/rules/no-buffer-constructor) | Implemented |
| [`no-caller`](https://eslint.org/docs/latest/rules/no-caller) | Implemented |
| [`no-case-declarations`](https://eslint.org/docs/latest/rules/no-case-declarations) | Implemented |
| [`no-class-assign`](https://eslint.org/docs/latest/rules/no-class-assign) | Implemented |
| [`no-confusing-arrow`](https://eslint.org/docs/latest/rules/no-confusing-arrow) | Supports `allowParens` with autofix when parentheses are allowed |
| [`no-comma-operator`](https://eslint.org/docs/latest/rules/no-comma-operator) | Implemented |
| [`no-compare-neg-zero`](https://eslint.org/docs/latest/rules/no-compare-neg-zero) | Implemented |
| [`no-cond-assign`](https://eslint.org/docs/latest/rules/no-cond-assign) | Implemented |
| [`no-console`](https://eslint.org/docs/latest/rules/no-console) | Implemented with `allow` support for configured console methods |
| [`no-const-assign`](https://eslint.org/docs/latest/rules/no-const-assign) | Implemented |
| [`no-constant-binary-expression`](https://eslint.org/docs/latest/rules/no-constant-binary-expression) | Detects constant logical/nullish short-circuiting, constant nullish/boolean comparisons, and newly constructed object comparisons |
| [`no-constant-condition`](https://eslint.org/docs/latest/rules/no-constant-condition) | Implemented |
| [`no-constructor-return`](https://eslint.org/docs/latest/rules/no-constructor-return) | Implemented |
| [`no-continue`](https://eslint.org/docs/latest/rules/no-continue) | Implemented |
| [`no-control-regex`](https://eslint.org/docs/latest/rules/no-control-regex) | Implemented |
| [`no-debugger`](https://eslint.org/docs/latest/rules/no-debugger) | Implemented |
| [`no-delete-var`](https://eslint.org/docs/latest/rules/no-delete-var) | Implemented |
| [`no-div-regex`](https://eslint.org/docs/latest/rules/no-div-regex) | Implemented with autofix |
| [`no-dupe-args`](https://eslint.org/docs/latest/rules/no-dupe-args) | Implemented |
| [`no-dupe-class-members`](https://eslint.org/docs/latest/rules/no-dupe-class-members) | Implemented |
| [`no-dupe-else-if`](https://eslint.org/docs/latest/rules/no-dupe-else-if) | Implemented |
| [`no-dupe-keys`](https://eslint.org/docs/latest/rules/no-dupe-keys) | Implemented |
| [`no-duplicate-case`](https://eslint.org/docs/latest/rules/no-duplicate-case) | Implemented |
| [`no-duplicate-imports`](https://eslint.org/docs/latest/rules/no-duplicate-imports) | Supports `allowSeparateTypeImports` and `includeExports` configuration |
| [`no-else-return`](https://eslint.org/docs/latest/rules/no-else-return) | Implemented |
| [`no-empty`](https://eslint.org/docs/latest/rules/no-empty) | Implemented with optional `allowEmptyCatch` behavior |
| [`no-empty-block-statements`](https://eslint.org/docs/latest/rules/no-empty-block-statements) | Implemented |
| [`no-empty-character-class`](https://eslint.org/docs/latest/rules/no-empty-character-class) | Implemented |
| [`no-empty-function`](https://eslint.org/docs/latest/rules/no-empty-function) | Implemented with `allow` behavior for functions, arrow functions, async/generator functions, methods, async/generator methods, getters, setters, and constructors |
| [`no-empty-pattern`](https://eslint.org/docs/latest/rules/no-empty-pattern) | Implemented with optional `allowObjectPatternsAsParameters` behavior |
| [`no-empty-static-block`](https://eslint.org/docs/latest/rules/no-empty-static-block) | Implemented |
| [`no-eq-null`](https://eslint.org/docs/latest/rules/no-eq-null) | Implemented |
| [`no-eval`](https://eslint.org/docs/latest/rules/no-eval) | Supports `allowIndirect` configuration |
| [`no-ex-assign`](https://eslint.org/docs/latest/rules/no-ex-assign) | Implemented |
| [`no-extend-native`](https://eslint.org/docs/latest/rules/no-extend-native) | Supports `exceptions` configuration |
| [`no-extra-bind`](https://eslint.org/docs/latest/rules/no-extra-bind) | Implemented with side-effect- and comment-safe autofix |
| [`no-extra-boolean-cast`](https://eslint.org/docs/latest/rules/no-extra-boolean-cast) | Supports safe autofix, `enforceForInnerExpressions`, and legacy `enforceForLogicalOperands` configuration |
| [`no-extra-label`](https://eslint.org/docs/latest/rules/no-extra-label) | Implemented with multi-pass autofix for redundant references and label declarations |
| [`no-extra-semi`](https://eslint.org/docs/latest/rules/no-extra-semi) | Implemented with autofix |
| [`no-fallthrough`](https://eslint.org/docs/latest/rules/no-fallthrough) | Supports `allowEmptyCase`, common `commentPattern`, and `reportUnusedFallthroughComment` configuration |
| [`no-floating-decimal`](https://eslint.org/docs/latest/rules/no-floating-decimal) | Implemented with token-safe autofix |
| [`no-for-in`](https://eslint.org/docs/latest/rules/no-for-in) | Implemented |
| [`no-func-assign`](https://eslint.org/docs/latest/rules/no-func-assign) | Implemented |
| [`no-global-assign`](https://eslint.org/docs/latest/rules/no-global-assign) | Supports `exceptions` configuration |
| [`no-global-is-finite`](https://eslint.org/docs/latest/rules/no-global-is-finite) | Implemented |
| [`no-global-is-nan`](https://eslint.org/docs/latest/rules/no-global-is-nan) | Implemented |
| [`no-implicit-coercion`](https://eslint.org/docs/latest/rules/no-implicit-coercion) | Supports `boolean`, `number`, `string`, `allow`, and `disallowTemplateShorthand` configuration |
| [`no-implicit-globals`](https://eslint.org/docs/latest/rules/no-implicit-globals) | Supports script top-level `var`/function checks and optional `lexicalBindings` checks |
| [`no-implied-eval`](https://eslint.org/docs/latest/rules/no-implied-eval) | Implemented for global timer and `execScript` calls with evaluated string arguments |
| [`no-import-assign`](https://eslint.org/docs/latest/rules/no-import-assign) | Implemented |
| [`no-inline-comments`](https://eslint.org/docs/latest/rules/no-inline-comments) | Supports `ignorePattern` configuration with common regex-like patterns |
| [`no-inner-declarations`](https://eslint.org/docs/latest/rules/no-inner-declarations) | Supports default `functions` mode and `both` mode for nested `var` declarations |
| [`no-invalid-regexp`](https://eslint.org/docs/latest/rules/no-invalid-regexp) | Implemented with optional `allowConstructorFlags` behavior |
| [`no-invalid-this`](https://eslint.org/docs/latest/rules/no-invalid-this) | Supports strict functions, modules, constructors, explicit callback bindings, class fields/static blocks, TypeScript `this` parameters, JSDoc `@this`, and `capIsConstructor` |
| [`no-irregular-whitespace`](https://eslint.org/docs/latest/rules/no-irregular-whitespace) | Implemented |
| [`no-iterator`](https://eslint.org/docs/latest/rules/no-iterator) | Implemented |
| [`no-label-var`](https://eslint.org/docs/latest/rules/no-label-var) | Implemented |
| [`no-labels`](https://eslint.org/docs/latest/rules/no-labels) | Implemented |
| [`no-lone-blocks`](https://eslint.org/docs/latest/rules/no-lone-blocks) | Implemented with block-scoped binding exceptions |
| [`no-lonely-if`](https://eslint.org/docs/latest/rules/no-lonely-if) | Implemented with safe autofix |
| [`no-loop-func`](https://eslint.org/docs/latest/rules/no-loop-func) | Implemented |
| [`no-loss-of-precision`](https://eslint.org/docs/latest/rules/no-loss-of-precision) | Implemented |
| [`no-magic-numbers`](https://eslint.org/docs/latest/rules/no-magic-numbers) | Supports `detectObjects`, `enforceConst`, `ignore`, `ignoreArrayIndexes`, `ignoreDefaultValues`, `ignoreClassFieldInitialValues`, `ignoreEnums`, `ignoreNumericLiteralTypes`, `ignoreReadonlyClassProperties`, and `ignoreTypeIndexes` |
| [`no-mixed-spaces-and-tabs`](https://eslint.org/docs/latest/rules/no-mixed-spaces-and-tabs) | Supports `smart-tabs` configuration |
| [`no-misleading-character-class`](https://eslint.org/docs/latest/rules/no-misleading-character-class) | Implemented |
| [`no-multi-assign`](https://eslint.org/docs/latest/rules/no-multi-assign) | Supports `ignoreNonDeclaration` configuration and class field initializers |
| [`no-multi-spaces`](https://eslint.org/docs/latest/rules/no-multi-spaces) | Supports `ignoreEOLComments` and common `exceptions` configuration with autofix |
| [`no-multi-str`](https://eslint.org/docs/latest/rules/no-multi-str) | Implemented |
| [`no-multiple-empty-lines`](https://eslint.org/docs/latest/rules/no-multiple-empty-lines) | Implemented with optional `max`, `maxBOF`, and `maxEOF` behavior and autofix |
| [`no-negated-condition`](https://eslint.org/docs/latest/rules/no-negated-condition) | Implemented |
| [`no-nested-ternary`](https://eslint.org/docs/latest/rules/no-nested-ternary) | Implemented |
| [`no-new`](https://eslint.org/docs/latest/rules/no-new) | Implemented |
| [`no-new-func`](https://eslint.org/docs/latest/rules/no-new-func) | Implemented |
| [`no-new-native-nonconstructor`](https://eslint.org/docs/latest/rules/no-new-native-nonconstructor) | Implemented |
| [`no-new-object`](https://eslint.org/docs/latest/rules/no-new-object) | Implemented |
| [`no-new-require`](https://eslint.org/docs/latest/rules/no-new-require) | Implemented |
| [`no-new-symbol`](https://eslint.org/docs/latest/rules/no-new-symbol) | Implemented |
| [`no-new-wrappers`](https://eslint.org/docs/latest/rules/no-new-wrappers) | Implemented |
| [`no-nonoctal-decimal-escape`](https://eslint.org/docs/latest/rules/no-nonoctal-decimal-escape) | Implemented |
| [`no-obj-calls`](https://eslint.org/docs/latest/rules/no-obj-calls) | Implemented |
| [`no-object-constructor`](https://eslint.org/docs/latest/rules/no-object-constructor) | Implemented |
| [`no-octal`](https://eslint.org/docs/latest/rules/no-octal) | Implemented |
| [`no-octal-escape`](https://eslint.org/docs/latest/rules/no-octal-escape) | Implemented |
| [`no-param-reassign`](https://eslint.org/docs/latest/rules/no-param-reassign) | Implemented with optional `props`, `ignorePropertyModificationsFor`, and common `ignorePropertyModificationsForRegex` behavior |
| [`no-path-concat`](https://eslint.org/docs/latest/rules/no-path-concat) | Implemented |
| [`no-plusplus`](https://eslint.org/docs/latest/rules/no-plusplus) | Implemented with optional `allowForLoopAfterthoughts` behavior |
| [`no-process-env`](https://eslint.org/docs/latest/rules/no-process-env) | Implemented |
| [`no-process-exit`](https://eslint.org/docs/latest/rules/no-process-exit) | Implemented |
| [`no-promise-executor-return`](https://eslint.org/docs/latest/rules/no-promise-executor-return) | Supports `allowVoid` configuration |
| [`no-proto`](https://eslint.org/docs/latest/rules/no-proto) | Implemented |
| [`no-prototype-builtins`](https://eslint.org/docs/latest/rules/no-prototype-builtins) | Implemented |
| [`no-redeclare`](https://eslint.org/docs/latest/rules/no-redeclare) | Implemented with TypeScript-aware fallback to `@typescript-eslint/no-redeclare` |
| [`no-restricted-exports`](https://eslint.org/docs/latest/rules/no-restricted-exports) | Supports `restrictedNamedExports` and `restrictDefaultExports` |
| [`no-restricted-globals`](https://eslint.org/docs/latest/rules/no-restricted-globals) | Supports direct global restrictions, custom messages, and optional global object checks |
| [`no-restricted-imports`](https://eslint.org/docs/latest/rules/no-restricted-imports) | Supports restricted `paths`, simple `patterns`, custom messages, import name allow/deny lists, type-only allowances, and re-export checks |
| [`no-restricted-modules`](https://eslint.org/docs/latest/rules/no-restricted-modules) | Supports restricted CommonJS `require()` sources, `paths`, simple `patterns`, negated patterns, and custom messages |
| [`no-restricted-properties`](https://eslint.org/docs/latest/rules/no-restricted-properties) | Supports object/property restrictions, destructuring, and `allowObjects`/`allowProperties` configuration |
| [`no-restricted-syntax`](https://eslint.org/docs/latest/rules/no-restricted-syntax) | Supports lightweight AST node selector restrictions with custom messages |
| [`no-regex-spaces`](https://eslint.org/docs/latest/rules/no-regex-spaces) | Implemented with safe autofix for literals and static string constructors |
| [`no-return-assign`](https://eslint.org/docs/latest/rules/no-return-assign) | Implemented for `except-parens` and optional `always` behavior |
| [`no-return-await`](https://eslint.org/docs/latest/rules/no-return-await) | Implemented for return statements, async arrow expression bodies, and nested tail expressions |
| [`no-script-url`](https://eslint.org/docs/latest/rules/no-script-url) | Implemented |
| [`no-self-assign`](https://eslint.org/docs/latest/rules/no-self-assign) | Supports `props` configuration |
| [`no-self-compare`](https://eslint.org/docs/latest/rules/no-self-compare) | Implemented |
| [`no-sequences`](https://eslint.org/docs/latest/rules/no-sequences) | Implemented with optional `allowInParentheses` behavior |
| [`no-setter-return`](https://eslint.org/docs/latest/rules/no-setter-return) | Implemented |
| [`no-shadow`](https://eslint.org/docs/latest/rules/no-shadow) | Supports `allow`, `builtinGlobals`, `hoist`, and `ignoreOnInitialization` configuration |
| [`no-shadow-restricted-names`](https://eslint.org/docs/latest/rules/no-shadow-restricted-names) | Implemented |
| [`no-sparse-arrays`](https://eslint.org/docs/latest/rules/no-sparse-arrays) | Implemented |
| [`no-tabs`](https://eslint.org/docs/latest/rules/no-tabs) | Supports `allowIndentationTabs` configuration |
| [`no-template-curly-in-string`](https://eslint.org/docs/latest/rules/no-template-curly-in-string) | Implemented |
| [`no-ternary`](https://eslint.org/docs/latest/rules/no-ternary) | Implemented |
| [`no-this-before-super`](https://eslint.org/docs/latest/rules/no-this-before-super) | Implemented |
| [`no-throw-literal`](https://eslint.org/docs/latest/rules/no-throw-literal) | Implemented |
| [`no-trailing-spaces`](https://eslint.org/docs/latest/rules/no-trailing-spaces) | Supports `skipBlankLines` and `ignoreComments` configuration with autofix |
| [`no-undef`](https://eslint.org/docs/latest/rules/no-undef) | Implemented |
| [`no-undef-init`](https://eslint.org/docs/latest/rules/no-undef-init) | Implemented with safe autofix for `let` bindings |
| [`no-unassigned-vars`](https://eslint.org/docs/latest/rules/no-unassigned-vars) | Reports read `let`/`var` bindings that have no initializer and no assignment |
| [`no-underscore-dangle`](https://eslint.org/docs/latest/rules/no-underscore-dangle) | Supports `allow`, `allowAfterThis`, `allowAfterSuper`, `allowAfterThisConstructor`, `allowFunctionParams`, `allowInArrayDestructuring`, `allowInObjectDestructuring`, `enforceInMethodNames`, and `enforceInClassFields` configuration |
| [`no-undefined`](https://eslint.org/docs/latest/rules/no-undefined) | Implemented for identifier references and binding names |
| [`no-unneeded-ternary`](https://eslint.org/docs/latest/rules/no-unneeded-ternary) | Supports `defaultAssignment` with precedence-, side-effect-, and comment-safe autofix |
| [`no-unexpected-multiline`](https://eslint.org/docs/latest/rules/no-unexpected-multiline) | Reports confusing multiline calls, computed property access, tagged templates, and regexp-looking division chains |
| [`no-unmodified-loop-condition`](https://eslint.org/docs/latest/rules/no-unmodified-loop-condition) | Implemented |
| [`no-unreachable`](https://eslint.org/docs/latest/rules/no-unreachable) | Implemented with hoisted declaration handling |
| [`no-unreachable-loop`](https://eslint.org/docs/latest/rules/no-unreachable-loop) | Supports loop body exit detection and `ignore` configuration |
| [`no-unsafe-finally`](https://eslint.org/docs/latest/rules/no-unsafe-finally) | Implemented with local loop, switch, and label exit handling |
| [`no-unsafe-negation`](https://eslint.org/docs/latest/rules/no-unsafe-negation) | Supports `enforceForOrderingRelations` configuration |
| [`no-unsafe-optional-chaining`](https://eslint.org/docs/latest/rules/no-unsafe-optional-chaining) | Implemented for unsafe member, call, constructor, tagged template, spread, iteration, destructuring, binary object, `with`, class `extends`, and optional `disallowArithmeticOperators` behavior |
| [`no-unused-private-class-members`](https://eslint.org/docs/latest/rules/no-unused-private-class-members) | Implemented for private fields, methods, accessors, and static blocks |
| [`no-use-before-define`](https://eslint.org/docs/latest/rules/no-use-before-define) | Supports `functions`, `classes`, `variables`, and `allowNamedExports` configuration |
| [`no-unused-expressions`](https://eslint.org/docs/latest/rules/no-unused-expressions) | Implemented with optional `allowShortCircuit`, `allowTernary`, and `allowTaggedTemplates` behavior |
| [`no-unused-labels`](https://eslint.org/docs/latest/rules/no-unused-labels) | Implemented with nested label shadowing and autofix |
| [`no-unused-vars`](https://eslint.org/docs/latest/rules/no-unused-vars) | Supports `vars`, `args`, `caughtErrors`, `ignoreRestSiblings`, `ignoreClassWithStaticInitBlock`, `ignoreUsingDeclarations`, `reportUsedIgnorePattern`, and common `argsIgnorePattern`/`caughtErrorsIgnorePattern`/`destructuredArrayIgnorePattern`/`varsIgnorePattern` configuration |
| [`no-useless-assignment`](https://eslint.org/docs/latest/rules/no-useless-assignment) | Implements control-flow-aware unused assignment analysis |
| [`no-useless-backreference`](https://eslint.org/docs/latest/rules/no-useless-backreference) | Detects nested, forward, disjunctive, and negative-lookaround backreferences in regex literals and static `RegExp` constructors |
| [`no-useless-call`](https://eslint.org/docs/latest/rules/no-useless-call) | Implemented |
| [`no-useless-catch`](https://eslint.org/docs/latest/rules/no-useless-catch) | Implemented |
| [`no-useless-computed-key`](https://eslint.org/docs/latest/rules/no-useless-computed-key) | Implemented with optional `enforceForClassMembers` behavior and autofix |
| [`no-useless-concat`](https://eslint.org/docs/latest/rules/no-useless-concat) | Implemented for adjacent static string and template literals in concatenation chains |
| [`no-useless-constructor`](https://eslint.org/docs/latest/rules/no-useless-constructor) | Implemented |
| [`no-useless-escape`](https://eslint.org/docs/latest/rules/no-useless-escape) | Supports `allowRegexCharacters` configuration and ESLint template escape handling |
| [`no-useless-rename`](https://eslint.org/docs/latest/rules/no-useless-rename) | Supports autofix plus `ignoreDestructuring`, `ignoreImport`, and `ignoreExport` configuration |
| [`no-useless-return`](https://eslint.org/docs/latest/rules/no-useless-return) | Implemented with comment-safe autofix for statement-list returns |
| [`no-var`](https://eslint.org/docs/latest/rules/no-var) | Implemented, with a scope-safe `var` to `let` autofix; multi-pass fixing can then apply `prefer-const` |
| [`no-void`](https://eslint.org/docs/latest/rules/no-void) | Implemented with optional `allowAsStatement` behavior |
| [`no-warning-comments`](https://eslint.org/docs/latest/rules/no-warning-comments) | Implemented with configurable `terms`, `location`, and common `decoration` behavior |
| [`no-with`](https://eslint.org/docs/latest/rules/no-with) | Implemented |
| [`object-shorthand`](https://eslint.org/docs/latest/rules/object-shorthand) | Supports `always`, `methods`, `properties`, `never`, `avoidQuotes`, `ignoreConstructors`, and `avoidExplicitReturnArrows` configuration with comment- and semantics-safe autofix |
| [`one-var`](https://eslint.org/docs/latest/rules/one-var) | Supports string `never` and per-kind `var`/`let`/`const` `never` configuration with comment- and context-safe autofix |
| [`operator-assignment`](https://eslint.org/docs/latest/rules/operator-assignment) | Supports `always` and `never` modes with safe autofix |
| [`prefer-arrow-callback`](https://eslint.org/docs/latest/rules/prefer-arrow-callback) | Supports callback function expressions plus `allowNamedFunctions` and `allowUnboundThis` configuration; autofixes anonymous synchronous callbacks when parameters, comments, and lexical bindings are safe |
| [`prefer-const`](https://eslint.org/docs/latest/rules/prefer-const) | Supports `destructuring` and `ignoreReadBeforeAssign` configuration; autofixes `let` declarations only when every binding can safely become `const` |
| [`prefer-destructuring`](https://eslint.org/docs/latest/rules/prefer-destructuring) | Supports object/array variable declarator and assignment expression configuration plus `enforceForRenamedProperties`; autofixes simple same-name object property declarations when comments can be preserved |
| [`prefer-exponentiation-operator`](https://eslint.org/docs/latest/rules/prefer-exponentiation-operator) | Implemented with safe autofix |
| [`prefer-named-capture-group`](https://eslint.org/docs/latest/rules/prefer-named-capture-group) | Detects unnamed capture groups in regex literals and static `RegExp` constructors |
| [`prefer-numeric-literals`](https://eslint.org/docs/latest/rules/prefer-numeric-literals) | Implemented with autofix for global static string and template `parseInt` calls with binary, octal, or hexadecimal radix |
| [`prefer-object-has-own`](https://eslint.org/docs/latest/rules/prefer-object-has-own) | Implemented with autofix |
| [`prefer-object-spread`](https://eslint.org/docs/latest/rules/prefer-object-spread) | Supports accessor-safe, comment-preserving autofix for global `Object.assign` calls with a new object literal target, including single-argument calls |
| [`prefer-promise-reject-errors`](https://eslint.org/docs/latest/rules/prefer-promise-reject-errors) | Supports `allowEmptyReject` configuration |
| [`preserve-caught-error`](https://eslint.org/docs/latest/rules/preserve-caught-error) | Reports rethrown built-in errors in `catch` blocks that omit or replace the caught error `cause`, with `requireCatchParameter` support |
| [`prefer-regex-literals`](https://eslint.org/docs/latest/rules/prefer-regex-literals) | Supports `disallowRedundantWrapping` configuration |
| [`prefer-rest-params`](https://eslint.org/docs/latest/rules/prefer-rest-params) | Implemented |
| [`prefer-spread`](https://eslint.org/docs/latest/rules/prefer-spread) | Implemented |
| [`prefer-template`](https://eslint.org/docs/latest/rules/prefer-template) | Implemented |
| [`radix`](https://eslint.org/docs/latest/rules/radix) | Implemented |
| [`require-await`](https://eslint.org/docs/latest/rules/require-await) | Implemented |
| [`require-atomic-updates`](https://eslint.org/docs/latest/rules/require-atomic-updates) | Supports `allowProperties` configuration |
| [`require-unicode-regexp`](https://eslint.org/docs/latest/rules/require-unicode-regexp) | Supports regexp literals, static `RegExp` constructors, and `requireFlag` configuration |
| [`require-yield`](https://eslint.org/docs/latest/rules/require-yield) | Implemented |
| [`sort-imports`](https://eslint.org/docs/latest/rules/sort-imports) | Supports declaration/member sorting, `ignoreCase`, `ignoreDeclarationSort`, `ignoreMemberSort`, `allowSeparatedGroups`, `memberSyntaxSortOrder`, and comment-safe named-member autofix |
| [`sort-keys`](https://eslint.org/docs/latest/rules/sort-keys) | Supports object literal key ordering with `asc`/`desc`, `caseSensitive`, `natural`, `minKeys`, and `allowLineSeparatedGroups` |
| [`sort-vars`](https://eslint.org/docs/latest/rules/sort-vars) | Supports same-declaration identifier sorting, `ignoreCase`, and formatting-preserving autofix for literal initializers |
| [`spaced-comment`](https://eslint.org/docs/latest/rules/spaced-comment) | Supports `always`, `never`, `markers`, and `exceptions` configuration with safe autofix |
| [`strict`](https://eslint.org/docs/latest/rules/strict) | Supports `safe`, `global`, `function`, and `never` modes with autofix for redundant directives |
| [`symbol-description`](https://eslint.org/docs/latest/rules/symbol-description) | Implemented |
| [`unicode-bom`](https://eslint.org/docs/latest/rules/unicode-bom) | Supports `never` and `always` configuration with autofix |
| [`use-isnan`](https://eslint.org/docs/latest/rules/use-isnan) | Supports `enforceForIndexOf` and `enforceForSwitchCase` configuration |
| [`valid-typeof`](https://eslint.org/docs/latest/rules/valid-typeof) | Supports `requireStringLiterals` configuration |
| [`vars-on-top`](https://eslint.org/docs/latest/rules/vars-on-top) | Implemented |
| [`wrap-iife`](https://eslint.org/docs/latest/rules/wrap-iife) | Implemented for `outside`, `inside`, and `any` options with autofix |
| [`yoda`](https://eslint.org/docs/latest/rules/yoda) | Supports `never`, `always`, `onlyEquality`, and `exceptRange` configuration with comment- and token-safe autofix |

## ESLint comments rules

| Rule | Status |
| --- | --- |
| [`eslint-comments/no-restricted-disable`](https://mysticatea.github.io/eslint-plugin-eslint-comments/rules/no-restricted-disable.html) | Supports restricted disable comments for configured rules |

## Import plugin rules

| Rule | Status |
| --- | --- |
| [`import/default`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/default.md) | Implemented for relative imports resolved with fishlint's configured extensions |
| [`import/export`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/export.md) | Implemented for duplicate local exports and relative `export *` |
| [`import/first`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/first.md) | Implemented |
| [`import/named`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/named.md) | Implemented for relative imports resolved with fishlint's configured extensions |
| [`import/namespace`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/namespace.md) | Implemented for relative namespace imports resolved with fishlint's configured extensions |
| [`import/newline-after-import`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/newline-after-import.md) | Implemented for `count`, `exactCount`, and `considerComments` configurations |
| [`import/no-amd`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-amd.md) | Implemented |
| [`import/no-cycle`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-cycle.md) | Implemented for relative imports and re-exports resolved with fishlint's configured extensions, with `maxDepth`, `commonjs`, and `amd` configuration |
| [`import/no-duplicates`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-duplicates.md) | Implemented with `considerQueryString` configuration |
| [`import/no-named-as-default`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-named-as-default.md) | Implemented for relative imports resolved with fishlint's configured extensions |
| [`import/no-named-as-default-member`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-named-as-default-member.md) | Implemented for relative imports resolved with fishlint's configured extensions |
| [`import/no-unresolved`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-unresolved.md) | Implemented for fishlint's node resolver extensions, `smallfish:`/`minifish:` ignores, `commonjs`, `amd`, and common `ignore` pattern behavior |
| [`import/no-self-import`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-self-import.md) | Implemented for relative imports resolved with fishlint's configured extensions |

## Jest plugin rules

| Rule | Status |
| --- | --- |
| [`jest/no-conditional-expect`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-conditional-expect.md) | Implemented for conditionals, catch clauses, Promise catch callbacks, inline test callbacks, and named test callbacks |
| [`jest/no-deprecated-functions`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-deprecated-functions.md) | Implemented with installed or configured Jest version detection and upstream autofixes |
| [`jest/no-export`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-export.md) | Implemented for ESM, CommonJS, and TypeScript exports in files containing Jest tests |
| [`jest/no-focused-tests`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-focused-tests.md) | Implemented for focused global, imported, aliased, and chained tests with upstream editor suggestions |
| [`jest/no-identical-title`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-identical-title.md) | Implemented for duplicate static test and suite titles at the same suite level |
| [`jest/no-interpolation-in-snapshots`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-interpolation-in-snapshots.md) | Implemented for interpolated inline snapshot templates, including property matcher overloads |
| [`jest/no-jasmine-globals`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-jasmine-globals.md) | Implemented for Jasmine globals, member calls, assignments, shadowed bindings, and upstream autofixes |
| [`jest/no-mocks-import`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-mocks-import.md) | Implemented for static imports, dynamic imports, and CommonJS requires from nested `__mocks__` directories |
| [`jest/no-standalone-expect`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-standalone-expect.md) | Supports suite, test, hook, helper, imported API, and `additionalTestBlockFunctions` context detection |
| [`jest/valid-describe-callback`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-describe-callback.md) | Enforces synchronous function callbacks without unexpected parameters or return values, including aliases and `describe.each` |
| [`jest/valid-expect-in-promise`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-expect-in-promise.md) | Requires expectation-bearing `then`, `catch`, and `finally` chains in tests to be returned, awaited, or consumed through supported promise patterns |
| [`jest/valid-expect`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-expect.md) | Implements argument bounds, matcher and modifier validation, and awaited or returned async assertion checks with all upstream options |
| [`jest/valid-title`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-title.md) | Supports static and template titles, all upstream options, `.each` specifiers, and upstream-safe autofixes |

## Promise plugin rules

| Rule | Status |
| --- | --- |
| [`promise/always-return`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/always-return.md) | Supports `ignoreLastCallback` and `ignoreAssignmentVariable` configuration |
| [`promise/catch-or-return`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/catch-or-return.md) | Supports `allowThen`, `allowThenStrict`, `allowFinally`, and string/array `terminationMethod` configuration |
| [`promise/no-callback-in-promise`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-callback-in-promise.md) | Supports `exceptions` and `timeoutsErr` configuration, including deferred-callback exceptions |
| [`promise/no-nesting`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-nesting.md) | Implements nested `then`/`catch` detection with closest-handler closure exceptions |
| [`promise/no-new-statics`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-new-statics.md) | Implements all Promise static methods with autofix |
| [`promise/no-promise-in-callback`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-promise-in-callback.md) | Implemented with `exemptDeclarations` configuration |
| [`promise/no-return-in-finally`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-return-in-finally.md) | Implemented |
| [`promise/no-return-wrap`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-return-wrap.md) | Implemented with `allowReject` configuration |
| [`promise/param-names`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/param-names.md) | Implemented with `resolvePattern` and `rejectPattern` configuration |
| [`promise/valid-params`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/valid-params.md) | Implemented with `exclude` configuration |

## JSX a11y rules

| Rule | Status |
| --- | --- |
| [`jsx-a11y/alt-text`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/alt-text.md) | Supports `elements` and element component mapping configuration |
| [`jsx-a11y/anchor-has-content`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/anchor-has-content.md) | Supports `components` configuration |
| [`jsx-a11y/aria-props`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/aria-props.md) | Implemented |
| [`jsx-a11y/aria-proptypes`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/aria-proptypes.md) | Implemented |
| [`jsx-a11y/aria-role`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/aria-role.md) | Supports `allowedInvalidRoles` and `ignoreNonDOM` configuration |
| [`jsx-a11y/aria-unsupported-elements`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/aria-unsupported-elements.md) | Implemented |
| [`jsx-a11y/iframe-has-title`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/iframe-has-title.md) | Implemented |
| [`jsx-a11y/img-redundant-alt`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/img-redundant-alt.md) | Supports `components` and `words` configuration |
| [`jsx-a11y/no-access-key`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/no-access-key.md) | Implemented |
| [`jsx-a11y/no-distracting-elements`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/no-distracting-elements.md) | Supports `elements` configuration |
| [`jsx-a11y/role-has-required-aria-props`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/role-has-required-aria-props.md) | Implemented |
| [`jsx-a11y/role-supports-aria-props`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/role-supports-aria-props.md) | Implemented |
| [`jsx-a11y/scope`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/scope.md) | Implemented |

## Parser diagnostics

`parser-semantic-errors` reports parse diagnostics from Yuku, including semantic early errors by default. It is not an ESLint rule and therefore does not have a corresponding ESLint rule page.

## React rules

| Rule | Status |
| --- | --- |
| [`react/button-has-type`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/button-has-type.md) | Supports `button`, `submit`, and `reset` configuration |
| [`react/default-props-match-prop-types`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/default-props-match-prop-types.md) | Supports `allowRequiredDefaults` configuration |
| [`react/display-name`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/display-name.md) | Supports `checkContextObjects` and `ignoreTranspilerName` configuration |
| [`react/forbid-prop-types`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/forbid-prop-types.md) | Supports `forbid`, `checkContextTypes`, and `checkChildContextTypes` configuration |
| [`react/jsx-boolean-value`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-boolean-value.md) | Implemented for `never` and `always` configurations |
| [`react/jsx-filename-extension`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-filename-extension.md) | Supports `extensions` and `allow` configuration |
| [`react/jsx-key`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-key.md) | Supports `checkKeyMustBeforeSpread`, `checkFragmentShorthand`, and `warnOnDuplicates` configuration |
| [`react/jsx-no-bind`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-bind.md) | Supports `allowArrowFunctions`, `allowFunctions`, `allowBind`, `ignoreRefs`, and `ignoreDOMComponents` configuration |
| [`react/jsx-no-comment-textnodes`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-comment-textnodes.md) | Implemented |
| [`react/jsx-no-duplicate-props`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-duplicate-props.md) | Implemented with configurable `ignoreCase` behavior |
| [`react/jsx-no-undef`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-undef.md) | Implemented |
| [`react/jsx-uses-react`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-uses-react.md) | Implemented |
| [`react/jsx-uses-vars`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-uses-vars.md) | Accepted for legacy config compatibility; JSX tags are always semantic variable references, matching ESLint 10 |
| [`react/jsx-no-target-blank`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-target-blank.md) | Supports `allowReferrer`, `enforceDynamicLinks`, `warnOnSpreadAttributes`, `links`, and `forms` configuration |
| [`react/jsx-pascal-case`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-pascal-case.md) | Supports `allowAllCaps`, `allowLeadingUnderscore`, `allowNamespace`, and `ignore` configuration |
| [`react/no-access-state-in-setstate`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-access-state-in-setstate.md) | Implemented |
| [`react/no-array-index-key`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-array-index-key.md) | Implemented |
| [`react/no-children-prop`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-children-prop.md) | Supports `allowFunctions` configuration |
| [`react/no-danger`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-danger.md) | Implemented |
| [`react/no-danger-with-children`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-danger-with-children.md) | Implemented |
| [`react/no-deprecated`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-deprecated.md) | Implemented |
| [`react/no-direct-mutation-state`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-direct-mutation-state.md) | Implemented |
| [`react/no-find-dom-node`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-find-dom-node.md) | Implemented |
| [`react/no-forward-ref`](https://eslint-react.xyz/docs/rules/no-forward-ref) | Opt-in React 19 diagnostic; recognizes named, aliased, default, and namespace imports from `react` |
| [`react/no-is-mounted`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-is-mounted.md) | Implemented |
| [`react/no-multi-comp`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-multi-comp.md) | Supports `ignoreStateless` configuration |
| [`react/no-unstable-nested-components`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unstable-nested-components.md) | Opt-in; supports `allowAsProps` and `propNamePattern`, including wrapped nested components |
| [`react/no-redundant-should-component-update`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-redundant-should-component-update.md) | Implemented |
| [`react/no-render-return-value`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-render-return-value.md) | Implemented for eslint-plugin-react's default/latest React version behavior |
| [`react/no-string-refs`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-string-refs.md) | Supports `noTemplateLiterals` configuration |
| [`react/no-this-in-sfc`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-this-in-sfc.md) | Implemented |
| [`react/no-typos`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-typos.md) | Implemented |
| [`react/no-unescaped-entities`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unescaped-entities.md) | Supports `forbid` configuration |
| [`react/no-unknown-property`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unknown-property.md) | Supports `ignore` and `requireDataLowercase` configuration |
| [`react/no-unused-prop-types`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unused-prop-types.md) | Supports `skipShapeProps`, `ignore`, and `customValidators` configuration |
| [`react/no-unused-state`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unused-state.md) | Implemented |
| [`react/no-will-update-set-state`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-will-update-set-state.md) | Implemented |
| [`react/prefer-es6-class`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/prefer-es6-class.md) | Supports `always` and `never` configurations |
| [`react/prop-types`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/prop-types.md) | Supports `skipUndeclared`, `ignore`, and `customValidators` configuration |
| [`react/require-render-return`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/require-render-return.md) | Implemented |
| [`react/self-closing-comp`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/self-closing-comp.md) | Supports `component` and `html` configuration |
| [`react/style-prop-object`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/style-prop-object.md) | Implemented |
| [`react/void-dom-elements-no-children`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/void-dom-elements-no-children.md) | Implemented |

## React Hooks rules

| Rule | Status |
| --- | --- |
| [`react-hooks/exhaustive-deps`](https://react.dev/reference/eslint-plugin-react-hooks/lints/exhaustive-deps) | Implements dependency-array validation for built-in hooks and `additionalHooks` literal, alternation, anchor, and wildcard patterns; reports missing, duplicate, unnecessary, complex, and unstable dependencies without type information |
| [`react-hooks/rules-of-hooks`](https://legacy.reactjs.org/docs/hooks-rules.html) | Implemented for top-level, ordinary function, class method, callback, conditional branch, and loop checks |
| [`react-hooks/use-memo`](https://react.dev/reference/eslint-plugin-react-hooks/lints/use-memo) | Opt-in; rejects parameters, async/generator callbacks, and direct writes to captured bindings in inline and statically resolved named `useMemo` callbacks. Callback-local reassignment is allowed; nested closure writes are not analyzed |

These opt-in checks are native approximations of React Compiler-related
lints, not the React Compiler diagnostic engine. React imports (ES modules and literal `require("react")`), stable local aliases,
and local shadowing are resolved. Component/hook names and React `memo`/`forwardRef`
wrappers identify render functions. Named memo callbacks are connected to render
invocations. Dynamic reassignment, arbitrary interprocedural analysis, and compiler
data-flow/configuration analysis are not covered. Rules such as
`refs`, `immutability`, `preserve-manual-memoization`, `config`, and `gating` remain
unsupported. See [configuration](configuration.md#react-compiler-related-checks).

## Unused Imports rules

| Rule | Status |
| --- | --- |
| [`unused-imports/no-unused-imports`](https://github.com/sweepline/eslint-plugin-unused-imports) | Detects unused default, named, namespace, and type-only bindings in JavaScript, TypeScript, and TSX; autofix preserves used bindings, comments, multiline syntax, and side-effect imports |

## TypeScript ESLint rules

| Rule | Status |
| --- | --- |
| [`@typescript-eslint/adjacent-overload-signatures`](https://typescript-eslint.io/rules/adjacent-overload-signatures/) | Implemented |
| [`@typescript-eslint/array-type`](https://typescript-eslint.io/rules/array-type/) | Implemented for `default: array`, `array-simple`, and `generic` configurations |
| [`@typescript-eslint/ban-ts-comment`](https://typescript-eslint.io/rules/ban-ts-comment/) | Implemented for directive modes and `minimumDescriptionLength` |
| [`@typescript-eslint/ban-tslint-comment`](https://typescript-eslint.io/rules/ban-tslint-comment/) | Implemented |
| [`@typescript-eslint/ban-types`](https://typescript-eslint.io/rules/ban-types/) | Supports `types` and `extendDefaults` configuration |
| [`@typescript-eslint/class-literal-property-style`](https://typescript-eslint.io/rules/class-literal-property-style/) | Implemented for `fields` and `getters` configurations |
| [`@typescript-eslint/consistent-type-assertions`](https://typescript-eslint.io/rules/consistent-type-assertions/) | Supports `assertionStyle` plus object/array literal assertion modes |
| [`@typescript-eslint/consistent-type-definitions`](https://typescript-eslint.io/rules/consistent-type-definitions/) | Implemented for `interface` and `type` configurations |
| [`@typescript-eslint/dot-notation`](https://typescript-eslint.io/rules/dot-notation/) | Implemented with autofix through the core rule |
| [`@typescript-eslint/explicit-member-accessibility`](https://typescript-eslint.io/rules/explicit-member-accessibility/) | Supports `accessibility: "no-public"`, `"explicit"`, and `"off"` |
| [`@typescript-eslint/member-ordering`](https://typescript-eslint.io/rules/member-ordering/) | Implemented for fishlint's default class member ordering |
| [`@typescript-eslint/method-signature-style`](https://typescript-eslint.io/rules/method-signature-style/) | Implemented for fishlint's `property` configuration |
| [`@typescript-eslint/no-array-constructor`](https://typescript-eslint.io/rules/no-array-constructor/) | Implemented with argument-preserving, ASI-safe autofix |
| [`@typescript-eslint/no-confusing-non-null-assertion`](https://typescript-eslint.io/rules/no-confusing-non-null-assertion/) | Implemented |
| [`@typescript-eslint/no-dupe-class-members`](https://typescript-eslint.io/rules/no-dupe-class-members/) | Implemented |
| [`@typescript-eslint/no-empty-function`](https://typescript-eslint.io/rules/no-empty-function/) | Supports base `allow` kinds plus `private-constructors`, `protected-constructors`, `decoratedFunctions`, and `overrideMethods` configuration |
| [`@typescript-eslint/no-empty-interface`](https://typescript-eslint.io/rules/no-empty-interface/) | Supports `allowSingleExtends` configuration |
| [`@typescript-eslint/no-empty-object-type`](https://typescript-eslint.io/rules/no-empty-object-type/) | Supports `allowInterfaces`, `allowObjectTypes`, and common anchored `allowWithName` patterns; excludes empty object constituents in intersection types |
| [`@typescript-eslint/no-duplicate-enum-values`](https://typescript-eslint.io/rules/no-duplicate-enum-values/) | Implemented |
| [`@typescript-eslint/no-extra-semi`](https://typescript-eslint.io/rules/no-extra-semi/) | Implemented with autofix |
| [`@typescript-eslint/no-extra-non-null-assertion`](https://typescript-eslint.io/rules/no-extra-non-null-assertion/) | Implemented |
| [`@typescript-eslint/no-explicit-any`](https://typescript-eslint.io/rules/no-explicit-any/) | Opt-in; supports `ignoreRestArgs`, `fixToUnknown`, and editor suggestions for `unknown` and `never` |
| [`@typescript-eslint/no-inferrable-types`](https://typescript-eslint.io/rules/no-inferrable-types/) | Supports `ignoreParameters` and `ignoreProperties` configuration |
| [`@typescript-eslint/no-invalid-void-type`](https://typescript-eslint.io/rules/no-invalid-void-type/) | Supports `allowAsThisParameter` and boolean/string-list `allowInGenericTypeArguments` configuration |
| [`@typescript-eslint/no-loop-func`](https://typescript-eslint.io/rules/no-loop-func/) | Implemented for TypeScript loop captures with core `no-loop-func` fallback when disabled |
| [`@typescript-eslint/no-loss-of-precision`](https://typescript-eslint.io/rules/no-loss-of-precision/) | Implemented |
| [`@typescript-eslint/no-misused-new`](https://typescript-eslint.io/rules/no-misused-new/) | Implemented |
| [`@typescript-eslint/no-namespace`](https://typescript-eslint.io/rules/no-namespace/) | Implemented for `allowDeclarations` and `allowDefinitionFiles` configurations |
| [`@typescript-eslint/no-non-null-asserted-optional-chain`](https://typescript-eslint.io/rules/no-non-null-asserted-optional-chain/) | Implemented |
| [`@typescript-eslint/no-redeclare`](https://typescript-eslint.io/rules/no-redeclare/) | Supports `builtinGlobals` and `ignoreDeclarationMerge` configuration |
| [`@typescript-eslint/no-require-imports`](https://typescript-eslint.io/rules/no-require-imports/) | Supports `allow` and `allowAsImport` configuration |
| [`@typescript-eslint/no-shadow`](https://typescript-eslint.io/rules/no-shadow/) | Supports `allow`, `builtinGlobals`, `hoist`, `ignoreOnInitialization`, `ignoreTypeValueShadow`, and `ignoreFunctionTypeParameterNameValueShadow` configuration |
| [`@typescript-eslint/no-this-alias`](https://typescript-eslint.io/rules/no-this-alias/) | Supports `allowedNames` and `allowDestructuring` configuration |
| [`@typescript-eslint/no-unsafe-declaration-merging`](https://typescript-eslint.io/rules/no-unsafe-declaration-merging/) | Implemented |
| [`@typescript-eslint/no-unsafe-function-type`](https://typescript-eslint.io/rules/no-unsafe-function-type/) | Reports unshadowed global `Function` references in type annotations, interface heritage, and class implements clauses |
| [`@typescript-eslint/triple-slash-reference`](https://typescript-eslint.io/rules/triple-slash-reference/) | Implemented for `path`, `types`, and `lib` `always`/`never` configurations |
| [`@typescript-eslint/typedef`](https://typescript-eslint.io/rules/typedef/) | Supports `propertyDeclaration`, `memberVariableDeclaration`, `parameter`, `arrowParameter`, `arrayDestructuring`, `objectDestructuring`, `variableDeclaration`, and `variableDeclarationIgnoreFunction` configuration |
| [`@typescript-eslint/unified-signatures`](https://typescript-eslint.io/rules/unified-signatures/) | Implemented |
| [`@typescript-eslint/no-unnecessary-parameter-property-assignment`](https://typescript-eslint.io/rules/no-unnecessary-parameter-property-assignment/) | Implemented for constructor assignments in the constructor body |
| [`@typescript-eslint/no-unnecessary-type-constraint`](https://typescript-eslint.io/rules/no-unnecessary-type-constraint/) | Implemented |
| [`@typescript-eslint/no-useless-constructor`](https://typescript-eslint.io/rules/no-useless-constructor/) | Implemented |
| [`@typescript-eslint/no-useless-empty-export`](https://typescript-eslint.io/rules/no-useless-empty-export/) | Implemented |
| [`@typescript-eslint/no-unused-expressions`](https://typescript-eslint.io/rules/no-unused-expressions/) | Supports `allowShortCircuit`, `allowTernary`, and `allowTaggedTemplates` configuration |
| [`@typescript-eslint/no-unused-vars`](https://typescript-eslint.io/rules/no-unused-vars/) | Supports `vars`, `args`, `caughtErrors`, `ignoreRestSiblings`, `ignoreClassWithStaticInitBlock`, `ignoreUsingDeclarations`, `reportUsedIgnorePattern`, and common `argsIgnorePattern`/`caughtErrorsIgnorePattern`/`destructuredArrayIgnorePattern`/`varsIgnorePattern` configuration |
| [`@typescript-eslint/no-use-before-define`](https://typescript-eslint.io/rules/no-use-before-define/) | Supports `functions`, `classes`, `variables`, `typedefs`, `enums`, `allowNamedExports`, and `ignoreTypeReferences` configuration |
| [`@typescript-eslint/no-var-requires`](https://typescript-eslint.io/rules/no-var-requires/) | Implemented |
| [`@typescript-eslint/no-wrapper-object-types`](https://typescript-eslint.io/rules/no-wrapper-object-types/) | Implemented |
| [`@typescript-eslint/prefer-as-const`](https://typescript-eslint.io/rules/prefer-as-const/) | Implemented |
| [`@typescript-eslint/prefer-namespace-keyword`](https://typescript-eslint.io/rules/prefer-namespace-keyword/) | Implemented |
| [`@typescript-eslint/restrict-plus-operands`](https://typescript-eslint.io/rules/restrict-plus-operands/) | Supports `allowNumberAndString` configuration for primitive literals and explicit primitive annotations |
