# Vord 选词快速添加

## macOS 全局入口

1. 将新版 Vord.app 放进「应用程序」文件夹，打开一次。
2. 在浏览器、文章或文本应用中选中英文词。
3. 右键 →「服务」→「快速添加到 Vord」；也可以从当前应用顶部菜单 →「服务」调用。
4. Vord 会显示选中词的中英文释义。按 Return 保存，Esc 关闭。

如果看不到服务，在系统设置 → 键盘 → 键盘快捷键 → 服务 → 文本中开启「快速添加到 Vord」。各应用是否在右键菜单里显示「服务」由该应用决定；不支持 macOS 服务的应用无法使用这一入口。

## Chrome / Edge 直接右键菜单

1. 在 Vord 的 Settings → Capture → Selection & browser 选择 Chrome 或 Edge 后点击 **Set up**。Finder 会定位 BrowserExtension 文件夹，并完成本机连接配置。
2. 打开 `chrome://extensions` 或 `edge://extensions`，开启「开发者模式」，选择「加载已解压的扩展程序」。
3. 选择刚才的 BrowserExtension 文件夹（`~/Library/Application Support/Vord/BrowserExtension`）。
4. 网页选中英文 → 右键 → **快速添加到 Vord**。

「加载已解压的扩展程序」只能选择文件夹，不能选择 `.zip`。选中的文件夹内必须直接有 `manifest.json`。使用 ZIP 安装包时，先解压，再选择里面的 `BrowserExtension` 子文件夹，不能选择外层的 `Vord-selection-plugin` 文件夹。也可以直接选择上述由 Vord 准备好的文件夹，无需解压安装包。

在 Chrome 的文件夹选择窗口中，按 `⌘⇧G`，粘贴 `~/Library/Application Support/Vord/BrowserExtension`，回车后点击「选择」。

这是本地安装版插件，尚未上架扩展商店。选中词只发给本机 Vord；不需要开启网页读取权限或辅助功能权限。应用移动位置后，请再点击一次 Set up browser。

## 更新和卸载

- 更新：更换 Vord.app 后点击 Set up；在浏览器扩展页点击扩展的「重新加载」。
- 卸载浏览器插件：在浏览器扩展页「移除」，并删除 `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/app.vord.selection.json`（Edge 对应 Microsoft Edge 目录）。这不会删除生词或复习记录。
- 只关闭系统服务：在键盘快捷键设置里取消勾选对应服务。
