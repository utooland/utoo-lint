export function implicit(value) { return value + 1; }
export function assertion(value: unknown) { return (value as any).count + 1; }
