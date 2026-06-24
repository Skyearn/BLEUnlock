# Release Notes

## 1.14.1

- Resolve MAC addresses from system paired Bluetooth devices via IOBluetooth and display them in the device list.
- Automatically remap device tracking when BLE UUID changes after disconnect or reboot, using MAC-based cross-correlation. No reconfiguration needed.
- Monitored devices are now sorted to the top of the device list, with unmonitored devices following in discovery order.
- Add Bluetooth entitlement for broader macOS compatibility.
- Fix MAC persistence: changed from `{UUID → MAC}` to `{MAC → UUID}` format with merge-on-write, preventing MAC entries from being overwritten when BLE correlation runs concurrently.
- Ensure monitored devices always appear in the runtime device dictionary, so MAC-based correlation can match rotated BLE UUIDs after app restart.
- Fix device menu not refreshing unmonitored devices after quick reopen caused by aggressive stale-device cleanup.
- Fix group separator line not appearing on first launch.
- Improve menu stability during tracking: defer full menu rebuilds while the menu is open, updating only separator visibility in real time.
- Fall back to macOS Bluetooth LE database for MAC address resolution when IOBluetooth name lookup fails.

<details>
<summary>中文发布说明</summary>

- 通过 IOBluetooth 从系统已配对蓝牙设备中获取 MAC 地址，并显示在设备列表中。
- 当设备 BLE UUID 因断连或系统重启发生变化时，自动通过 MAC 地址交叉关联重映射追踪，无需手动重新配置。
- 已勾选的监控设备自动排序到设备列表顶部，未勾选设备按发现顺序排列在下方。
- 添加 Bluetooth entitlement 以兼容更多 macOS 版本。
- 修复 MAC 持久化：改为 `{MAC → UUID}` 格式并合并写入，避免并发 BLE 关联时覆盖已有 MAC 映射。
- 确保监控设备始终出现在运行时设备字典中，使重启后 MAC 交叉关联能匹配已轮换的 BLE UUID。
- 修复快速重开菜单时未勾选设备不刷新的问题，将过期设备清理延迟到菜单关闭时执行。
- 修复首次启动时已勾选/未勾选设备间分割线不出现的问题。
- 改进菜单追踪期间的稳定性：菜单打开期间仅更新分割线可见性，推迟完整重建。
- IOBluetooth 名称查找失败时，回退到 macOS 蓝牙 LE 数据库解析 MAC 地址。

</details>
