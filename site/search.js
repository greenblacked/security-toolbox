(() => {
  const form = document.getElementById('search-form');
  const input = document.getElementById('search-query');
  const status = document.getElementById('search-status');
  const results = document.getElementById('search-results');
  let index;
  async function search() {
    const query = input.value.trim().toLowerCase();
    if (!query) return;
    status.textContent = 'Searching…';
    results.replaceChildren();
    try {
      if (!index) {
        const response = await fetch('/search/search_index.json');
        if (!response.ok) throw new Error('Search index unavailable');
        index = (await response.json()).docs;
      }
      const words = query.split(/\s+/);
      const matches = index.filter(doc => words.every(word => (doc.title + ' ' + doc.text).toLowerCase().includes(word)));
      status.textContent = `${matches.length} ${matches.length === 1 ? 'guide' : 'guides'} found.`;
      for (const doc of matches) {
        const item = document.createElement('li');
        const link = document.createElement('a');
        link.href = doc.location;
        link.textContent = doc.title;
        item.append(link);
        results.append(item);
      }
    } catch {
      status.textContent = 'Search is unavailable. Please try again.';
    }
  }
  form.addEventListener('submit', event => { event.preventDefault(); search(); });
  form.hidden = false;
  status.hidden = false;
  const initial = new URLSearchParams(location.search).get('q');
  if (initial) { input.value = initial; search(); }
})();
