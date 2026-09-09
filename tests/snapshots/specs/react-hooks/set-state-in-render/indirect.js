const {useState: state} = require('react');
function Component() {
  const [, setter] = state(0);
  const update = setter;
  for (let i = 0; i < 3; i++) {}
  update(1);
  return null;
}
