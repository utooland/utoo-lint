import { createHash } from 'node:crypto';
import { access, readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoDir = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);
const siteDir = path.join(repoDir, 'dist', 'site');
const playgroundDir = path.join(siteDir, 'playground');

async function requireFile(relativePath) {
  const absolutePath = path.join(siteDir, relativePath);
  const entry = await stat(absolutePath).catch(() => undefined);
  if (!entry?.isFile()) throw new Error(`missing site file: ${relativePath}`);
  return absolutePath;
}

async function collectFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await collectFiles(absolutePath)));
    else if (entry.isFile()) files.push(absolutePath);
  }

  return files;
}

async function verifyTranslationSources() {
  const stems = [
    'index',
    'quick-start',
    'configuration',
    'eslint-migration',
    'rule-status',
    'suppressions',
    'wasm',
    'benchmarks',
  ];
  const sources = new Map();

  for (const stem of stems) {
    const english = await readFile(
      path.join(repoDir, 'docs', `${stem}.md`),
      'utf8',
    );
    const chinese = await readFile(
      path.join(repoDir, 'docs', `${stem}.zh-CN.md`),
      'utf8',
    );
    sources.set(stem, { english, chinese });

    const englishHeadings = english.match(/^#{1,6} /gm)?.length ?? 0;
    const chineseHeadings = chinese.match(/^#{1,6} /gm)?.length ?? 0;
    if (englishHeadings !== chineseHeadings) {
      throw new Error(`${stem} translation has a different heading structure`);
    }

    const extractCodeBlocks = (source) =>
      [...source.matchAll(/^```[^\n]*\n[\s\S]*?^```[ \t]*$/gm)].map(
        (match) => match[0],
      );
    const englishCodeBlocks = extractCodeBlocks(english);
    const chineseCodeBlocks = extractCodeBlocks(chinese);
    if (
      englishCodeBlocks.length !== chineseCodeBlocks.length ||
      englishCodeBlocks.some(
        (block, index) => block !== chineseCodeBlocks[index],
      )
    ) {
      throw new Error(`${stem} translation changed a code example`);
    }

    if (
      /(?:\]\(|href=["'])\/(?:quick-start|configuration|rule-status|eslint-migration|suppressions|wasm)(?=[/#?"')])/i.test(
        chinese,
      )
    ) {
      throw new Error(
        `${stem} translation links back to an English docs route`,
      );
    }
  }

  const extractRuleIds = (source) =>
    [...source.matchAll(/^\| \[`([^`]+)`\]/gm)].map((match) => match[1]);
  const englishRuleIds = extractRuleIds(sources.get('rule-status').english);
  const chineseRuleIds = extractRuleIds(sources.get('rule-status').chinese);
  if (
    englishRuleIds.length === 0 ||
    englishRuleIds.length !== chineseRuleIds.length ||
    englishRuleIds.some((ruleId, index) => ruleId !== chineseRuleIds[index])
  ) {
    throw new Error(
      `Chinese rule status must preserve all ${englishRuleIds.length} rule IDs in order`,
    );
  }
}

async function verifyLocalAssets(html, label) {
  for (const match of html.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
    const value = match[1];
    if (value.startsWith('data:') || value.startsWith('#')) continue;

    const url = new URL(value, 'https://utlint.umijs.org/');
    if (url.origin !== 'https://utlint.umijs.org') continue;
    if (!/\.[a-z0-9]+$/i.test(url.pathname)) continue;

    const assetPath = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    try {
      await access(path.join(siteDir, assetPath));
    } catch {
      throw new Error(`${label} references a missing asset: ${url.pathname}`);
    }
  }
}

function verifyDocumentMetadata(html, expectedTitle, label) {
  const head = html.slice(0, html.indexOf('</head>'));
  const tags = [
    ['title', /<title\b[^>]*>/g],
    ['viewport', /<meta\b(?=[^>]*\bname="viewport")[^>]*>/g],
    ['description', /<meta\b(?=[^>]*\bname="description")[^>]*>/g],
    ['Open Graph title', /<meta\b(?=[^>]*\bproperty="og:title")[^>]*>/g],
    [
      'Open Graph description',
      /<meta\b(?=[^>]*\bproperty="og:description")[^>]*>/g,
    ],
  ];

  for (const [name, pattern] of tags) {
    const count = head.match(pattern)?.length ?? 0;
    if (count !== 1) {
      throw new Error(`${label} must contain one ${name}, found ${count}`);
    }
  }

  const escapedTitle = expectedTitle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (!new RegExp(`<title\\b[^>]*>${escapedTitle}</title>`).test(head)) {
    throw new Error(`${label} has the wrong document title`);
  }
}

function verifyDocumentEnvelope(html, label) {
  if (html.includes('\0')) {
    throw new Error(`${label} contains a null byte`);
  }

  if (
    /<!--\$\?-->|<template\b[^>]*\bdata-msg=|\bid="[BS]:|\$RC\(/i.test(html)
  ) {
    throw new Error(`${label} contains an unfinished streamed SSR boundary`);
  }

  const closingHtmlTags = html.match(/<\/html\s*>/gi)?.length ?? 0;
  if (closingHtmlTags !== 1 || !/<\/html\s*>\s*$/i.test(html)) {
    throw new Error(`${label} must end with exactly one closing html tag`);
  }
}

function getHtmlAttribute(openingTag, name) {
  const match = openingTag.match(
    new RegExp(
      `\\s${name}(?:\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+)))?`,
      'i',
    ),
  );

  if (!match) return undefined;
  return match[1] ?? match[2] ?? match[3] ?? '';
}

function findOpeningTagByClass(html, className) {
  for (const match of html.matchAll(/<[a-z][a-z0-9:-]*\b[^>]*>/gi)) {
    const classes = getHtmlAttribute(match[0], 'class')?.split(/\s+/) ?? [];
    if (classes.includes(className)) return match[0];
  }

  return undefined;
}

function verifyDocumentLanguage(html, expectedLanguage, label) {
  const htmlTag = html.match(/<html\b[^>]*>/i)?.[0];
  if (getHtmlAttribute(htmlTag ?? '', 'lang') !== expectedLanguage) {
    throw new Error(`${label} has the wrong document language`);
  }
}

function verifyLocalizedHead(
  html,
  { currentPath, englishPath, chinesePath, label },
) {
  const head = html.slice(0, html.indexOf('</head>'));
  const expectedLinks = [
    {
      rel: 'canonical',
      href: `https://utlint.umijs.org${currentPath}`,
    },
    {
      rel: 'alternate',
      hrefLang: 'en',
      href: `https://utlint.umijs.org${englishPath}`,
    },
    {
      rel: 'alternate',
      hrefLang: 'zh-CN',
      href: `https://utlint.umijs.org${chinesePath}`,
    },
    {
      rel: 'alternate',
      hrefLang: 'x-default',
      href: `https://utlint.umijs.org${englishPath}`,
    },
  ];

  for (const expected of expectedLinks) {
    const links = [...head.matchAll(/<link\b[^>]*>/gi)].filter((match) => {
      const tag = match[0];
      return (
        getHtmlAttribute(tag, 'rel') === expected.rel &&
        getHtmlAttribute(tag, 'hrefLang') === expected.hrefLang &&
        getHtmlAttribute(tag, 'href') === expected.href
      );
    });

    if (links.length !== 1) {
      const descriptor = expected.hrefLang
        ? `${expected.rel} ${expected.hrefLang}`
        : expected.rel;
      throw new Error(`${label} must contain one ${descriptor} link`);
    }
  }
}

