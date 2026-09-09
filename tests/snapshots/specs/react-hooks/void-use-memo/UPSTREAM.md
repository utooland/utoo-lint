# Upstream coverage: void-use-memo

Reference: React `e92bda78750136493cb324e98df1726f62ba8e92`. These fixtures exercise the compiler validation passes
exposed by `packages/eslint-plugin-react-hooks/src/shared/ReactCompiler.ts`.

- [invalid-useMemo-no-return-value.js](https://github.com/facebook/react/blob/e92bda78750136493cb324e98df1726f62ba8e92/compiler/packages/babel-plugin-react-compiler/src/__tests__/fixtures/compiler/invalid-useMemo-no-return-value.js): 2 native diagnostics.
- [useMemo-empty-return.js](https://github.com/facebook/react/blob/e92bda78750136493cb324e98df1726f62ba8e92/compiler/packages/babel-plugin-react-compiler/src/__tests__/fixtures/compiler/useMemo-empty-return.js): 0 native diagnostics.
- [useMemo-explicit-null-return.js](https://github.com/facebook/react/blob/e92bda78750136493cb324e98df1726f62ba8e92/compiler/packages/babel-plugin-react-compiler/src/__tests__/fixtures/compiler/useMemo-explicit-null-return.js): 0 native diagnostics.

Lowercase fixture entry points are capitalized because the upstream harness explicitly
selects the function to compile, while the linter uses React naming conventions.
Explicit bare returns are accepted, matching the pinned upstream `useMemo-empty-return`
fixture. In current React main, no-value and unused-result checks belong to
`void-use-memo` (recommended-latest), separately from `use-memo` (recommended).

## License for copied fixtures

MIT License

Copyright (c) Meta Platforms, Inc. and affiliates.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
