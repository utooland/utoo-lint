import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";

import { SourceCode as ESMSourceCode } from "../index.js";

const require = createRequire(import.meta.url);
const { SourceCode: CommonJSSourceCode } = require("../index.cjs");

function fixture(SourceCode) {
  const tokens = [0, 2, 4, 6].map((start) => ({ value: `t${start}`, range: [start, start + 1] }));
  const comments = [
    { value: "first comment", range: [2, 3] },
    { value: "second comment", range: [2, 3] },
    { value: "last comment", range: [5, 6] }
  ];
  return new SourceCode("a b c d", { tokens, comments });
}

for (const [format, SourceCode] of [["ESM", ESMSourceCode], ["CommonJS", CommonJSSourceCode]]) {
  test(`${format} token windows preserve skip, count, boundaries, and token identity`, () => {
    const source = fixture(SourceCode);
    const [a, b, c, d] = source.tokens;
    const whole = { range: [0, 7] };

    assert.equal(source.getFirstToken(whole, 1), b);
    assert.equal(source.getLastToken(whole, 1), c);
    assert.equal(source.getTokenBefore(c), b);
    assert.equal(source.getTokenAfter(b), c);
    assert.equal(source.getTokenBefore(a), null);
    assert.equal(source.getTokenAfter(d), null);
    assert.deepEqual(source.getFirstTokens(whole, { skip: 1, count: 2 }), [b, c]);
    assert.deepEqual(source.getLastTokens(whole, { skip: 1, count: 2 }), [b, c]);
    assert.deepEqual(source.getTokensBefore(d, { skip: 1, count: 2 }), [a, b]);
    assert.deepEqual(source.getTokensAfter(a, { skip: 1, count: 2 }), [c, d]);
    assert.deepEqual(source.getTokensBetween(a, d, 2), [b, c]);
    assert.equal(source.getFirstTokenBetween(a, d, 1), c);
    assert.equal(source.getLastTokenBetween(a, d, 1), b);
    assert.deepEqual(source.getFirstTokensBetween(a, d, 2), [b, c]);
    assert.deepEqual(source.getLastTokensBetween(a, d, 2), [b, c]);
    assert.deepEqual(source.getTokensAfter(a, { count: 0 }), []);
    assert.deepEqual(source.getTokensBefore(d, { skip: 10, count: 2 }), []);
    assert.deepEqual(source.getFirstTokens({ range: [3, 4] }, { beforeCount: 1, afterCount: 1 }), [b, c]);
  });

  test(`${format} token APIs retain their omitted-count defaults`, () => {
    const source = fixture(SourceCode);
    const [a, b, c, d] = source.tokens;
    const whole = { range: [0, 7] };

    for (const node of [whole, undefined]) {
      assert.deepEqual(source.getFirstTokens(node, {}), [a, b, c, d]);
      assert.deepEqual(source.getLastTokens(node, {}), [a, b, c, d]);
      assert.deepEqual(source.getFirstTokens(node, { count: null }), [a]);
      assert.deepEqual(source.getLastTokens(node, { count: null }), [d]);
    }
    assert.deepEqual(source.getTokensAfter(a, {}), [b]);
    assert.deepEqual(source.getTokensBefore(d, {}), [c]);
    assert.deepEqual(source.getTokensBetween(a, d, {}), [b]);
    assert.deepEqual(source.getFirstTokensBetween(a, d, {}), [b]);
    assert.deepEqual(source.getLastTokensBetween(a, d, {}), [c]);
    assert.equal(source.getLastTokens(undefined, {}), source.tokens);
    assert.notEqual(source.getFirstTokens(undefined, {}), source.tokens);
  });

  test(`${format} comments keep stable ordering at equal token starts`, () => {
    const source = fixture(SourceCode);
    const [a, b, c] = source.tokens;
    const [first, second] = source.comments;

    assert.equal(source.getTokenAfter(a, { includeComments: true }), b);
    assert.equal(source.getTokenBefore(c, { includeComments: true }), second);
    assert.equal(source.getTokenOrCommentAfter(a), b);
    assert.equal(source.getTokenOrCommentBefore(c), second);
    assert.equal(source.getTokenAfter(a, { includeComments: true, skip: 1 }), first);
    assert.deepEqual(source.getTokensAfter(a, { includeComments: true, count: 3 }), [b, first, second]);
    assert.deepEqual(source.getTokensBefore(c, { includeComments: true, count: 3 }), [b, first, second]);
  });

  test(`${format} filtered queries visit every candidate in order before skip and count`, () => {
    const source = fixture(SourceCode);
    const [a, b, c, d] = source.tokens;
    const [first, second, last] = source.comments;
    const visited = [];
    const filter = (item) => {
      visited.push(item);
      return item !== first;
    };

    assert.equal(source.getTokenAfter(a, { includeComments: true, filter }), b);
    assert.deepEqual(visited, [b, first, second, c, last, d]);
    visited.length = 0;
    assert.deepEqual(source.getTokensBefore(d, { includeComments: true, filter, count: 0 }), []);
    assert.deepEqual(visited, [a, b, first, second, c, last]);
    visited.length = 0;
    assert.equal(source.getTokenBefore(d, { filter, skip: 1 }), b);
    assert.deepEqual(visited, [a, b, c]);
    assert.throws(() => source.getTokenAfter(a, {
      filter(item) {
        if (item === d) throw new Error("last candidate");
        return true;
      }
    }), /last candidate/u);
  });

  test(`${format} live arrays support unsorted edits, replacements, and missing ranges`, () => {
    const source = fixture(SourceCode);
    const [a, b, c, d] = source.tokens;
    source.tokens.splice(0, 4, c, a, { value: "missing range" }, d, b);

    assert.equal(source.getTokenAfter(a), c);
    assert.equal(source.getTokenBefore(d), b);
    assert.deepEqual(source.getTokensBefore(d, { skip: 1, count: 2 }), [c, a]);
    assert.equal(source.getTokenAfter(a, { includeComments: true }), b);
    const replacement = { value: "replacement", range: [1, 2] };
    source.tokens[source.tokens.indexOf(b)] = replacement;
    assert.equal(source.getTokenAfter(a, { includeComments: true }), replacement);
    replacement.range = [3, 4];
    assert.equal(source.getTokenAfter(a, { includeComments: true }), source.comments[0]);
    source.comments.reverse();
    assert.equal(source.getTokenAfter(a, { includeComments: true }), source.comments[1]);

    const returned = source.getTokensAfter(a, { includeComments: true, count: 2 });
    const expected = [...returned];
    returned.reverse();
    returned.length = 0;
    assert.deepEqual(source.getTokensAfter(a, { includeComments: true, count: 2 }), expected);
    assert.equal(source.getAllTokens(), source.tokens);
  });

  test(`${format} malformed sort keys retain the combined stream's stable-sort behavior`, () => {
    for (const start of [NaN, undefined, Infinity, "2"]) {
      const tokens = [
        { value: "late", range: [6, 7] },
        { value: "malformed", range: [start, 4] },
        { value: "early", range: [2, 3] }
      ];
      const source = new SourceCode("a b c d", { tokens, comments: [{ value: "comment", range: [5, 6] }] });
      const ordered = [...tokens, ...source.comments].sort((left, right) => (left.range[0] ?? 0) - (right.range[0] ?? 0));
      const after = ordered.filter((item) => item.range[0] >= 1);
      const before = ordered.filter((item) => item.range[1] <= 6);

      assert.equal(source.getTokenAfter({ range: [0, 1] }, { includeComments: true }), after[0] ?? null);
      assert.equal(source.getTokenBefore({ range: [6, 7] }, { includeComments: true }), before.at(-1) ?? null);
    }
  });

  test(`${format} index locations preserve line boundaries and clamping`, () => {
    const source = new SourceCode("a\r\nbb\nccc\rdd\u2028ee");
    const cases = [
      [-Infinity, { line: 1, column: 0 }],
      [-1, { line: 1, column: 0 }],
      [2, { line: 1, column: 2 }],
      [3, { line: 2, column: 0 }],
      [5.5, { line: 2, column: 2.5 }],
      [6, { line: 3, column: 0 }],
      [Infinity, { line: 3, column: source.text.length - 6 }],
      [NaN, { line: 1, column: NaN }]
    ];
    for (const [index, expected] of cases) {
      assert.deepEqual(source.getLocFromIndex(index), expected);
    }
    assert.deepEqual(new SourceCode("").getLocFromIndex(1), { line: 1, column: 0 });
    assert.deepEqual(new SourceCode("a\n").getLocFromIndex(2), { line: 2, column: 0 });
  });
}
