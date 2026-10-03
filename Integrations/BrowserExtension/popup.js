chrome.storage.local.get('lastCapture').then(({ lastCapture }) => {
  if (!lastCapture) return;
  const status = document.getElementById('status');
  status.textContent = lastCapture.ok ? `已在 Vord 中打开「${lastCapture.text}」。按 Return 保存。` : lastCapture.error;
});
