# 配置

`utoo-lint` 会从当前工作目录或其上级目录中选择一份配置，然后应用与规则相关的 CLI 覆盖项。

规范配置文件名如下：

- `utlint.config.ts`：由 npm/Node CLI 加载的类型化可执行配置。
- `utlint.config.json`：npm CLI 和原生二进制文件都能读取的静态 JSON 配置。

请根据配置的使用方式选择格式：

| 配置 | 适用场景 | npm/Node CLI | 原生二进制文件 |
| --- | --- | --- | --- |
| `utlint.config.ts` | 编写时类型检查、导入、共享预设和计算值 | 是 | 否 |
| `utlint.config.json` | 静态配置、Schema 验证和直接由原生程序使用 | 是 | 是 |

这两种格式是同一份生效配置的不同表示，二者不会隐式合并。对于 npm/Node 入口，配置查找遵循由近及远的顺序：程序会先检查同一目录中的所有受支持文件名，再考虑其上级目录。在同一目录中，检查顺序为：

1. `utlint.config.ts`
2. `utlint.config.json`
3. `utoo.json`（已弃用）
4. `utoo-lint.json`（已弃用）

因此，更近的 `utlint.config.json` 会优先于更远的 `utlint.config.ts`。两个旧版 JSON 文件名会在迁移期间暂时保留支持，但新项目应使用规范文件名。

npm CLI 会自动查找两种规范格式中的任意一种：

```bash
npx utoo-lint src
```

如需显式选择配置文件，可将任一格式传给 `--config`：

```bash
npx utoo-lint --config=utlint.config.ts src
npx utoo-lint --config=utlint.config.json src
```

使用 `--no-config` 可忽略本地配置。`--rules` 和单条规则开关等与规则相关的 CLI 选项，会在选定配置之后应用。解析后的 `rules` 映射就是完整的已启用规则集，与 ESLint 的配置模型一致：未写出的规则处于禁用状态。如果没有选中任何配置，utoo-lint 会使用内置默认规则。

项目配置中的 `files` 和 `ignores` 模式，相对于所选配置文件所在目录解析；无论该配置是在上级目录中自动找到，还是通过参数显式指定，行为都相同。

## TypeScript 配置

如需在编写配置时获得类型支持，或使用 TypeScript 语法、导入和计算配置，请使用 `utlint.config.ts`：

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

包内提供的前端预设带有类型化导出，可以直接扩展，无需复制对应的 JSON 文件，也无需手动断言规则类型：

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

### 全局忽略与配置项级忽略

使用 `globalIgnores()` 可以从所有配置项中排除文件或整个目录。该辅助函数返回一个仅包含忽略规则的配置项，因此应将它作为单独的 `defineConfig()` 参数或数组项传入：

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

只有当配置项包含 `ignores`，以及可选的 `name`，而不包含其他字段时，它才是全局忽略配置。加入 `files`、`rules` 或其他配置键后，其中的 `ignores` 模式会变成配置项级忽略：它们会阻止该配置项应用到匹配文件，但不会阻止其他配置项处理这些文件。只有全局忽略会在文件查找期间跳过匹配目录，并停止继续遍历。末尾的斜杠表示目录；使用 `dist/` 或 `.next/` 表示配置文件旁的目录，使用 `**/generated/` 表示任意深度下同名的目录。

