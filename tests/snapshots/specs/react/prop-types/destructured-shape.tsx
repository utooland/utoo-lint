import PropTypes from 'prop-types';
export function Example({ data }) { return <span>{data.name}</span>; }
Example.propTypes = { data: PropTypes.shape({}) };
