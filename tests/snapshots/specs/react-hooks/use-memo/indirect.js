const {useMemo: memo} = require('react');
const calculate = async value => value;
function Component() {
  return memo(calculate, []);
}
