type Value = any;
export function alias(a: Value) { return a + 1; }
interface Data { value: any; }
export function property(a: Data) { return a.value + 1; }
