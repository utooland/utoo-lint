import { useMemo } from 'react';
import { log } from './helpers';
const { value } = window.settings;
export function Example() { return useMemo(() => { log(); return value; }, []); }
