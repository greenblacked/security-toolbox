// Entrance, reading progress and header elevation for the site.
//
// boot.js has already added .js in the head, so [data-reveal] is hidden from the
// first paint. This file reveals each section once, and is written so that no
// failure leaves content hidden: anything on screen is revealed on the next frame
// with a timer behind it, and a single safety net drops the hiding rule entirely
// if the page never renders a frame or the observer never reports.
(() => {
  // Cancels the no-JS failsafe in the stylesheet before it can fire.
  const root = document.documentElement;
  root.classList.add('js-ready');

  const revealable = [...document.querySelectorAll('[data-reveal]')];
  const reveal = element => element.classList.add('is-visible');
  const onScreen = element => {
    const rect = element.getBoundingClientRect();
    return rect.top < window.innerHeight && rect.bottom > 0;
  };

  const visibleNow = revealable.filter(onScreen);
  const later = revealable.filter(element => !visibleNow.includes(element));

  // Next frame, so the transition runs from the painted hidden state; the timer
  // covers a renderer that never delivers one.
  requestAnimationFrame(() => visibleNow.forEach(reveal));
  setTimeout(() => visibleNow.forEach(reveal), 250);

  let reported = false;
  if (later.length) {
    if ('IntersectionObserver' in window) {
      const observer = new IntersectionObserver(entries => {
        reported = true;
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          reveal(entry.target);
          observer.unobserve(entry.target);
        }
      }, {rootMargin: '0px 0px -6% 0px', threshold: 0.08});
      for (const element of later) observer.observe(element);
    } else {
      for (const element of later) reveal(element);
    }
  }

  // One safety net for both failure modes: a renderer that never advances the
  // transitions (no frames), and an observer that never reports. Either way the
  // page gets the finished still rather than an entrance it cannot animate.
  // Cancelling the transitions matters: a stuck transition keeps applying its
  // start value even after the rule that started it is gone.
  setTimeout(() => {
    const stuck = visibleNow.some(element => Number(getComputedStyle(element).opacity) < 0.99);
    if (!stuck && !(later.length && !reported)) return;
    root.classList.remove('js');
    for (const element of revealable) {
      for (const animation of element.getAnimations()) animation.cancel();
    }
  }, 1600);

  // Reading progress: one passive listener, written once per frame.
  const progress = document.querySelector('.scroll-progress > span');
  if (progress) {
    let queued = false;
    const update = () => {
      queued = false;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const ratio = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
      progress.style.transform = `scaleX(${ratio})`;
    };
    const queue = () => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(update);
    };
    addEventListener('scroll', queue, {passive: true});
    addEventListener('resize', queue, {passive: true});
    update();
  }

  // The header lifts off the page once it has scrolled.
  const header = document.querySelector('.site-header');
  if (header) {
    const sync = () => header.classList.toggle('is-stuck', window.scrollY > 8);
    addEventListener('scroll', sync, {passive: true});
    sync();
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

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const showToTop = () => toTop.classList.toggle('is-shown', window.scrollY > 600);
  addEventListener('scroll', showToTop, {passive: true});
  showToTop();
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
