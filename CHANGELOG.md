# Release Notes

## 1.13.2

- Reduced BLE scan, connection, and RSSI polling activity during the system sleep transition to lower the chance of the Mac waking immediately after being put to sleep.
- Resume BLE monitoring automatically after the system wakes, while keeping normal proximity detection and unlock behavior intact.
- Preserved wake-on-proximity behavior for display sleep without letting the app keep aggressively probing devices at the system sleep boundary.

<details>
<summary>中文发布说明</summary>

- 收紧了系统进入睡眠前后的 BLE 扫描、连接与 RSSI 轮询行为，降低 Mac 刚睡下去就被再次唤醒的概率。
- 在系统唤醒后自动恢复 BLE 监控，同时保持正常的设备检测与解锁流程。
- 保留了显示器休眠场景下的靠近唤醒能力，但避免应用在整机睡眠边界继续激进探测设备。

</details>

## 1.13.1

- Reduced aggressive display wake retries around sleep/wake transitions to avoid getting stuck in a half-wake display state.
- Added automatic recovery after required permissions are granted, so BLEUnlock can resume work without forcing an app restart.
- Fixed temporary mismatches between the menu bar summary and the monitored device list when scan cache entries expire.
- Refined the monitored-device summary text to show the detected count and strongest RSSI more clearly.

<details>
<summary>中文发布说明</summary>

- 收紧了睡眠/唤醒边界上的亮屏重试逻辑，避免显示器卡在“被唤醒但没有真正点亮”的半唤醒状态。
- 在授予所需权限后新增了自动恢复流程，避免应用陷入“必须重启才能恢复”的循环。
- 修复了扫描缓存过期时，菜单栏摘要与受监控设备列表短暂显示不一致的问题。
- 优化了受监控设备的摘要文案，更直观地显示已检测设备数量和当前最强 RSSI。

</details>

## 1.13.0

- Added support for monitoring multiple BLE devices at the same time, with configurable unlock and lock logic.
- Improved wake-from-sleep unlock reliability by waiting for the lock screen to become ready before sending the password, and retrying when the first attempt lands too early.
- Simplified the menu bar summary into a single status line that shows the number of selected devices, how many are currently detected, and the strongest monitored signal.
- Unified RSSI display between the summary line and the monitored devices in the device list so the values are easier to understand.
- Restored live updates in the device scan list while keeping monitored-but-currently-undetected devices visible.
- Added a Simplified Chinese README and linked it from the English documentation.

<details>
<summary>中文发布说明</summary>

- 新增了同时监控多台 BLE 设备的支持，并可分别配置解锁逻辑与锁定逻辑。
- 改进了从睡眠唤醒后的自动解锁可靠性：现在会等待锁屏界面准备就绪，并在首次输入密码时机过早的情况下自动重试。
- 简化了菜单栏摘要，改为用单行状态显示已选设备数、当前已检测到的设备数，以及当前最强的监控信号。
- 统一了菜单摘要与设备列表中的 RSSI 显示方式，让信号强度数值更容易理解。
- 恢复了设备扫描列表的实时更新，同时保留了“已设为监控但当前未检测到”的设备显示。
- 新增了简体中文 README，并在英文文档中加入了链接。

</details>
