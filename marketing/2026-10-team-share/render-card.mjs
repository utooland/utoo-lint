#!/usr/bin/env node

import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// Keep the card tied to one archived comparison. Never mix a newer utoo-lint
// result into these five rows without rerunning the other tools as well.
const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..');
const snapshotPath = join(root, 'benchmarks/snapshots/2026-10-13-bun-49-rules.json');
const snapshot = JSON.parse(await readFile(snapshotPath, 'utf8'));
const order = ['utoo-lint', 'bun', 'oxlint', 'biome', 'eslint'];
const labels = {
  'utoo-lint': 'utoo-lint',
  bun: 'Bun lint (canary)',
  oxlint: 'Oxlint',
  biome: 'Biome',
  eslint: 'ESLint',
};
const rows = order.map((name) => {
  const result = snapshot.results.find((entry) => entry.name === name);
  const validation = snapshot.validation.tools.find((entry) => entry.name === name);
  if (!result || !validation) throw new Error(`Missing evidence for ${name}`);
  if (
    result.warmups !== 5 || result.runs !== 20 || result.samplesMs.length !== 20 ||
    validation.negativeDiagnostics !== snapshot.rules.length ||
    validation.cleanDiagnostics !== 0 || validation.targetDiagnostics !== 0 ||
    validation.targetFiles !== snapshot.targetFiles ||
    snapshot.rules.some((rule) => validation.ruleCounts[rule] !== 1)
  ) throw new Error(`Unexpected benchmark or validation scope for ${name}`);
  const samples = [...result.samplesMs].sort((a, b) => a - b);
  const median = (samples[9] + samples[10]) / 2;
  if (Math.abs(median - result.summary.medianMs) > 0.00051) {
    throw new Error(`Recorded median differs from samples for ${name}`);
  }
  return result;
});
if (snapshot.targetFiles !== 1000 || snapshot.rules.length !== 49) {
  throw new Error('The layout expects the archived 1,000-file / 49-rule comparison');
}

const esc = (value) => String(value).replace(/[&<>"']/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;',
})[character]);
const decimal = (value, places) => value.toLocaleString('en-US', {
  minimumFractionDigits: places,
  maximumFractionDigits: places,
});
const text = (x, y, content, size, attributes = '') =>
  `<text x="${x}" y="${y}" font-size="${size}" ${attributes}>${esc(content)}</text>`;
const logo = Buffer.from(await readFile(join(root, 'assets/utoo-lint-logo.svg'))).toString('base64');
const native = rows[0];
const bun = rows.find((row) => row.name === 'bun');
const fileCount = decimal(snapshot.targetFiles, 0);
const nativeBuild = `${snapshot.sourceCommit.slice(0, 7)}${snapshot.sourceDirty ? ' · 工作树含改动' : ''}`;
const rowLabel = (row) => {
  if (!['oxlint', 'biome', 'eslint'].includes(row.name)) return labels[row.name];
  if (!row.version) throw new Error(`Missing version for ${row.name}`);
  return `${labels[row.name]} ${row.version.replace(/^(?:Version:\s*|v)/, '')}`;
};
const resultRows = rows.map((row, index) => {
  const top = 789 + index * 66;
  const selected = row.name === 'utoo-lint';
  return `<g>
    <rect x="88" y="${top}" width="904" height="58" rx="14" fill="${selected ? '#e9f5ff' : index % 2 === 0 ? '#f6f6f2' : '#ffffff'}"/>
    ${selected ? `<rect x="88" y="${top + 13}" width="5" height="32" rx="2.5" fill="#009cf3"/>` : ''}
    ${text(112, top + 39, rowLabel(row), 30, `font-weight="${selected ? 750 : 500}" fill="${selected ? '#007fc6' : '#29313a'}"`)}
    ${text(903, top + 39, decimal(row.summary.medianMs, 3), 32, `class="number" text-anchor="end" font-weight="${selected ? 750 : 550}" fill="${selected ? '#007fc6' : '#29313a'}"`)}
    ${text(963, top + 39, 'ms', 24, 'text-anchor="end" fill="#63717b"')}
  </g>`;
}).join('\n');

