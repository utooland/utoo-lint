interface Props { value: string; other: number; }
export function Example(props: Props) {
  const { other } = props;
  return <Child {...props} other={other}/>;
}
