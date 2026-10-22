/// <reference lib="webworker" />

import {
  AST_SOURCE_LENGTH_MAX,
  normalizeASTWorkerError,
  type ASTWorkerRequest,
  type ASTWorkerResponse,
} from './protocol';

const workerScope = self as unknown as DedicatedWorkerGlobalScope;
type Parser = typeof import('yuku');
let parserPromise: Promise<Parser> | undefined;

function getParser() {
  if (!parserPromise) {
    const candidate = import('yuku');
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

    const { parse } = await getParser();
    const startedAt = performance.now();
    const parsed = parse(source, {
      attachComments: false,
      path: filePath,
      preserveParens: true,
      semanticErrors: false,
    });
    // SourceFile decodes its AST lazily; include that work in the parse time.
    const { diagnostics, program } = parsed;

    workerScope.postMessage({
      id,
      result: {
        diagnostics,
        elapsedMs: performance.now() - startedAt,
        program,
      },
    } satisfies ASTWorkerResponse);
  } catch (error) {
    workerScope.postMessage({
      error: normalizeASTWorkerError(error),
      id,
    } satisfies ASTWorkerResponse);
  }
};
