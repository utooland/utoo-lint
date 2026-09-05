import { useLocale } from 'dumi';
import React, { useState } from 'react';
import SourceCode from '../../builtins/SourceCode';

const before = `function greet(name: string) {
  let message = \`Hello, \${name}\`;;
  const messages = new Array(message, 'Welcome');
  return { messages: messages };
}`;
const after = `function greet(name: string) {
  const message = \`Hello, \${name}\`;
  const messages = [message, 'Welcome'];
  return { messages };
}`;

export default function AutofixExample() {
  const isChinese = useLocale().id === 'zh-CN';
  const [fixed, setFixed] = useState(false);
  return (
    <div className="product-demo">
      <div className="product-demo-title">
        <span>
          <span className="product-code-symbol" aria-hidden="true">
            {'</>'}
          </span>{' '}
          index.ts
        </span>
        <span>TypeScript</span>
      </div>
      <div className="product-demo-tools">
        <span>{isChinese ? '自动修复示例' : 'Autofix example'}</span>
        <div
          role="group"
          aria-label={isChinese ? '查看修复示例' : 'View autofix example'}
        >
          <button
            type="button"
            aria-pressed={!fixed}
            onClick={() => setFixed(false)}
          >
            {isChinese ? '修复前' : 'Before'}
          </button>
          <button
            type="button"
            aria-pressed={fixed}
            onClick={() => setFixed(true)}
          >
            {isChinese ? '修复后' : 'After fix'}
          </button>
        </div>
      </div>
      <SourceCode lang="typescript">{fixed ? after : before}</SourceCode>
      <div className="product-demo-result" data-fixed={fixed} role="status">
        <span className="product-demo-status" aria-hidden="true">
          {fixed ? '✓' : '!'}
        </span>
        <div>
          <strong>
            {fixed
              ? isChinese
                ? '4 处问题，已全部修复。'
                : 'Four fixes. Cleaner code.'
              : isChinese
                ? '4 处可自动修复的问题'
                : '4 diagnostics with safe autofixes'}
          </strong>
        </div>
      </div>
    </div>
  );
}
