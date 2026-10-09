import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { promisify } from 'node:util';
import test from 'node:test';

const run = promisify(execFile);
const playgroundDirectory = fileURLToPath(new URL('..', import.meta.url));
const outputDirectory = await mkdtemp(join(tmpdir(), 'utoo-lint-client-'));
await run(
  process.execPath,
  [
    fileURLToPath(
      new URL('../node_modules/typescript/bin/tsc', import.meta.url),
    ),
    '--ignoreConfig',
    fileURLToPath(new URL('../src/features/lint/client.ts', import.meta.url)),
    fileURLToPath(new URL('../src/features/ast/client.ts', import.meta.url)),
    fileURLToPath(
      new URL('../src/features/playground/model.ts', import.meta.url),
    ),
    fileURLToPath(
      new URL('../src/features/playground/versions.ts', import.meta.url),
    ),
    '--target',
    'es2022',
    '--module',
    'es2022',
    '--moduleResolution',
    'bundler',
    '--lib',
    'es2022,dom',
    '--skipLibCheck',
    '--outDir',
    outputDirectory,
  ],
  { cwd: playgroundDirectory },
);
await writeFile(join(outputDirectory, 'package.json'), '{"type":"module"}');
const compiledASTClient = join(outputDirectory, 'ast', 'client.js');
await writeFile(
  compiledASTClient,
  (await readFile(compiledASTClient, 'utf8')).replace(
    "from './protocol';",
    "from './protocol.js';",
  ),
);
const { LintWorkerClient } = await import(
  pathToFileURL(join(outputDirectory, 'lint', 'client.js')).href
);
const { ASTWorkerClient } = await import(
  pathToFileURL(join(outputDirectory, 'ast', 'client.js')).href
);
const { AST_SOURCE_LENGTH_MAX } = await import(
  pathToFileURL(join(outputDirectory, 'ast', 'protocol.js')).href
);
const {
  createPlaygroundShareUrl,
  fileNameForLanguage,
  INITIAL_SOURCES,
  parsePlaygroundShareUrl,
  RECOMMENDED_RULES,
  removePlaygroundShareState,
} = await import(
  pathToFileURL(join(outputDirectory, 'playground', 'model.js')).href
);
const {
  initialLintVersion,
  LATEST_LINT_VERSION,
  lintVersionManifestUrl,
  lintVersionUrl,
  parseLintVersionCatalog,
  resolveLintVersion,
} = await import(
  pathToFileURL(join(outputDirectory, 'playground', 'versions.js')).href
);
await rm(outputDirectory, { force: true, recursive: true });

class MockWorker {
  static instances = [];

  messages = [];
  onerror = null;
  onmessage = null;
  onmessageerror = null;

  constructor() {
    MockWorker.instances.push(this);
  }

  postMessage(message) {
    this.messages.push(message);
  }

  respond(data) {
    this.onmessage?.({ data });
  }

  terminate() {}
}

test('coalesces queued lint work to the newest request', async (t) => {
  MockWorker.instances = [];
  globalThis.Worker = MockWorker;

  const client = new LintWorkerClient();
  t.after(() => {
    client.dispose();
    delete globalThis.Worker;
  });
  const first = client.run('lint', 'first', {});
  void first.catch(() => {});
  const superseded = client.run('lint', 'superseded', {});
  const supersededAssertion = assert.rejects(
    superseded,
    (error) =>
      error?.name === 'AbortError' && /superseded/i.test(error.message),
  );
  const latest = client.run('lint', 'latest', {});
  void latest.catch(() => {});
  const worker = MockWorker.instances[0];

  assert.deepEqual(
    worker.messages.map(({ source }) => source),
    ['first'],
  );
  await supersededAssertion;

  const firstResult = { diagnostics: [], mode: 'lint' };
  worker.respond({ id: worker.messages[0].id, result: firstResult });
  assert.equal(await first, firstResult);
  assert.deepEqual(
    worker.messages.map(({ source }) => source),
    ['first', 'latest'],
  );

  const latestResult = { diagnostics: [], mode: 'lint' };
  worker.respond({ id: worker.messages[1].id, result: latestResult });
  assert.equal(await latest, latestResult);
});

test('can discard queued work before its debounce replacement is ready', async (t) => {
  MockWorker.instances = [];
  globalThis.Worker = MockWorker;

  const client = new LintWorkerClient();
  t.after(() => {
    client.dispose();
    delete globalThis.Worker;
  });
  const active = client.run('lint', 'active', {});
  void active.catch(() => {});
  const queued = client.run('lint', 'queued', {});
  const queuedAssertion = assert.rejects(
    queued,
    (error) =>
      error?.name === 'AbortError' && /superseded/i.test(error.message),
  );
  const worker = MockWorker.instances[0];

  client.cancelQueued();
  await queuedAssertion;
  worker.respond({
    id: worker.messages[0].id,
    result: { diagnostics: [], mode: 'lint' },
  });
  await active;
  assert.deepEqual(
    worker.messages.map(({ source }) => source),
    ['active'],
  );
});