const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1080" height="1760" viewBox="0 0 1080 1760" fill="#202b35" role="img" aria-labelledby="card-title card-description">
  <title id="card-title">utoo-lint：${fileCount} 个生成 TypeScript 文件、${snapshot.rules.length} 条共享规则，${decimal(native.summary.medianMs, 1)} 毫秒</title>
  <desc id="card-description">团队内功能与性能介绍。${esc(rows.map((row) => `${rowLabel(row)} ${decimal(row.summary.medianMs, 3)} ms`).join('；'))}。数据来自 2026 年 10 月 13 日 Apple M4 Pro 上的归档基准，新进程中位数，5 次预热、20 次采样。原生源码构建，不含 utoo npm 包装层与 JS 插件执行，仅本组合成语料。Bun ${esc(bun.revision)}。</desc>
  <defs>
    <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#f8f7ef"/>
      <stop offset="1" stop-color="#f2f6f8"/>
    </linearGradient>
    <linearGradient id="blue" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#008edc"/>
      <stop offset="1" stop-color="#00a8f7"/>
    </linearGradient>
    <style>
      text { font-family: "PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei", sans-serif; }
      .number { font-family: "Avenir Next", "Arial", sans-serif; font-variant-numeric: tabular-nums; }
      .code { font-family: "SF Mono", "Menlo", "DejaVu Sans Mono", monospace; }
    </style>
  </defs>
  <rect width="1080" height="1760" fill="url(#background)"/>
  <circle cx="1007" cy="118" r="190" fill="#e4f3fa" opacity=".65"/>
  <circle cx="1046" cy="81" r="124" fill="none" stroke="#cde9f8" stroke-width="2"/>
  <image x="64" y="50" width="350" height="106" xlink:href="data:image/svg+xml;base64,${logo}"/>
  <rect x="768" y="69" width="248" height="43" rx="21.5" fill="#e2eef4"/>
  ${text(892, 98, '团队技术分享 · 2026.10', 22, 'text-anchor="middle" fill="#46616f" font-weight="600"')}

  ${text(68, 229, '让日常代码检查更轻快', 48, 'font-weight="650" letter-spacing="1"')}
  ${text(60, 405, decimal(native.summary.medianMs, 1), 174, 'class="number" font-weight="750" letter-spacing="-8" fill="#008fdc"')}
  ${text(497, 404, 'ms', 65, 'class="number" font-weight="600" fill="#008fdc"')}
  ${text(68, 467, `${fileCount} 个生成 TypeScript 文件 · ${snapshot.rules.length} 条共享规则`, 32, 'font-weight="600"')}
  ${text(68, 513, '本组基准中的新进程耗时中位数', 27, 'fill="#65747e"')}

  <g>
    <rect x="64" y="558" width="462" height="61" rx="17" fill="#ffffff" stroke="#e0e8eb"/>
    <circle cx="96" cy="588" r="6" fill="#009cf3"/>
    ${text(119, 599, '300+ 内置规则', 29, 'font-weight="600"')}
    <rect x="542" y="558" width="474" height="61" rx="17" fill="#ffffff" stroke="#e0e8eb"/>
    <circle cx="574" cy="588" r="6" fill="#009cf3"/>
    ${text(597, 599, 'ESLint 插件接入', 29, 'font-weight="600"')}
    <rect x="64" y="635" width="952" height="61" rx="17" fill="#ffffff" stroke="#e0e8eb"/>
    <circle cx="96" cy="665" r="6" fill="#009cf3"/>
    ${text(119, 676, 'Zig + Yuku 原生引擎', 29, 'font-weight="600"')}
    ${text(982, 675, 'JS / TS / React', 25, 'text-anchor="end" fill="#687782"')}
  </g>

  <rect x="64" y="726" width="952" height="454" rx="26" fill="#ffffff" stroke="#e0e8eb"/>
  ${text(89, 768, '同规则 · 同语料 · 同轮采样', 26, 'font-weight="650"')}
  ${text(965, 768, '越低越快', 23, 'text-anchor="end" fill="#75818a"')}
  ${resultRows}
  ${text(90, 1155, `Bun ${bun.revision}`, 23, 'class="code" fill="#697984"')}

  ${text(68, 1232, `2026-10-13 · ${snapshot.cpu.model} · ${native.warmups} 次预热 / ${native.runs} 次采样`, 25, 'fill="#566773"')}
  ${text(68, 1273, '新进程中位数 · 规则与语料覆盖已校验', 25, 'fill="#566773"')}
  ${text(68, 1321, '原生源码构建；不含 utoo npm 包装层与 JS 插件执行；', 25, 'fill="#566773"')}
  ${text(68, 1362, '仅本组合成语料。实际项目结果随配置与规模变化。', 25, 'fill="#566773"')}
  ${text(68, 1405, `utoo-lint 源码 ${nativeBuild} · ReleaseFast`, 22, 'fill="#75818a"')}

  <rect x="64" y="1450" width="952" height="210" rx="26" fill="#202e39"/>
  <rect x="64" y="1450" width="7" height="210" rx="3.5" fill="url(#blue)"/>
  ${text(98, 1502, '在项目里试一试', 27, 'fill="#dce8f0" font-weight="600"')}
  ${text(98, 1560, 'npm i -D @utoo/lint', 33, 'class="code" fill="#ffffff" font-weight="600"')}
  ${text(98, 1615, 'npx utoo-lint src', 33, 'class="code" fill="#7cd2ff" font-weight="600"')}
  ${text(68, 1713, 'utlint.umijs.org', 30, 'class="number" font-weight="650" fill="#0088d0"')}
  ${text(1013, 1713, 'UTOO · 开源 JavaScript 工具链', 23, 'text-anchor="end" fill="#687782"')}
</svg>
`;

const outputDirectory = join(here, 'assets');
await mkdir(outputDirectory, { recursive: true });
const svgPath = join(outputDirectory, 'utoo-lint-team-share.svg');
const pngPath = join(outputDirectory, 'utoo-lint-team-share.png');
await writeFile(svgPath, svg.replace(/[ \t]+$/gm, ''));
const converter = process.env.RSVG_CONVERT ||
  (existsSync('/opt/homebrew/bin/rsvg-convert') ? '/opt/homebrew/bin/rsvg-convert' : 'rsvg-convert');
const converted = spawnSync(converter, [svgPath, '-o', pngPath], { encoding: 'utf8' });
if (converted.error) throw converted.error;
if (converted.status !== 0) throw new Error(converted.stderr || 'PNG rendering failed');
console.log(`Rendered ${svgPath}`);
console.log(`Rendered ${pngPath}`);
console.log(rows.map((row) => `${labels[row.name]}: ${decimal(row.summary.medianMs, 3)} ms`).join('\n'));
