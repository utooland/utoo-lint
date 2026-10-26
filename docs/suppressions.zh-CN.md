# 抑制注释

`utoo-lint` 支持采用 `utlint-ignore` 前缀的 Biome 风格抑制注释。抑制可以针对某一条规则，也可以针对所有 lint 规则。建议在 `:` 后添加说明；API 会将这段说明与被抑制的诊断一并保留。

## 下一行代码

在需要豁免的代码之前使用 `utlint-ignore`：

```js
// utlint-ignore no-debugger: generated breakpoint
debugger;
```

指令与代码之间可以出现空行或其他注释。中间一旦出现代码行，该指令就会被这行代码消耗。省略规则 ID 可以抑制该行代码触发的所有 lint 规则：

```js
// utlint-ignore: generated statement
debugger; console.log("generated");
```

## 整个文件

在文件中的任何代码之前使用 `utlint-ignore-all`：

```js
// utlint-ignore-all no-debugger: generated file
```

该指令之前可以出现文件开头的注释、UTF-8 字节顺序标记或脚本 shebang。放在代码之后的 `utlint-ignore-all` 不会生效。

## 区间

使用配对的 `utlint-ignore-start` 和 `utlint-ignore-end` 指令：

```js
// utlint-ignore-start no-debugger: generated section
debugger;
debugger;
// utlint-ignore-end no-debugger: generated section
```

区间可以重叠或嵌套。带规则名称的结束指令会关闭同一规则对应的区间；不带规则 ID 的结束指令会关闭针对所有规则的区间。

四种指令都可以写在行注释或块注释中。规则 ID 使用与配置相同的名称，包括 `@typescript-eslint/no-unused-vars` 这样的带命名空间 ID。

## 诊断与自动修复

抑制会应用于 lint 规则诊断，包括兼容 ESLint 的自定义规则所产生的诊断。解析错误永远不会被抑制。被抑制诊断对应的修复不会由 `--fix` 或 `--fix-dry-run` 应用。

原生 JSON 以及 `lintFiles()` / `lintText()` API 会在 `suppressedDiagnostics` 中暴露被抑制的项目。兼容 ESLint 的 API 会在 `suppressedMessages` 中暴露这些项目，并在 `suppressions` 中包含指令说明。

ESLint 的 disable/enable 指令会检查命名规则，即使配置了 `rules: {}` 或没有 lint 规则报告问题也会检查。未知名称会在注释范围内产生 `Definition for rule 'unknown-rule' was not found.` 错误，且不能被抑制。已注册的原生规则和当前文件挂载的 JS 插件规则，即使关闭，也视为已知规则。这项检查不适用于 `utlint-ignore` 指令。
