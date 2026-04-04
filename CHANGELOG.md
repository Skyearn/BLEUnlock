# Changelog

## 1.13.0

- Improved wake-from-sleep unlock reliability by waiting for the lock screen to become ready before sending the password, and retrying when the first attempt lands too early.
- Simplified the menu bar summary into a single status line that shows detected/selected device count and the strongest monitored signal.
- Unified RSSI display between the summary line and the monitored devices in the device list so the values are easier to understand.
- Restored live updates in the device scan list while keeping monitored-but-currently-undetected devices visible.
- Added a Simplified Chinese README and linked it from the English documentation.

<details>
<summary>中文更新日志</summary>

- 改进了从睡眠唤醒后的自动解锁可靠性：现在会等待锁屏界面准备就绪，并在首次输入密码时机过早的情况下自动重试。
- 简化了菜单栏摘要，改为用单行状态显示已检测/已选设备数量以及当前最强的监控信号。
- 统一了菜单摘要与设备列表中的 RSSI 显示方式，让信号强度数值更容易理解。
- 恢复了设备扫描列表的实时更新，同时保留了“已设为监控但当前未检测到”的设备显示。
- 新增了简体中文 README，并在英文文档中加入了链接。

</details>
