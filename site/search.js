(() => {
  if (/^\/search\/?$/.test(location.pathname)) {
    const home = new URL('/', location.origin);
    const query = new URLSearchParams(location.search).get('q');
    if (query) home.searchParams.set('q', query);
    location.replace(home);
    return;
  }

  const dialog = document.createElement('dialog');
  dialog.id = 'site-search';
  dialog.setAttribute('aria-labelledby', 'search-title');
  dialog.innerHTML = `
    <div class="search-heading">
      <h2 id="search-title">Search guides</h2>
      <button type="button" class="search-close" aria-label="Close search">×</button>
    </div>
    <form role="search">
      <label for="search-query">Search terms</label>
      <input id="search-query" name="q" type="search" autocomplete="off" autofocus>
    </form>
    <p id="search-status" role="status"></p>
    <ul id="search-results"></ul>`;
  document.body.append(dialog);

  const form = dialog.querySelector('form');
  const input = dialog.querySelector('input');
  const status = dialog.querySelector('#search-status');
  const results = dialog.querySelector('#search-results');
  let indexRequest;
  let returnFocus;

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

  function loadIndex() {
    indexRequest ||= fetch('/search/search_index.json')
      .then(response => {
        if (!response.ok) throw new Error('Search index unavailable');
        return response.json();
      })
      .then(data => data.docs)
      .catch(error => {
        indexRequest = undefined;
        throw error;
      });
    return indexRequest;
  }

  async function search() {
    const query = input.value.trim();
    const terms = words(query);
    results.replaceChildren();
    if (!terms.length) {
      status.textContent = 'Enter a word or phrase to search.';
      return;
    }
    status.textContent = 'Searching…';
    try {
      const index = await loadIndex();
      if (!dialog.open || input.value.trim() !== query) return;
      const entries = index
        .map(doc => ({doc, score: score(doc, terms)}))
        .filter(entry => entry.score > 0)
        .sort((a, b) => b.score - a.score || a.doc.title.localeCompare(b.doc.title));
      render(entries, terms, query);
    } catch {
      if (dialog.open && input.value.trim() === query) {
        status.textContent = 'Search is unavailable. Please try again.';
      }
    }
  }

  function openSearch(trigger) {
    if (dialog.open) return;
    returnFocus = trigger;
    dialog.showModal();
    input.focus();
    input.select();
    search();
  }

  function enableTrigger(button) {
    button.hidden = false;
    button.addEventListener('click', () => openSearch(button));
  }

  const headerTrigger = document.querySelector('.site-header [data-search-open]');
  document.querySelectorAll('[data-search-open]').forEach(enableTrigger);
  if (headerTrigger && 'IntersectionObserver' in window) {
    const floating = document.createElement('button');
    floating.type = 'button';
    floating.className = 'search-floating';
    floating.setAttribute('aria-label', 'Search guides');
    floating.setAttribute('aria-haspopup', 'dialog');
    floating.innerHTML = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg>';
    enableTrigger(floating);
    floating.hidden = true;
    document.body.append(floating);
    const observer = new IntersectionObserver(([entry]) => {
      if (!dialog.open) floating.hidden = entry.isIntersecting;
    });
    observer.observe(headerTrigger);
  }
  dialog.querySelector('.search-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
  dialog.addEventListener('close', () => returnFocus?.focus({preventScroll: true}));
  input.addEventListener('input', search);
  form.addEventListener('submit', event => {
    event.preventDefault();
    const first = results.querySelector('a');
    if (first) first.click();
    else search();
  });
  results.addEventListener('click', event => {
    if (event.target.closest('a') && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) {
      dialog.close();
    }
  });
  dialog.addEventListener('keydown', event => {
    if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return;
    const links = [...results.querySelectorAll('a')];
    const position = links.indexOf(document.activeElement);
    if (position < 0 && document.activeElement !== input) return;
    const next = event.key === 'ArrowDown' ? links[position + 1] : links[position - 1] || input;
    if (!next) return;
    event.preventDefault();
    next.focus();
  });

  document.addEventListener('keydown', event => {
    if (event.defaultPrevented || event.altKey || dialog.open || document.querySelector('dialog[open]')) return;
    const shortcut = (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k';
    const target = event.target;
    if (!shortcut && (event.key !== '/' || event.ctrlKey || event.metaKey ||
      (target instanceof HTMLElement && (target.isContentEditable || target.matches('input, textarea, select'))))) return;
    event.preventDefault();
    openSearch(document.activeElement);
  });

  const url = new URL(location.href);
  const initial = url.pathname === '/' && url.searchParams.get('q');
  if (initial) {
    input.value = initial;
    url.searchParams.delete('q');
    history.replaceState(history.state, '', url);
    openSearch(document.querySelector('[data-search-open]'));
  }
})();
