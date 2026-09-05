import { Link, useLocale } from 'dumi';
import React from 'react';
import SourceCode from '../SourceCode';
import BenchmarkChart from '../../components/BenchmarkChart';
import AutofixExample from '../../components/AutofixExample';
import NativeLink from '../../components/NativeLink';
import benchmark from '../../../../public/benchmarks/2026-08-30.json';

const config = `import { defineConfig } from '@utoo/lint/config';
import frontend from '@utoo/lint/configs/frontend';

export default defineConfig({
  ...frontend,
  rules: {
    ...frontend.rules,
    'no-console': 'warn',
  },
});`;
const messages = {
  en: {
    features: [
      [
        'Native at the core',
        'Built in Zig, with Yuku parsing and semantic analysis. Lint files in parallel using prebuilt binaries for macOS, Linux, and Windows.',
      ],
      [
        'Made for real projects',
        'JavaScript, TypeScript, React, accessibility, and import rules. Use familiar rule IDs and severities, with safe autofix where supported.',
      ],
      [
        'Ready for your workflow',
        'Typed or JSON configuration, suppression comments, and JSON diagnostics. Use the CLI, JavaScript API, or in-memory WebAssembly package.',
      ],
    ],
    performance: 'PERFORMANCE',
    benchmarkTitle: 'More feedback. Less waiting.',
    benchmarkDescription:
      'The same TypeScript corpus. The same 12 shared rules. Every sample starts a fresh CLI process, including startup time.',
    median: 'utoo-lint median',
    faster: 'faster than ESLint in this run',
    benchmarkNote:
      'A recorded run on one generated workload. Results vary with hardware, code, and enabled rules. The archived report documents the environment and comparison limits.',
    methodology: 'Reproduce the benchmark',
    raw: 'Download raw results',
    details: 'Read the recorded results',
    configLabel: 'CONFIGURATION',
    configTitle: 'Your rules. In your language.',
    configDescription:
      'Start with the frontend preset, then adapt it to your project. Typed configuration brings editor completion; static JSON works when you need a data-only config.',
    configItems: [
      'ESLint-style rule names and severities',
      'File patterns, global ignores, and flat config arrays',
      'Presets you can extend and override',
    ],
    configLink: 'Explore configuration',
    migrationLabel: 'ADOPTION',
    migrationTitle: 'Start small. Migrate with confidence.',
    migrationDescription:
      'Bring over supported rules at your own pace. The migration report shows what can move and what still needs ESLint.',
    steps: [
      [
        'Inspect your config',
        'Preview the migration before writing files. Review the report for unsupported options and plugin behavior.',
      ],
      [
        'Move supported rules',
        'Check coverage for the rules your project uses. Keep unsupported processors, custom plugins, and type-service workflows in ESLint.',
      ],
      [
        'Verify in your project',
        'Run both tools in CI and compare diagnostics. Remove duplicate ESLint coverage as each rule is verified.',
      ],
    ],
    coverage: 'Check rule coverage',
    migrationLink: 'Read the migration guide',
    runtimeLabel: 'ONE ENGINE, MULTIPLE RUNTIMES',
    runtimeTitle: 'From your repository to the browser.',
    runtimes: [
      [
        'Native CLI',
        'Lint your source tree and apply supported fixes, locally or in CI.',
        'pnpm exec utoo-lint src',
        '/quick-start',
        'Use the CLI',
      ],
      [
        'JavaScript API',
        'Integrate linting into Node.js tools with ESM and CommonJS entry points.',
        '@utoo/lint',
        '/configuration',
        'Configure your project',
      ],
      [
        'WebAssembly',
        'Lint and fix one in-memory file. The Playground processes code locally in your browser.',
        '@utoo/lint-wasm',
        '/wasm',
        'Explore WebAssembly',
      ],
    ],
    ctaTitle: 'Give your code a faster feedback loop.',
    ctaDescription:
      'Try a file in the browser, or add utoo-lint to your next commit.',
    start: 'Quick Start',
    playground: 'Open Playground',
  },
  zh: {
    features: [
      [
        '原生引擎，高效检查',
        'Zig 引擎结合 Yuku 解析与语义分析，并行检查项目文件。macOS、Linux 和 Windows 均提供预构建二进制。',
      ],
      [
        '面向真实项目',
        '覆盖 JavaScript、TypeScript、React、无障碍和导入规则。沿用熟悉的规则 ID 与严重级别，为受支持的问题提供安全修复。',
      ],
      [
        '融入现有工作流',
        '支持类型化或 JSON 配置、抑制注释和 JSON 诊断输出。通过 CLI、JavaScript API 或内存中的 WebAssembly 调用。',
      ],
    ],
    performance: '性能基准',
    benchmarkTitle: '更快获得反馈，少一点等待。',
    benchmarkDescription:
      '同一批 TypeScript 文件，同样的 12 条共有规则。每次独立启动 CLI，计时包含启动开销。',
    median: 'utoo-lint 耗时中位数',
    faster: '本次测试中，相对 ESLint 的速度',
    benchmarkNote:
      '数据来自一组已归档的生成语料测试。结果会随硬件、代码和启用规则变化；完整测试条件与对比范围见测试记录。',
    methodology: '复现基准测试',
    raw: '下载原始数据',
    details: '查看测试记录',
    configLabel: '项目配置',
    configTitle: '你的规则，用熟悉的方式配置。',
    configDescription:
      '从 frontend 预设开始，按项目需求调整。TypeScript 配置提供编辑器补全；需要纯数据配置时，也可以使用静态 JSON。',
    configItems: [
      'ESLint 风格的规则名称与严重级别',
      '文件模式、全局忽略与 flat config 数组',
      '可扩展、可覆盖的规则预设',
    ],
    configLink: '了解配置方式',
    migrationLabel: '渐进接入',
    migrationTitle: '从小范围开始，有把握地迁移。',
    migrationDescription:
      '按项目节奏迁移受支持的规则。先用迁移报告确认哪些可以迁移，哪些仍需保留在 ESLint 中。',
    steps: [
      [
        '检查现有配置',
        '先预览，再写入。阅读迁移报告，确认尚不支持的选项与插件行为。',
      ],
      [
        '迁移已支持的规则',
        '核对项目所用规则的覆盖情况。暂不支持的处理器、自定义插件和类型服务工作流继续交给 ESLint。',
      ],
      [
        '在项目中验证',
        '在 CI 中同时运行两个工具并比较诊断结果。逐条验证后，移除 ESLint 中的重复检查。',
      ],
    ],
    coverage: '查看规则覆盖',
    migrationLink: '阅读迁移指南',
    runtimeLabel: '同一个引擎，多种运行方式',
    runtimeTitle: '从代码仓库，到浏览器。',
    runtimes: [
      [
        '原生 CLI',
        '在本地或 CI 中检查源代码目录，并应用受支持的自动修复。',
        'pnpm exec utoo-lint src',
        '/quick-start',
        '使用 CLI',
      ],
      [
        'JavaScript API',
        '通过 ESM 和 CommonJS 入口，将检查能力集成到 Node.js 工具中。',
        '@utoo/lint',
        '/configuration',
        '配置项目',
      ],
      [
        'WebAssembly',
        '检查并修复单个内存文件。Playground 直接在浏览器本地处理代码。',
        '@utoo/lint-wasm',
        '/wasm',
        '了解 WebAssembly',
      ],
    ],
    ctaTitle: '让代码反馈，跟上开发节奏。',
    ctaDescription: '在浏览器里试一段代码，或把 utoo-lint 加入下一次提交。',
    start: '快速开始',
    playground: '打开 Playground',
  },
};

