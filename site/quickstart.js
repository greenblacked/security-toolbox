const copyButton = document.getElementById('copy-command');
const command = document.getElementById('quickstart-command');
const copyStatus = document.getElementById('copy-status');

if (navigator.clipboard?.writeText) {
  copyButton.hidden = false;
  copyButton.addEventListener('click', async () => {
    copyStatus.textContent = '';
    try {
      await navigator.clipboard.writeText(command.textContent);
      copyStatus.textContent = 'Commands copied.';
    } catch {
      copyStatus.textContent = 'Copy failed. Select and copy the commands manually.';
    }
  });
}
