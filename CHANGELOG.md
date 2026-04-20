# Release Notes

## 1.13.5

- Improve media pause handling when locking the Mac.
- Fix playback pause/resume compatibility for Apple Music, QuickTime Player, Spotify, and Safari.
- Request Automation permission ahead of time instead of during lock, reducing lock-time freezes.
- Make media pause and lock flow asynchronous to avoid blocking the main app process.

<details>
<summary>中文发布说明</summary>

- 改进锁定 Mac 时的媒体暂停逻辑。
- 修复 Apple Music、QuickTime Player、Spotify 和 Safari 的播放暂停/恢复兼容性。
- 自动化权限改为前置申请，不再在锁屏瞬间触发，减少卡死问题。
- 媒体暂停与锁屏流程改为异步执行，避免阻塞主进程。

</details>
