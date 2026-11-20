const toggle = document.getElementById('theme-toggle');
let current = 'dark';

try {
  const saved = localStorage.getItem('theme');
  if (saved === 'light' || saved === '') current = 'light';
  if (saved === 'night' || saved === 'reactor' || saved === '') {
    localStorage.setItem('theme', current);
  }
} catch {
  // Theme switching still works when storage is unavailable.
}

function renderTheme() {
  document.documentElement.dataset.theme = current;
  toggle.textContent = current === 'dark' ? 'Dark' : 'Light';
  toggle.setAttribute('aria-label', `${toggle.textContent} theme. Switch to ${current === 'dark' ? 'light' : 'dark'} theme`);
}

renderTheme();
toggle.hidden = false;
toggle.addEventListener('click', () => {
  current = current === 'dark' ? 'light' : 'dark';
  renderTheme();
  try {
    localStorage.setItem('theme', current);
  } catch {
    // Keep the selected theme for the current page.
  }
});
