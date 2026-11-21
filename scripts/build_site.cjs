#!/usr/bin/env node
// Render the project's Markdown through a small first-party site shell.
//
// Sources stay where they are: guides in docs/, checks and policies beside their
// code, skill procedures in plugins/. This script is the only place that knows
// which sources become public routes, so a new page is added once, here.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const MarkdownIt = require('markdown-it');

const root = path.resolve(__dirname, '..');
const target = path.resolve(process.argv[2] || path.join(root, 'site'));
const siteUrl = 'https://security.szolotov.com';
const repoUrl = 'https://github.com/greenblacked/security-toolbox';

const escape = s => String(s).replace(/[&<>"']/g, c => ({'&': '&amp;','<': '&lt;','>': '&gt;','"': '&quot;',"'": '&#39;'}[c]));
const titleCase = s => s.split('-').map(w => w ? w[0].toUpperCase() + w.slice(1) : w).join(' ');

/** Split YAML front matter from the body. Skills carry name/description there. */
function frontMatter(text) {
  const match = /^---\r?\n([\s\S]*?)\r?\n---[ \t]*\r?\n?/.exec(text);
  if (!match) return {data: {}, body: text};
  const data = {};
  for (const line of match[1].split(/\r?\n/)) {
    const pair = /^([A-Za-z0-9_-]+):[ \t]*(.*)$/.exec(line);
    if (!pair) continue;
    let value = pair[2].trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      try { value = JSON.parse(value); } catch { value = value.slice(1, -1); }
    }
    data[pair[1]] = value;
  }
  return {data, body: text.slice(match[0].length)};
}

const firstHeading = text => ((/^#[ \t]+(.+)$/m.exec(text) || [null, ''])[1] || '').trim();

/** The description's leading clause, before its "Use when" trigger list. */
function summarise(description, body) {
  const clause = description ? description.split(/\s+Use when\s+/)[0].trim() : '';
  if (clause) return clause;
  const paragraph = body.split(/\r?\n\r?\n/).find(block => block.trim() && !block.startsWith('#') && !block.startsWith('-'));
  return paragraph ? paragraph.trim().replace(/\s+/g, ' ') : '';
}

// ---------------------------------------------------------------- page manifest
const pages = [];
const add = (group, label, source, url, extra = {}) => {
  pages.push({group, label, source, url, ...extra});
};

add('guides', 'Kubernetes / GKE', 'docs/kubernetes/index.md', '/kubernetes/');
add('guides', 'Google Cloud', 'docs/gcp/index.md', '/gcp/');
add('guides', 'Terraform', 'docs/terraform/index.md', '/terraform/');
add('guides', 'GitHub Actions', 'docs/github/index.md', '/github/');
add('guides', 'Secrets', 'docs/secrets/index.md', '/secrets/');

add('checks', 'Checks', 'checks/README.md', '/checks/');
add('checks', 'GKE hardening check', 'checks/gke/README.md', '/checks/gke/');
add('checks', 'Kubernetes workload check', 'checks/kubernetes/README.md', '/checks/kubernetes/');
add('checks', 'GitHub Actions checklist', 'checks/github/actions-hardening.md', '/checks/github-actions/');

add('policies', 'Policies', 'policies/README.md', '/policies/');
add('policies', 'Terraform GCP policy', 'docs/policies/terraform.md', '/policies/terraform/');
add('policies', 'Kubernetes pod security policy', 'docs/policies/kubernetes.md', '/policies/kubernetes/');
add('policies', 'Checkov GCP checks', 'docs/policies/checkov.md', '/policies/checkov/');

add('project', 'CI and deploy', 'docs/ci.md', '/ci/');
add('project', 'Contributing', 'docs/contributing.md', '/contributing/');
add('project', 'About this project', 'docs/index.md', '/about/');

// Skills are published from the plugin that ships them: SKILL.md is the page and
// each references/*.md is a sub-page, so the procedure a reader gets here is the
// same one an agent loads.
const SKILL_LABELS = {'iac-review': 'IaC Review', 'threat-model': 'Threat Model'};
const skillDir = path.join(root, 'plugins/security/skills');
const skillNames = fs.readdirSync(skillDir, {withFileTypes: true})
  .filter(entry => entry.isDirectory()).map(entry => entry.name).sort();

const skills = skillNames.map(name => {
  const source = `plugins/security/skills/${name}/SKILL.md`;
  const {data, body} = frontMatter(fs.readFileSync(path.join(root, source), 'utf8'));
  return {
    name,
    source,
    body,
    url: `/skills/${name}/`,
    label: SKILL_LABELS[name] || titleCase(name),
    title: firstHeading(body) || titleCase(name),
    summary: summarise(data.description || '', body),
  };
});

const references = skills.flatMap(skill => {
  const dir = path.join(skillDir, skill.name, 'references');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter(file => file.endsWith('.md')).sort().map(file => {
    const source = `plugins/security/skills/${skill.name}/references/${file}`;
    const body = frontMatter(fs.readFileSync(path.join(root, source), 'utf8')).body;
    return {
      skill: skill.name,
      source,
      body,
      url: `/skills/${skill.name}/${file.replace(/\.md$/, '')}/`,
      // The H1 is a sentence describing the reference; the filename is the label.
      label: titleCase(file.replace(/\.md$/, '')),
    };
  });
});

const skillsIndex = [
  '# Security skills',
  '',
  'Defensive review procedures adapted from the Security plugin. Each page is the full procedure,',
  'with its reference files, rather than a summary.',
  '',
  ...skills.map(skill => `- [${skill.label}](${skill.url}): ${skill.summary}`),
].join('\n');

add('skills', 'Security skills', null, '/skills/', {markdown: skillsIndex});
for (const skill of skills) {
  add('skills', skill.label, skill.source, skill.url, {markdown: skill.body});
  for (const reference of references.filter(item => item.skill === skill.name)) {
    add('skills', reference.label, reference.source, reference.url, {
      markdown: reference.body, reference: true, parent: skill.url,
    });
  }
}

const GROUP_LABELS = {
  guides: 'Guides', checks: 'Checks', policies: 'Policies', skills: 'Skills', project: 'Project',
};

// Existing Markdown links that point at repository paths keep working.
const aliases = {
  'checks/gke/': '/checks/gke/', 'checks/kubernetes/': '/checks/kubernetes/',
  'checks/github/': '/checks/github-actions/', 'policies/': '/policies/',
  'checks/gke/gke-report.sh': '/checks/gke/',
  'checks/kubernetes/cis-workload-report.sh': '/checks/kubernetes/',
  'policies/opa/terraform/gcp.rego': '/policies/terraform/',
  'policies/opa/kubernetes/pod_security.rego': '/policies/kubernetes/',
  'policies/checkov/checks': '/policies/checkov/',
  ...Object.fromEntries(skills.map(skill => [skill.source, skill.url])),
};
const bySource = new Map(pages.filter(page => page.source).map(page => [page.source, page.url]));
const routes = new Set(['/', '/search/', ...pages.map(page => page.url)]);

// ------------------------------------------------------------------- rendering
const md = new MarkdownIt({html: false, linkify: false});

const linkOpen = md.renderer.rules.link_open ||
  ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
  const token = tokens[idx];
  const href = token.attrGet('href');
  if (href) {
    const own = [
      'https://github.com/greenblacked/security-toolbox/blob/main/',
      'https://github.com/greenblacked/security-toolbox/tree/main/',
    ].find(prefix => href.startsWith(prefix));
    const relative = !/^(?:[a-z][a-z0-9+.-]*:|\/|#)/i.test(href);
    if (relative || own) {
      const [file, fragment = ''] = (relative ? href : href.slice(own.length)).split('#');
      const dest = relative
        ? path.posix.normalize(path.posix.join(path.posix.dirname(env.source), file))
        : file;
      const normalized = dest.endsWith('/') ? dest : dest + '/';
      const route = aliases[dest] || aliases[normalized] || bySource.get(dest);
      if (!route) throw new Error(`Unresolved local link ${href} in ${env.source}`);
      token.attrSet('href', route + (fragment ? '#' + fragment : ''));
    } else if (href.startsWith('/')) {
      // Absolute internal links never passed through the resolver before, so a
      // renamed route could ship a 404. Validate them the same way.
      const pathname = href.split('#')[0].split('?')[0];
      const asset = /\.[a-z0-9]+$/i.test(pathname);
      if (pathname && !asset && !routes.has(pathname)) {
        throw new Error(`Unresolved absolute link ${href} in ${env.source}`);
      }
    }
  }
  return linkOpen(tokens, idx, options, env, self);
};
// Keep the table's native layout and semantics inside a locally scrollable container.
md.renderer.rules.table_open = () => '<div class="table-scroll" role="region" aria-label="Scrollable table" tabindex="0">\n<table>\n';
md.renderer.rules.table_close = () => '</table>\n</div>\n';

const plainText = content => content.replace(/\s+/g, ' ').trim();

/** Text of an inline token without Markdown syntax: link targets, backticks. */
const inlineText = token => plainText((token.children || [])
  .map(child => (child.type === 'text' || child.type === 'code_inline') ? child.content : (child.type === 'softbreak' || child.type === 'hardbreak') ? ' ' : '')
  .join(''));

/** The page's own first paragraph, used for the description and social cards. */
function leadParagraph(tokens) {
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type !== 'paragraph_open') continue;
    const inline = tokens[i + 1];
    if (inline && inline.type === 'inline') {
      const text = inlineText(inline);
      if (text) return text;
    }
  }
  return '';
}

function truncate(text, limit = 155) {
  if (text.length <= limit) return text;
  return text.slice(0, limit - 1).replace(/[\s,;:]+\S*$/, '') + '…';
}

function lastUpdated(source) {
  if (!source) return null;
  // A checkout without history (shallow clone, exported tree) simply has no date
  // to show; keep git's stderr out of the build log either way.
  const options = {cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']};
  try {
    if (execFileSync('git', ['rev-parse', '--is-shallow-repository'], options).trim() === 'true') return null;
    return execFileSync('git', ['log', '-1', '--format=%cs', '--', source], options).trim() || null;
  } catch {
    return null;
  }
}

const searchItems = [];
const sitemap = [];

for (const page of pages) {
  const source = page.source || 'generated';
  let markdown = page.markdown;
  if (markdown === undefined) markdown = fs.readFileSync(path.join(root, page.source), 'utf8');
  if (page.url === '/policies/') {
    markdown += '\n## Policy details\n\n- [Terraform GCP policy](/policies/terraform/)\n- [Kubernetes pod security policy](/policies/kubernetes/)\n- [Checkov GCP checks](/policies/checkov/)\n';
  }
  const env = {source};
  const tokens = md.parse(markdown, env);
  const ids = new Map();
  const toc = [];
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type !== 'heading_open') continue;
    const text = inlineText(tokens[i + 1]).replace(/[`*_]/g, '');
    const base = text.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, '').trim().replace(/\s+/g, '-') || 'section';
    const count = ids.get(base) || 0;
    ids.set(base, count + 1);
    const id = count ? `${base}-${count}` : base;
    tokens[i].attrSet('id', id);
    if (tokens[i].tag === 'h2') toc.push([id, text]);
  }
  const content = md.renderer.render(tokens, md.options, env);

  // Search: the page plus one entry per H2 so a hit can deep-link to its section.
  const sections = [];
  let section = null;
  for (const token of tokens) {
    if (token.type === 'heading_open' && token.tag === 'h2') {
      section = {id: token.attrGet('id'), title: '', text: ''};
      sections.push(section);
    } else if (token.type === 'inline') {
      if (section) section.text += ' ' + inlineText(token);
    }
  }
  for (const entry of sections) {
    const heading = toc.find(([id]) => id === entry.id);
    entry.title = heading ? heading[1] : '';
    entry.text = plainText(entry.text);
  }
  const bodyText = plainText(tokens.filter(token => token.type === 'inline').map(inlineText).join(' '));
  searchItems.push({title: page.label, location: page.url, text: bodyText, sections});
  sitemap.push(page.url);

  const description = truncate(leadParagraph(tokens) || page.label);
  const canonical = siteUrl + page.url;
  const navCurrent = page.parent || page.url;

  const nav = Object.entries(GROUP_LABELS).map(([group, groupLabel]) => {
    const links = pages.filter(item => item.group === group && !item.reference)
      .map(item => `<li><a href="${item.url}"${item.url === navCurrent ? ' aria-current="page"' : ''}>${escape(item.label)}</a></li>`)
      .join('');
    return `<li class="nav-group"><span class="nav-group-label">${escape(groupLabel)}</span><ul>${links}</ul></li>`;
  }).join('');

  const crumbs = [`<li><a href="/">Home</a></li>`];
  if (page.reference) {
    const parent = pages.find(item => item.url === page.parent);
    crumbs.push(`<li><a href="/skills/">Skills</a></li>`);
    crumbs.push(`<li><a href="${page.parent}">${escape(parent ? parent.label : 'Skills')}</a></li>`);
  } else if (page.group === 'skills') {
    if (page.url !== '/skills/') crumbs.push(`<li><a href="/skills/">Skills</a></li>`);
  } else {
    crumbs.push(`<li><span>${escape(GROUP_LABELS[page.group])}</span></li>`);
  }
  crumbs.push(`<li><span aria-current="page">${escape(page.label)}</span></li>`);

  const siblings = pages.filter(item => item.group === page.group);
  const index = siblings.findIndex(item => item.url === page.url);
  const previous = index > 0 ? siblings[index - 1] : null;
  const next = index >= 0 && index < siblings.length - 1 ? siblings[index + 1] : null;
  const pager = (previous || next) ? `<nav class="page-nav" aria-label="Previous and next pages">
      ${previous ? `<a class="page-nav-link" href="${previous.url}" rel="prev"><span aria-hidden="true">←</span><span><small>Previous</small>${escape(previous.label)}</span></a>` : '<span></span>'}
      ${next ? `<a class="page-nav-link next" href="${next.url}" rel="next"><span><small>Next</small>${escape(next.label)}</span><span aria-hidden="true">→</span></a>` : ''}
    </nav>` : '';

  const references_ = page.url.startsWith('/skills/') && !page.reference
    ? references.filter(item => `/skills/${item.skill}/` === page.url)
    : [];
  const referenceList = references_.length
    ? `<aside class="reference-list" aria-labelledby="reference-title">
      <h2 id="reference-title">Reference files</h2>
      <ul>${references_.map(item => `<li><a href="${item.url}">${escape(item.label)}</a></li>`).join('')}</ul>
    </aside>`
    : '';

  const updated = lastUpdated(page.source);
  const editLink = page.source
    ? `<a href="${repoUrl}/blob/main/${page.source}">Edit this page on GitHub <span aria-hidden="true">↗</span></a>`
    : '';
  const footer = (editLink || updated)
    ? `<footer class="guide-footer">${editLink}${updated ? `<span class="updated">Last updated <time datetime="${updated}">${updated}</time></span>` : ''}</footer>`
    : '';

  const tocList = toc.map(([id, text]) => `<li><a href="#${escape(id)}">${escape(text)}</a></li>`).join('');

  const structuredData = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'TechArticle',
    headline: page.label,
    description,
    url: canonical,
    isPartOf: {'@type': 'WebSite', name: 'Security Toolbox', url: siteUrl + '/'},
  }).replace(/</g, '\\u003c');

  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="description" content="${escape(description)}">
  <title>${escape(page.label)} | Security Toolbox</title>
  <link rel="canonical" href="${escape(canonical)}">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="Security Toolbox">
  <meta property="og:title" content="${escape(page.label)} | Security Toolbox">
  <meta property="og:description" content="${escape(description)}">
  <meta property="og:url" content="${escape(canonical)}">
  <meta name="twitter:card" content="summary">
  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
  <script src="/boot.js"></script>
  <link rel="stylesheet" href="/home.css">
  <link rel="stylesheet" href="/guides.css">
  <script src="/theme.js" defer></script>
  <script src="/motion.js" defer></script>
  <script type="application/ld+json">${structuredData}</script>
</head>
<body>
  <div class="scroll-progress" aria-hidden="true"><span></span></div>
  <a class="skip" href="#main">Skip to content</a>
  <header class="site-header"><div class="wrap header-inner">
    <a class="brand" href="/"><span class="brand-mark" aria-hidden="true"></span>Security Toolbox</a>
    <div class="header-actions">
      <a class="repo-link" href="/search/">Search</a>
      <a class="repo-link" href="${repoUrl}">GitHub <span aria-hidden="true">↗</span></a>
      <button type="button" id="theme-toggle" hidden>Theme</button>
    </div>
  </div></header>
  <div class="wrap guide-layout">
    <aside class="guide-sidebar"><nav aria-label="Guide navigation"><ul class="nav-groups">${nav}</ul></nav></aside>
    <details class="guide-menu"><summary>Guide navigation</summary><nav aria-label="Guide navigation"><ul class="nav-groups">${nav}</ul></nav></details>
    <main id="main" tabindex="-1">
      <nav class="breadcrumb" aria-label="Breadcrumb"><ol>${crumbs.join('')}</ol></nav>
      ${toc.length ? `<details class="guide-jump"><summary>On this page</summary><ul>${tocList}</ul></details>` : ''}
      <article class="guide-content" data-reveal>${content}${referenceList}</article>
      ${footer}
      ${pager}
    </main>
    ${toc.length ? `<aside class="guide-toc"><nav aria-label="On this page"><strong>On this page</strong><ul>${tocList}</ul></nav></aside>` : ''}
  </div>
  <footer class="site-footer"><div class="wrap footer-inner">
    <a class="brand" href="/"><span class="brand-mark" aria-hidden="true"></span>Security Toolbox</a>
    <div class="footer-links">
      <a href="${repoUrl}">View on GitHub <span aria-hidden="true">↗</span></a>
      <a href="/contributing/">Contribute a guide</a>
      <a href="/about/">About</a>
    </div>
  </div></footer>
</body></html>`;

  const output = path.join(target, page.url, 'index.html');
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, html);
}

// ------------------------------------------------------------------- artifacts
const searchDir = path.join(target, 'search');
fs.mkdirSync(searchDir, {recursive: true});
fs.writeFileSync(path.join(searchDir, 'search_index.json'), JSON.stringify({docs: searchItems}));

const sitemapEntries = ['/', ...sitemap].map(url => `  <url><loc>${escape(siteUrl + url)}</loc></url>`).join('\n');
fs.writeFileSync(path.join(target, 'sitemap.xml'),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${sitemapEntries}\n</urlset>\n`);
