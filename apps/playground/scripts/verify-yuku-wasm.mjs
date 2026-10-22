import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

// Yuku ships its browser WASM as a base64 string in JavaScript. Audit the
// decoded bytes against the installed package, just as external WASM assets
// are checked, so a missing or changed parser cannot pass deployment checks.
export async function verifyInlineParserWasm(files) {
  const expected = await readFile(new URL(import.meta.resolve('yuku/yuku.wasm')));
  if (!WebAssembly.validate(expected)) {
    throw new Error('installed Yuku parser WebAssembly is invalid');
  }
  const expectedSha256 = createHash('sha256').update(expected).digest('hex');
  let parserWasm;

  for (const file of files) {
    if (path.extname(file) !== '.js') continue;
    const source = await readFile(file, 'utf8');
    for (const match of source.matchAll(/["'](AGFzbQ[A-Za-z0-9+/]*={0,2})["']/g)) {
      if (parserWasm) {
        throw new Error(`duplicate inline parser WebAssembly in ${file}`);
      }
      const contents = Buffer.from(match[1], 'base64');
      const actualSha256 = createHash('sha256').update(contents).digest('hex');
      if (actualSha256 !== expectedSha256) {
        throw new Error(`inline parser WebAssembly does not match installed Yuku: ${file}`);
      }
      parserWasm = contents;
    }
  }

  if (!parserWasm) throw new Error('missing inline parser WebAssembly');
  return parserWasm;
}
