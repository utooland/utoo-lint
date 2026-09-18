type Data = { name: string; unused: string };
export function Example(props: { data: Data }) {
  const { data } = props;
  const { name } = data || {};
  return <span>{name}</span>;
}
