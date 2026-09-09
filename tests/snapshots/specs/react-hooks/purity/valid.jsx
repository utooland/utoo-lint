function Component() {
  const [time] = useState(() => Date.now());
  return <button onClick={() => console.log(Math.random())}>{time}</button>;
}
