// Copy button for every code block on a guide page.
//
// The button is in the markup and hidden; this reveals it, so a reader without
// JavaScript sees the code and no dead control. The async clipboard API needs a
// secure context and, in some browsers, a permission; when it is refused this
// falls back to selecting the code and copying the selection, which is bound to
// the click itself.
(() => {
  const canAsync = navigator.clipboard && typeof navigator.clipboard.writeText === 'function';
  const canLegacy = typeof document.execCommand === 'function';
  if (!canAsync && !canLegacy) return;

  const blocks = [...document.querySelectorAll('.code-block')];
  if (!blocks.length) return;

  const status = document.createElement('p');
  status.className = 'visually-hidden';
  status.setAttribute('role', 'status');
  document.body.append(status);

  const selectAndCopy = element => {
    const selection = window.getSelection();
    const saved = selection.rangeCount ? selection.getRangeAt(0) : null;
    const range = document.createRange();
    range.selectNodeContents(element);
    selection.removeAllRanges();
    selection.addRange(range);
    let copied = false;
    try {
      copied = document.execCommand('copy');
    } catch {
      copied = false;
    }
    selection.removeAllRanges();
    if (saved) selection.addRange(saved);
    return copied;
  };

  const copy = async element => {
    const text = element.textContent;
    if (canAsync) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch {
        // Refused: fall through to the selection path.
      }
    }
    return canLegacy && selectAndCopy(element);
  };

  for (const block of blocks) {
    const button = block.querySelector('.copy-code');
    const code = block.querySelector('code');
    if (!button || !code) continue;

    button.hidden = false;
    const label = button.getAttribute('aria-label') || 'Copy code';
    let reset;

    button.addEventListener('click', async () => {
      const copied = await copy(code);
      button.textContent = copied ? 'Copied' : 'Copy failed';
      button.setAttribute('aria-label', copied ? label.replace(/^Copy/, 'Copied') : label);
      if (copied) button.dataset.state = 'copied';
      else delete button.dataset.state;
      status.textContent = copied
        ? 'Code copied to clipboard'
        : 'Could not copy. Select the code and copy it manually.';
      clearTimeout(reset);
      reset = setTimeout(() => {
        button.textContent = 'Copy';
        button.setAttribute('aria-label', label);
        delete button.dataset.state;
      }, 2000);
    });
  }
})();
