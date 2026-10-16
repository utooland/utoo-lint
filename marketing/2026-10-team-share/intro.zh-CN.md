# utoo-lint 功能与性能介绍

utoo-lint 是一个用 Zig 编写、基于 Yuku 的 JavaScript / TypeScript Linter。常用检查由原生引擎执行，项目定制规则可以通过 ESLint 插件桥接接入，让团队在熟悉的规则和配置方式下试用原生 lint。

![utoo-lint 功能与性能介绍，1,000 个生成 TS 文件运行 49 条共享规则的原生 CLI 中位数为 50.6 ms](./assets/utoo-lint-team-share.png)

## 日常开发能用到什么

- **300+ 内置规则**：覆盖 JavaScript、TypeScript、React、React Hooks、import 和 JSX 无障碍等检查；具体行为和选项以[规则支持状态](https://utlint.umijs.org/zh-CN/rule-status)为准。
- **熟悉的配置方式**：支持 `utlint.config.ts`、JSON 和 flat config，沿用 ESLint 风格的规则名称、严重级别和逐文件配置。
- **常用工程能力**：支持已覆盖规则的自动修复、注释抑制、JSON 输出，以及 JavaScript API，方便接入本地脚本和 CI。
- **ESLint 插件接入**：可以在类型化配置中挂载社区插件。已有原生实现的规则优先使用原生规则，其他受支持的插件规则通过 Node 执行。
- **浏览器内检查**：单独的 `@utoo/lint-wasm` 包可以在内存中检查和修复单个文件，适合 Playground 和编辑器集成。

## 一组共享规则下的性能

2026 年 10 月 13 日，在 Apple M4 Pro 上检查 **1,000 个生成的 TypeScript 文件，每个文件 30 个语句块，启用 49 条共享规则**。每个工具预热 5 次，再交错采样 20 次；以下为每次启动新 CLI 进程的耗时中位数，越低越好。

| 工具 | 本轮构建或版本 | 耗时中位数 |
| --- | --- | ---: |
| utoo-lint | 原生 ReleaseFast 源码构建 | **50.62 ms** |
| Bun lint | `1.4.4-canary.1+b92e2f470` | 61.31 ms |
| Oxlint | `1.69.0` | 66.52 ms |
| Biome | `2.4.16` | 161.39 ms |
| ESLint | `10.4.1` | 3,064.17 ms |

本轮 utoo-lint 原生 CLI 的耗时约为 ESLint 的 **1/60**，比该 Bun canary 的耗时低约 **17.4%**。计时包含原生 CLI 启动和配置加载，**不含 utoo npm 启动包装层，也不包含 JavaScript 插件执行**。这组结果针对生成语料上的 49 条无类型信息共享规则，不能直接换算为真实项目全量配置的加速倍数。

运行前逐条核验了 49 条规则能够触发诊断，并核对各工具都处理了 1,000 个目标文件、干净语料无诊断。完整命令、样本和构建元数据见[基准方法](../../benchmarks/README.md)及[原始记录](../../benchmarks/snapshots/2026-10-13-bun-49-rules.json)。

主分支随后合入了符号查询和工作线程内存复用优化。在另一轮独立的优化前后对照中，1,000 文件、49 规则的中位数从 **50.44 ms 降至 47.16 ms，耗时降低约 6.5%**；10,000 文件时降低约 **8.8%**。这轮结果不替换上表中的同轮数据。优化已合入 [PR #1290](https://github.com/utooland/utoo-lint/pull/1290)，截至 2026 年 10 月 16 日尚未包含在 npm 最新版 `0.4.8` 中。[独立对照记录](../../benchmarks/snapshots/2026-10-13-native-perf.json)

## 在项目中试用

安装 npm 包即可获得当前平台的预编译二进制，无需安装 Zig。CLI 需要 Node.js 20 或更高版本；插件桥接需要 Node.js 20.19+ 或 22.12+。

```bash
npm install --save-dev @utoo/lint
npx utoo-lint src
```

需要明确配置时，在项目根目录创建 `utlint.config.ts`，从项目关心的规则开始：

```ts
import { defineConfig } from "@utoo/lint/config";

export default defineConfig({
  files: ["src/**/*.{js,jsx,ts,tsx}"],
  rules: {
    "no-debugger": "error",
    "@typescript-eslint/no-unused-vars": "warn",
    "react/jsx-key": "error"
  }
});
```

已有 ESLint 配置的项目，可以先预览迁移报告，查看哪些规则已覆盖：

```bash
npx utoo-lint migrate eslint --from eslint.config.js --print --report=json
```

utoo-lint 当前仍处于实验阶段，适合从已覆盖规则开始渐进接入。插件桥接尚不支持类型感知解析器服务、自定义解析器、processor 和代码路径分析事件；格式化与 `tsc` 继续作为独立步骤。WASM 面向单文件内存输入，不执行项目文件遍历和依赖解析。

[中文文档](https://utlint.umijs.org/zh-CN/) · [规则支持状态](https://utlint.umijs.org/zh-CN/rule-status) · [ESLint 迁移指南](https://utlint.umijs.org/zh-CN/eslint-migration) · [在线 Playground](https://utlint.umijs.org/playground/) · [GitHub](https://github.com/utooland/utoo-lint)
