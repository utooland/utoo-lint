/// <reference lib="webworker" />

import {
  AST_SOURCE_LENGTH_MAX,
  normalizeASTWorkerError,
  type ASTWorkerRequest,
  type ASTWorkerResponse,
} from './protocol';

const workerScope = self as unknown as DedicatedWorkerGlobalScope;
type Parser = typeof import('yuku-parser') & { core: import('yuku-parser').Core };
let parserPromise: Promise<Parser> | undefined;

function getParser() {
  if (!parserPromise) {
    const candidate = Promise.all([
      import('yuku-parser'),
      import('@yuku-core/wasm'),
    ]).then(async ([parser, { load }]) => ({ ...parser, core: await load() }));
    parserPromise = candidate;
    void candidate.catch(() => {
      if (parserPromise === candidate) parserPromise = undefined;
    });
  }

  return parserPromise;
}

workerScope.onmessage = async ({ data }: MessageEvent<ASTWorkerRequest>) => {
  const { filePath, id, source } = data;

  try {
    if (source.length > AST_SOURCE_LENGTH_MAX) {
      throw new RangeError(
        `AST input exceeds ${AST_SOURCE_LENGTH_MAX.toLocaleString()} characters`,
      );
    }

    const { core, langFromPath, parse, sourceTypeFromPath } = await getParser();
    const startedAt = performance.now();
    const parsed = parse(source, {
      attachComments: false,
      core,
      lang: langFromPath(filePath),
      preserveParens: true,
      semanticErrors: false,
      sourceType: sourceTypeFromPath(filePath),
    });

    workerScope.postMessage({
      id,
      result: {
        diagnostics: parsed.diagnostics,
        elapsedMs: performance.now() - startedAt,
        program: parsed.program,
      },
    } satisfies ASTWorkerResponse);
  } catch (error) {
    workerScope.postMessage({
      error: normalizeASTWorkerError(error),
      id,
    } satisfies ASTWorkerResponse);
  }
};
