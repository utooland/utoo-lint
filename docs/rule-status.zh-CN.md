# 规则支持状态

本文档跟踪 `utoo-lint` 当前已实现的 ESLint 兼容规则。
每条规则均链接到对应的 ESLint 规则参考文档。
支持自动修复的规则会特别注明；对于不安全的代码形态，仍会报告诊断，而不会重写代码。

| 规则 | 状态 |
| --- | --- |
| [`accessor-pairs`](https://eslint.org/docs/latest/rules/accessor-pairs) | 支持 `setWithoutGet`、`getWithoutSet` 和 `enforceForClassMembers` 配置 |
| [`array-callback-return`](https://eslint.org/docs/latest/rules/array-callback-return) | 已实现可选的 `allowImplicit`、`checkForEach` 和 `allowVoid` 行为 |
| [`arrow-body-style`](https://eslint.org/docs/latest/rules/arrow-body-style) | 支持 `always`、`as-needed`、`never` 和 `requireReturnForObjectLiteral`，并提供对注释、优先级和 ASI 安全的自动修复 |
| [`block-scoped-var`](https://eslint.org/docs/latest/rules/block-scoped-var) | 已实现 |
| [`camelcase`](https://eslint.org/docs/latest/rules/camelcase) | 支持声明、导入、可选属性检查、`ignoreDestructuring`、`ignoreImports`、轻量级 `allow` 模式，并会解析 `ignoreGlobals` 以兼容迁移 |
| [`capitalized-comments`](https://eslint.org/docs/latest/rules/capitalized-comments) | 支持 `always`、`never`、`ignoreInlineComments` 和 `ignoreConsecutiveComments` 配置，并支持自动修复 |
| [`class-methods-use-this`](https://eslint.org/docs/latest/rules/class-methods-use-this) | 支持方法、访问器、以函数为值的类字段，以及 `exceptMethods`、`enforceForClassFields`、`ignoreOverrideMethods` 和 `ignoreClassesWithImplements` 配置 |
| [`complexity`](https://eslint.org/docs/latest/rules/complexity) | 支持 `max`、已弃用的 `maximum`、`classic` 和 `modified` 变体，以及函数、箭头函数和静态块 |
| [`consistent-return`](https://eslint.org/docs/latest/rules/consistent-return) | 已实现对显式返回值与空返回混用，以及可能执行到底部的值返回函数的检查 |
| [`consistent-this`](https://eslint.org/docs/latest/rules/consistent-this) | 支持为直接捕获 `this` 配置别名，并检查同一作用域内的延迟赋值 |
| [`constructor-super`](https://eslint.org/docs/latest/rules/constructor-super) | 已实现 |
| [`curly`](https://eslint.org/docs/latest/rules/curly) | 支持 `all`、`multi-line`、`multi` 和 `multi-or-nest` 配置；可在保留注释的同时稳定地自动添加或删除代码块，并拒绝存在 ASI 或悬空 `else` 风险的修复 |
| [`default-case`](https://eslint.org/docs/latest/rules/default-case) | 已实现常见的 `commentPattern` 行为 |
| [`default-case-last`](https://eslint.org/docs/latest/rules/default-case-last) | 已实现 |
| [`default-param-last`](https://eslint.org/docs/latest/rules/default-param-last) | 已实现 |
| [`dot-notation`](https://eslint.org/docs/latest/rules/dot-notation) | 支持自动修复、`allowKeywords` 及常见的 `allowPattern` 配置 |
| [`eol-last`](https://eslint.org/docs/latest/rules/eol-last) | 支持 `always`、`never`、`unix` 和 `windows` 配置，并支持自动修复 |
| [`eqeqeq`](https://eslint.org/docs/latest/rules/eqeqeq) | 支持 `always`、`allow-null` 和 `smart` 配置，并提供安全的自动修复 |
| [`for-direction`](https://eslint.org/docs/latest/rules/for-direction) | 已实现 |
| [`func-name-matching`](https://eslint.org/docs/latest/rules/func-name-matching) | 支持 `always`、`never`、`includeCommonJSModuleExports` 和 `considerPropertyDescriptor` 配置 |
| [`func-names`](https://eslint.org/docs/latest/rules/func-names) | 支持 `always`、`as-needed`、`never` 和 `generators` 配置 |
| [`func-style`](https://eslint.org/docs/latest/rules/func-style) | 支持声明式和表达式式风格、`allowArrowFunctions` 以及 `overrides.namedExports` |
| [`getter-return`](https://eslint.org/docs/latest/rules/getter-return) | 支持可选的 `allowImplicit` 行为 |
| [`grouped-accessor-pairs`](https://eslint.org/docs/latest/rules/grouped-accessor-pairs) | 已实现 `anyOrder`、`getBeforeSet` 和 `setBeforeGet` 选项 |
| [`guard-for-in`](https://eslint.org/docs/latest/rules/guard-for-in) | 已实现 |
| [`id-denylist`](https://eslint.org/docs/latest/rules/id-denylist) | 支持配置受限标识符、私有标识符、成员写入检查，并跳过已重命名的导入和导出 |
| [`id-length`](https://eslint.org/docs/latest/rules/id-length) | 对绑定、导入、函数及类/对象属性支持 `min`、`max`、`exceptions`、常见 `exceptionPatterns` 和 `properties` |
| [`id-match`](https://eslint.org/docs/latest/rules/id-match) | 支持对声明和导入别名进行轻量级模式匹配，并支持 `properties`、`classFields`、`onlyDeclarations` 和 `ignoreDestructuring` 配置 |
| [`init-declarations`](https://eslint.org/docs/latest/rules/init-declarations) | 支持 `always`、`never` 和 `ignoreForLoopInit` |
| [`linebreak-style`](https://eslint.org/docs/latest/rules/linebreak-style) | 支持 `unix` 和 `windows` 配置，并支持自动修复 |
| [`logical-assignment-operators`](https://eslint.org/docs/latest/rules/logical-assignment-operators) | 已实现 `always`、可选的 `never` 及可选的 `enforceForIfStatements: true` 行为，并提供对注释、优先级和求值安全的自动修复 |
| [`max-classes-per-file`](https://eslint.org/docs/latest/rules/max-classes-per-file) | 支持 `max` 和 `ignoreExpressions` 配置 |
| [`max-depth`](https://eslint.org/docs/latest/rules/max-depth) | 支持 `max`、已弃用的 `maximum`、函数作用域、静态块和 `else if` 链 |
| [`max-lines`](https://eslint.org/docs/latest/rules/max-lines) | 支持 `max`、`skipBlankLines` 和 `skipComments` 配置 |
| [`max-lines-per-function`](https://eslint.org/docs/latest/rules/max-lines-per-function) | 支持统计函数和箭头函数的行数，以及 `max`、`skipBlankLines`、`skipComments` 和 `IIFEs` 配置 |
| [`max-nested-callbacks`](https://eslint.org/docs/latest/rules/max-nested-callbacks) | 支持 `max`、已弃用的 `maximum`，以及调用参数中的回调检测 |
| [`max-params`](https://eslint.org/docs/latest/rules/max-params) | 支持 `max`、已弃用的 `maximum` 和 `countThis` 配置 |
| [`max-statements`](https://eslint.org/docs/latest/rules/max-statements) | 支持 `max`、已弃用的 `maximum`、`ignoreTopLevelFunctions` 和静态块隔离 |
| [`new-cap`](https://eslint.org/docs/latest/rules/new-cap) | 支持 `newIsCap`、`capIsNew`、`properties`、例外名称和例外模式 |
| [`new-parens`](https://eslint.org/docs/latest/rules/new-parens) | 已实现，并提供对嵌套表达式安全的自动修复 |
| [`no-alert`](https://eslint.org/docs/latest/rules/no-alert) | 已实现对全局 `this`、`window` 和 `globalThis` 的检测 |
| [`no-array-constructor`](https://eslint.org/docs/latest/rules/no-array-constructor) | 已实现保留参数且对 ASI 安全的自动修复 |
| [`no-async-promise-executor`](https://eslint.org/docs/latest/rules/no-async-promise-executor) | 已实现 |
| [`no-await-in-loop`](https://eslint.org/docs/latest/rules/no-await-in-loop) | 已实现 |
| [`no-bitwise`](https://eslint.org/docs/latest/rules/no-bitwise) | 已实现 |
| [`no-buffer-constructor`](https://eslint.org/docs/latest/rules/no-buffer-constructor) | 已实现 |
| [`no-caller`](https://eslint.org/docs/latest/rules/no-caller) | 已实现 |
| [`no-case-declarations`](https://eslint.org/docs/latest/rules/no-case-declarations) | 已实现 |
| [`no-class-assign`](https://eslint.org/docs/latest/rules/no-class-assign) | 已实现 |
| [`no-confusing-arrow`](https://eslint.org/docs/latest/rules/no-confusing-arrow) | 支持 `allowParens`，并可在允许括号时自动修复 |
| [`no-comma-operator`](https://eslint.org/docs/latest/rules/no-comma-operator) | 已实现 |
| [`no-compare-neg-zero`](https://eslint.org/docs/latest/rules/no-compare-neg-zero) | 已实现 |
| [`no-cond-assign`](https://eslint.org/docs/latest/rules/no-cond-assign) | 已实现 |
| [`no-console`](https://eslint.org/docs/latest/rules/no-console) | 已实现，并通过 `allow` 支持配置允许的 console 方法 |
| [`no-const-assign`](https://eslint.org/docs/latest/rules/no-const-assign) | 已实现 |
| [`no-constant-binary-expression`](https://eslint.org/docs/latest/rules/no-constant-binary-expression) | 检测恒定的逻辑/空值短路、恒定的空值/布尔比较，以及新构造对象之间的比较 |
| [`no-constant-condition`](https://eslint.org/docs/latest/rules/no-constant-condition) | 已实现 |
| [`no-constructor-return`](https://eslint.org/docs/latest/rules/no-constructor-return) | 已实现 |
| [`no-continue`](https://eslint.org/docs/latest/rules/no-continue) | 已实现 |
| [`no-control-regex`](https://eslint.org/docs/latest/rules/no-control-regex) | 已实现 |
| [`no-debugger`](https://eslint.org/docs/latest/rules/no-debugger) | 已实现 |
| [`no-delete-var`](https://eslint.org/docs/latest/rules/no-delete-var) | 已实现 |
| [`no-div-regex`](https://eslint.org/docs/latest/rules/no-div-regex) | 已实现并支持自动修复 |
| [`no-dupe-args`](https://eslint.org/docs/latest/rules/no-dupe-args) | 已实现 |
| [`no-dupe-class-members`](https://eslint.org/docs/latest/rules/no-dupe-class-members) | 已实现 |
| [`no-dupe-else-if`](https://eslint.org/docs/latest/rules/no-dupe-else-if) | 已实现 |
| [`no-dupe-keys`](https://eslint.org/docs/latest/rules/no-dupe-keys) | 已实现 |
| [`no-duplicate-case`](https://eslint.org/docs/latest/rules/no-duplicate-case) | 已实现 |
| [`no-duplicate-imports`](https://eslint.org/docs/latest/rules/no-duplicate-imports) | 支持 `allowSeparateTypeImports` 和 `includeExports` 配置 |
| [`no-else-return`](https://eslint.org/docs/latest/rules/no-else-return) | 已实现 |
| [`no-empty`](https://eslint.org/docs/latest/rules/no-empty) | 已实现可选的 `allowEmptyCatch` 行为 |
| [`no-empty-block-statements`](https://eslint.org/docs/latest/rules/no-empty-block-statements) | 已实现 |
| [`no-empty-character-class`](https://eslint.org/docs/latest/rules/no-empty-character-class) | 已实现 |
| [`no-empty-function`](https://eslint.org/docs/latest/rules/no-empty-function) | 已实现函数、箭头函数、异步/生成器函数、方法、异步/生成器方法、getter、setter 和构造函数的 `allow` 行为 |
| [`no-empty-pattern`](https://eslint.org/docs/latest/rules/no-empty-pattern) | 已实现可选的 `allowObjectPatternsAsParameters` 行为 |
| [`no-empty-static-block`](https://eslint.org/docs/latest/rules/no-empty-static-block) | 已实现 |
| [`no-eq-null`](https://eslint.org/docs/latest/rules/no-eq-null) | 已实现 |
| [`no-eval`](https://eslint.org/docs/latest/rules/no-eval) | 支持 `allowIndirect` 配置 |
| [`no-ex-assign`](https://eslint.org/docs/latest/rules/no-ex-assign) | 已实现 |
| [`no-extend-native`](https://eslint.org/docs/latest/rules/no-extend-native) | 支持 `exceptions` 配置 |
| [`no-extra-bind`](https://eslint.org/docs/latest/rules/no-extra-bind) | 已实现对副作用和注释安全的自动修复 |
| [`no-extra-boolean-cast`](https://eslint.org/docs/latest/rules/no-extra-boolean-cast) | 支持安全自动修复、`enforceForInnerExpressions` 及旧版 `enforceForLogicalOperands` 配置 |
| [`no-extra-label`](https://eslint.org/docs/latest/rules/no-extra-label) | 已实现多轮自动修复，可移除冗余引用和标签声明 |
| [`no-extra-semi`](https://eslint.org/docs/latest/rules/no-extra-semi) | 已实现并支持自动修复 |
| [`no-fallthrough`](https://eslint.org/docs/latest/rules/no-fallthrough) | 支持 `allowEmptyCase`、常见 `commentPattern` 和 `reportUnusedFallthroughComment` 配置 |
| [`no-floating-decimal`](https://eslint.org/docs/latest/rules/no-floating-decimal) | 已实现对 token 安全的自动修复 |
| [`no-for-in`](https://eslint.org/docs/latest/rules/no-for-in) | 已实现 |
| [`no-func-assign`](https://eslint.org/docs/latest/rules/no-func-assign) | 已实现 |
| [`no-global-assign`](https://eslint.org/docs/latest/rules/no-global-assign) | 支持 `exceptions` 配置 |
| [`no-global-is-finite`](https://eslint.org/docs/latest/rules/no-global-is-finite) | 已实现 |
| [`no-global-is-nan`](https://eslint.org/docs/latest/rules/no-global-is-nan) | 已实现 |
| [`no-implicit-coercion`](https://eslint.org/docs/latest/rules/no-implicit-coercion) | 支持 `boolean`、`number`、`string`、`allow` 和 `disallowTemplateShorthand` 配置 |
| [`no-implicit-globals`](https://eslint.org/docs/latest/rules/no-implicit-globals) | 支持检查脚本顶层的 `var`/函数，以及可选的 `lexicalBindings` 检查 |
| [`no-implied-eval`](https://eslint.org/docs/latest/rules/no-implied-eval) | 已实现对使用求值字符串参数的全局定时器及 `execScript` 调用的检查 |
| [`no-import-assign`](https://eslint.org/docs/latest/rules/no-import-assign) | 已实现 |
| [`no-inline-comments`](https://eslint.org/docs/latest/rules/no-inline-comments) | 支持 `ignorePattern` 配置及常见的类正则模式 |
| [`no-inner-declarations`](https://eslint.org/docs/latest/rules/no-inner-declarations) | 支持默认的 `functions` 模式，以及检查嵌套 `var` 声明的 `both` 模式 |
| [`no-invalid-regexp`](https://eslint.org/docs/latest/rules/no-invalid-regexp) | 已实现可选的 `allowConstructorFlags` 行为 |
| [`no-invalid-this`](https://eslint.org/docs/latest/rules/no-invalid-this) | 支持严格模式函数、模块、构造函数、显式绑定的回调、类字段和静态块、TypeScript `this` 参数、JSDoc `@this` 以及 `capIsConstructor` |
| [`no-irregular-whitespace`](https://eslint.org/docs/latest/rules/no-irregular-whitespace) | 已实现 |
| [`no-iterator`](https://eslint.org/docs/latest/rules/no-iterator) | 已实现 |
| [`no-label-var`](https://eslint.org/docs/latest/rules/no-label-var) | 已实现 |
| [`no-labels`](https://eslint.org/docs/latest/rules/no-labels) | 已实现 |
| [`no-lone-blocks`](https://eslint.org/docs/latest/rules/no-lone-blocks) | 已实现，并对块级作用域绑定作例外处理 |
| [`no-lonely-if`](https://eslint.org/docs/latest/rules/no-lonely-if) | 已实现并支持安全自动修复 |
| [`no-loop-func`](https://eslint.org/docs/latest/rules/no-loop-func) | 已实现 |
| [`no-loss-of-precision`](https://eslint.org/docs/latest/rules/no-loss-of-precision) | 已实现 |
| [`no-magic-numbers`](https://eslint.org/docs/latest/rules/no-magic-numbers) | 支持 `detectObjects`、`enforceConst`、`ignore`、`ignoreArrayIndexes`、`ignoreDefaultValues`、`ignoreClassFieldInitialValues`、`ignoreEnums`、`ignoreNumericLiteralTypes`、`ignoreReadonlyClassProperties` 和 `ignoreTypeIndexes` 配置 |
| [`no-mixed-spaces-and-tabs`](https://eslint.org/docs/latest/rules/no-mixed-spaces-and-tabs) | 支持 `smart-tabs` 配置 |
| [`no-misleading-character-class`](https://eslint.org/docs/latest/rules/no-misleading-character-class) | 已实现 |
| [`no-multi-assign`](https://eslint.org/docs/latest/rules/no-multi-assign) | 支持 `ignoreNonDeclaration` 配置和类字段初始化器 |
| [`no-multi-spaces`](https://eslint.org/docs/latest/rules/no-multi-spaces) | 支持 `ignoreEOLComments` 和常见 `exceptions` 配置，并支持自动修复 |
| [`no-multi-str`](https://eslint.org/docs/latest/rules/no-multi-str) | 已实现 |
| [`no-multiple-empty-lines`](https://eslint.org/docs/latest/rules/no-multiple-empty-lines) | 已实现可选的 `max`、`maxBOF` 和 `maxEOF` 行为，并支持自动修复 |
| [`no-negated-condition`](https://eslint.org/docs/latest/rules/no-negated-condition) | 已实现 |
| [`no-nested-ternary`](https://eslint.org/docs/latest/rules/no-nested-ternary) | 已实现 |
| [`no-new`](https://eslint.org/docs/latest/rules/no-new) | 已实现 |
| [`no-new-func`](https://eslint.org/docs/latest/rules/no-new-func) | 已实现 |
| [`no-new-native-nonconstructor`](https://eslint.org/docs/latest/rules/no-new-native-nonconstructor) | 已实现 |
| [`no-new-object`](https://eslint.org/docs/latest/rules/no-new-object) | 已实现 |
| [`no-new-require`](https://eslint.org/docs/latest/rules/no-new-require) | 已实现 |
| [`no-new-symbol`](https://eslint.org/docs/latest/rules/no-new-symbol) | 已实现 |
| [`no-new-wrappers`](https://eslint.org/docs/latest/rules/no-new-wrappers) | 已实现 |
| [`no-nonoctal-decimal-escape`](https://eslint.org/docs/latest/rules/no-nonoctal-decimal-escape) | 已实现 |
| [`no-obj-calls`](https://eslint.org/docs/latest/rules/no-obj-calls) | 已实现 |
| [`no-object-constructor`](https://eslint.org/docs/latest/rules/no-object-constructor) | 已实现 |
| [`no-octal`](https://eslint.org/docs/latest/rules/no-octal) | 已实现 |
| [`no-octal-escape`](https://eslint.org/docs/latest/rules/no-octal-escape) | 已实现 |
| [`no-param-reassign`](https://eslint.org/docs/latest/rules/no-param-reassign) | 已实现可选的 `props`、`ignorePropertyModificationsFor` 及常见 `ignorePropertyModificationsForRegex` 行为 |
| [`no-path-concat`](https://eslint.org/docs/latest/rules/no-path-concat) | 已实现 |
| [`no-plusplus`](https://eslint.org/docs/latest/rules/no-plusplus) | 已实现可选的 `allowForLoopAfterthoughts` 行为 |
| [`no-process-env`](https://eslint.org/docs/latest/rules/no-process-env) | 已实现 |
| [`no-process-exit`](https://eslint.org/docs/latest/rules/no-process-exit) | 已实现 |
| [`no-promise-executor-return`](https://eslint.org/docs/latest/rules/no-promise-executor-return) | 支持 `allowVoid` 配置 |
| [`no-proto`](https://eslint.org/docs/latest/rules/no-proto) | 已实现 |
| [`no-prototype-builtins`](https://eslint.org/docs/latest/rules/no-prototype-builtins) | 已实现 |
| [`no-redeclare`](https://eslint.org/docs/latest/rules/no-redeclare) | 已实现，并针对 TypeScript 感知场景回退到 `@typescript-eslint/no-redeclare` |
| [`no-restricted-exports`](https://eslint.org/docs/latest/rules/no-restricted-exports) | 支持 `restrictedNamedExports` 和 `restrictDefaultExports` |
| [`no-restricted-globals`](https://eslint.org/docs/latest/rules/no-restricted-globals) | 支持直接限制全局变量、自定义消息，以及可选的全局对象检查 |
| [`no-restricted-imports`](https://eslint.org/docs/latest/rules/no-restricted-imports) | 支持受限 `paths`、简单 `patterns`、自定义消息、导入名称允许/拒绝列表、仅类型例外及再导出检查 |
| [`no-restricted-modules`](https://eslint.org/docs/latest/rules/no-restricted-modules) | 支持受限 CommonJS `require()` 来源、`paths`、简单 `patterns`、否定模式和自定义消息 |
| [`no-restricted-properties`](https://eslint.org/docs/latest/rules/no-restricted-properties) | 支持对象/属性限制、解构，以及 `allowObjects`/`allowProperties` 配置 |
| [`no-restricted-syntax`](https://eslint.org/docs/latest/rules/no-restricted-syntax) | 支持带自定义消息的轻量级 AST 节点选择器限制 |
| [`no-regex-spaces`](https://eslint.org/docs/latest/rules/no-regex-spaces) | 已实现对字面量及静态字符串构造器的安全自动修复 |
| [`no-return-assign`](https://eslint.org/docs/latest/rules/no-return-assign) | 已实现 `except-parens` 和可选的 `always` 行为 |
| [`no-return-await`](https://eslint.org/docs/latest/rules/no-return-await) | 已实现对 return 语句、异步箭头函数表达式主体和嵌套尾部表达式的检查 |
| [`no-script-url`](https://eslint.org/docs/latest/rules/no-script-url) | 已实现 |
| [`no-self-assign`](https://eslint.org/docs/latest/rules/no-self-assign) | 支持 `props` 配置 |
| [`no-self-compare`](https://eslint.org/docs/latest/rules/no-self-compare) | 已实现 |
| [`no-sequences`](https://eslint.org/docs/latest/rules/no-sequences) | 已实现可选的 `allowInParentheses` 行为 |
| [`no-setter-return`](https://eslint.org/docs/latest/rules/no-setter-return) | 已实现 |
| [`no-shadow`](https://eslint.org/docs/latest/rules/no-shadow) | 支持 `allow`、`builtinGlobals`、`hoist` 和 `ignoreOnInitialization` 配置 |
| [`no-shadow-restricted-names`](https://eslint.org/docs/latest/rules/no-shadow-restricted-names) | 已实现 |
| [`no-sparse-arrays`](https://eslint.org/docs/latest/rules/no-sparse-arrays) | 已实现 |
| [`no-tabs`](https://eslint.org/docs/latest/rules/no-tabs) | 支持 `allowIndentationTabs` 配置 |
| [`no-template-curly-in-string`](https://eslint.org/docs/latest/rules/no-template-curly-in-string) | 已实现 |
| [`no-ternary`](https://eslint.org/docs/latest/rules/no-ternary) | 已实现 |
| [`no-this-before-super`](https://eslint.org/docs/latest/rules/no-this-before-super) | 已实现 |
| [`no-throw-literal`](https://eslint.org/docs/latest/rules/no-throw-literal) | 已实现 |
| [`no-trailing-spaces`](https://eslint.org/docs/latest/rules/no-trailing-spaces) | 支持 `skipBlankLines` 和 `ignoreComments` 配置，并支持自动修复 |
| [`no-undef`](https://eslint.org/docs/latest/rules/no-undef) | 已实现 |
| [`no-undef-init`](https://eslint.org/docs/latest/rules/no-undef-init) | 已实现对 `let` 绑定安全的自动修复 |
| [`no-unassigned-vars`](https://eslint.org/docs/latest/rules/no-unassigned-vars) | 报告已被读取但没有初始化器且从未赋值的 `let`/`var` 绑定 |
| [`no-underscore-dangle`](https://eslint.org/docs/latest/rules/no-underscore-dangle) | 支持 `allow`、`allowAfterThis`、`allowAfterSuper`、`allowAfterThisConstructor`、`allowFunctionParams`、`allowInArrayDestructuring`、`allowInObjectDestructuring`、`enforceInMethodNames` 和 `enforceInClassFields` 配置 |
| [`no-undefined`](https://eslint.org/docs/latest/rules/no-undefined) | 已实现对标识符引用和绑定名称的检查 |
| [`no-unneeded-ternary`](https://eslint.org/docs/latest/rules/no-unneeded-ternary) | 支持 `defaultAssignment`，并提供对优先级、副作用和注释安全的自动修复 |
| [`no-unexpected-multiline`](https://eslint.org/docs/latest/rules/no-unexpected-multiline) | 报告容易混淆的多行调用、计算属性访问、标签模板以及看似正则表达式的除法链 |
| [`no-unmodified-loop-condition`](https://eslint.org/docs/latest/rules/no-unmodified-loop-condition) | 已实现 |
| [`no-unreachable`](https://eslint.org/docs/latest/rules/no-unreachable) | 已实现，并处理提升声明 |
| [`no-unreachable-loop`](https://eslint.org/docs/latest/rules/no-unreachable-loop) | 支持循环体退出检测和 `ignore` 配置 |
| [`no-unsafe-finally`](https://eslint.org/docs/latest/rules/no-unsafe-finally) | 已实现，并处理局部循环、switch 和标签退出 |
| [`no-unsafe-negation`](https://eslint.org/docs/latest/rules/no-unsafe-negation) | 支持 `enforceForOrderingRelations` 配置 |
| [`no-unsafe-optional-chaining`](https://eslint.org/docs/latest/rules/no-unsafe-optional-chaining) | 已实现对不安全成员访问、调用、构造器、标签模板、展开、迭代、解构、二元对象操作、`with`、类 `extends` 的检查，以及可选的 `disallowArithmeticOperators` 行为 |
| [`no-unused-private-class-members`](https://eslint.org/docs/latest/rules/no-unused-private-class-members) | 已实现对私有字段、方法、访问器和静态块的检查 |
| [`no-use-before-define`](https://eslint.org/docs/latest/rules/no-use-before-define) | 支持 `functions`、`classes`、`variables` 和 `allowNamedExports` 配置 |
| [`no-unused-expressions`](https://eslint.org/docs/latest/rules/no-unused-expressions) | 已实现可选的 `allowShortCircuit`、`allowTernary` 和 `allowTaggedTemplates` 行为 |
| [`no-unused-labels`](https://eslint.org/docs/latest/rules/no-unused-labels) | 已实现嵌套标签遮蔽检查，并支持自动修复 |
| [`no-unused-vars`](https://eslint.org/docs/latest/rules/no-unused-vars) | 支持 `vars`、`args`、`caughtErrors`、`ignoreRestSiblings`、`ignoreClassWithStaticInitBlock`、`ignoreUsingDeclarations`、`reportUsedIgnorePattern`，以及常见的 `argsIgnorePattern`/`caughtErrorsIgnorePattern`/`destructuredArrayIgnorePattern`/`varsIgnorePattern` 配置 |
| [`no-useless-assignment`](https://eslint.org/docs/latest/rules/no-useless-assignment) | 实现了可感知控制流的无用赋值分析 |
| [`no-useless-backreference`](https://eslint.org/docs/latest/rules/no-useless-backreference) | 检测正则字面量和静态 `RegExp` 构造器中的嵌套、前向、分支及负向环视反向引用 |
| [`no-useless-call`](https://eslint.org/docs/latest/rules/no-useless-call) | 已实现 |
| [`no-useless-catch`](https://eslint.org/docs/latest/rules/no-useless-catch) | 已实现 |
| [`no-useless-computed-key`](https://eslint.org/docs/latest/rules/no-useless-computed-key) | 已实现可选的 `enforceForClassMembers` 行为，并支持自动修复 |
| [`no-useless-concat`](https://eslint.org/docs/latest/rules/no-useless-concat) | 已实现对连接链中相邻静态字符串和模板字面量的检查 |
| [`no-useless-constructor`](https://eslint.org/docs/latest/rules/no-useless-constructor) | 已实现 |
| [`no-useless-escape`](https://eslint.org/docs/latest/rules/no-useless-escape) | 支持 `allowRegexCharacters` 配置及 ESLint 模板转义处理 |
| [`no-useless-rename`](https://eslint.org/docs/latest/rules/no-useless-rename) | 支持自动修复，以及 `ignoreDestructuring`、`ignoreImport` 和 `ignoreExport` 配置 |
| [`no-useless-return`](https://eslint.org/docs/latest/rules/no-useless-return) | 已实现对语句列表中 return 语句的注释安全自动修复 |
| [`no-var`](https://eslint.org/docs/latest/rules/no-var) | 已实现作用域安全的 `var` 到 `let` 自动修复；多轮修复随后可应用 `prefer-const` |
| [`no-void`](https://eslint.org/docs/latest/rules/no-void) | 已实现可选的 `allowAsStatement` 行为 |
| [`no-warning-comments`](https://eslint.org/docs/latest/rules/no-warning-comments) | 已实现可配置的 `terms`、`location` 和常见 `decoration` 行为 |
| [`no-with`](https://eslint.org/docs/latest/rules/no-with) | 已实现 |
| [`object-shorthand`](https://eslint.org/docs/latest/rules/object-shorthand) | 支持 `always`、`methods`、`properties`、`never`、`avoidQuotes`、`ignoreConstructors` 和 `avoidExplicitReturnArrows` 配置，并提供对注释和语义安全的自动修复 |
| [`one-var`](https://eslint.org/docs/latest/rules/one-var) | 支持字符串形式的 `never`，以及按类型设置 `var`/`let`/`const` 的 `never` 配置，并提供对注释和上下文安全的自动修复 |
| [`operator-assignment`](https://eslint.org/docs/latest/rules/operator-assignment) | 支持 `always` 和 `never` 模式，并提供安全自动修复 |
| [`prefer-arrow-callback`](https://eslint.org/docs/latest/rules/prefer-arrow-callback) | 支持回调函数表达式，以及 `allowNamedFunctions` 和 `allowUnboundThis` 配置；当参数、注释和词法绑定均安全时，可自动修复匿名同步回调 |
| [`prefer-const`](https://eslint.org/docs/latest/rules/prefer-const) | 支持 `destructuring` 和 `ignoreReadBeforeAssign` 配置；仅当每个绑定都能安全改为 `const` 时，才会自动修复 `let` 声明 |
| [`prefer-destructuring`](https://eslint.org/docs/latest/rules/prefer-destructuring) | 支持对象/数组变量声明器和赋值表达式配置，以及 `enforceForRenamedProperties`；当可保留注释时，会自动修复简单的同名对象属性声明 |
| [`prefer-exponentiation-operator`](https://eslint.org/docs/latest/rules/prefer-exponentiation-operator) | 已实现并支持安全自动修复 |
| [`prefer-named-capture-group`](https://eslint.org/docs/latest/rules/prefer-named-capture-group) | 检测正则字面量和静态 `RegExp` 构造器中的未命名捕获组 |
| [`prefer-numeric-literals`](https://eslint.org/docs/latest/rules/prefer-numeric-literals) | 已实现对全局静态字符串和模板形式 `parseInt` 调用的自动修复，支持二进制、八进制或十六进制基数 |
| [`prefer-object-has-own`](https://eslint.org/docs/latest/rules/prefer-object-has-own) | 已实现并支持自动修复 |
| [`prefer-object-spread`](https://eslint.org/docs/latest/rules/prefer-object-spread) | 对以新对象字面量为目标的全局 `Object.assign` 调用支持访问器安全、保留注释的自动修复，包括单参数调用 |
| [`prefer-promise-reject-errors`](https://eslint.org/docs/latest/rules/prefer-promise-reject-errors) | 支持 `allowEmptyReject` 配置 |
| [`preserve-caught-error`](https://eslint.org/docs/latest/rules/preserve-caught-error) | 报告 `catch` 块中重新抛出的内置错误：其省略或替换了捕获错误的 `cause`；支持 `requireCatchParameter` |
| [`prefer-regex-literals`](https://eslint.org/docs/latest/rules/prefer-regex-literals) | 支持 `disallowRedundantWrapping` 配置 |
| [`prefer-rest-params`](https://eslint.org/docs/latest/rules/prefer-rest-params) | 已实现 |
| [`prefer-spread`](https://eslint.org/docs/latest/rules/prefer-spread) | 已实现 |
| [`prefer-template`](https://eslint.org/docs/latest/rules/prefer-template) | 已实现 |
| [`radix`](https://eslint.org/docs/latest/rules/radix) | 已实现 |
| [`require-await`](https://eslint.org/docs/latest/rules/require-await) | 已实现 |
| [`require-atomic-updates`](https://eslint.org/docs/latest/rules/require-atomic-updates) | 支持 `allowProperties` 配置 |
| [`require-unicode-regexp`](https://eslint.org/docs/latest/rules/require-unicode-regexp) | 支持正则字面量、静态 `RegExp` 构造器和 `requireFlag` 配置 |
| [`require-yield`](https://eslint.org/docs/latest/rules/require-yield) | 已实现 |
| [`sort-imports`](https://eslint.org/docs/latest/rules/sort-imports) | 支持声明/成员排序、`ignoreCase`、`ignoreDeclarationSort`、`ignoreMemberSort`、`allowSeparatedGroups`、`memberSyntaxSortOrder`，以及对注释安全的具名成员自动修复 |
| [`sort-keys`](https://eslint.org/docs/latest/rules/sort-keys) | 支持对象字面量键排序，以及 `asc`/`desc`、`caseSensitive`、`natural`、`minKeys` 和 `allowLineSeparatedGroups` |
| [`sort-vars`](https://eslint.org/docs/latest/rules/sort-vars) | 支持同一声明内的标识符排序、`ignoreCase`，以及对字面量初始化器保持格式的自动修复 |
| [`spaced-comment`](https://eslint.org/docs/latest/rules/spaced-comment) | 支持 `always`、`never`、`markers` 和 `exceptions` 配置，并提供安全自动修复 |
| [`strict`](https://eslint.org/docs/latest/rules/strict) | 支持 `safe`、`global`、`function` 和 `never` 模式，并可自动修复冗余指令 |
| [`symbol-description`](https://eslint.org/docs/latest/rules/symbol-description) | 已实现 |
| [`unicode-bom`](https://eslint.org/docs/latest/rules/unicode-bom) | 支持 `never` 和 `always` 配置，并支持自动修复 |
| [`use-isnan`](https://eslint.org/docs/latest/rules/use-isnan) | 支持 `enforceForIndexOf` 和 `enforceForSwitchCase` 配置 |
| [`valid-typeof`](https://eslint.org/docs/latest/rules/valid-typeof) | 支持 `requireStringLiterals` 配置 |
| [`vars-on-top`](https://eslint.org/docs/latest/rules/vars-on-top) | 已实现 |
| [`wrap-iife`](https://eslint.org/docs/latest/rules/wrap-iife) | 已实现 `outside`、`inside` 和 `any` 选项，并支持自动修复 |
| [`yoda`](https://eslint.org/docs/latest/rules/yoda) | 支持 `never`、`always`、`onlyEquality` 和 `exceptRange` 配置，并提供对注释和 token 安全的自动修复 |

## ESLint 注释规则

| 规则 | 状态 |
| --- | --- |
| [`eslint-comments/no-restricted-disable`](https://mysticatea.github.io/eslint-plugin-eslint-comments/rules/no-restricted-disable.html) | 支持针对已配置规则限制 disable 注释 |

## Import 插件规则

| 规则 | 状态 |
| --- | --- |
| [`import/default`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/default.md) | 已实现对使用 fishlint 已配置扩展名解析的相对导入的检查 |
| [`import/export`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/export.md) | 已实现对重复本地导出和相对 `export *` 的检查 |
| [`import/first`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/first.md) | 已实现 |
| [`import/named`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/named.md) | 已实现对使用 fishlint 已配置扩展名解析的相对导入的检查 |
| [`import/namespace`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/namespace.md) | 已实现对使用 fishlint 已配置扩展名解析的相对命名空间导入的检查 |
| [`import/newline-after-import`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/newline-after-import.md) | 已实现 `count`、`exactCount` 和 `considerComments` 配置 |
| [`import/no-amd`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-amd.md) | 已实现 |
| [`import/no-cycle`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-cycle.md) | 已实现对使用 fishlint 已配置扩展名解析的相对导入和再导出的检查，并支持 `maxDepth`、`commonjs` 和 `amd` 配置 |
| [`import/no-duplicates`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-duplicates.md) | 已实现 `considerQueryString` 配置 |
| [`import/no-named-as-default`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-named-as-default.md) | 已实现对使用 fishlint 已配置扩展名解析的相对导入的检查 |
| [`import/no-named-as-default-member`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-named-as-default-member.md) | 已实现对使用 fishlint 已配置扩展名解析的相对导入的检查 |
| [`import/no-unresolved`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-unresolved.md) | 已实现 fishlint 的 Node 解析器扩展名、`smallfish:`/`minifish:` 忽略、`commonjs`、`amd` 及常见 `ignore` 模式行为 |
| [`import/no-self-import`](https://github.com/import-js/eslint-plugin-import/blob/main/docs/rules/no-self-import.md) | 已实现对使用 fishlint 已配置扩展名解析的相对导入的检查 |

## Jest 插件规则

| 规则 | 状态 |
| --- | --- |
| [`jest/no-conditional-expect`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-conditional-expect.md) | 已实现条件表达式、`catch` 子句、Promise `catch` 回调、内联测试回调及命名测试回调检查 |
| [`jest/no-deprecated-functions`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-deprecated-functions.md) | 已实现已安装或显式配置的 Jest 版本检测，并支持上游自动修复 |
| [`jest/no-export`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-export.md) | 已实现对包含 Jest 测试的文件中的 ESM、CommonJS 和 TypeScript 导出检查 |
| [`jest/no-focused-tests`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-focused-tests.md) | 已实现对全局、导入、别名及链式聚焦测试的检查，并提供上游编辑器建议 |
| [`jest/no-identical-title`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-identical-title.md) | 已实现对同一测试套件层级中重复静态测试和套件标题的检查 |
| [`jest/no-interpolation-in-snapshots`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-interpolation-in-snapshots.md) | 已实现对内联快照模板插值的检查，包括属性匹配器重载形式 |
| [`jest/no-jasmine-globals`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-jasmine-globals.md) | 已实现 Jasmine 全局函数、成员调用、赋值、局部遮蔽和上游自动修复 |
| [`jest/no-mocks-import`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-mocks-import.md) | 已实现对嵌套 `__mocks__` 目录中静态导入、动态导入和 CommonJS `require` 的检查 |
| [`jest/no-standalone-expect`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/no-standalone-expect.md) | 支持测试套件、测试、钩子、辅助函数、导入 API 和 `additionalTestBlockFunctions` 上下文检查 |
| [`jest/valid-describe-callback`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-describe-callback.md) | 校验同步函数回调、意外参数和返回值，并支持别名及 `describe.each` |
| [`jest/valid-expect-in-promise`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-expect-in-promise.md) | 要求测试中包含断言的 `then`、`catch` 和 `finally` 链被返回、等待或通过受支持的 Promise 模式消费 |
| [`jest/valid-expect`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-expect.md) | 已实现参数数量、匹配器与修饰符校验、异步断言等待或返回检查，并支持全部上游选项 |
| [`jest/valid-title`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-title.md) | 支持静态及模板标题、全部上游选项、`.each` 格式符检查和上游安全自动修复 |

## Promise 插件规则

| 规则 | 状态 |
| --- | --- |
| [`promise/always-return`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/always-return.md) | 支持 `ignoreLastCallback` 和 `ignoreAssignmentVariable` 配置 |
| [`promise/catch-or-return`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/catch-or-return.md) | 支持 `allowThen`、`allowThenStrict`、`allowFinally`，以及字符串/数组形式的 `terminationMethod` 配置 |
| [`promise/no-callback-in-promise`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-callback-in-promise.md) | 支持 `exceptions` 和 `timeoutsErr` 配置，包括延迟回调例外 |
| [`promise/no-nesting`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-nesting.md) | 已实现嵌套 `then`/`catch` 检测，并对最近处理器中的闭包作例外处理 |
| [`promise/no-new-statics`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-new-statics.md) | 已实现所有 Promise 静态方法，并支持自动修复 |
| [`promise/no-promise-in-callback`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-promise-in-callback.md) | 已实现 `exemptDeclarations` 配置 |
| [`promise/no-return-in-finally`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-return-in-finally.md) | 已实现 |
| [`promise/no-return-wrap`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/no-return-wrap.md) | 已实现 `allowReject` 配置 |
| [`promise/param-names`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/param-names.md) | 已实现 `resolvePattern` 和 `rejectPattern` 配置 |
| [`promise/valid-params`](https://github.com/eslint-community/eslint-plugin-promise/blob/main/docs/rules/valid-params.md) | 已实现 `exclude` 配置 |

## JSX 无障碍规则

| 规则 | 状态 |
| --- | --- |
| [`jsx-a11y/alt-text`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/alt-text.md) | 支持 `elements` 和元素组件映射配置 |
| [`jsx-a11y/anchor-has-content`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/anchor-has-content.md) | 支持 `components` 配置 |
| [`jsx-a11y/aria-props`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/aria-props.md) | 已实现 |
| [`jsx-a11y/aria-proptypes`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/aria-proptypes.md) | 已实现 |
| [`jsx-a11y/aria-role`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/aria-role.md) | 支持 `allowedInvalidRoles` 和 `ignoreNonDOM` 配置 |
| [`jsx-a11y/aria-unsupported-elements`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/aria-unsupported-elements.md) | 已实现 |
| [`jsx-a11y/iframe-has-title`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/iframe-has-title.md) | 已实现 |
| [`jsx-a11y/img-redundant-alt`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/img-redundant-alt.md) | 支持 `components` 和 `words` 配置 |
| [`jsx-a11y/no-access-key`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/no-access-key.md) | 已实现 |
| [`jsx-a11y/no-distracting-elements`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/no-distracting-elements.md) | 支持 `elements` 配置 |
| [`jsx-a11y/role-has-required-aria-props`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/role-has-required-aria-props.md) | 已实现 |
| [`jsx-a11y/role-supports-aria-props`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/role-supports-aria-props.md) | 已实现 |
| [`jsx-a11y/scope`](https://github.com/jsx-eslint/eslint-plugin-jsx-a11y/blob/main/docs/rules/scope.md) | 已实现 |

## 解析器诊断

`parser-semantic-errors` 报告来自 Yuku 的解析诊断，默认包括语义早期错误。它不是 ESLint 规则，因此没有对应的 ESLint 规则页面。

## React 规则

| 规则 | 状态 |
| --- | --- |
| [`react/button-has-type`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/button-has-type.md) | 支持 `button`、`submit` 和 `reset` 配置 |
| [`react/default-props-match-prop-types`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/default-props-match-prop-types.md) | 支持 `allowRequiredDefaults` 配置 |
| [`react/display-name`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/display-name.md) | 支持 `checkContextObjects` 和 `ignoreTranspilerName` 配置 |
| [`react/forbid-prop-types`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/forbid-prop-types.md) | 支持 `forbid`、`checkContextTypes` 和 `checkChildContextTypes` 配置 |
| [`react/jsx-boolean-value`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-boolean-value.md) | 已实现 `never` 和 `always` 配置 |
| [`react/jsx-filename-extension`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-filename-extension.md) | 支持 `extensions` 和 `allow` 配置 |
| [`react/jsx-key`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-key.md) | 支持 `checkKeyMustBeforeSpread`、`checkFragmentShorthand` 和 `warnOnDuplicates` 配置 |
| [`react/jsx-no-bind`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-bind.md) | 支持 `allowArrowFunctions`、`allowFunctions`、`allowBind`、`ignoreRefs` 和 `ignoreDOMComponents` 配置 |
| [`react/jsx-no-comment-textnodes`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-comment-textnodes.md) | 已实现 |
| [`react/jsx-no-duplicate-props`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-duplicate-props.md) | 已实现可配置的 `ignoreCase` 行为 |
| [`react/jsx-no-undef`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-undef.md) | 已实现 |
| [`react/jsx-uses-react`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-uses-react.md) | 已实现 |
| [`react/jsx-uses-vars`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-uses-vars.md) | 为兼容旧配置而接受此规则；JSX 标签始终作为语义变量引用，与 ESLint 10 一致 |
| [`react/jsx-no-target-blank`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-no-target-blank.md) | 支持 `allowReferrer`、`enforceDynamicLinks`、`warnOnSpreadAttributes`、`links` 和 `forms` 配置 |
| [`react/jsx-pascal-case`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-pascal-case.md) | 支持 `allowAllCaps`、`allowLeadingUnderscore`、`allowNamespace` 和 `ignore` 配置 |
| [`react/no-access-state-in-setstate`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-access-state-in-setstate.md) | 已实现 |
| [`react/no-array-index-key`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-array-index-key.md) | 已实现 |
| [`react/no-children-prop`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-children-prop.md) | 支持 `allowFunctions` 配置 |
| [`react/no-danger`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-danger.md) | 已实现 |
| [`react/no-danger-with-children`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-danger-with-children.md) | 已实现 |
| [`react/no-deprecated`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-deprecated.md) | 已实现 |
| [`react/no-direct-mutation-state`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-direct-mutation-state.md) | 已实现 |
| [`react/no-find-dom-node`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-find-dom-node.md) | 已实现 |
| [`react/no-forward-ref`](https://eslint-react.xyz/docs/rules/no-forward-ref) | 可选择启用的 React 19 诊断；识别来自 `react` 的具名、别名、默认和命名空间导入 |
| [`react/no-is-mounted`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-is-mounted.md) | 已实现 |
| [`react/no-multi-comp`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-multi-comp.md) | 支持 `ignoreStateless` 配置 |
| [`react/no-unstable-nested-components`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unstable-nested-components.md) | 可选择启用；支持 `allowAsProps` 和 `propNamePattern`，包括包装后的嵌套组件 |
| [`react/no-redundant-should-component-update`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-redundant-should-component-update.md) | 已实现 |
| [`react/no-render-return-value`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-render-return-value.md) | 已实现 eslint-plugin-react 默认/最新 React 版本的行为 |
| [`react/no-string-refs`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-string-refs.md) | 支持 `noTemplateLiterals` 配置 |
| [`react/no-this-in-sfc`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-this-in-sfc.md) | 已实现 |
| [`react/no-typos`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-typos.md) | 已实现 |
| [`react/no-unescaped-entities`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unescaped-entities.md) | 支持 `forbid` 配置 |
| [`react/no-unknown-property`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unknown-property.md) | 支持 `ignore` 和 `requireDataLowercase` 配置 |
| [`react/no-unused-prop-types`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unused-prop-types.md) | 支持 `skipShapeProps`、`ignore` 和 `customValidators` 配置 |
| [`react/no-unused-state`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-unused-state.md) | 已实现 |
| [`react/no-will-update-set-state`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/no-will-update-set-state.md) | 已实现 |
| [`react/prefer-es6-class`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/prefer-es6-class.md) | 支持 `always` 和 `never` 配置 |
| [`react/prop-types`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/prop-types.md) | 支持 `skipUndeclared`、`ignore` 和 `customValidators` 配置 |
| [`react/require-render-return`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/require-render-return.md) | 已实现 |
| [`react/self-closing-comp`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/self-closing-comp.md) | 支持 `component` 和 `html` 配置 |
| [`react/style-prop-object`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/style-prop-object.md) | 已实现 |
| [`react/void-dom-elements-no-children`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/void-dom-elements-no-children.md) | 已实现 |

## React Hooks 规则

| 规则 | 状态 |
| --- | --- |
| [`react-hooks/exhaustive-deps`](https://react.dev/reference/eslint-plugin-react-hooks/lints/exhaustive-deps) | 已实现内置 Hook 和 `additionalHooks` 字面量、分支、锚点及通配符模式的依赖数组验证；无需类型信息即可报告缺失、重复、不必要、复杂和不稳定的依赖 |
| [`react-hooks/rules-of-hooks`](https://legacy.reactjs.org/docs/hooks-rules.html) | 已实现顶层、普通函数、类方法、回调、条件分支和循环检查 |
| [`react-hooks/use-memo`](https://react.dev/reference/eslint-plugin-react-hooks/lints/use-memo) | 按需开启；检查内联和可静态解析的具名 `useMemo` 回调的参数、async/generator 和对捕获变量的直接重赋值；允许回调内部局部变量重赋值，暂不分析嵌套闭包写入 |

这些按需开启的规则是 React Compiler 相关检查的原生实现子集，并未运行 React Compiler 诊断引擎。
支持 ES 模块及字面量 `require("react")` 导入、稳定局部别名和局部变量遮蔽，通过组件/Hook 命名以及 React `memo`/`forwardRef` 包装识别渲染函数。
具名 memo 回调会关联到渲染时的调用点；暂不覆盖动态重赋值、任意跨函数调用分析以及 Compiler 的数据流和配置分析。
`refs`、`immutability`、`preserve-manual-memoization`、`config`、`gating` 等规则仍不支持。
用法见[配置](configuration.zh-CN.md#react-compiler-相关检查)。

## Unused Imports 规则

| 规则 | 状态 |
| --- | --- |
| [`unused-imports/no-unused-imports`](https://github.com/sweepline/eslint-plugin-unused-imports) | 检测 JavaScript、TypeScript 和 TSX 中未使用的默认、具名、命名空间及仅类型绑定；自动修复会保留已使用的绑定、注释、多行语法和副作用导入 |

## TypeScript ESLint 规则

| 规则 | 状态 |
| --- | --- |
| [`@typescript-eslint/adjacent-overload-signatures`](https://typescript-eslint.io/rules/adjacent-overload-signatures/) | 已实现 |
| [`@typescript-eslint/array-type`](https://typescript-eslint.io/rules/array-type/) | 已实现 `default: array`、`array-simple` 和 `generic` 配置 |
| [`@typescript-eslint/ban-ts-comment`](https://typescript-eslint.io/rules/ban-ts-comment/) | 已实现指令模式和 `minimumDescriptionLength` |
| [`@typescript-eslint/ban-tslint-comment`](https://typescript-eslint.io/rules/ban-tslint-comment/) | 已实现 |
| [`@typescript-eslint/ban-types`](https://typescript-eslint.io/rules/ban-types/) | 支持 `types` 和 `extendDefaults` 配置 |
| [`@typescript-eslint/class-literal-property-style`](https://typescript-eslint.io/rules/class-literal-property-style/) | 已实现 `fields` 和 `getters` 配置 |
| [`@typescript-eslint/consistent-type-assertions`](https://typescript-eslint.io/rules/consistent-type-assertions/) | 支持 `assertionStyle`，以及对象/数组字面量断言模式 |
| [`@typescript-eslint/consistent-type-definitions`](https://typescript-eslint.io/rules/consistent-type-definitions/) | 已实现 `interface` 和 `type` 配置 |
| [`@typescript-eslint/dot-notation`](https://typescript-eslint.io/rules/dot-notation/) | 已通过核心规则实现并支持自动修复 |
| [`@typescript-eslint/explicit-member-accessibility`](https://typescript-eslint.io/rules/explicit-member-accessibility/) | 支持 `accessibility: "no-public"`、`"explicit"` 和 `"off"` |
| [`@typescript-eslint/member-ordering`](https://typescript-eslint.io/rules/member-ordering/) | 已实现 fishlint 的默认类成员顺序 |
| [`@typescript-eslint/method-signature-style`](https://typescript-eslint.io/rules/method-signature-style/) | 已实现 fishlint 的 `property` 配置 |
| [`@typescript-eslint/no-array-constructor`](https://typescript-eslint.io/rules/no-array-constructor/) | 已实现保留参数且对 ASI 安全的自动修复 |
| [`@typescript-eslint/no-confusing-non-null-assertion`](https://typescript-eslint.io/rules/no-confusing-non-null-assertion/) | 已实现 |
| [`@typescript-eslint/no-dupe-class-members`](https://typescript-eslint.io/rules/no-dupe-class-members/) | 已实现 |
| [`@typescript-eslint/no-empty-function`](https://typescript-eslint.io/rules/no-empty-function/) | 支持基础 `allow` 类型，以及 `private-constructors`、`protected-constructors`、`decoratedFunctions` 和 `overrideMethods` 配置 |
| [`@typescript-eslint/no-empty-interface`](https://typescript-eslint.io/rules/no-empty-interface/) | 支持 `allowSingleExtends` 配置 |
| [`@typescript-eslint/no-empty-object-type`](https://typescript-eslint.io/rules/no-empty-object-type/) | 支持 `allowInterfaces`、`allowObjectTypes` 和常见的锚定 `allowWithName` 模式；排除交叉类型中的空对象组成部分 |
| [`@typescript-eslint/no-duplicate-enum-values`](https://typescript-eslint.io/rules/no-duplicate-enum-values/) | 已实现 |
| [`@typescript-eslint/no-extra-semi`](https://typescript-eslint.io/rules/no-extra-semi/) | 已实现并支持自动修复 |
| [`@typescript-eslint/no-extra-non-null-assertion`](https://typescript-eslint.io/rules/no-extra-non-null-assertion/) | 已实现 |
| [`@typescript-eslint/no-explicit-any`](https://typescript-eslint.io/rules/no-explicit-any/) | 按配置启用；支持 `ignoreRestArgs`、`fixToUnknown` 及替换为 `unknown` 或 `never` 的编辑器建议 |
| [`@typescript-eslint/no-inferrable-types`](https://typescript-eslint.io/rules/no-inferrable-types/) | 支持 `ignoreParameters` 和 `ignoreProperties` 配置 |
| [`@typescript-eslint/no-invalid-void-type`](https://typescript-eslint.io/rules/no-invalid-void-type/) | 支持 `allowAsThisParameter`，以及布尔值/字符串列表形式的 `allowInGenericTypeArguments` 配置 |
| [`@typescript-eslint/no-loop-func`](https://typescript-eslint.io/rules/no-loop-func/) | 已实现 TypeScript 循环捕获检查；禁用时回退到核心 `no-loop-func` |
| [`@typescript-eslint/no-loss-of-precision`](https://typescript-eslint.io/rules/no-loss-of-precision/) | 已实现 |
| [`@typescript-eslint/no-misused-new`](https://typescript-eslint.io/rules/no-misused-new/) | 已实现 |
| [`@typescript-eslint/no-namespace`](https://typescript-eslint.io/rules/no-namespace/) | 已实现 `allowDeclarations` 和 `allowDefinitionFiles` 配置 |
| [`@typescript-eslint/no-non-null-asserted-optional-chain`](https://typescript-eslint.io/rules/no-non-null-asserted-optional-chain/) | 已实现 |
| [`@typescript-eslint/no-redeclare`](https://typescript-eslint.io/rules/no-redeclare/) | 支持 `builtinGlobals` 和 `ignoreDeclarationMerge` 配置 |
| [`@typescript-eslint/no-require-imports`](https://typescript-eslint.io/rules/no-require-imports/) | 支持 `allow` 和 `allowAsImport` 配置 |
| [`@typescript-eslint/no-shadow`](https://typescript-eslint.io/rules/no-shadow/) | 支持 `allow`、`builtinGlobals`、`hoist`、`ignoreOnInitialization`、`ignoreTypeValueShadow` 和 `ignoreFunctionTypeParameterNameValueShadow` 配置 |
| [`@typescript-eslint/no-this-alias`](https://typescript-eslint.io/rules/no-this-alias/) | 支持 `allowedNames` 和 `allowDestructuring` 配置 |
| [`@typescript-eslint/no-unsafe-declaration-merging`](https://typescript-eslint.io/rules/no-unsafe-declaration-merging/) | 已实现 |
| [`@typescript-eslint/no-unsafe-function-type`](https://typescript-eslint.io/rules/no-unsafe-function-type/) | 报告类型注解、接口继承及类 implements 子句中未被遮蔽的全局 `Function` 引用 |
| [`@typescript-eslint/triple-slash-reference`](https://typescript-eslint.io/rules/triple-slash-reference/) | 已实现 `path`、`types` 和 `lib` 的 `always`/`never` 配置 |
| [`@typescript-eslint/typedef`](https://typescript-eslint.io/rules/typedef/) | 支持 `propertyDeclaration`、`memberVariableDeclaration`、`parameter`、`arrowParameter`、`arrayDestructuring`、`objectDestructuring`、`variableDeclaration` 和 `variableDeclarationIgnoreFunction` 配置 |
| [`@typescript-eslint/unified-signatures`](https://typescript-eslint.io/rules/unified-signatures/) | 已实现 |
| [`@typescript-eslint/no-unnecessary-parameter-property-assignment`](https://typescript-eslint.io/rules/no-unnecessary-parameter-property-assignment/) | 已实现对构造函数体内构造函数赋值的检查 |
| [`@typescript-eslint/no-unnecessary-type-constraint`](https://typescript-eslint.io/rules/no-unnecessary-type-constraint/) | 已实现 |
| [`@typescript-eslint/no-useless-constructor`](https://typescript-eslint.io/rules/no-useless-constructor/) | 已实现 |
| [`@typescript-eslint/no-useless-empty-export`](https://typescript-eslint.io/rules/no-useless-empty-export/) | 已实现 |
| [`@typescript-eslint/no-unused-expressions`](https://typescript-eslint.io/rules/no-unused-expressions/) | 支持 `allowShortCircuit`、`allowTernary` 和 `allowTaggedTemplates` 配置 |
| [`@typescript-eslint/no-unused-vars`](https://typescript-eslint.io/rules/no-unused-vars/) | 支持 `vars`、`args`、`caughtErrors`、`ignoreRestSiblings`、`ignoreClassWithStaticInitBlock`、`ignoreUsingDeclarations`、`reportUsedIgnorePattern`，以及常见的 `argsIgnorePattern`/`caughtErrorsIgnorePattern`/`destructuredArrayIgnorePattern`/`varsIgnorePattern` 配置 |
| [`@typescript-eslint/no-use-before-define`](https://typescript-eslint.io/rules/no-use-before-define/) | 支持 `functions`、`classes`、`variables`、`typedefs`、`enums`、`allowNamedExports` 和 `ignoreTypeReferences` 配置 |
| [`@typescript-eslint/no-var-requires`](https://typescript-eslint.io/rules/no-var-requires/) | 已实现 |
| [`@typescript-eslint/no-wrapper-object-types`](https://typescript-eslint.io/rules/no-wrapper-object-types/) | 已实现 |
| [`@typescript-eslint/prefer-as-const`](https://typescript-eslint.io/rules/prefer-as-const/) | 已实现 |
| [`@typescript-eslint/prefer-namespace-keyword`](https://typescript-eslint.io/rules/prefer-namespace-keyword/) | 已实现 |
| [`@typescript-eslint/restrict-plus-operands`](https://typescript-eslint.io/rules/restrict-plus-operands/) | 对原始类型字面量和显式原始类型注解支持 `allowNumberAndString` 配置 |
