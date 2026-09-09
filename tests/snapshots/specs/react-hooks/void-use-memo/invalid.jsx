function Component() {
  return useMemo(() => { console.log('render'); }, []);
}