function verifyLanguageSwitch(html, expectedHref, expectedText, label) {
  const switchLink = [...html.matchAll(/(<a\b[^>]*>)([\s\S]*?)<\/a>/gi)].find(
    (match) => {
      const classes = getHtmlAttribute(match[1], 'class')?.split(/\s+/) ?? [];
      return classes.includes('dumi-default-lang-switch');
    },
  );
  const text = switchLink?.[2]
    .replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  if (
    !switchLink ||
    getHtmlAttribute(switchLink[1], 'href') !== expectedHref ||
    text !== expectedText
  ) {
    throw new Error(`${label} has the wrong language switch target`);
  }
}

function verifyHomepageVisual(html) {
  for (const requiredClass of [
    'product-hero',
    'product-demo',
    'product-install',
    'product-features',
    'product-benchmark',
    'product-chart',
    'product-config',
    'product-steps',
    'product-runtimes',
    'product-cta',
  ]) {
    if (!findOpeningTagByClass(html, requiredClass)) {
      throw new Error(`docs index is missing ${requiredClass}`);
    }
  }
  const chart = findOpeningTagByClass(html, 'product-chart');
  if (!getHtmlAttribute(chart, 'aria-labelledby')) {
    throw new Error(
      'docs index is missing its accessible benchmark chart title',
    );
  }
  const lanes = [
    ...html.matchAll(/<button\b[^>]*class="benchmark-lane"[^>]*>/gi),
  ];
  if (
    lanes.length !== 4 ||
    lanes.some(
      ([tag]) => !getHtmlAttribute(tag, 'aria-label')?.match(/\d+\.\d{2}/),
    )
  ) {
    throw new Error(
      'docs index must render all four benchmark times before JavaScript runs',
    );
  }
  if (!/href="\/benchmarks\/comparison-(en|zh)\.svg"/.test(html)) {
    throw new Error('docs index is missing its downloadable benchmark image');
  }
  if (!html.includes('/benchmarks/2026-08-30.json')) {
    throw new Error('docs index is missing its raw benchmark data link');
  }
}

