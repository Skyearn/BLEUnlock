# Release Notes

## 1.13.6

- Add an Updates submenu with automatic update checks and manual update actions.
- Let manual update checks open the latest DMG download directly, with a fallback to the release page.
- Show pending update status in the menu even when notifications are disabled.
- Make automatic update notifications silent to reduce interruptions.
- Move BLE name-resolution logs into the current user's Library/Logs directory.
- Harden password handling, timer lifecycle, manual-lock recovery, and media pause state synchronization.
- Fix iBeacon prefix parsing and improve launcher path validation.
- Migrate the app bundle identifier to `com.github.Skyearn.BLEUnlock` with compatibility for legacy settings, Keychain data, and login items.

<details>
<summary>中文发布说明</summary>

- 新增“更新”子菜单，整合自动检查更新与手动检查更新入口。
- 手动检查更新时可直接下载最新 DMG，若没有 DMG 资源则回退到发布页。
- 即使未开启系统通知，也会在菜单中显示新版本状态提示。
- 自动检查更新通知改为静默提示，减少对当前工作的打断。
- BLE 设备名称解析日志改为写入当前用户的 `~/Library/Logs/BLEUnlock/`。
- 加强密码读取、定时器生命周期、手动锁定恢复逻辑，以及媒体暂停状态的线程安全。
- 修复 iBeacon 前缀识别问题，并改进 Launcher 对主程序路径的定位与校验。
- 将应用 Bundle ID 迁移为 `com.github.Skyearn.BLEUnlock`，并兼容旧版本的配置、钥匙串密码与登录项迁移。

</details>
