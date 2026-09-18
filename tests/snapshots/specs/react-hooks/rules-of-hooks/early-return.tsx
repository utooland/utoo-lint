import { useEffect } from 'react';
export default function Example({ready}) {
  if (!ready) { return null; }
  useEffect(() => {}, []);
  return null;
}
