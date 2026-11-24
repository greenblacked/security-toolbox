// Keep both responsive contents lists in sync with the bookmarked section.
(() => {
  const links = document.querySelectorAll('.guide-jump a, .guide-toc a');
  const inlineContents = document.querySelector('.guide-jump');
  const menu = document.querySelector('.guide-menu');
  menu?.addEventListener('keydown', event => {
    if (event.key !== 'Escape' || !menu.open) return;
    event.preventDefault();
    menu.open = false;
    menu.querySelector('summary').focus();
  });

  // The native table remains readable regardless of JavaScript. Only a
  // horizontally scrollable table needs a named region and extra tab stop.
  const tables = document.querySelectorAll('.table-scroll[data-table-label]');
  const markScrollable = table => {
    const scrollable = table.scrollWidth > table.clientWidth;
    if (scrollable) {
      table.setAttribute('tabindex', '0');
      table.setAttribute('role', 'region');
      table.setAttribute('aria-label', table.dataset.tableLabel);
    } else {
      for (const attribute of ['tabindex', 'role', 'aria-label']) table.removeAttribute(attribute);
    }
  };
  if ('ResizeObserver' in window && tables.length) {
    const observer = new ResizeObserver(entries => {
      for (const {target} of entries) markScrollable(target);
    });
    for (const table of tables) observer.observe(table);
  }

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