未传入 lint 目标时，npm/Node 封装层会从配置的 `files` 模式中查找目标；如果没有 `files`，则扫描当前目录。全局忽略会过滤这一查找过程，并阻止程序进入被忽略目录。配置项级忽略会稍后执行，在为每个已找到文件解析匹配配置时生效。该结构有意遵循 [ESLint 扁平配置中的全局与非全局忽略语义](https://eslint.org/docs/latest/use/configure/ignore)。

`defineConfig()` 接受配置对象和扁平配置数组，并返回扁平数组。它还会基于导出的配置类型提供编辑器补全和编译期检查。TypeScript 配置属于受信任的可执行代码：加载配置时，代码可以使用 Node 进程的权限执行任意操作。默认导出必须是可序列化为 JSON 的配置对象或扁平配置数组。加载器会转译并执行 TypeScript 语法；启动 lint 时，它不会运行 `tsc`，也不会执行类型检查。

对于扁平配置数组，每个配置项的 `files` 和 `ignores` 决定该配置项适用的文件。匹配的配置项会按数组顺序合并，因此对于同一规则，后匹配配置项中的值会覆盖前面的值。npm CLI、JavaScript API 和 fishlint 兼容命令会分别为每个接受检查的文件执行这套规则解析。

npm 封装层会执行 TypeScript 文件，将其结果转换为 JSON，再把该 JSON 传给原生二进制文件。原生二进制文件本身不会执行或查找 TypeScript 配置。它会查找 `utlint.config.json`，然后再查找旧版 JSON 文件名。对于 `utlint.config.ts`，请使用 npm CLI；直接调用原生二进制文件时，请使用 `utlint.config.json`。

原生二进制文件会应用 JSON 配置中的 `rules` 以及受支持的共享 `settings`。由配置驱动的 `files` 和 `ignores` 过滤，以及默认 lint 目标的选择，均由 npm/Node 封装层实现。直接调用原生二进制文件时，请显式传入 lint 目标。

## JSON 配置

如果需要静态且与运行时无关的配置，请使用 `utlint.config.json`：

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

可选的 `$schema` 属性可以在支持 JSON Schema 的编辑器中启用补全和验证。JSON 配置不能包含导入或计算值；需要这些能力时，请使用 `utlint.config.ts`。

需要感知版本的 Jest 规则默认会检测距离待检查文件最近的已安装 `jest` 包；未找到安装时会回退到当前支持的最新主版本。如果仓库使用多个 Jest 版本，或需要固定 lint 使用的版本，可显式设置 `settings.jest.version`：

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

可通过 `settings.jest.globalAliases` 将 Jest 的标准函数名映射到项目自定义的全局别名。例如，上面的配置会将 `context` 视为 `describe` 的别名。

使用 `languageOptions.globals` 声明项目全局变量，取值与 ESLint flat config 相同。`no-undef` 会接受声明过的名称，`no-global-assign` 会报告对 `readonly` 全局变量的写入并允许写入 `writable` 全局变量，`"off"` 则会移除某个全局变量（包括内置全局变量）：

```json
{
  "languageOptions": {
    "globals": {
      "APP_VERSION": "readonly",
      "__DEV__": "writable",
      "window": "off"
    }
  },
  "rules": {
    "no-undef": "error",
    "no-global-assign": "error"
  }
}
```

在扁平配置数组中，每个匹配文件的配置项都会贡献自己的 globals，后面的配置项会按名称覆盖前面的值。ESLint 兼容的 JavaScript API 也会把 eslintrc 风格的 `globals` 转发给原生规则。

ESLint 配置文件仅作为迁移输入，不是推荐的长期配置格式。可使用以下命令生成原生配置：

```bash
npx utoo-lint migrate eslint --from eslint.config.js --output utlint.config.json
```

## 前端项目配置

对于 React 或 TypeScript 前端项目，可以先将包内提供的前端模板复制到项目根目录：

```bash
cp node_modules/@utoo/lint/configs/frontend.json utlint.config.json
npx utoo-lint
```

该模板包含用于编辑器验证的 `$schema`，以及一组聚焦于浏览器、import、React、JSX 无障碍和 TypeScript 的规则：

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

未传入目标参数时，复制得到的预设会扫描 `src` 下的 JavaScript 和 TypeScript 文件。它的规则不会应用于 `dist`、`coverage` 或 `node_modules`；即使显式传入 `.`，也是如此。请将 `.next`、`storybook-static` 或 `build` 等框架生成目录加入复制后的 `ignores` 数组。类型化配置可以像上面的 TypeScript 示例一样，向 `frontend.ignores` 追加内容。

`utoo-lint` 与 ESLint 使用相同的配置严重级别。`off`、`0` 和 `false` 会禁用规则；`warn`、`warning`、`on` 和 `1` 会报告警告；`error`、`2` 和 `true` 会报告错误。系统也接受 ESLint 风格的数组：第一项控制严重级别，受支持的选项对象会传给原生规则实现。警告不会改变进程的退出状态 0，而错误会返回状态 1。

## 规则名称

在 `rules` 中使用 ESLint 的规范规则名称：

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

未知规则名称会被拒绝，避免拼写错误被静默放过。已实现的规则列表请参阅[规则支持状态](/zh-CN/rule-status)。

## ESLint 插件

`utoo-lint` 可以在原生规则之外运行社区 ESLint 插件。在 TypeScript 或 JavaScript
配置模块中把插件挂载到一个命名空间下，然后以 `<命名空间>/<规则>` 的形式启用规则：

```ts
import { defineConfig } from "@utoo/lint/config";
import unicorn from "eslint-plugin-unicorn";

export default defineConfig({
  files: ["**/*.{js,jsx,ts,tsx}"],
  plugins: { unicorn },
  rules: {
    "no-debugger": "error",
    "unicorn/prefer-string-slice": "error",
    "unicorn/catch-error-name": ["warn", { name: "err" }]
  }
});
```

插件诊断会和原生诊断合并到同一份报告中并按位置排序，CLI、`fishlint` 以及 JavaScript
API（`lintFiles`、`lintText`、`ESLint`、`Linter`、`RuleTester`）行为一致。`eslint-disable`
注释和 `utlint-ignore` 对插件规则同样生效；插件的自动修复和建议会由 `--fix` 应用、由
`--fix-dry-run` 报告。

工作方式：

- 原生引擎先检查每个文件。插件提供的规则不会传给原生二进制，因此不需要原生实现。
- 每个启用了插件规则的文件会在 Node.js 中用
  [`yuku-parser`](https://www.npmjs.com/package/yuku-parser)（原生引擎所基于的解析器）
  再解析一次，得到 ESTree / TypeScript-ESTree 语法树；规则通过 ESLint 兼容的 `context`
  和 `sourceCode` 在这棵树上运行。
- 插件对象会在当前进程中从配置模块加载，因此插件必须从 `utlint.config.ts`（或
  `.js`、`.mjs`、`.cjs`、`.mts`、`.cts`）挂载；JSON 配置无法挂载插件。

原生规则优先。当挂载的插件提供了 `utoo-lint` 已原生实现的规则（例如 `eslint-plugin-react`
的 `react/jsx-key`）时，运行的是原生实现，插件中的同名规则会被跳过；只有没有原生实现的
规则 ID 才会交给插件。这样从 ESLint 复制过来的配置仍然保持原生速度。原生规则列表见
[规则支持状态](/zh-CN/rule-status)。

支持的规则 API：

- `context.report`，支持 `message` 或 `messageId`、`data`、`loc`、`fix`、`suggest`。
- `context.options`，包含 `meta.defaultOptions` 以及对已提供选项对象应用 JSON Schema 的
  `default` 值。
- `context.settings`、`context.languageOptions`（`sourceType`、`ecmaVersion`、`globals`、
  `parserOptions.ecmaFeatures`）、`context.filename`、`context.cwd`。
- esquery 选择器，包括 `:exit`、属性、子代、后代、`:has`、`:matches`、`:not`。
- `sourceCode` 的文本、行、token、注释、`getAncestors`，以及作用域分析（`getScope`、
  `getDeclaredVariables`、`markVariableAsUsed`）：JavaScript 文件使用 `eslint-scope`，
  TypeScript 文件使用 `@typescript-eslint/scope-manager`。ECMAScript 内置全局、CommonJS
  全局以及 `languageOptions.globals` 都会声明在全局作用域中。

不支持：`sourceCode.parserServices`（类型感知规则）、自定义 `languageOptions.parser`、
`processor`，以及 `onCodePathStart` 等代码路径分析事件。依赖这些能力的规则可以正常加载，
但对应功能不会产生任何报告。

插件规则运行在 JavaScript 中，比原生规则慢；请用 `files` 把它们限定在需要的源码范围内。
运行插件规则需要 Node.js 20.19 或更高版本（或 22.12 及以上）。

## CLI 优先级

与规则相关的 CLI 选项会在配置文件之后应用：

```bash
npx utoo-lint --config=utlint.config.json --no-console=off src
```

对于一次性的聚焦检查，`--rules` 会先禁用所有规则，再只启用列出的规则：

```bash
npx utoo-lint --rules=no-debugger,react/jsx-no-target-blank src
```

## React Compiler 相关检查

在 `utlint.config.json` 中显式开启原生 React Compiler 相关检查：

```json
{
  "rules": {
    "react-hooks/use-memo": "error",
    "react-hooks/void-use-memo": "error",
    "react-hooks/set-state-in-render": "error",
    "react-hooks/purity": "error"
  }
}
```

这些规则默认关闭，`frontend` 预设也不会自动开启；原生和 WebAssembly 构建均支持，
无需安装 React Compiler。当前覆盖上游规则的部分场景，通过检查不代表组件一定能被 Compiler 编译。
支持范围与限制见[规则状态](rule-status.zh-CN.md)。

规则划分参照 React 主线 `e92bda78750136493cb324e98df1726f62ba8e92`：`use-memo` 检查回调签名和捕获变量赋值；
`void-use-memo` 检查缺失返回值和未使用的结果，上游将其放在 `recommended-latest` 中。
每条规则的 `tests/snapshots/specs/react-hooks/<rule>/UPSTREAM.md` 记录选取的上游测试与覆盖边界。
