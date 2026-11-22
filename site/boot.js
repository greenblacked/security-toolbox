// Head bootstrap: the stored theme, and the opt-in that lets the stylesheet hide
// [data-reveal] before the first paint. Loaded without defer, so both decisions
// are made before anything is drawn and neither can flash.
(() => {
  try {
    if (localStorage.getItem('theme') === 'light') {
      document.documentElement.dataset.theme = 'light';
    }
  } catch {
    // Storage can be unavailable; the dark default still applies.
  }

  // Motion is opt-in only where it can run and the reader wants it. motion.js
  // adds .js-ready when it starts, which cancels the stylesheet's failsafe reveal.
  const wantsMotion = !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (wantsMotion && 'IntersectionObserver' in window) {
    document.documentElement.classList.add('js');
  }
})();
