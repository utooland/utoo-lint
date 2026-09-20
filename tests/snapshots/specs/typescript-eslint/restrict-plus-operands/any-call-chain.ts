export function dynamic(items: any) { return items.map(value => value).slice(0).map((value, index) => index + 1); }
export function typed(items: number[]) { return items.map(value => value).slice(0).map((value, index) => index + 1); }
