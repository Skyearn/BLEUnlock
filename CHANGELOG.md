# Release Notes

## 1.13.4

- Reorganized the unlock and lock controls by grouping logic and RSSI settings into `Unlock Settings` and `Lock Settings` submenus.
- Disable the logic choices when only one device is being monitored, and refresh that state immediately after device selections change.
- Keep monitored devices in the name-resolution path even when their RSSI temporarily drops below the scan list threshold, reducing UUID fallback for devices such as Apple Watch.
- Updated the README files to match the revised menu structure and installation notes for this fork.

<details>
<summary>中文发布说明</summary>

- 将解锁与锁定相关选项重新整理为 `解锁设置` 和 `锁定设置` 子菜单，把逻辑选择与 RSSI 阈值放到同一处。
- 当只监控一台设备时，自动禁用逻辑选择项，并在勾选设备变化后立即刷新菜单状态。
- 对已监控设备，即使瞬时 RSSI 低于扫描列表门槛，也继续参与名称解析，减少 Apple Watch 这类设备回退显示为 UUID 的情况。
- 同步更新了 README，反映新的菜单结构以及此 fork 的安装说明。

</details>
