#!/usr/bin/env node
// Render the project's Markdown through a small first-party site shell.
const fs = require('node:fs');
const path = require('node:path');
const MarkdownIt = require('markdown-it');
const root = path.resolve(__dirname, '..');
const target = path.resolve(process.argv[2] || path.join(root, 'site'));
const pages = [
  ['Kubernetes / GKE', 'kubernetes/index.md', '/kubernetes/'],
  ['Google Cloud', 'gcp/index.md', '/gcp/'],
  ['Terraform', 'terraform/index.md', '/terraform/'],
  ['GitHub Actions', 'github/index.md', '/github/'],
  ['Secrets', 'secrets/index.md', '/secrets/'],
  ['CI & deploy', 'ci.md', '/ci/'],
  ['Contributing', 'contributing.md', '/contributing/'],
];
const escape = s => s.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const md = new MarkdownIt({html: false, linkify: false});
// Preserve existing Markdown links while exposing stable public routes.
const linkOpen = md.renderer.rules.link_open || ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
  const token = tokens[idx]; const href = token.attrGet('href');
  if (href && !/^(?:[a-z][a-z0-9+.-]*:|\/|#)/i.test(href)) {
    const [file, fragment = ''] = href.split('#');
    const dest = path.posix.normalize(path.posix.join(path.posix.dirname(env.source), file));
    const match = pages.find(p => p[1] === dest);
    if (!match) throw new Error(`Unresolved local link ${href} in ${env.source}`);
    token.attrSet('href', match[2] + (fragment ? '#' + fragment : ''));
  }
  return linkOpen(tokens, idx, options, env, self);
};
const searchItems = [];
for (const [label, source, url] of pages) {
  const markdown = fs.readFileSync(path.join(root, 'docs', source), 'utf8');
  const env = {source}; const tokens = md.parse(markdown, env); const ids = new Map(); const toc = [];
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type !== 'heading_open') continue;
    const text = tokens[i + 1].content.replace(/[`*_]/g, '');
    const base = text.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, '').trim().replace(/\s+/g, '-') || 'section';
    const count = ids.get(base) || 0; ids.set(base, count + 1);
    const id = count ? `${base}-${count}` : base; tokens[i].attrSet('id', id);
    if (tokens[i].tag === 'h2') toc.push([id, text]);
  }
  const content = md.renderer.render(tokens, md.options, env);
  const plain = tokens.filter(t => t.type === 'inline').map(t => t.content).join(' ');
  searchItems.push({title: label, location: url, text: plain});
  const links = pages.map(([name,,href]) => `<li><a href="${href}"${href === url ? ' aria-current="page"' : ''}>${escape(name)}</a></li>`).join('');
  const sections = toc.map(([id, text]) => `<li><a href="#${escape(id)}">${escape(text)}</a></li>`).join('');
  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="theme-color" content="#101211">
  <title>${escape(label)} | Security Toolbox</title>
  <link rel="stylesheet" href="/home.css">
  <link rel="stylesheet" href="/guides.css">
  <script src="/theme.js" defer></script>
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <header class="site-header"><div class="wrap header-inner">
    <a class="brand" href="/"><span class="brand-mark" aria-hidden="true"></span>Security Toolbox</a>
    <div class="header-actions">
      <a class="repo-link" href="/search/">Search</a>
      <a class="repo-link" href="https://github.com/greenblacked/security-toolbox">GitHub ↗</a>
      <button type="button" id="theme-toggle" hidden>Theme</button>
    </div>
  </div></header>
  <div class="wrap guide-layout">
    <aside class="guide-sidebar"><nav aria-label="Guide navigation"><ul>${links}</ul></nav></aside>
    <main id="main"><article class="guide-content">${content}</article></main>
    <aside class="guide-toc"><nav aria-label="On this page"><strong>On this page</strong><ul>${sections}</ul></nav></aside>
  </div>
  <footer class="site-footer"><div class="wrap footer-inner">
    <a href="/">Security Toolbox</a>
    <a href="https://github.com/greenblacked/security-toolbox">View on GitHub ↗</a>
  </div></footer>
</body></html>`;
  const output = path.join(target, url, 'index.html'); fs.mkdirSync(path.dirname(output), {recursive:true}); fs.writeFileSync(output, html);
}

const searchDir = path.join(target, 'search');
fs.mkdirSync(searchDir, {recursive: true});
fs.writeFileSync(path.join(searchDir, 'search_index.json'), JSON.stringify({docs: searchItems}));
