const MENU_ID = 'vord-add-selection';
const HOST = 'app.vord.selection';

function registerMenu() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: MENU_ID, title: '快速添加到 Vord', contexts: ['selection'] });
  });
}
chrome.runtime.onInstalled.addListener(registerMenu);
chrome.runtime.onStartup.addListener(registerMenu);
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== MENU_ID) return;
  const text = (info.selectionText || '').trim();
  if (!text) return;
  try {
    const response = await chrome.runtime.sendNativeMessage(HOST, {
      text, source: info.frameUrl || info.pageUrl || tab?.url || ''
    });
    if (!response?.ok) {
      await reportFailure(text, response?.error || 'Vord 未能接收这个词。');
      return;
    }
    await chrome.storage.local.set({ lastCapture: { text, ok: true, time: Date.now() } });
    await chrome.action.setBadgeText({ text: '' });
  } catch (error) {
    await reportFailure(text, '无法连接 Vord。请打开 Vord → Settings → Selection & browser，完成浏览器连接设置。');
  }
});

async function reportFailure(text, error) {
  await chrome.storage.local.set({ lastCapture: { text, ok: false, time: Date.now(), error: String(error).slice(0, 300) } });
  await chrome.action.setBadgeText({ text: '!' });
  await chrome.action.setBadgeBackgroundColor({ color: '#222222' });
}
