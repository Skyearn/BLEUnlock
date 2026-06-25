# Release Notes

## 1.14.2

- **Fix:** RSSI signal display is more stable — switched from 5-sample moving average to median-of-3 filter. Single outliers are completely eliminated, while real signal changes track with lower latency.
- **Fix:** When a monitored device's Bluetooth UUID rotates (privacy feature), the app now correctly detects and inherits the new UUID in real time. Previously it could get stuck showing 'Not Detected' until restart.
- **Fix:** Screen lock no longer stops background scanning — UUID rotations and proximity detection continue working as long as any device is monitored.
- **Fix:** RSSI 0 dBm no longer appears — treated as disconnected.
- **Fix:** Separator and 'Scanning…' now work correctly in all cases: when unmonitored devices arrive, when the first device is checked during menu tracking, and when no devices are checked.
- **Fix:** MAC resolution no longer fails when a device broadcasts both classic Bluetooth and BLE with the same name (e.g. RedMagic) — prefers the classic entry.
- **Fix:** Device detection count (e.g. '1/2') is accurate immediately on menu open.
- **Fix:** Monitored device list order no longer flickers during scans.

- **Feat:** Hold ⌥ (Option) to show full MAC address and UUID — default menu displays device name and RSSI only.
- **Feat:** UUID-only devices show collapsed `XXXX…YYYY` format for readability.
- **Feat:** Clickable "Pair to stabilize random address tracking →" hint opens Bluetooth settings.
- **Feat:** ⌥ indicator on "Device List" main menu item.
<details>
<summary>中文发布说明</summary>

- **修复:** RSSI 信号显示更稳定 — 由 5 样本均值平滑改为中值滤波（3 样本取中位数）。偶发异常值被完全消除，真实信号变化响应延迟更低。
- **修复:** 已监控设备的蓝牙 UUID 轮转（隐私特性）后，应用现在能实时识别并继承新 UUID。之前可能卡在「未检测到信息」直到重启。
- **修复:** 屏幕锁定不再中断后台扫描 — 只要存在已监控设备，UUID 轮转和距离检测持续运行。
- **修复:** RSSI 0 dBm 不再出现，统一视为断连。
- **修复:** 分隔线和「扫描中…」在所有场景下正确显示：未勾选设备到达时、菜单追踪期间勾选首个设备时、以及无已勾选设备时。
- **修复:** 设备同时广播经典蓝牙和 BLE 且同名时（如 RedMagic）MAC 解析失败 — 优先选经典蓝牙条目。
- **修复:** 打开菜单时设备检测计数（如 '1/2'）即时准确。
- **修复:** 已勾选设备列表不再因扫描而频繁跳动。
- **新增:** 按住 ⌥ 显示完整 MAC 地址和 UUID — 默认仅显示设备名和 RSSI。
- **新增:** 无名称设备显示折叠 UUID `XXXX…YYYY`。
- **新增:** 可点击提示「配对以稳定追踪随机地址 →」打开蓝牙设置。
- **新增:** 主菜单「设备列表」⌥ 提示。

</details>