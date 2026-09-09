function Component() {
  const [count, setCount] = useState(0);
  setCount(1);
  return <div>{count}</div>;
}
