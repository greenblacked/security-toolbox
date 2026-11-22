// theme-init.js has already applied the stored choice before first paint; read it
// back so this file and the toggle agree without touching storage twice.
const toggle = document.getElementById('theme-toggle');
let current = document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';

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
