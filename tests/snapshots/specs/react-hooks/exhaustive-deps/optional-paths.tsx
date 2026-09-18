export function Example({data}) { return useMemo(() => data?.items.map(x => x), [data]); }
export function Callback({data}) { return useCallback(() => data.id, [data?.id]); }
