const toggle = document.getElementById('theme-toggle');
const themes = ['night', 'light', 'reactor'];
const labels = { night: 'Dark', light: 'Light', reactor: 'Reactor' };
let current = 'night';

try {
  const saved = localStorage.getItem('theme');
  current = saved === '' ? 'light' : themes.includes(saved) ? saved : current;
} catch {
  // Theme switching still works when storage is unavailable.
}

function renderTheme() {
  document.documentElement.dataset.theme = current;
  toggle.textContent = labels[current];
  toggle.setAttribute('aria-label', `${labels[current]} theme. Change theme`);
}

renderTheme();
toggle.hidden = false;
toggle.addEventListener('click', () => {
  current = themes[(themes.indexOf(current) + 1) % themes.length];
  renderTheme();
  try {
    localStorage.setItem('theme', current);
  } catch {
    // Keep the selected theme for the current page.
  }
});
