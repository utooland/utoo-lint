export function Example() { function getValue() { return 1; } return useMemo(() => getValue(), []); }
