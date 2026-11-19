// Theme toggle: light (default), night, reactor. The choice is kept in localStorage.
(() => {
  const themes = ['', 'night', 'reactor'];
  const root = document.documentElement;
  let saved = '';
  try {
    saved = localStorage.getItem('theme') || '';
  } catch {
    // Storage can be blocked; the page still works in the default theme.
  }
  let i = Math.max(themes.indexOf(saved), 0);
  root.dataset.theme = themes[i];
  const btn = document.getElementById('theme-toggle');
  if (!btn) return;
  btn.addEventListener('click', () => {
    i = (i + 1) % themes.length;
    root.dataset.theme = themes[i];
    try {
      localStorage.setItem('theme', themes[i]);
    } catch {
      // Not persisted; the toggle still applies for this page view.
    }
  });
})();
