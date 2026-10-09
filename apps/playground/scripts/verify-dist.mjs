import { createHash } from 'node:crypto';
import { readdir, readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const appDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const clientDir = path.join(appDir, 'dist', 'client');
const deploymentFile = path.join(appDir, 'dist', 'deployment-metadata.json');
const requiredFiles = [
  'index.html',
  '_headers',
  '_redirects',
  'deployment.static.json',
  'versions/manifest.json',
];
const forbiddenText = [
  '@alipay/evjs',
  'registry.antgroup-inc.cn',
  '__RENDER_STATIC_URL_PREFIX__',
  '__RENDER_PACK_URL__',
  '__UNIO_VERSION__',
];
const textExtensions = new Set(['.css', '.html', '.js', '.json', '.map', '.ts']);

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

for (const fileName of requiredFiles) {
  const file = path.join(clientDir, fileName);
  if (!(await stat(file)).isFile()) throw new Error(`missing ${fileName}`);
}

const files = await collectFiles(clientDir);
const versionManifest = JSON.parse(
  await readFile(path.join(clientDir, 'versions', 'manifest.json'), 'utf8'),
);
if (
  typeof versionManifest.latest !== 'string' ||
  !Array.isArray(versionManifest.versions) ||
  versionManifest.versions.length === 0 ||
  versionManifest.versions[0]?.id !== versionManifest.latest
) {
  throw new Error('invalid Playground version manifest');
}

const wasmFiles = files.filter((file) => path.extname(file) === '.wasm');
if (wasmFiles.length !== versionManifest.versions.length + 2) {
  throw new Error(
    `expected ${versionManifest.versions.length + 2} WebAssembly assets, found ${wasmFiles.length}`,
  );
}

let parserWasm;
let bundledLintWasm;
for (const file of wasmFiles) {
  const name = path.basename(file);
  const isParser = name.includes('yuku-core');
  const isLintVersion = /^utoo-lint-v\d+\.\d+\.\d+\.wasm$/.test(name);
  const isBundledLint = /^utoo-lint\.[^.]+\.wasm$/.test(name);
  if (!isParser && !isLintVersion && !isBundledLint) {
    throw new Error(`unexpected WebAssembly asset: ${name}`);
  }

  const contents = await readFile(file);
  if (
    contents.length === 0 ||
    !contents.subarray(0, 4).equals(Buffer.from([0, 97, 115, 109]))
  ) {
    throw new Error(`invalid WebAssembly asset: ${name}`);
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

if (!parserWasm) throw new Error('missing parser WebAssembly asset');
if (!bundledLintWasm) throw new Error('missing bundled lint WebAssembly asset');

const lintWasmSizes = new Map();
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
    path.join(clientDir, 'versions', version.file),
  );
  const actualSha256 = createHash('sha256').update(contents).digest('hex');
  if (actualSha256 !== version.sha256) {
    throw new Error(
      `unexpected ${version.label} WebAssembly SHA-256: ${actualSha256}`,
    );
  }
  lintWasmSizes.set(version.id, contents.length);
}

const latestVersion = versionManifest.versions[0];
const bundledLintSha256 = createHash('sha256')
  .update(bundledLintWasm)
  .digest('hex');
if (bundledLintSha256 !== latestVersion.sha256) {
  throw new Error(
    `bundled lint WebAssembly does not match latest ${latestVersion.label}`,
  );
}

const deployment = JSON.parse(
  await readFile(path.join(clientDir, 'deployment.static.json'), 'utf8'),
);
if (
  deployment.platform !== 'static' ||
  deployment.metadata?.static?.complete !== true ||
  deployment.metadata.static.unsupportedCapabilities.length !== 0 ||
  Object.keys(deployment.server ?? {}).length !== 0
) {
  throw new Error('static deployment is incomplete or requires a server');
}

const canonicalDeployment = JSON.parse(await readFile(deploymentFile, 'utf8'));
if (Object.keys(canonicalDeployment.server ?? {}).length !== 0) {
  throw new Error('canonical deployment unexpectedly requires a server');
}

const indexHtml = await readFile(path.join(clientDir, 'index.html'), 'utf8');
if (!indexHtml.includes('id="__EVJS_CLIENT_RUNTIME__"')) {
  throw new Error('missing EVJS browser runtime');
}
if (!indexHtml.includes('"path":"/playground"')) {
  throw new Error('Playground runtime is not mounted at /playground');
}

const headers = await readFile(path.join(clientDir, '_headers'), 'utf8');
for (const directive of [
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval'",
  "frame-ancestors 'none'",
  "object-src 'none'",
  'X-Content-Type-Options: nosniff',
  'X-Frame-Options: DENY',
]) {
  if (!headers.includes(directive)) {
    throw new Error(`missing security header directive: ${directive}`);
  }
}

for (const match of indexHtml.matchAll(/(?:href|src)="([^"]+)"/g)) {
  if (/^https?:\/\//.test(match[1])) {
    throw new Error(`external runtime asset in index.html: ${match[1]}`);
  }
  if (match[1].startsWith('/') && !match[1].startsWith('/playground/')) {
    throw new Error(`root-scoped runtime asset in index.html: ${match[1]}`);
  }
}

if (!indexHtml.includes('src="/playground/')) {
  throw new Error('Playground runtime assets are missing the /playground/ prefix');
}

for (const file of files) {
  if (!textExtensions.has(path.extname(file)) && path.basename(file) !== '_redirects') {
    continue;
  }

  const source = await readFile(file, 'utf8');
  const forbidden = forbiddenText.find((candidate) => source.includes(candidate));
  if (forbidden) {
    const relativePath = path.relative(clientDir, file);
    throw new Error(
      `internal dependency marker ${JSON.stringify(forbidden)} in ${relativePath}`,
    );
  }
}

const wasmSizes = [
  `parser ${(parserWasm.length / 1024 / 1024).toFixed(1)} MiB`,
  ...versionManifest.versions.map(
    (version) =>
      `${version.label} ${(lintWasmSizes.get(version.id) / 1024 / 1024).toFixed(1)} MiB`,
  ),
].join(', ');
console.log(
  `verified static EVJS deployment (${files.length} files, ${wasmSizes})`,
);
