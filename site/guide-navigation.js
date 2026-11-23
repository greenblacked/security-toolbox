// Keep both responsive contents lists in sync with the bookmarked section.
(() => {
  const links = document.querySelectorAll('.guide-jump a, .guide-toc a');
  const inlineContents = document.querySelector('.guide-jump');

  function syncLocation() {
    const hash = location.hash;
    for (const link of links) {
      if (hash && link.hash === hash) link.setAttribute('aria-current', 'location');
      else link.removeAttribute('aria-current');
    }
  }

  // Close before native fragment navigation calculates the heading position.
  // The focusable heading lets native navigation move keyboard focus as well.
  inlineContents?.addEventListener('click', event => {
    if (event.defaultPrevented || event.button !== 0 ||
        event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    if (event.target.closest('a[href^="#"]')) inlineContents.open = false;
  });

  addEventListener('hashchange', syncLocation);
  syncLocation();
})();
