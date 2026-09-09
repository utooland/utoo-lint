function Component({items}) {
  const [previous, setPrevious] = useState(items);
  if (items !== previous) setPrevious(items);
  return <button onClick={() => setPrevious([])} />;
}
