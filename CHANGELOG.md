# Release Notes

## 1.14.2

- **Fix:** Remove name-based MAC resolution — device name matching is unsafe due to name collisions. Persisted MAC→UUID mapping and LE database lookup are now the only MAC sources on startup.
- **Fix:** `scheduleDeviceMenuReorder` guard prevented separator visibility updates during menu tracking, causing separator and "Scanning…" to disappear when unmonitored devices arrived after the menu opened.
- Fix late MAC correlation in mergeDevice leaving stale "not detected" entries by removing any existing menu item for the new UUID before adding.
- Add MAC correlation check in newDevice: before creating a separate unmonitored entry, verify the device's MAC doesn't match a monitored one and merge if so.
- Fix monitored device reorder flicker: sort by stable MAC key instead of evolving resolved name; simplify menu rebuild to full replace instead of error-prone diff algorithm.
- Fix mergeDevice during menu tracking: repurpose the existing menu item without touching menu structure, eliminating position shifts from insertItem repositioning.
- Normalize all MAC comparisons and storage to canonical lowercase-dash format, resolving mismatches between resolveMACForDeviceName and getMACFromUUID return formats.
- Cache Bluetooth preferences plist reads (30s TTL) and throttle per-device IOBluetooth lookups (5s cooldown) to eliminate redundant disk I/O from allowDuplicates scanning callbacks.

<details>
<summary>中文发布说明</summary>

- **修复:** 移除基于设备名称的 MAC 解析 — 设备名可能重复，有安全隐患。启动时仅使用持久化 MAC→UUID 映射和 LE 数据库查找作为 MAC 来源。
- **修复:** `scheduleDeviceMenuReorder` 的 guard 在菜单追踪期间阻止后续分隔线可见性更新，导致菜单打开后新发现的未勾选设备无法触发分隔线和「扫描中…」显示。
- 修复延迟 MAC 关联时 mergeDevice 残留「未检测到信息」条目的问题：添加新条目前先移除 newUUID 已有的菜单项。
- newDevice 加入 MAC 关联检查：未监控设备创建前，校验其 MAC 是否与已监控设备相同，相同则直接合并。
- 修复已勾选设备排序抖动：改用 MAC 稳定键排序替代变化的解析名；简化菜单重建为全量替换，避免 diff 算法的边界错误。
- 修复菜单追踪期间 mergeDevice 造成的位序跳变：原地复用已有菜单项，不触碰菜单元数据。
- 统一所有 MAC 地址比较和存储为小写短横线格式，消除 resolveMACForDeviceName 与 getMACFromUUID 返回格式不一致导致的匹配失败。
- 蓝牙偏好 plist 读取缓存（30 秒）和设备级 IOBluetooth 查询冷却（5 秒），消除 allowDuplicates 扫描回调引发的冗余磁盘 I/O。

</details>
