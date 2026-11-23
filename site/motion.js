// Entrance, reading progress and header elevation for the site.
//
// boot.js has already added .js in the head, so [data-reveal] is hidden from the
// first paint. This file reveals each section once, and is written so that no
// failure leaves content hidden: anything on screen is revealed on the next frame
// with a timer behind it, and a single safety net drops the hiding rule entirely
// if the page never renders a frame or the observer never reports.
(() => {
  const root = document.documentElement;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  if (root.classList.contains('js') && !reducedMotion.matches) {
    const revealable = [...document.querySelectorAll('[data-reveal]')];
    const visibleNow = [];
    const later = [];
    for (const element of revealable) {
      const rect = element.getBoundingClientRect();
      (rect.top < window.innerHeight && rect.bottom > 0 ? visibleNow : later).push(element);
    }

    const reveal = element => element.classList.add('is-visible');
    let reported = false;
    const observer = later.length ? new IntersectionObserver(entries => {
      reported = true;
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        reveal(entry.target);
        observer.unobserve(entry.target);
      }
    }, {rootMargin: '0px 0px -6% 0px', threshold: 0.08}) : null;
    for (const element of later) observer.observe(element);

    const revealVisible = () => visibleNow.forEach(reveal);
    const fallback = setTimeout(revealVisible, 250);
    const frame = requestAnimationFrame(() => {
      clearTimeout(fallback);
      revealVisible();
    });
    const finish = () => {
      root.classList.remove('js');
      observer?.disconnect();
      cancelAnimationFrame(frame);
      clearTimeout(fallback);
      clearTimeout(safety);
      reducedMotion.removeEventListener?.('change', finish);
      // A stuck transition can keep applying its start value after .js is gone.
      for (const element of revealable) {
        element.getAnimations?.().forEach(animation => animation.cancel());
      }
    };
    const safety = setTimeout(() => {
      const stuck = visibleNow.some(element => Number(getComputedStyle(element).opacity) < 0.99);
      if (stuck || (observer && !reported)) finish();
    }, 1600);
    reducedMotion.addEventListener?.('change', finish);

    // The observer and the timer are ready, so cancel the stylesheet failsafe.
    root.classList.add('js-ready');
  } else {
    root.classList.remove('js');
  }

  // Back to top. Hidden with visibility rather than opacity alone, so it is not
  // in the tab order until it is on screen, and it returns focus to the main
  // landmark instead of leaving it on a button that has just disappeared.
  const toTop = document.createElement('button');
  toTop.type = 'button';
  toTop.className = 'to-top';
  toTop.setAttribute('aria-label', 'Back to top');
  const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  icon.setAttribute('viewBox', '0 0 24 24');
  icon.setAttribute('aria-hidden', 'true');
  icon.setAttribute('focusable', 'false');
  const arrow = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  arrow.setAttribute('d', 'M12 19V5M5 12l7-7 7 7');
  arrow.setAttribute('fill', 'none');
  arrow.setAttribute('stroke', 'currentColor');
  arrow.setAttribute('stroke-width', '2');
  arrow.setAttribute('stroke-linecap', 'round');
  arrow.setAttribute('stroke-linejoin', 'round');
  icon.append(arrow);
  toTop.append(icon);
  document.body.append(toTop);

  const header = document.querySelector('.site-header');
  const progress = document.querySelector('.scroll-progress > span');
  let queued = false;
  let lastRatio;
  const update = () => {
    queued = false;
    const scrollY = window.scrollY;
    if (progress) {
      const max = root.scrollHeight - window.innerHeight;
      const ratio = max > 0 ? Math.min(1, Math.max(0, scrollY / max)) : 0;
      if (ratio !== lastRatio) {
        progress.style.transform = `scaleX(${ratio})`;
        lastRatio = ratio;
      }
    }
    header?.classList.toggle('is-stuck', scrollY > 8);
    toTop.classList.toggle('is-shown', scrollY > 600);
  };
  const queue = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(update);
  };
  addEventListener('scroll', queue, {passive: true});
  addEventListener('resize', queue, {passive: true});
  update();
  toTop.addEventListener('click', () => {
    const from = window.scrollY;
    const smooth = !reducedMotion.matches;
    window.scrollTo({top: 0, behavior: smooth ? 'smooth' : 'auto'});
    // A renderer that is throttled never advances the smooth animation, so the
    // page would stay where it is. If nothing has moved shortly after, jump.
    if (smooth) {
      setTimeout(() => { if (window.scrollY >= from) window.scrollTo(0, 0); }, 250);
    }
    const main = document.getElementById('main');
    if (main) main.focus({preventScroll: true});
  });
})();
