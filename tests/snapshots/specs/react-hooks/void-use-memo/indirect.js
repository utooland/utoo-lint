const {useMemo: memo} = require('react');
function Component() {
  const calculate = () => {};
  return memo(calculate, []);
}
