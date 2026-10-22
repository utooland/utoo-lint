import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { verifyInlineParserWasm } from './verify-yuku-wasm.mjs';

test('requires exactly one unmodified inline Yuku WASM module', async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), 'utoo-lint-yuku-wasm-'));
  t.after(() => rm(directory, { force: true, recursive: true }));
  const file = path.join(directory, 'parser.js');
  const wasm = await readFile(new URL(import.meta.resolve('yuku/yuku.wasm')));
  const moduleSource = `const wasm = "${wasm.toString('base64')}";`;

  await writeFile(file, moduleSource);
  assert.deepEqual(await verifyInlineParserWasm([file]), wasm);

  await writeFile(file, 'const wasm = undefined;');
  await assert.rejects(verifyInlineParserWasm([file]), /missing inline parser/);

  const changed = Buffer.from(wasm);
  changed[changed.length - 1] ^= 1;
  await writeFile(file, `const wasm = "${changed.toString('base64')}";`);
  await assert.rejects(verifyInlineParserWasm([file]), /does not match installed Yuku/);

  await writeFile(file, `${moduleSource}\n${moduleSource}`);
  await assert.rejects(verifyInlineParserWasm([file]), /duplicate inline parser/);
});
