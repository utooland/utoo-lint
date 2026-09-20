import React from 'react';
type Props = { name: string };
export const Example = React.forwardRef<HTMLDivElement, Props>((props, ref) => <div ref={ref}>{props.name}</div>);