test('passes the selected WebAssembly version URL to the lint worker', async (t) => {
  MockWorker.instances = [];
  globalThis.Worker = MockWorker;

  const client = new LintWorkerClient();
  t.after(() => {
    client.dispose();
    delete globalThis.Worker;
  });
  const result = client.run(
    'lint',
    'const value = 1;',
    {},
    'https://example.test/v0.4.0/utoo-lint.wasm',
  );
  const worker = MockWorker.instances[0];

  assert.equal(
    worker.messages[0].wasmUrl,
    'https://example.test/v0.4.0/utoo-lint.wasm',
  );
  worker.respond({
    id: worker.messages[0].id,
    result: { diagnostics: [], mode: 'lint' },
  });
  await result;
});

test('loads versioned WebAssembly URLs and defaults to the latest release', () => {
  const manifestUrl = lintVersionManifestUrl(
    'https://example.test/playground/',
  );
  const catalog = parseLintVersionCatalog(
    {
      latest: '0.3.4',
      versions: [
        {
          id: '0.3.4',
          label: 'v0.3.4',
          file: 'utoo-lint-v0.3.4.wasm',
          sha256: 'a'.repeat(64),
        },
        {
          id: '0.3.3',
          label: 'v0.3.3',
          file: 'utoo-lint-v0.3.3.wasm',
          sha256: 'b'.repeat(64),
        },
      ],
    },
    manifestUrl,
  );

  assert.equal(
    manifestUrl,
    'https://example.test/playground/versions/manifest.json',
  );
  assert.equal(
    lintVersionManifestUrl('https://example.test/playground'),
    'https://example.test/playground/versions/manifest.json',
  );
  assert.equal(
    catalog.versions[0].wasmUrl,
    'https://example.test/playground/versions/utoo-lint-v0.3.4.wasm',
  );
  assert.equal(
    initialLintVersion(catalog, 'https://example.test/playground/'),
    LATEST_LINT_VERSION,
  );
  assert.equal(
    initialLintVersion(
      catalog,
      'https://example.test/playground/?version=0.3.3',
    ),
    '0.3.3',
  );
  assert.equal(
    initialLintVersion(
      catalog,
      'https://example.test/playground/?version=0.2.9',
    ),
    LATEST_LINT_VERSION,
  );
  assert.equal(resolveLintVersion(catalog, LATEST_LINT_VERSION)?.id, '0.3.4');
  assert.equal(resolveLintVersion(catalog, '0.3.3')?.id, '0.3.3');
});

test('resolves version assets within the Playground after shared URL normalization', () => {
  for (const route of ['/playground', '/playground/']) {
    assert.equal(
      lintVersionManifestUrl(
        `https://example.test${route}?version=0.3.3#playground=state`,
      ),
      'https://example.test/playground/versions/manifest.json',
    );
  }
  assert.equal(
    lintVersionManifestUrl('http://localhost:3000/playground?version=0.3.3'),
    'http://localhost:3000/playground/versions/manifest.json',
  );
});

test('pins concrete version selections but leaves the latest channel implicit', () => {
  assert.equal(
    lintVersionUrl(
      'https://example.test/playground/?theme=dark#playground=state',
      '0.3.3',
    ),
    'https://example.test/playground/?theme=dark&version=0.3.3#playground=state',
  );
  assert.equal(
    lintVersionUrl(
      'https://example.test/playground/?theme=dark&version=0.3.3#playground=state',
      '0.3.4',
    ),
    'https://example.test/playground/?theme=dark&version=0.3.4#playground=state',
  );
  assert.equal(
    lintVersionUrl(
      'https://example.test/playground/?theme=dark&version=0.3.3#playground=state',
      LATEST_LINT_VERSION,
    ),
    'https://example.test/playground/?theme=dark#playground=state',
  );
});

test('rejects unsafe or inconsistent version manifests', () => {
  assert.throws(
    () =>
      parseLintVersionCatalog(
        {
          latest: '0.3.4',
          versions: [
            {
              id: '0.3.4',
              label: 'v0.3.4',
              file: '../utoo-lint.wasm',
              sha256: 'a'.repeat(64),
            },
          ],
        },
        'https://example.test/playground/versions/manifest.json',
      ),
    /invalid/i,
  );
});

