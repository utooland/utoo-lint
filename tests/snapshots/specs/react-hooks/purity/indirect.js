const {useMemo: memo} = require('react');
const random = Math.random;
const calculate = () => random();
function Component() {
  return memo(calculate, []);
}
