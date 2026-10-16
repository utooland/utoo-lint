# utoo-lint 团队分享素材

面向团队内部的中文功能与性能介绍，按 2026 年 10 月 16 日的功能和发布状态整理。

- [群内转发文案](./message.zh-CN.md)：配图、功能概览和试用命令。
- [详细介绍](./intro.zh-CN.md)：功能、同轮性能对比、独立优化结果和接入方式。
- [PNG 分享卡](./assets/utoo-lint-team-share.png) 与 [SVG 源图](./assets/utoo-lint-team-share.svg)。

## 版式参考

参考 [Bun 官方 2026 年 10 月 15 日的 lint 预告](https://x.com/bunjavascript/status/2110692261508079721)，采用产品主张、醒目数字、对比表、能力标签和试用入口的顺序，使用 utoo 自身的品牌和数据。该预告介绍的是下一版 Bun 的能力。

Bun 原图比较真实项目各自的配置及插件；这里使用生成 TypeScript 语料上的共享规则基准，不能将两套结果合并、计算平均值或相互背书。

## 数字与功能来源

分享卡读取 [49 规则五工具快照](../../benchmarks/snapshots/2026-10-13-bun-49-rules.json)。该快照记录原生源码构建，`sourceCommit` 为 `b3c9f28`，`sourceDirty` 为 `true`，二进制 SHA-256 及完整工具版本保存在记录中。它不代表 npm 包端到端计时，也没有测量 JavaScript 插件桥接。

详细介绍中的 47.16 ms 来自[独立优化前后对照](../../benchmarks/snapshots/2026-10-13-native-perf.json)，不得替换五工具表中的 50.62 ms。基准与优化已分别合入 [#1289](https://github.com/utooland/utoo-lint/pull/1289) 和 [#1290](https://github.com/utooland/utoo-lint/pull/1290)。

功能描述依据 [v0.4.8 README](https://github.com/utooland/utoo-lint/blob/v0.4.8/README.md)、[配置文档](https://github.com/utooland/utoo-lint/blob/v0.4.8/docs/configuration.zh-CN.md)、[迁移指南](https://github.com/utooland/utoo-lint/blob/v0.4.8/docs/eslint-migration.zh-CN.md)和 [WASM 文档](https://github.com/utooland/utoo-lint/blob/v0.4.8/docs/wasm.zh-CN.md)。版本状态依据 [v0.4.8 发布记录](https://github.com/utooland/utoo-lint/releases/tag/v0.4.8)。发布前若版本有变化，应同步更新介绍中的 npm 版本和优化发布状态。

## 生成分享卡

需要 Node.js 和 `rsvg-convert`，与现有基准图渲染方式一致。在仓库根目录运行：

```bash
node marketing/2026-10-team-share/render-card.mjs
```

脚本从归档快照读取实测数值，生成 SVG 和 PNG。保持图中测试日期、生成语料、共享规则数、采样方法、Bun canary 版本和原生入口范围，避免转发图片后丢失影响解读的条件。