function verifyHomepageActions(html, quickStartText, quickStartHref) {
  let linkCount = 0;
  let quickStartFound = false;
  let githubFound = false;

  for (const match of html.matchAll(/(<a\b[^>]*>)([\s\S]*?)<\/a>/gi)) {
    const text = match[2]
      .replace(/<[^>]*>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    const href = getHtmlAttribute(match[1], 'href');

    if (/\bPlayground\b/i.test(text)) {
      if (href !== '/playground/') {
        throw new Error(`${text} must be a native link to /playground/`);
      }
      linkCount += 1;
    }

    quickStartFound ||= text === quickStartText && href === quickStartHref;
    githubFound ||= href === 'https://github.com/utooland/utoo-lint';
  }

  if (!quickStartFound) {
    throw new Error('docs index is missing the localized Quick Start hero CTA');
  }
  if (!githubFound) {
    throw new Error('docs index is missing its GitHub repository link');
  }
  if (linkCount < 1) {
    throw new Error('docs index is missing its native Playground link');
  }
}

function verifyAccessibleControls(html, label, colorThemeLabel) {
  const menuButton = findOpeningTagByClass(
    html,
    'dumi-default-header-menu-btn',
  );
  if (
    !menuButton ||
    !getHtmlAttribute(menuButton, 'aria-label') ||
    getHtmlAttribute(menuButton, 'aria-expanded') === undefined
  ) {
    throw new Error(`${label} has an inaccessible mobile navigation control`);
  }

  const colorThemeControl = [...html.matchAll(/<select\b[^>]*>/gi)].find(
    (match) => getHtmlAttribute(match[0], 'aria-label') === colorThemeLabel,
  );
  if (!colorThemeControl) {
    throw new Error(`${label} has an inaccessible color theme control`);
  }

  const skipLink = html.match(
    /<a\b(?=[^>]*\bclass="[^"]*\butlint-skip-link\b[^"]*")[^>]*>/i,
  )?.[0];
  if (
    !skipLink ||
    getHtmlAttribute(skipLink, 'href') !== '#utlint-main-content' ||
    !html.includes('id="utlint-main-content"')
  ) {
    throw new Error(`${label} is missing its working skip link`);
  }

  for (const match of html.matchAll(/<button\b[^>]*>/gi)) {
    const classes = getHtmlAttribute(match[0], 'class')?.split(/\s+/) ?? [];
    if (
      classes.includes('dumi-default-source-code-copy') &&
      !getHtmlAttribute(match[0], 'aria-label')
    ) {
      throw new Error(`${label} has an inaccessible code copy control`);
    }
  }
}

function isCdnHost(hostname) {
  const knownCdnSuffixes = [
    'cdnjs.cloudflare.com',
    'cloudfront.net',
    'esm.run',
    'esm.sh',
    'jsdelivr.net',
    'skypack.dev',
    'unpkg.com',
  ];

  return (
    hostname.split('.').includes('cdn') ||
    knownCdnSuffixes.some(
      (suffix) => hostname === suffix || hostname.endsWith(`.${suffix}`),
    )
  );
}

function verifyHomepageBuildScript(source, label) {
  for (const [name, pattern] of [
    ['eval()', /\beval\s*\(/],
    ['new Function()', /\bnew\s+Function\s*\(/],
  ]) {
    if (pattern.test(source)) {
      throw new Error(`${label} unexpectedly contains ${name}`);
    }
  }

  const normalizedSource = source.replaceAll('\\/', '/');
  for (const match of normalizedSource.matchAll(
    /(?:https?:)?\/\/[a-z0-9][^\s"'`()<>]*/gi,
  )) {
    const rawUrl = match[0];
    let url;
    try {
      url = new URL(rawUrl.startsWith('//') ? `https:${rawUrl}` : rawUrl);
    } catch {
      continue;
    }

    const nearbySource = normalizedSource.slice(
      Math.max(0, match.index - 160),
      match.index + rawUrl.length + 160,
    );
    const isRemoteTexture =
      /(?:^|\/)textures?(?:\/|$)/i.test(url.pathname) ||
      /\.(?:avif|basis|bmp|exr|gif|hdr|jpe?g|ktx2?|png|webp)$/i.test(
        url.pathname,
      ) ||
      /\btexture/i.test(nearbySource);

    if (isCdnHost(url.hostname.toLowerCase()) || isRemoteTexture) {
      throw new Error(
        `${label} unexpectedly references remote asset ${rawUrl}`,
      );
    }
  }
}

async function verifyHomepageBuildScripts() {
  const entries = await readdir(siteDir, { withFileTypes: true });
  const scriptGroups = [
    [
      'homepage build script',
      /^docs__index(?:\.zh-CN)?\.md(?:\.[a-f0-9]+)?(?:\.async)?\.js$/i,
    ],
    [
      'DocLayout build script',
      /^nm__dumi__theme-default__layouts__DocLayout__index(?:\.[a-f0-9]+)?(?:\.async)?\.js$/i,
    ],
  ];

  for (const [label, pattern] of scriptGroups) {
    const scripts = entries.filter(
      (entry) => entry.isFile() && pattern.test(entry.name),
    );
    if (scripts.length === 0) {
      throw new Error(`missing ${label}`);
    }

    for (const script of scripts) {
      verifyHomepageBuildScript(
        await readFile(path.join(siteDir, script.name), 'utf8'),
        script.name,
      );
    }
  }
}

await verifyTranslationSources();

const documentSpecs = [
  {
    file: 'index.html',
    title: 'utoo-lint',
    label: 'English docs index',
    language: 'en',
    currentPath: '/',
    englishPath: '/',
    chinesePath: '/zh-CN/',
    switchHref: '/zh-CN',
    switchText: '中文',
    colorThemeLabel: 'Color theme',
    homepage: 'en',
  },
  {
    file: 'quick-start/index.html',
    title: 'Quick Start',
    label: 'English quick start',
    language: 'en',
    currentPath: '/quick-start',
    englishPath: '/quick-start',
    chinesePath: '/zh-CN/quick-start',
    switchHref: '/zh-CN/quick-start',
    switchText: '中文',
    colorThemeLabel: 'Color theme',
  },
  {
    file: 'configuration/index.html',
    title: 'Configuration',
    label: 'English configuration',
    language: 'en',
    currentPath: '/configuration',
    englishPath: '/configuration',
    chinesePath: '/zh-CN/configuration',
    switchHref: '/zh-CN/configuration',
    switchText: '中文',
    colorThemeLabel: 'Color theme',
  },
  {
    file: 'rule-status/index.html',
    title: 'Rule status',
    label: 'English rule status',
    language: 'en',
    currentPath: '/rule-status',
    englishPath: '/rule-status',
    chinesePath: '/zh-CN/rule-status',
    switchHref: '/zh-CN/rule-status',
    switchText: '中文',
    colorThemeLabel: 'Color theme',
  },
  {
    file: 'eslint-migration/index.html',
    title: 'Migrating from ESLint',
    label: 'English ESLint migration',
    language: 'en',
    currentPath: '/eslint-migration',
    englishPath: '/eslint-migration',
    chinesePath: '/zh-CN/eslint-migration',
    switchHref: '/zh-CN/eslint-migration',
    switchText: '中文',
    colorThemeLabel: 'Color theme',
  },
  {
    file: 'suppressions/index.html',
    title: 'Suppression comments',
    label: 'English suppressions',
    language: 'en',
    currentPath: '/suppressions',
    englishPath: '/suppressions',
    chinesePath: '/zh-CN/suppressions',
    switchHref: '/zh-CN/suppressions',
    switchText: '中文',
    colorThemeLabel: 'Color theme',
  },
  {
    file: 'wasm/index.html',
    title: 'WebAssembly',
    label: 'English WebAssembly',
    language: 'en',
    currentPath: '/wasm',
    englishPath: '/wasm',
    chinesePath: '/zh-CN/wasm',
    switchHref: '/zh-CN/wasm',
    switchText: '中文',
    colorThemeLabel: 'Color theme',
  },
  {
    file: 'zh-CN/index.html',
    title: 'utoo-lint 中文文档',
    label: 'Chinese docs index',
    language: 'zh-CN',
    currentPath: '/zh-CN/',
    englishPath: '/',
    chinesePath: '/zh-CN/',
    switchHref: '/',
    switchText: 'English',
    colorThemeLabel: '颜色主题',
    homepage: 'zh-CN',
  },
  {
    file: 'zh-CN/quick-start/index.html',
    title: '快速开始',
    label: 'Chinese quick start',
    language: 'zh-CN',
    currentPath: '/zh-CN/quick-start',
    englishPath: '/quick-start',
    chinesePath: '/zh-CN/quick-start',
    switchHref: '/quick-start',
    switchText: 'English',
    colorThemeLabel: '颜色主题',
  },
  {
    file: 'zh-CN/configuration/index.html',
    title: '配置',
    label: 'Chinese configuration',
    language: 'zh-CN',
    currentPath: '/zh-CN/configuration',
    englishPath: '/configuration',
    chinesePath: '/zh-CN/configuration',
    switchHref: '/configuration',
    switchText: 'English',
    colorThemeLabel: '颜色主题',
  },
  {
    file: 'zh-CN/rule-status/index.html',
    title: '规则支持状态',
    label: 'Chinese rule status',
    language: 'zh-CN',
    currentPath: '/zh-CN/rule-status',
    englishPath: '/rule-status',
    chinesePath: '/zh-CN/rule-status',
    switchHref: '/rule-status',
    switchText: 'English',
    colorThemeLabel: '颜色主题',
  },
  {
    file: 'zh-CN/eslint-migration/index.html',
    title: '从 ESLint 迁移',
    label: 'Chinese ESLint migration',
    language: 'zh-CN',
    currentPath: '/zh-CN/eslint-migration',
    englishPath: '/eslint-migration',
    chinesePath: '/zh-CN/eslint-migration',
    switchHref: '/eslint-migration',
    switchText: 'English',
    colorThemeLabel: '颜色主题',
  },
  {
    file: 'zh-CN/suppressions/index.html',
    title: '抑制注释',
    label: 'Chinese suppressions',
    language: 'zh-CN',
    currentPath: '/zh-CN/suppressions',
    englishPath: '/suppressions',
    chinesePath: '/zh-CN/suppressions',
    switchHref: '/suppressions',
    switchText: 'English',
    colorThemeLabel: '颜色主题',
  },
  {
    file: 'zh-CN/wasm/index.html',
    title: 'WebAssembly',
    label: 'Chinese WebAssembly',
    language: 'zh-CN',
    currentPath: '/zh-CN/wasm',
    englishPath: '/wasm',
    chinesePath: '/zh-CN/wasm',
    switchHref: '/wasm',
    switchText: 'English',
    colorThemeLabel: '颜色主题',
  },
  {
    file: 'benchmarks/index.html',
    title: 'Benchmark results',
    label: 'English benchmark report',
    language: 'en',
    currentPath: '/benchmarks',
    englishPath: '/benchmarks',
    chinesePath: '/zh-CN/benchmarks',
    switchHref: '/zh-CN/benchmarks',
    switchText: '中文',
    colorThemeLabel: 'Color theme',
  },
  {
    file: 'zh-CN/benchmarks/index.html',
    title: '性能测试记录',
    label: 'Chinese benchmark report',
    language: 'zh-CN',
    currentPath: '/zh-CN/benchmarks',
    englishPath: '/benchmarks',
    chinesePath: '/zh-CN/benchmarks',
    switchHref: '/benchmarks',
    switchText: 'English',
    colorThemeLabel: '颜色主题',
  },
];
const documents = new Map();

for (const spec of documentSpecs) {
  const html = await readFile(await requireFile(spec.file), 'utf8');
  documents.set(spec.file, html);
  verifyDocumentEnvelope(html, spec.label);
  verifyDocumentMetadata(html, spec.title, spec.label);
  verifyDocumentLanguage(html, spec.language, spec.label);
  verifyLocalizedHead(html, spec);
  verifyLanguageSwitch(html, spec.switchHref, spec.switchText, spec.label);
  verifyAccessibleControls(html, spec.label, spec.colorThemeLabel);
  await verifyLocalAssets(html, spec.label);

  if (spec.homepage === 'en') {
    verifyHomepageVisual(html);
    verifyHomepageActions(html, 'Quick Start', '/quick-start');
  } else if (spec.homepage === 'zh-CN') {
    verifyHomepageVisual(html);
    verifyHomepageActions(html, '快速开始', '/zh-CN/quick-start');
  }
}

const benchmark = JSON.parse(
  await readFile(await requireFile('benchmarks/2026-08-30.json'), 'utf8'),
);
for (const language of ['en', 'zh', 'en-compact', 'zh-compact']) {
  const chart = await readFile(
    await requireFile(`benchmarks/comparison-${language}.svg`),
    'utf8',
  );
  for (const result of benchmark.results) {
    const sorted = [...result.samplesMs].sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);
    const median =
      sorted.length % 2
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
    if (
      sorted.length !== result.runs ||
      !Number.isFinite(median) ||
      Math.abs(median - result.summary.medianMs) > 0.001 ||
      !chart.includes(`${result.summary.medianMs.toFixed(2)} ms`)
    ) {
      throw new Error(
        `benchmark chart does not match ${result.name} measurements`,
      );
    }
  }
}

await requireFile('robots.txt');
await requireFile('sitemap.xml');
const docsIndex = documents.get('index.html');
const chineseDocsIndex = documents.get('zh-CN/index.html');
if (docsIndex.includes('__EVJS_CLIENT_RUNTIME__')) {
  throw new Error('root document unexpectedly contains the Playground runtime');
}
if (chineseDocsIndex.includes('__EVJS_CLIENT_RUNTIME__')) {
  throw new Error(
    'Chinese document unexpectedly contains the Playground runtime',
  );
}
for (const [label, html] of [
  ['English root document', docsIndex],
  ['Chinese root document', chineseDocsIndex],
]) {
  if (!findOpeningTagByClass(html, 'product-home')) {
    throw new Error(`${label} was not statically rendered`);
  }
}
await verifyHomepageBuildScripts();

const sitemap = await readFile(await requireFile('sitemap.xml'), 'utf8');
for (const url of [
  'https://utlint.umijs.org/',
  'https://utlint.umijs.org/configuration',
  'https://utlint.umijs.org/rule-status',
  'https://utlint.umijs.org/eslint-migration',
  'https://utlint.umijs.org/suppressions',
  'https://utlint.umijs.org/wasm',
  'https://utlint.umijs.org/benchmarks',
  'https://utlint.umijs.org/zh-CN/',
  'https://utlint.umijs.org/zh-CN/configuration',
  'https://utlint.umijs.org/zh-CN/rule-status',
  'https://utlint.umijs.org/zh-CN/eslint-migration',
  'https://utlint.umijs.org/zh-CN/suppressions',
  'https://utlint.umijs.org/zh-CN/wasm',
  'https://utlint.umijs.org/zh-CN/benchmarks',
  'https://utlint.umijs.org/playground/',
]) {
  if (!sitemap.includes(`<loc>${url}</loc>`)) {
    throw new Error(`sitemap is missing ${url}`);
  }
}

const playgroundIndex = await readFile(
  await requireFile('playground/index.html'),
  'utf8',
);
verifyDocumentEnvelope(playgroundIndex, 'Playground index');
if (!playgroundIndex.includes('id="__EVJS_CLIENT_RUNTIME__"')) {
  throw new Error('Playground browser runtime is missing');
}
if (!playgroundIndex.includes('"path":"/playground"')) {
  throw new Error('Playground runtime route is not mounted at /playground');
}
for (const match of playgroundIndex.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
  if (match[1].startsWith('/') && !match[1].startsWith('/playground/')) {
    throw new Error(`Playground asset escaped its subpath: ${match[1]}`);
  }
}
await verifyLocalAssets(playgroundIndex, 'Playground index');

const playgroundFiles = await collectFiles(playgroundDir);
const versionManifest = JSON.parse(
  await readFile(
    await requireFile('playground/versions/manifest.json'),
    'utf8',
  ),
);
if (
  typeof versionManifest.latest !== 'string' ||
  !Array.isArray(versionManifest.versions) ||
  versionManifest.versions.length === 0 ||
  versionManifest.versions[0]?.id !== versionManifest.latest
) {
  throw new Error('invalid Playground version manifest');
}

const wasmFiles = playgroundFiles.filter(
  (file) => path.extname(file) === '.wasm',
);
if (wasmFiles.length !== versionManifest.versions.length + 2) {
  throw new Error(
    `expected ${versionManifest.versions.length + 2} Playground WebAssembly assets, found ${wasmFiles.length}`,
  );
}

let parserWasm;
let bundledLintWasm;
for (const file of wasmFiles) {
  const name = path.basename(file);
  const isParser = name.includes('yuku-parser');
  const isLintVersion = /^utoo-lint-v\d+\.\d+\.\d+\.wasm$/.test(name);
  const isBundledLint = /^utoo-lint\.[^.]+\.wasm$/.test(name);
  if (!isParser && !isLintVersion && !isBundledLint) {
    throw new Error(`unexpected Playground WebAssembly asset: ${name}`);
  }

  const contents = await readFile(file);
  if (
    contents.length === 0 ||
    !contents.subarray(0, 4).equals(Buffer.from([0, 97, 115, 109]))
  ) {
    throw new Error(`invalid Playground WebAssembly asset: ${name}`);
  }
  if (isParser) {
    if (parserWasm) {
      throw new Error(`duplicate parser WebAssembly asset: ${name}`);
    }
    parserWasm = contents;
  } else if (isBundledLint) {
    if (bundledLintWasm) {
      throw new Error(`duplicate bundled lint WebAssembly asset: ${name}`);
    }
    bundledLintWasm = contents;
  }
}

for (const version of versionManifest.versions) {
  if (
    !/^\d+\.\d+\.\d+$/.test(version.id) ||
    version.label !== `v${version.id}` ||
    version.file !== `utoo-lint-v${version.id}.wasm` ||
    !/^[a-f0-9]{64}$/.test(version.sha256)
  ) {
    throw new Error(
      `invalid Playground version entry: ${JSON.stringify(version)}`,
    );
  }
  const contents = await readFile(
    path.join(playgroundDir, 'versions', version.file),
  );
  const actualSha256 = createHash('sha256').update(contents).digest('hex');
  if (actualSha256 !== version.sha256) {
    throw new Error(
      `unexpected ${version.label} WebAssembly SHA-256: ${actualSha256}`,
    );
  }
}

if (!parserWasm) {
  throw new Error('missing Playground parser WebAssembly asset');
}
if (!bundledLintWasm) {
  throw new Error('missing bundled Playground lint WebAssembly asset');
}
const bundledLintSha256 = createHash('sha256')
  .update(bundledLintWasm)
  .digest('hex');
if (bundledLintSha256 !== versionManifest.versions[0].sha256) {
  throw new Error(
    `bundled lint WebAssembly does not match latest ${versionManifest.versions[0].label}`,
  );
}
for (const controlFile of ['_headers', '_redirects']) {
  if (playgroundFiles.some((file) => path.basename(file) === controlFile)) {
    throw new Error(
      `nested Playground control file was not removed: ${controlFile}`,
    );
  }
}

const redirects = await readFile(await requireFile('_redirects'), 'utf8');
if (!redirects.includes('/playground /playground/ 301')) {
  throw new Error('missing canonical /playground/ redirect');
}
if (redirects.includes('/*')) {
  throw new Error('root redirects must not capture the dumi site');
}

const headers = await readFile(await requireFile('_headers'), 'utf8');
for (const directive of [
  '/playground/*',
  "script-src 'self' 'wasm-unsafe-eval'",
  "frame-ancestors 'none'",
  'X-Content-Type-Options: nosniff',
]) {
  if (!headers.includes(directive)) {
    throw new Error(`missing unified header directive: ${directive}`);
  }
}

console.log(
  `verified unified site (${(await collectFiles(siteDir)).length} files, ${wasmFiles.length} WASM assets)`,
);