test('coalesces queued AST work to the newest source', async (t) => {
  MockWorker.instances = [];
  globalThis.Worker = MockWorker;

  const client = new ASTWorkerClient();
  t.after(() => {
    client.dispose();
    delete globalThis.Worker;
  });
  const first = client.parse('first', 'index.ts');
  void first.catch(() => {});
  const superseded = client.parse('superseded', 'index.ts');
  const supersededAssertion = assert.rejects(
    superseded,
    (error) =>
      error?.name === 'AbortError' && /superseded/i.test(error.message),
  );
  const latest = client.parse('latest', 'index.ts');
  void latest.catch(() => {});
  const worker = MockWorker.instances[0];

  assert.deepEqual(
    worker.messages.map(({ source }) => source),
    ['first'],
  );
  await supersededAssertion;

  const firstResult = { diagnostics: [], elapsedMs: 1, program: {} };
  worker.respond({ id: worker.messages[0].id, result: firstResult });
  assert.equal(await first, firstResult);
  assert.deepEqual(
    worker.messages.map(({ source }) => source),
    ['first', 'latest'],
  );

  const latestResult = { diagnostics: [], elapsedMs: 2, program: {} };
  worker.respond({ id: worker.messages[1].id, result: latestResult });
  assert.equal(await latest, latestResult);
});

test('rejects oversized AST input before starting a worker', async () => {
  MockWorker.instances = [];
  globalThis.Worker = MockWorker;

  const client = new ASTWorkerClient();
  await assert.rejects(
    client.parse('x'.repeat(AST_SOURCE_LENGTH_MAX + 1), 'index.ts'),
    (error) => error?.name === 'RangeError' && /exceeds/i.test(error.message),
  );
  assert.equal(MockWorker.instances.length, 0);
  client.dispose();
  delete globalThis.Worker;
});

test('keeps Yuku spans aligned with Monaco UTF-16 offsets', async () => {
  const { parse } = await import('yuku-parser');
  const { load } = await import('@yuku-core/wasm');
  const core = await load();
  const source = "const 前缀 = '🐰';\nfunction greet() {}";
  const { program } = parse(source, {
    core,
    lang: 'ts',
    sourceType: 'module',
  });
  const declaration = program.body[1];
  const expectedStart = source.indexOf('function');
  const utf8Start = new TextEncoder().encode(
    source.slice(0, expectedStart),
  ).length;

  assert.equal(declaration.type, 'FunctionDeclaration');
  assert.equal(declaration.start, expectedStart);
  assert.notEqual(declaration.start, utf8Start);
  assert.equal(
    source.slice(declaration.start, declaration.end),
    'function greet() {}',
  );
});

test('fixes every diagnostic in each default Playground fixture', async () => {
  const { createUtooLint } = await import('@utoo/lint-wasm');
  const { langFromPath, parse } = await import('yuku-parser');
  const { load } = await import('@yuku-core/wasm');
  const core = await load();
  const linter = await createUtooLint();

  for (const [language, source] of Object.entries(INITIAL_SOURCES)) {
    const options = {
      filePath: fileNameForLanguage(language),
      rules: RECOMMENDED_RULES,
    };
    const before = linter.lint(source, options);
    assert.ok(
      before.diagnostics.length > 0,
      `${language} should demonstrate lint errors`,
    );
    assert.ok(
      before.diagnostics.every((diagnostic) => diagnostic.fixes.length > 0),
      `${language} should only demonstrate fixable diagnostics`,
    );

    const fixed = linter.lintAndFix(source, options);
    assert.equal(fixed.fixed, true, `${language} should be changed`);
    assert.deepEqual(
      fixed.diagnostics,
      [],
      `${language} should be clean after one Fix all action`,
    );

    const ast = parse(source, {
      core,
      lang: langFromPath(options.filePath),
      preserveParens: true,
      sourceType: 'module',
    });
    assert.equal(ast.program.type, 'Program');
    assert.equal(ast.program.start, 0);
    assert.equal(ast.program.end, source.length);
  }
});

test('round-trips Playground state through a share URL', () => {
  const payload = {
    language: 'tsx',
    rulesMode: 'custom',
    rulesSource: '{"react/jsx-key":"error"}',
    source: "const greeting = '你好，🐰';",
    version: 1,
  };
  const shareUrl = createPlaygroundShareUrl(
    'https://example.test/playground/?theme=dark',
    payload,
  );

  assert.match(shareUrl, /#playground=[\w-]+$/u);
  assert.deepEqual(parsePlaygroundShareUrl(shareUrl), payload);
  assert.equal(new URL(shareUrl).searchParams.get('theme'), 'dark');
});

test('ignores malformed or unsupported Playground share state', () => {
  assert.equal(
    parsePlaygroundShareUrl('https://example.test/#playground=not-base64'),
    undefined,
  );

  const unsupported = Buffer.from(
    JSON.stringify({
      language: 'typescript',
      rulesMode: 'custom',
      rulesSource: '{}',
      source: 'const value = 1;',
      version: 2,
    }),
  ).toString('base64url');
  assert.equal(
    parsePlaygroundShareUrl(
      `https://example.test/#playground=${unsupported}`,
    ),
    undefined,
  );
});

test('removes stale Playground state without changing other URL data', () => {
  assert.equal(
    removePlaygroundShareState(
      'https://example.test/playground/?theme=dark#playground=old&panel=ast',
    ),
    'https://example.test/playground/?theme=dark#panel=ast',
  );
});