export default function ProductHome() {
  const chinese = useLocale().id === 'zh-CN';
  const t = chinese ? messages.zh : messages.en;
  const base = chinese ? '/zh-CN' : '';
  const median = benchmark.results.find(
    (result) => result.name === 'utoo-lint',
  )!.summary.medianMs;
  const speedup =
    benchmark.results.find((result) => result.name === 'eslint')!.summary
      .medianMs / median;
  return (
    <div className="product-home">
      <section
        className="product-container product-features"
        aria-label={chinese ? '核心能力' : 'Core capabilities'}
      >
        <div className="product-feature-list">
          {t.features.map(([title, description], index) => (
            <article key={title}>
              <span className="product-feature-icon" aria-hidden="true">
                {['↯', '{ }', '>_'][index]}
              </span>
              <h2>{title}</h2>
              <p>{description}</p>
            </article>
          ))}
        </div>
        <AutofixExample />
      </section>
      <section
        id="performance"
        className="product-container product-section product-benchmark"
        aria-labelledby="benchmark-title"
      >
        <header className="product-section-heading">
          <span className="product-kicker">{t.performance}</span>
          <h2 id="benchmark-title">{t.benchmarkTitle}</h2>
          <p>{t.benchmarkDescription}</p>
        </header>
        <div className="product-benchmark-layout">
          <div className="product-benchmark-stats">
            <div>
              <strong>
                {median.toFixed(2)}
                <small>ms</small>
              </strong>
              <span>{t.median}</span>
            </div>
            <div className="product-benchmark-speedup">
              <strong>
                {speedup.toFixed(1)}
                <small>×</small>
              </strong>
              <span>{t.faster}</span>
            </div>
            <Link className="product-text-link" to={`${base}/benchmarks`}>
              {t.details} <span aria-hidden="true">↗</span>
            </Link>
          </div>
          <BenchmarkChart chinese={chinese} />
        </div>
        <div className="product-benchmark-notes">
          <p>{t.benchmarkNote}</p>
          <div>
            <a
              href="https://github.com/utooland/utoo-lint/tree/main/benchmarks"
              target="_blank"
              rel="noreferrer"
            >
              {t.methodology} ↗
            </a>
            <a href="/benchmarks/2026-08-30.json" download>
              {t.raw} ↓
            </a>
          </div>
        </div>
      </section>
      <section
        className="product-container product-section product-config"
        aria-labelledby="config-title"
      >
        <div className="product-section-heading">
          <span className="product-kicker">{t.configLabel}</span>
          <h2 id="config-title">{t.configTitle}</h2>
          <p>{t.configDescription}</p>
          <ul className="product-checklist">
            {t.configItems.map((item) => (
              <li key={item}>
                <span aria-hidden="true">✓</span>
                {item}
              </li>
            ))}
          </ul>
          <Link className="product-text-link" to={`${base}/configuration`}>
            {t.configLink} <span aria-hidden="true">→</span>
          </Link>
        </div>
        <div className="product-config-code">
          <div className="product-demo-title">
            <span>utlint.config.ts</span>
            <span>TypeScript</span>
          </div>
          <SourceCode lang="typescript">{config}</SourceCode>
        </div>
      </section>
      <section
        className="product-container product-section product-migration"
        aria-labelledby="migration-title"
      >
        <header className="product-section-heading">
          <span className="product-kicker">{t.migrationLabel}</span>
          <h2 id="migration-title">{t.migrationTitle}</h2>
          <p>{t.migrationDescription}</p>
        </header>
        <ol className="product-steps">
          {t.steps.map(([title, description], index) => (
            <li key={title}>
              <span className="product-step-number" aria-hidden="true">
                0{index + 1}
              </span>
              <h3>{title}</h3>
              <p>{description}</p>
              {index === 0 ? (
                <code>utoo-lint migrate eslint --print</code>
              ) : (
                <Link
                  to={
                    base + (index === 1 ? '/rule-status' : '/eslint-migration')
                  }
                >
                  {index === 1 ? t.coverage : t.migrationLink} →
                </Link>
              )}
            </li>
          ))}
        </ol>
      </section>
      <section
        className="product-container product-section"
        aria-labelledby="runtime-title"
      >
        <header className="product-section-heading">
          <span className="product-kicker">{t.runtimeLabel}</span>
          <h2 id="runtime-title">{t.runtimeTitle}</h2>
        </header>
        <div className="product-runtimes">
          {t.runtimes.map(([title, description, command, href, label]) => (
            <article key={title}>
              <h3>{title}</h3>
              <p>{description}</p>
              <code>{command}</code>
              <Link to={base + href}>{label} →</Link>
            </article>
          ))}
        </div>
      </section>
      <aside
        className="product-container product-cta"
        aria-labelledby="cta-title"
      >
        <div>
          <span className="product-kicker">
            {chinese ? '开始使用' : 'START BUILDING'}
          </span>
          <h2 id="cta-title">{t.ctaTitle}</h2>
          <p>{t.ctaDescription}</p>
        </div>
        <div className="product-actions">
          <Link
            className="product-button product-button-primary"
            to={`${base}/quick-start`}
          >
            {t.start} ↗
          </Link>
          <NativeLink className="product-button" href="/playground/">
            {t.playground} →
          </NativeLink>
        </div>
      </aside>
    </div>
  );
}
