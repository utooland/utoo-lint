import type { Data } from './types';
export function Example({ value, items, data }: { value: string; items: string[]; data: Data }) {
  return <span>{value.slice(1)}{items.length}{items.map(x => x)}{data.name}</span>;
}
