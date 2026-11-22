(() => {
  const form = document.getElementById('search-form');
  const input = document.getElementById('search-query');
  const status = document.getElementById('search-status');
  const results = document.getElementById('search-results');
  let index;

  const words = text => text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  const count = (haystack, needle) => haystack.split(needle).length - 1;

  // Title hits outrank heading hits, which outrank body hits. Every term must
  // match somewhere, so adding a word narrows rather than widens the result set.
  function score(doc, terms) {
    const title = doc.title.toLowerCase();
    const body = doc.text.toLowerCase();
    const sections = doc.sections || [];
    let total = 0;
    for (const term of terms) {
      let best = 0;
      if (title === term) best = 60;
      else if (title.startsWith(term)) best = 40;
      else if (title.includes(term)) best = 30;
      for (const section of sections) {
        if (section.title.toLowerCase().includes(term)) best = Math.max(best, 20);
      }
      const hits = count(body, term);
      if (hits) best = Math.max(best, 10 + Math.min(hits, 5));
      if (!best) return 0;
      total += best;
    }
    return total;
  }

  // Prefer the section that mentions the most terms, so the deep link and the
  // snippet point at the same place.
  function excerpt(doc, terms) {
    const sections = doc.sections || [];
    const matches = terms.map(term => term.toLowerCase());
    const ranked = sections
      .map(section => ({section, hits: matches.filter(term => (section.title + ' ' + section.text).toLowerCase().includes(term)).length}))
      .filter(entry => entry.hits > 0)
      .sort((a, b) => b.hits - a.hits);
    const best = ranked[0];
    const text = best ? best.section.text : doc.text;
    const lower = text.toLowerCase();
    let at = -1;
    for (const term of matches) {
      const found = lower.indexOf(term);
      if (found >= 0 && (at < 0 || found < at)) at = found;
    }
    const start = Math.max(0, (at < 0 ? 0 : at) - 70);
    const slice = text.slice(start, start + 200).trim();
    return {
      text: (start > 0 ? '…' : '') + slice + (start + 200 < text.length ? '…' : ''),
      section: best ? best.section : null,
    };
  }

  function highlight(text, terms) {
    const fragment = document.createDocumentFragment();
    const pattern = new RegExp(`(${terms.map(term => term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})`, 'gi');
    let last = 0;
    for (const match of text.matchAll(pattern)) {
      if (match.index > last) fragment.append(text.slice(last, match.index));
      const mark = document.createElement('mark');
      mark.textContent = match[0];
      fragment.append(mark);
      last = match.index + match[0].length;
    }
    if (last < text.length) fragment.append(text.slice(last));
    return fragment;
  }

  function render(entries, terms, query) {
    results.replaceChildren();
    if (!entries.length) {
      status.textContent = `No resources match “${query}”. Try fewer words, or browse the guides from the homepage.`;
      return;
    }
    status.textContent = `${entries.length} ${entries.length === 1 ? 'resource' : 'resources'} found for “${query}”.`;
    for (const entry of entries) {
      const item = document.createElement('li');
      const link = document.createElement('a');
      const {text, section} = excerpt(entry.doc, terms);
      link.href = entry.doc.location + (section && section.id ? '#' + section.id : '');
      const title = document.createElement('strong');
      title.textContent = entry.doc.title;
      link.append(title);
      if (section && section.title) {
        const label = document.createElement('span');
        label.className = 'search-section';
        label.textContent = section.title;
        link.append(label);
      }
      const snippet = document.createElement('span');
      snippet.className = 'search-snippet';
      snippet.append(highlight(text, terms));
      link.append(snippet);
      item.append(link);
      results.append(item);
    }
  }

  async function search() {
    const query = input.value.trim();
    if (!query) return;
    status.textContent = 'Searching…';
    results.replaceChildren();
    try {
      if (!index) {
        const response = await fetch('/search/search_index.json');
        if (!response.ok) throw new Error('Search index unavailable');
        index = (await response.json()).docs;
      }
      const terms = words(query);
      if (!terms.length) {
        status.textContent = 'Enter a word or phrase to search.';
        return;
      }
      const entries = index
        .map(doc => ({doc, score: score(doc, terms)}))
        .filter(entry => entry.score > 0)
        .sort((a, b) => b.score - a.score || a.doc.title.localeCompare(b.doc.title));
      render(entries, terms, query);
      const url = new URL(location.href);
      url.searchParams.set('q', query);
      history.replaceState(null, '', url);
    } catch {
      status.textContent = 'Search is unavailable. Please try again.';
    }
  }

  form.addEventListener('submit', event => { event.preventDefault(); search(); });
  form.hidden = false;
  status.hidden = false;

  // "/" jumps to the search box, unless the reader is already typing somewhere.
  document.addEventListener('keydown', event => {
    if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey) return;
    const target = event.target;
    if (target instanceof HTMLElement && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
    event.preventDefault();
    input.focus();
  });

  const initial = new URLSearchParams(location.search).get('q');
  if (initial) { input.value = initial; search(); }
})();
