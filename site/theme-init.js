// Set the stored theme before the first paint so a light-theme reader never
// sees the dark palette flash. This file is loaded without defer on purpose.
try {
  if (localStorage.getItem('theme') === 'light') {
    document.documentElement.dataset.theme = 'light';
  }
} catch {
  // Storage can be unavailable; the dark default still applies.
}
