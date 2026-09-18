export function Example({items, inputRef}) {
  const result = useMemo(() => items.map(x => x), []);
  useEffect(() => { inputRef.current = 1; }, []);
  return result;
}
