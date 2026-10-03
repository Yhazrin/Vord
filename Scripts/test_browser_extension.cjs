// Exercise the actual MV3 worker with a local Chrome API double; no profile or network access.
const vm = require('node:vm');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const folder = path.join(root, 'Integrations/BrowserExtension');
const manifest = JSON.parse(fs.readFileSync(path.join(folder, 'manifest.json')));
const identity = JSON.parse(fs.readFileSync(path.join(folder, 'identity.json')));
const id = [...crypto.createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest('hex').slice(0, 32)]
  .map(c => String.fromCharCode(97 + parseInt(c, 16))).join('');
assert.equal(id, identity.extension_id);
assert.deepEqual(manifest.permissions.sort(), ['contextMenus', 'nativeMessaging', 'storage']);
assert.equal(manifest.host_permissions, undefined);
let install, clicked, menu, message, stored, badge;
let fail = false;
let rejected = false;
const chrome = {
  runtime: { onInstalled: { addListener: fn => install = fn }, onStartup: { addListener() {} },
    async sendNativeMessage(host, payload) { assert.equal(host, identity.host); message = payload; if (fail) throw Error('missing host'); if (rejected) return { ok: false, error: 'Select a short English word.' }; return { ok: true }; } },
  contextMenus: { removeAll: fn => fn(), create: value => menu = value, onClicked: { addListener: fn => clicked = fn } },
  storage: { local: { async set(value) { stored = value; } } },
  action: { async setBadgeText(value) { badge = value.text; }, async setBadgeBackgroundColor() {} }
};
vm.runInNewContext(fs.readFileSync(path.join(folder, 'background.js'), 'utf8'), { chrome });
(async () => {
  install(); assert.equal(menu.title, '快速添加到 Vord'); assert.equal(menu.contexts[0], 'selection');
  await clicked({ menuItemId: menu.id, selectionText: 'plight', pageUrl: 'https://example.com/article' }, {});
  assert.equal(message.text, 'plight'); assert.equal(message.source, 'https://example.com/article');
  assert.equal(stored.lastCapture.ok, true); assert.equal(badge, '');
  rejected = true;
  await clicked({ menuItemId: menu.id, selectionText: 'a long paragraph' }, {});
  assert.equal(stored.lastCapture.error, 'Select a short English word.');
  rejected = false;
  fail = true;
  await clicked({ menuItemId: menu.id, selectionText: 'reluctant' }, {});
  assert.equal(stored.lastCapture.ok, false); assert.equal(badge, '!');
  assert.ok(stored.lastCapture.error.includes('Settings'));
  console.log('Browser menu, stable identity, local handoff and failure feedback passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
