#!/usr/bin/env node
// Render the project's Markdown through a small first-party site shell.
const fs = require('node:fs');
const path = require('node:path');
const MarkdownIt = require('markdown-it');
const root = path.resolve(__dirname, '..');
const target = path.resolve(process.argv[2] || path.join(root, 'site'));
const skills = ['access-review', 'certificate-automation', 'compromise-evidence-preservation', 'dependency-triage', 'detection-engineering', 'host-hardening', 'iac-review', 'image-hardening', 'secret-rotation', 'security-review', 'threat-model'];
const pages = [
  ['Kubernetes / GKE', 'docs/kubernetes/index.md', '/kubernetes/'],
  ['Google Cloud', 'docs/gcp/index.md', '/gcp/'],
  ['Terraform', 'docs/terraform/index.md', '/terraform/'],
  ['GitHub Actions', 'docs/github/index.md', '/github/'],
  ['Secrets', 'docs/secrets/index.md', '/secrets/'],
  ['CI & deploy', 'docs/ci.md', '/ci/'],
  ['Contributing', 'docs/contributing.md', '/contributing/'],
  ['Checks', 'checks/README.md', '/checks/'],
  ['GKE hardening check', 'checks/gke/README.md', '/checks/gke/'],
  ['Kubernetes workload check', 'checks/kubernetes/README.md', '/checks/kubernetes/'],
  ['GitHub Actions hardening check', 'checks/github/actions-hardening.md', '/checks/github-actions/'],
  ['Policies', 'policies/README.md', '/policies/'],
  ['Terraform GCP policy', 'docs/policies/terraform.md', '/policies/terraform/'],
  ['Kubernetes pod security policy', 'docs/policies/kubernetes.md', '/policies/kubernetes/'],
  ['Checkov GCP checks', 'docs/policies/checkov.md', '/policies/checkov/'],
  ['Security skills', 'docs/skills/index.md', '/skills/'],
  ...skills.map(name => [name === 'iac-review' ? 'IaC Review' : name.split('-').map(w => w[0].toUpperCase() + w.slice(1)).join(' '), `docs/skills/${name}.md`, `/skills/${name}/`]),
];
const aliases = {
  'checks/gke/': '/checks/gke/', 'checks/kubernetes/': '/checks/kubernetes/',
  'checks/github/': '/checks/github-actions/', 'policies/': '/policies/',
  'checks/gke/gke-report.sh': '/checks/gke/', 'checks/kubernetes/cis-workload-report.sh': '/checks/kubernetes/',
  'policies/opa/terraform/gcp.rego': '/policies/terraform/',
  'policies/opa/kubernetes/pod_security.rego': '/policies/kubernetes/',
  'policies/checkov/checks': '/policies/checkov/',
  ...Object.fromEntries(skills.map(name => [`plugins/security/skills/${name}/SKILL.md`, `/skills/${name}/`])),
};
const navigation = pages.filter(p => ['/kubernetes/', '/gcp/', '/terraform/', '/github/', '/secrets/', '/checks/', '/policies/', '/skills/', '/ci/', '/contributing/'].includes(p[2]));
const escape = s => s.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const md = new MarkdownIt({html: false, linkify: false});
// Preserve existing Markdown links while exposing stable public routes.
const linkOpen = md.renderer.rules.link_open || ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
  const token = tokens[idx]; const href = token.attrGet('href');
  if (href) {
    const own = ['https://github.com/greenblacked/security-toolbox/blob/main/', 'https://github.com/greenblacked/security-toolbox/tree/main/'].find(prefix => href.startsWith(prefix));
    const relative = !/^(?:[a-z][a-z0-9+.-]*:|\/|#)/i.test(href);
    if (relative || own) {
      const [file, fragment = ''] = (relative ? href : href.slice(own.length)).split('#');
      const dest = relative ? path.posix.normalize(path.posix.join(path.posix.dirname(env.source), file)) : file;
      const normalized = dest.endsWith('/') ? dest : dest + '/';
      const match = pages.find(p => p[1] === dest);
      const route = (dest === 'policies/README.md' ? '/policies/' : null) || aliases[dest] || aliases[normalized] || (match && match[2]);
      if (!route) throw new Error(`Unresolved local link ${href} in ${env.source}`);
      token.attrSet('href', route + (fragment ? '#' + fragment : ''));
    }
  }
  return linkOpen(tokens, idx, options, env, self);
};
// Keep the table's native layout and semantics inside a locally scrollable container.
md.renderer.rules.table_open = () => '<div class="table-scroll" role="region" aria-label="Scrollable table" tabindex="0">\n<table>\n';
md.renderer.rules.table_close = () => '</table>\n</div>\n';
const searchItems = [];
for (const [label, source, url] of pages) {
  let markdown = fs.readFileSync(path.join(root, source), 'utf8');
  if (url === '/policies/') markdown += '\n## Policy details\n\n- [Terraform GCP policy](/policies/terraform/)\n- [Kubernetes pod security policy](/policies/kubernetes/)\n- [Checkov GCP checks](/policies/checkov/)\n';
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
  const links = navigation.map(([name,,href]) => `<li><a href="${href}"${href === url ? ' aria-current="page"' : ''}>${escape(name)}</a></li>`).join('');
  const sections = toc.map(([id, text]) => `<li><a href="#${escape(id)}">${escape(text)}</a></li>`).join('');
  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="description" content="Security Toolbox guidance for ${escape(label)}.">
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
      <a class="repo-link" href="https://github.com/greenblacked/security-toolbox">GitHub <span aria-hidden="true">↗</span></a>
      <button type="button" id="theme-toggle" hidden>Theme</button>
    </div>
  </div></header>
  <div class="wrap guide-layout">
    <aside class="guide-sidebar"><nav aria-label="Guide navigation"><ul>${links}</ul></nav></aside>
    <details class="guide-menu"><summary>Guide navigation</summary><nav aria-label="Guide navigation"><ul>${links}</ul></nav></details>
    <main id="main" tabindex="-1">
      ${sections ? `<details class="guide-jump"><summary>On this page</summary><ul>${sections}</ul></details>` : ''}
      <article class="guide-content">${content}</article>
    </main>
    ${sections ? `<aside class="guide-toc"><nav aria-label="On this page"><strong>On this page</strong><ul>${sections}</ul></nav></aside>` : ''}
  </div>
  <footer class="site-footer"><div class="wrap footer-inner">
    <a class="brand" href="/"><span class="brand-mark" aria-hidden="true"></span>Security Toolbox</a>
    <a href="https://github.com/greenblacked/security-toolbox">View on GitHub <span aria-hidden="true">↗</span></a>
  </div></footer>
</body></html>`;
  const output = path.join(target, url, 'index.html'); fs.mkdirSync(path.dirname(output), {recursive:true}); fs.writeFileSync(output, html);
}

const searchDir = path.join(target, 'search');
fs.mkdirSync(searchDir, {recursive: true});
fs.writeFileSync(path.join(searchDir, 'search_index.json'), JSON.stringify({docs: searchItems}));
