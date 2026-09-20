export function branch(a: unknown) { if (typeof a === 'number') return a + 1; return 0; }
export function guard(a: unknown) { if (typeof a !== 'number') return 0; return a + 1; }
export function text(a: unknown) { if (typeof a === 'string') return a + 'x'; return ''; }
