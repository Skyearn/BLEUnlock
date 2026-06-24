# Release Notes

## 1.14.2

- Fix late MAC correlation in mergeDevice leaving stale "not detected" entries by removing any existing menu item for the new UUID before adding.
- Add MAC correlation check in newDevice: before creating a separate unmonitored entry, verify the device's MAC doesn't match a monitored one and merge if so.
- Fix monitored device reorder flicker: sort by stable MAC key instead of evolving resolved name; fix diff algorithm to insert new items in-place rather than removing and re-adding trailing items.
- Fix mergeDevice during menu tracking: repurpose the existing menu item without touching menu structure, eliminating position shifts from insertItem repositioning.
- Normalize all MAC comparisons and storage to canonical lowercase-dash format, resolving mismatches between resolveMACForDeviceName and getMACFromUUID return formats.
- On startup, inject orphaned persisted MAC mappings into currently-monitored devices whose UUIDs have rotated, enabling MAC-based correlation across UUID changes immediately rather than waiting for a fresh BLE discovery.
- Cache Bluetooth preferences plist reads (30s TTL) and throttle per-device IOBluetooth lookups (5s cooldown) to eliminate redundant disk I/O from allowDuplicates scanning callbacks.

<details>
<summary>中文发布说明</summary>

- 修复延迟 MAC 关联时 mergeDevice 残留"未检测到信息"条目的问题：添加新条目前先移除 newUUID 已有的菜单项。
- newDevice 加入 MAC 关联检查：未监控设备创建前，校验其 MAC 是否与已监控设备相同，相同则直接合并。
- 修复已勾选设备排序抖动：改用 MAC 稳定键排序替代变化的解析名；修复 diff 算法将新条目原地插入而非移除尾部再追加。
- 修复菜单追踪期间 mergeDevice 造成的位序跳变：原地复用已有菜单项，不触碰菜单元数据。
- 统一所有 MAC 地址比较和存储为小写短横线格式，消除 resolveMACForDeviceName 与 getMACFromUUID 返回格式不一致导致的匹配失败。
- 启动时将持久化中已轮换 UUID 的孤立 MAC 注入同名当前监控设备，使 MAC 交叉关联立即可用，无需等待 BLE 重新发现。
- 蓝牙偏好 plist 读取缓存（30 秒）和设备级 IOBluetooth 查询冷却（5 秒），消除 allowDuplicates 扫描回调引发的冗余磁盘 I/O。

</details>
