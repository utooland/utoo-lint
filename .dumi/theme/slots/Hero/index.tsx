import { Link, useLocale, useRouteMeta } from 'dumi';
import React from 'react';
import SourceCode from '../../builtins/SourceCode';
import NativeLink from '../../components/NativeLink';

interface HeroData {
  title: string;
  accent: string;
  description: string;
}

export default function Hero() {
  const { frontmatter } = useRouteMeta();
  const isChinese = useLocale().id === 'zh-CN';
  if (!frontmatter.hero) return null;
  const hero = frontmatter.hero as HeroData;
  const docs = isChinese ? '/zh-CN' : '';

  return (
    <section
      className="dumi-default-hero product-hero"
      aria-labelledby="product-title"
    >
      <div className="product-container product-hero-content">
        <div className="product-hero-copy">
          <img
            className="product-hero-logo"
            src="/utoo-lint-mark.svg"
            alt={isChinese ? 'UTOO 蓝白兔子标志' : 'UTOO rabbit logo'}
            width="105"
            height="150"
          />
          <h1 id="product-title">
            {hero.title} <span>{hero.accent}</span>
          </h1>
          <p>{hero.description}</p>
          <div className="product-actions">
            <Link
              className="product-button product-button-primary"
              to={`${docs}/quick-start`}
            >
              {isChinese ? '快速开始' : 'Quick Start'}
              <span aria-hidden="true">↗</span>
            </Link>
            <NativeLink className="product-button" href="/playground/">
              {isChinese ? '打开 Playground' : 'Open Playground'}
              <span aria-hidden="true">→</span>
            </NativeLink>
          </div>
          <div className="product-install">
            <SourceCode lang="bash">ut install -D @utoo/lint</SourceCode>
          </div>
        </div>
      </div>
    </section>
  );
}
