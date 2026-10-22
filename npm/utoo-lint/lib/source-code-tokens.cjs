"use strict";

function inRange(item, start, end) {
  return item.range && (start === null || item.range[0] >= start) && (end === null || item.range[1] <= end);
}

function select(items, options, backwards, single) {
  const filtered = options.filter ? items.filter((item) => options.filter(item)) : items;
  if (single) {
    return backwards ? filtered.at(-(options.skip + 1)) ?? null : filtered[options.skip] ?? null;
  }
  if (!backwards) {
    return filtered.slice(options.skip, options.count === null ? undefined : options.skip + options.count);
  }
  if (options.count === 0) {
    return [];
  }
  if (options.count === null && options.skip === 0) {
    return filtered;
  }
  const end = Math.max(0, filtered.length - options.skip);
  const start = options.count === null ? 0 : Math.max(0, end - options.count);
  return filtered.slice(start, end);
}

function collect(sourceCode, options, start, end) {
  if (!options.includeComments) {
    return sourceCode.tokens.filter((item) => inRange(item, start, end));
  }
  // Sort the live arrays for each query: callers can replace, reorder, or edit
  // tokens and comments in place. Equal starts keep tokens before comments.
  const items = [...sourceCode.tokens, ...sourceCode.comments];
  items.sort((left, right) => (left.range?.[0] ?? 0) - (right.range?.[0] ?? 0));
  return items.filter((item) => inRange(item, start, end));
}

/** Select a token window without assuming the public arrays remain sorted. */
function tokenWindow(sourceCode, options, start, end, backwards, single) {
  // A predicate must see every candidate in the same order, even when only
  // one token is requested or count is zero.
  if (options.filter) {
    return select(collect(sourceCode, options, start, end), options, backwards, single);
  }

  if (options.includeComments) {
    if (!single || options.skip !== 0) {
      return select(collect(sourceCode, options, start, end), options, backwards, single);
    }
    // The nearest item in the sorted combined stream can be selected without
    // allocating or sorting it. Scan both arrays to also handle unsorted input.
    let found = null;
    let foundStart = backwards ? -Infinity : Infinity;
    for (const items of [sourceCode.tokens, sourceCode.comments]) {
      for (const item of items) {
        const itemStart = item.range?.[0] ?? 0;
        if (typeof itemStart !== "number" || !Number.isFinite(itemStart)) {
          return select(collect(sourceCode, options, start, end), options, backwards, single);
        }
        if (!inRange(item, start, end)) {
          continue;
        }
        if (backwards ? itemStart >= foundStart : itemStart < foundStart) {
          found = item;
          foundStart = itemStart;
        }
      }
    }
    return found;
  }

  const items = sourceCode.tokens;
  const result = [];
  const count = single ? 1 : options.count;
  if (count === 0) {
    return result;
  }
  let skip = options.skip;
  for (let index = backwards ? items.length - 1 : 0; backwards ? index >= 0 : index < items.length; index += backwards ? -1 : 1) {
    if (!(index in items) || !inRange(items[index], start, end)) {
      continue;
    }
    if (skip > 0) {
      skip -= 1;
      continue;
    }
    if (single) {
      return items[index];
    }
    result.push(items[index]);
    if (count !== null && result.length === count) {
      break;
    }
  }
  return single ? null : backwards ? result.reverse() : result;
}

module.exports = { tokenWindow, selectTokenItems: select };
