import type { Diagnostic, Program } from 'yuku-parser';

export const AST_SOURCE_LENGTH_MAX = 256 * 1024;

export interface ASTParseResult {
  diagnostics: Diagnostic[];
  elapsedMs: number;
  program: Program;
}

export interface ASTWorkerRequest {
  filePath: string;
  id: number;
  source: string;
}

export interface ASTWorkerError {
  message: string;
  name: string;
}

export type ASTWorkerResponse =
  | { id: number; result: ASTParseResult }
  | { error: ASTWorkerError; id: number };

export function normalizeASTWorkerError(error: unknown): ASTWorkerError {
  if (error instanceof Error) {
    return { message: error.message, name: error.name };
  }

  return {
    message: typeof error === 'string' ? error : 'Unknown AST parser error',
    name: 'Error',
  };
}
