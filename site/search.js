(() => {
  if (/^\/search\/?$/.test(location.pathname)) {
    const home = new URL('/', location.origin);
    const query = new URLSearchParams(location.search).get('q');
    if (query) home.searchParams.set('q', query);
    location.replace(home);
    return;
  }

  const dialog = document.createElement('dialog');
  const searchIcon = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg>';
  dialog.id = 'site-search';
  dialog.setAttribute('aria-labelledby', 'search-title');
  dialog.innerHTML = `
    <div class="search-heading">
      <h2 id="search-title">Search toolbox</h2>
      <button type="button" class="search-close" aria-label="Close search">&#215;</button>
    </div>
    <form role="search">
      <label for="search-query">Search terms</label>
      <div class="search-form-row">
        <div class="search-input-wrap">
          ${searchIcon}
          <input id="search-query" name="q" type="search" maxlength="120" placeholder="OIDC or pod security" autocomplete="off" enterkeyhint="search" autofocus>
        </div>
        <button type="submit" class="search-submit">Search</button>
      </div>
    </form>
    <p id="search-status" role="status"></p>
    <a class="text-link search-browse" href="/#guides" hidden>Browse topics</a>
    <div class="search-results-scroll"><ul id="search-results"></ul>
    <button type="button" class="repo-link search-more" hidden>Show more results</button></div>`;
  document.body.append(dialog);

  const form = dialog.querySelector('form');
  const input = dialog.querySelector('input');
  const submit = dialog.querySelector('.search-submit');
  const status = dialog.querySelector('#search-status');
  const browse = dialog.querySelector('.search-browse');
  const results = dialog.querySelector('#search-results');
  const more = dialog.querySelector('.search-more');
  const scroller = dialog.querySelector('.search-results-scroll');
  const pageSize = 8;
  let currentResults;
  let rendered = 0;
  let indexRequest;
  let searchVersion = 0;
  let returnFocus;

  const words = text => text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);

  function countHits(text, term) {
    let hits = 0;
    let from = 0;
    while (hits < 5) {
      const found = text.indexOf(term, from);
      if (found === -1) break;
      hits++;
      from = found + term.length;
    }
    return hits;
  }

  // Title hits outrank heading hits, which outrank body hits. Every term must
  // match somewhere, so adding a word narrows rather than widens the result set.
  function score({title, body, headings}, terms) {
    let total = 0;
    for (const term of terms) {
      let best = 0;
      if (title === term) best = 60;
      else if (title.startsWith(term)) best = 40;
      else if (title.includes(term)) best = 30;
      else if (headings.some(heading => heading.includes(term))) best = 20;
      else {
        const hits = countHits(body, term);
        if (!hits) return 0;
        best = 10 + hits;
      }
      total += best;
    }
    return total;
  }

  // Prefer the section that mentions the most terms, so the deep link and the
  // snippet point at the same place.
  function excerpt(doc, terms) {
    const title = doc.title.toLowerCase();
    if (doc.summary && terms.every(term => title.includes(term))) {
      return {text: doc.summary, section: null};
    }
    const sections = doc.sections || [];
    let best = null;
    let bestHits = 0;
    for (const section of sections) {
      const content = (section.title + ' ' + section.text).toLowerCase();
      const hits = terms.filter(term => content.includes(term)).length;
      if (hits <= bestHits) continue;
      best = section;
      bestHits = hits;
      if (hits === terms.length) break;
    }
    const text = best ? best.text : doc.text || doc.summary;
    const lower = text.toLowerCase();
    let at = -1;
    for (const term of terms) {
      const found = lower.indexOf(term);
      if (found >= 0 && (at < 0 || found < at)) at = found;
    }
    const start = Math.max(0, (at < 0 ? 0 : at) - 70);
    const slice = text.slice(start, start + 200).trim();
    return {
      text: (start > 0 ? '…' : '') + slice + (start + 200 < text.length ? '…' : ''),
      section: best,
    };
  }

  function highlight(text, pattern) {
    const fragment = document.createDocumentFragment();
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

  function render(entries, terms, query, remembered) {
    currentResults = {entries, terms};
    rendered = 0;
    if (!entries.length) {
      status.textContent = `No resources match "${query}". Try fewer words.`;
      browse.hidden = false;
      return;
    }
    status.textContent = `${entries.length} ${entries.length === 1 ? 'resource' : 'resources'} found for “${query}”.`;
    appendResults(remembered?.count || pageSize);
    submit.textContent = 'Open first';
    if (remembered) {
      const link = [...results.querySelectorAll('a')].find(item => item.pathname + item.hash === remembered.target);
      link?.focus({preventScroll: true});
      scroller.scrollTop = remembered.scroll;
      dialog.scrollTop = remembered.dialogScroll;
    }
  }

  function appendResults(amount) {
    const {entries, terms} = currentResults;
    const fragment = document.createDocumentFragment();
    // words() only yields letters and numbers, which are literal regex matches.
    const pattern = new RegExp(`(${terms.join('|')})`, 'gi');
    const batch = entries.slice(rendered, rendered + amount);
    for (const entry of batch) {
      const item = document.createElement('li');
      const link = document.createElement('a');
      const {text, section} = excerpt(entry.doc, terms);
      link.href = entry.doc.location + (section && section.id ? '#' + section.id : '');
      if (entry.doc.category) {
        const category = document.createElement('span');
        category.className = 'search-category';
        category.textContent = entry.doc.category;
        link.append(category);
      }
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
      snippet.append(highlight(text, pattern));
      link.append(snippet);
      const arrow = document.createElement('span');
      arrow.className = 'search-result-arrow';
      arrow.setAttribute('aria-hidden', 'true');
      arrow.textContent = '→';
      link.append(arrow);
      item.append(link);
      fragment.append(item);
    }
    results.append(fragment);
    rendered += batch.length;
    more.hidden = rendered === entries.length;
  }

  more.addEventListener('click', () => {
    const firstNew = rendered;
    appendResults(pageSize);
    results.children[firstNew]?.querySelector('a')?.focus();
  });

  function loadIndex() {
    indexRequest ||= fetch('/search/search_index.json')
      .then(response => {
        if (!response.ok) throw new Error('Search index unavailable');
        return response.json();
      })
      .then(data => data.docs.map(doc => ({
        doc,
        title: doc.title.toLowerCase(),
        body: [doc.text, ...(doc.sections || []).map(section => section.text)].join(' ').toLowerCase(),
        headings: (doc.sections || []).map(section => section.title.toLowerCase()),
      })))
      .catch(error => {
        indexRequest = undefined;
        throw error;
      });
    return indexRequest;
  }

  async function search(remembered) {
    const version = ++searchVersion;
    const query = input.value.trim();
    const terms = words(query);
    results.replaceChildren();
    more.hidden = true;
    currentResults = undefined;
    submit.textContent = 'Search';
    browse.hidden = true;
    if (!terms.length) {
      status.textContent = 'Find guides, checks, policies, labs, and security skills.';
      browse.hidden = false;
      return;
    }
    status.textContent = 'Searching…';
    try {
      const index = await loadIndex();
      if (!dialog.open || version !== searchVersion || input.value.trim() !== query) return;
      const entries = index
        .map(entry => ({doc: entry.doc, score: score(entry, terms)}))
        .filter(entry => entry.score > 0)
        .sort((a, b) => b.score - a.score || a.doc.title.localeCompare(b.doc.title));
      render(entries, terms, query, remembered);
    } catch {
      if (dialog.open && version === searchVersion && input.value.trim() === query) {
        status.textContent = 'Search is unavailable. Please try again.';
        browse.hidden = false;
      }
    }
  }

  function openSearch(trigger, remembered) {
    if (dialog.open) return;
    returnFocus = trigger;
    dialog.showModal();
    input.focus();
    input.select();
    search(remembered);
  }

  function enableTrigger(button) {
    button.hidden = false;
    button.addEventListener('click', () => openSearch(button));
  }

  const headerTrigger = document.querySelector('.site-header [data-search-open]');
  if (headerTrigger) {
    const shortcut = document.createElement('kbd');
    shortcut.className = 'search-shortcut';
    shortcut.textContent = 'Ctrl/⌘ K';
    shortcut.setAttribute('aria-hidden', 'true');
    headerTrigger.setAttribute('aria-keyshortcuts', 'Control+k Meta+k');
    headerTrigger.append(shortcut);
  }
  document.querySelectorAll('[data-search-open]').forEach(enableTrigger);
  if (headerTrigger && 'IntersectionObserver' in window) {
    const floating = document.createElement('button');
    floating.type = 'button';
    floating.className = 'search-floating';
    floating.setAttribute('aria-label', 'Search toolbox');
    floating.setAttribute('aria-haspopup', 'dialog');
    floating.innerHTML = searchIcon;
    enableTrigger(floating);
    floating.inert = true;
    document.body.append(floating);
    const observer = new IntersectionObserver(([entry]) => {
      floating.inert = entry.isIntersecting;
      floating.classList.toggle('is-visible', !entry.isIntersecting);
    });
    observer.observe(headerTrigger);
  }
  dialog.querySelector('.search-close').addEventListener('click', () => dialog.close());
  browse.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    returnFocus = null;
    dialog.close();
  });
  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
  dialog.addEventListener('close', () => {
    if (!dialog.open) returnFocus?.focus({preventScroll: true});
  });
  input.addEventListener('input', () => search());
  form.addEventListener('submit', event => {
    event.preventDefault();
    const first = results.querySelector('a');
    if (first) first.click();
    else search();
  });
  results.addEventListener('click', event => {
    const link = event.target.closest('a');
    if (!link || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    // A same-page anchor jump keeps its native history behavior.
    if (link.pathname !== location.pathname) {
      history.replaceState({...history.state, toolboxSearch: {
        query: input.value, count: rendered, scroll: scroller.scrollTop,
        dialogScroll: dialog.scrollTop, target: link.pathname + link.hash,
      }}, '');
    }
    dialog.close();
  });
  dialog.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      event.preventDefault();
      dialog.close();
      return;
    }
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
    if (!shortcut) return;
    event.preventDefault();
    openSearch(document.activeElement);
  });

  function restoreSearch() {
    const remembered = history.state?.toolboxSearch;
    if (!remembered) return;
    const state = {...history.state};
    delete state.toolboxSearch;
    history.replaceState(state, '');
    input.value = remembered.query;
    openSearch(headerTrigger, remembered);
  }

  // pageshow also runs when the browser restores the page from its back cache.
  addEventListener('pageshow', restoreSearch);

  const url = new URL(location.href);
  const initial = url.pathname === '/' && url.searchParams.get('q');
  if (initial) {
    input.value = initial;
    url.searchParams.delete('q');
    history.replaceState(history.state, '', url);
    openSearch(document.querySelector('[data-search-open]'));
  }
})();
