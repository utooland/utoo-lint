# 从 ESLint 迁移

本指南介绍目前从 ESLint 迁移到 `utoo-lint` 的方法，以及如何在修改 CI 之前估算迁移成本。

`utoo-lint` 仍处于实验阶段。应当把它视为对已原生实现规则集的渐进式替换，而不是整个 ESLint 生态的可直接替代品。

## 哪些项目可以顺利迁移

迁移成本最低的项目通常具备以下特点：

- 检查 JavaScript、JSX、TypeScript 或 TSX 源文件。
- ESLint 配置可以归纳为可序列化为 JSON 的 `files`、`ignores` 和 `rules` 配置项。
- 大多数已启用规则来自 ESLint 核心，或来自 utoo-lint 已支持的 `@typescript-eslint`、`eslint-plugin-react`、`eslint-plugin-import`、`eslint-plugin-jsx-a11y`、`eslint-plugin-react-hooks`、`eslint-plugin-eslint-comments`。其他插件的规则可以通过 [ESLint 插件桥接](/zh-CN/configuration#eslint-插件) 继续运行。
- 格式化已经由 Prettier、Biome 或 ESLint 之外的其他格式化工具处理。
- CI 和 pre-commit 脚本可以在短期验证阶段同时运行 ESLint 与 `utoo-lint`。

内置兼容层目前通过 JavaScript API 提供 300 多个 ESLint 兼容规则 ID，覆盖 ESLint 核心、TypeScript ESLint、React、import、JSX 无障碍、React Hooks 和 eslint-comments。确切的实现列表与选项支持范围请参阅[规则支持状态](/zh-CN/rule-status)。

## 迁移成本

可以先用下表进行估算。

| 项目形态 | 预计成本 | 通常需要处理的工作 |
| --- | --- | --- |
| 主要使用已支持规则的简单应用或包 | 低，通常不到半天 | 安装包、生成 `utlint.config.json`、更新脚本、对比诊断结果 |
| 使用多个插件预设和覆盖项的前端应用 | 中等，约 1–2 天 | 扁平化配置、挂载没有原生实现的插件规则、确定暂时保留在 ESLint 中的规则 |
| 使用自定义 ESLint 插件、处理器、类型化解析器服务或依赖自动修复工作流的 monorepo | 高，数天或更久 | 在 `utlint.config.ts` 中挂载自定义插件、为处理器和类型感知规则保留双 lint 任务、审计自动修复覆盖 |

主要成本不在于修改文件语法，而在于决定如何处理目前还没有原生等价实现的 ESLint 能力。

常见的低成本项目：

- 规则严重级别：支持 `"off"`、`"warn"`、`"warning"`、`"error"`、`0`、`1`、`2`、布尔值和 ESLint 风格数组。
- 规则名称：继续使用 `no-debugger`、`react/jsx-no-target-blank`、`@typescript-eslint/no-unused-vars` 等规范 ESLint 规则 ID。
- `files` 和 `ignores`：简单的扁平配置模式会由迁移器复制，并由 JS 封装层/API 使用。
- 格式化规则：迁移器会忽略 `prettier/prettier`，因为格式化应继续留在 `utoo-lint` 之外。

常见的中高成本项目：

- 没有原生实现的插件规则可以把插件挂载到 `utlint.config.ts` 中继续运行，见 [ESLint 插件](/zh-CN/configuration#eslint-插件)；它们运行在 JavaScript 中，有原生实现时优先使用原生规则。
- 动态 JavaScript 配置值、函数、Symbol、解析器对象和不可序列化的插件对象会被迁移器移除。需要这些插件的规则时，请在 TypeScript 配置中手动补回 `plugins`。
- Markdown、Vue SFC、MDX 等非 JS 文件处理器，目前不能直接迁移到原生实现。
- 依赖自动修复的工作流需要明确检查覆盖情况。`utoo-lint` 会为受支持的规则应用安全修复；对于[规则支持状态](/zh-CN/rule-status)中未标记为可修复的转换，请继续使用 ESLint 或其他工具。
- 依赖 TypeScript 类型检查器服务的规则需要人工审计。`utoo-lint` 是原生解析器和语义 linter，并不是围绕 `@typescript-eslint/parser` 构建的 ESLint 运行时。

## 第 1 步：安装

```bash
npm install --save-dev @utoo/lint
```

先在明确的目标目录上运行：

```bash
npx utoo-lint src test
```

首次检查可以只运行两个项目中都存在的规则：

```bash
npx utoo-lint --rules=no-debugger,no-unused-vars,@typescript-eslint/no-unused-vars src
```

## 第 2 步：生成原生配置

使用迁移命令把现有 ESLint 配置转换为规范的静态配置 `utlint.config.json`：

```bash
npx utoo-lint migrate eslint --from eslint.config.js --output utlint.config.json
```

生成的是原生 `utoo-lint` 配置，并不是通过兼容层执行的 ESLint 配置。ESLint flat config 中的配置项会保持分离和原有顺序，包括其中的 `files`、`ignores` 及受支持的规则值。这样可以保留按文件覆盖的行为：仅含忽略规则的配置项仍为全局忽略，其他忽略项仍限于各自配置项。

迁移器还会跳过 `prettier/prettier` 等仅用于格式化的规则，并报告仍需原生 utoo 规则或明确替代方案的已启用规则。已禁用且不受支持的规则没有需要迁移的运行时行为，因此会被省略。

只预览而不写入文件：

```bash
npx utoo-lint migrate eslint --print --report=json
```

每条规则选定的值都会保留，包括 `['error', { ...options }]` 这样的数组。原生 utoo 规则会读取它们支持的选项；已启用但不受支持的规则会进入报告，不会被复制。配置为 `"off"`、`0`、`false`，或数组首项为这些值的规则不会阻塞迁移。

flat config 输出以一个 Schema 元数据配置项开始，后面依次是迁移后的配置项。匹配项按数组顺序应用，因此同一规则后出现的值仍会保留 ESLint 的覆盖行为。

对于 `.eslintrc`、`.eslintrc.json`、`.eslintrc.js` 和 `.eslintrc.cjs`，迁移器会先使用 ESLint 的 classic config 解析器展开配置，再进行转换。相对路径、共享配置包名、`plugin:name/preset` 引用及 `extends` 数组都会保留 ESLint 的应用顺序。嵌套继承的规则和 overrides 会成为有序的 utoo 配置项；`files`、`excludedFiles` 和 `ignorePatterns` 会分别转换为对应的作用域选择器和全局忽略项。这些模式会相对输出配置目录重新定位，包括从祖先目录发现 `.eslintrc` 的情况。`**/*.@(js|ts)` 这类仅包含字面选项的 extglob 会展开为原生选择器备选项；无法安全表示的 extglob 会给出可操作的错误并停止迁移，避免静默改变文件范围。遇到循环链或缺失配置时，迁移同样会停止，并在错误中给出 extends 链或引用配置，而不会生成不完整输出。

当下列经过审核的别名存在原生等价行为时，迁移器会进行转换。这些映射是语义兼容性决策，而不只是字符串重命名：每条源规则只有在与目标规则已经实现的行为及所支持的选项完成核对后，才会加入此表。

| ESLint 规则 | utoo-lint 规则 |
| --- | --- |
| `no-native-reassign` | `no-global-assign` |
| `@typescript-eslint/no-invalid-this` | `no-invalid-this` |
| `@eslint-react/no-array-index-key` | `react/no-array-index-key` |
| `@eslint-react/dom-no-find-dom-node` | `react/no-find-dom-node` |
| `@eslint-react/dom-no-render-return-value` | `react/no-render-return-value` |
| `@eslint-react/dom-no-void-elements-with-children` | `react/void-dom-elements-no-children` |
| `@eslint-react/rules-of-hooks` | `react-hooks/rules-of-hooks` |

转换后的别名会在迁移报告中单独列出。其他旧规则或插件规则 ID 只有在添加明确等价实现后才会受支持；迁移器不会因为名称相似就推断映射关系。

使用 JSON 报告评估迁移规模：

- `supportedRules`：可以立即迁移到 `utoo-lint`。
- `unsupportedRules`：需要替代规则、新的原生规则，或临时保留 ESLint 覆盖。
- `ignoredRules`：有意留在 `utoo-lint` 之外，通常是格式化规则。
- `inheritedSources`：在 classic config 迁移中实际参与的相对路径、共享包、插件或内置配置来源。
- `unsupportedInheritedRules`：不受支持的继承规则，以及引入该规则的继承来源。

发现不受支持的规则时，命令会以状态码 `1` 退出。这对自动化是有用信号，并不表示生成的配置不可使用。

## 第 3 步：从前端模板开始

在项目根目录创建 `utlint.config.json`，或复制包内的前端模板：

```bash
cp node_modules/@utoo/lint/configs/frontend.json utlint.config.json
```

模板包含 `$schema`、源码 glob、常见构建目录忽略项，以及一组聚焦于浏览器、import、React、JSX 无障碍和 TypeScript 的规则。需要在完整迁移 ESLint 配置前建立已知基线时，可以先使用它。

最小原生配置：

```json
{
  "$schema": "https://raw.githubusercontent.com/utooland/utoo-lint/main/npm/utoo-lint/schema.json",
  "rules": {
    "no-debugger": "error",
    "no-console": "off",
    "no-unused-vars": "warn",
    "@typescript-eslint/no-unused-vars": ["warn"],
    "react/jsx-no-target-blank": "error",
    "jsx-a11y/aria-props": "error"
  }
}
```

规范配置文件名为 `utlint.config.ts` 和 `utlint.config.json`。它们是同一份生效配置的两种表示，不会隐式合并。对于 npm/Node 入口，程序会由近及远查找配置；同一目录中，`utlint.config.ts` 优先于 `utlint.config.json`。旧的 `utoo.json` 与 `utoo-lint.json` 文件名暂时继续受支持，但已弃用。使用 `--config=path/to/utlint.config.json` 可显式选择文件，使用 `--no-config` 可忽略本地配置。

项目配置中的 `files` 和 `ignores` 模式相对于所选配置文件所在目录解析。对于扁平配置数组，系统会逐个文件匹配并按数组顺序合并配置项；后匹配的规则值会覆盖前面的值。npm CLI、JavaScript API 和 fishlint 兼容命令都使用这种逐文件解析方式。

npm/Node CLI 也可以执行可信的类型化配置。默认导出必须是可序列化为 JSON 的对象或扁平配置数组：

```ts
// utlint.config.ts
import { defineConfig } from "@utoo/lint/config";

export default defineConfig({
  files: ["src/**/*.{js,jsx,ts,tsx}"],
  rules: {
    "no-debugger": "error",
    "@typescript-eslint/no-unused-vars": "warn"
  }
});
```

加载 `utlint.config.ts` 会执行项目代码。npm 封装层会把导出值转换为 JSON，再传给原生二进制文件；原生二进制文件本身不会执行或查找 TypeScript 配置。它会查找 `utlint.config.json`，然后再查找旧版 JSON 名称，因此直接调用时应使用 JSON。

原生二进制文件只应用该 JSON 中的 `rules`；未写出的规则处于禁用状态，与 ESLint 的配置模型一致。由配置驱动的 `files`、`ignores` 过滤和默认目标选择属于 npm/Node 封装层能力。直接调用原生二进制文件时，请显式传入 lint 目标。

## 第 4 步：必要时手动迁移规则

- `"off"`、`0` 或 `false` 会禁用规则。
- `"warn"`、`"error"`、`1`、`2` 或 `true` 会启用规则。
- `['error', { ...options }]` 这样的数组以第一项作为严重级别，并把受支持的选项传给原生规则实现。

与 ESLint 一样，警告诊断不会让命令失败，错误诊断会返回退出状态 1。fishlint 兼容 CLI 还支持在警告数量应使 CI 失败时设置 `--max-warnings`。

与规则相关的 CLI 选项会在配置之后应用，因此命令行开关会覆盖配置中的规则值：

```bash
npx utoo-lint --config=utlint.config.json --no-console=off src
```

## 手动迁移 ESLint 规则

把规则从 `eslint.config.js` 或 `.eslintrc` 移到 `utlint.config.json`，同时保留相同的规范规则名称：

```js
// eslint.config.js
export default [
  {
    rules: {
      "no-debugger": "error",
      "@typescript-eslint/no-unused-vars": ["warn"],
      "react/jsx-no-target-blank": "error"
    }
  }
];
```

```json
{
  "rules": {
    "no-debugger": "error",
    "@typescript-eslint/no-unused-vars": ["warn"],
    "react/jsx-no-target-blank": "error"
  }
}
```

通过[规则支持状态](/zh-CN/rule-status)确认当前已经实现的 ESLint、TypeScript ESLint、React、import、React Hooks、eslint-comments 和 JSX a11y 规则。规则缺失时，可以选择：

- 在过渡期继续用 ESLint 执行该规则。
- 明确禁用，并记录原因。
- 在 `src/rules` 中实现原生规则。
- 使用已支持的规则或非 lint 工具替代。

## 第 5 步：对比诊断结果

并行运行 ESLint 和 `utoo-lint`，直到所选规则集保持稳定：

```bash
npx eslint src test
npx utoo-lint --config=utlint.config.json src test
```

可使用以下方式对比：

```bash
npx eslint src test --format json > eslint-report.json
npx utoo-lint --config=utlint.config.json --format=json src test > utoo-report.json
```

第一次运行时可能出现以下差异：

- `utoo-lint` 只报告所选配置中已经启用的原生规则。
- 不受支持的 ESLint 规则在完成移植前不会出现在结果中。
- 部分受支持规则会先实现 ESLint 最常见的行为；选项级说明请查看[规则支持状态](/zh-CN/rule-status)。

诊断结果符合预期后，可以为这组规则替换 ESLint 任务；也可以继续保留两个任务，同时逐步扩大规则覆盖范围。

## 替换包脚本

常见的脚本迁移方式：

```json
{
  "scripts": {
    "lint:eslint": "eslint src test",
    "lint:utoo": "utoo-lint --config=utlint.config.json src test",
    "lint": "utoo-lint --config=utlint.config.json src test"
  }
}
```

迁移期间可以同时保留两者：

```json
{
  "scripts": {
    "lint": "npm run lint:eslint && npm run lint:utoo",
    "lint:eslint": "eslint src test",
    "lint:utoo": "utoo-lint --config=utlint.config.json src test"
  }
}
```

使用 JavaScript API 时，不带模式调用 `lintFiles()` 会遵循 `utlint.config.json` 中的 `files` 配置项。对于命令行脚本，迁移期间请显式传入目标，让 CI 行为更容易理解。

## 替换 Fishlint 命令

`@utoo/lint` 会安装一个 `fishlint` 兼容命令，供已经调用 eslint 子命令的脚本使用：

```bash
npx fishlint eslint --disable-setup --config utlint.config.json --ext .js,.ts --glob src
```

封装层会先转换常见的 fishlint eslint 参数，再调用 `utoo-lint`。它会转发 `--config`，把 `--glob` 值映射为 lint 目标，为兼容性接受 `--ext`，并忽略仅属于 fishlint 的 setup/debug 参数。`--fix` 会应用受支持原生规则的修复，`--fix-dry-run` 会计算修复后的输出而不写入文件。

它会查找 `utlint.config.ts`、`utlint.config.json`、已弃用的 `utoo.json`/`utoo-lint.json`，以及 `eslint.config.js`/`eslint.config.mjs`/`eslint.config.cjs` 等 ESLint 迁移输入。可执行配置会先被加载并转换为临时 JSON，然后再调用原生二进制文件。

Fishlint 预设经常包含 `prettier/prettier`。为兼容现有配置，`utoo-lint` 会接受该规则并忽略它，因为格式化仍应由原生 linter 之外的工具负责。

## 替换 ESLint API 调用

已经使用 ESLint Node API 的脚本，可以从 `@utoo/lint` 导入 `ESLint`，并保留高层调用结构：

```js
import { ESLint } from "@utoo/lint";

const eslint = new ESLint({
  useEslintrc: false,
  overrideConfig: {
    rules: {
      "no-debugger": "warn",
      "no-console": "warn"
    }
  }
});

const results = await eslint.lintFiles(["src"]);
const formatter = await eslint.loadFormatter("stylish");
console.log(formatter.format(results));
```

同时支持 `ESLint#lintText()`。它会把文本写入临时文件，再把诊断映射回传入的 `filePath`，适合编辑器、pre-commit 和 codemod 集成：

```js
const [result] = await eslint.lintText("debugger;\n", {
  filePath: "inline.js"
});
```

仍在使用旧版 ESLint `CLIEngine` 的集成可以导入一个轻量的同步门面：

```js
import { CLIEngine } from "@utoo/lint";

const cli = new CLIEngine({
  useEslintrc: false,
  baseConfig: {
    rules: {
      "no-debugger": "error"
    }
  }
});

const report = cli.executeOnFiles(["src"]);
console.log(cli.getFormatter("stylish")(report.results));
```

## 迁移决策检查清单

从 CI 中移除 ESLint 之前，请确认：

- `utoo-lint migrate eslint --report=json` 没有意外的不受支持规则。
- `utlint.config.json` 中的目标和忽略模式与旧 lint 范围一致。
- 已审查所选规则集的并行诊断结果。
- 格式化仍是独立步骤；所需自动修复已有原生覆盖或已记录的后备方案。
- 自定义 ESLint 插件已挂载到 `utlint.config.ts`；处理器和类型感知规则仍保留在 ESLint 任务中，或已经有可跟踪的原生替换计划。
