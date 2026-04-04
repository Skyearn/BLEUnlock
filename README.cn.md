# BLEUnlock

## 请注意：本应用不在 Mac App Store 发布，你可以在这里免费获取。

![CI](https://github.com/ts1/BLEUnlock/workflows/CI/badge.svg)
![Github All Releases](https://img.shields.io/github/downloads/ts1/BLEUnlock/total.svg)
[![Buy me a coffee](img/buymeacoffee.svg)](https://www.buymeacoffee.com/tsone)

BLEUnlock 是一款常驻菜单栏的小工具，可以根据 iPhone、Apple Watch 或其他蓝牙低功耗设备与 Mac 的距离，自动锁定或解锁 Mac。

本文档也提供 [English](README.md) 和 [Japanese (日本語)](README.ja.md) 版本。

## 功能

- 不需要 iPhone 端 App
- 支持任意会周期性广播、并且使用[静态 MAC 地址](#关于-mac-地址)的 BLE 设备
- 当 BLE 设备靠近 Mac 时自动解锁，无需手动输入密码
- 当 BLE 设备远离 Mac 时自动锁屏
- 可在锁定/解锁时执行你自己的脚本
- 可在靠近时唤醒显示器
- 可在离开和返回时暂停/恢复音乐或视频播放
- 密码安全保存在钥匙串中

## 运行要求

- 一台支持 Bluetooth Low Energy 的 Mac
- macOS 10.13 (High Sierra) 或更高版本
- iPhone 5s 及以上、任意 Apple Watch，或任意会周期性广播且使用[静态 MAC 地址](#关于-mac-地址)的 BLE 设备

## 安装

### 使用 Homebrew Cask

```sh
brew install bleunlock
```

### 手动安装

从 [Releases](https://github.com/ts1/BLEUnlock/releases) 下载 zip 文件，解压后拖到“应用程序”文件夹。

## 初次设置

首次启动时，应用会请求以下权限，请全部按提示授权：

权限 | 说明
---|---
蓝牙 | 显然需要蓝牙访问权限，选择 *好* / *允许*。
辅助功能 | 用于在锁屏状态下输入密码并完成解锁。点击 *打开系统设置* / *打开系统偏好设置*，解锁设置页后启用 BLEUnlock。
钥匙串 | （不一定每次都会弹）如果弹出，请选择 **始终允许**，因为锁屏状态下也需要读取保存的密码。
通知 | （可选）锁屏时 BLEUnlock 会显示通知，便于确认它是否正常工作。如果希望在锁屏界面也显示通知，需要在通知设置里把 *显示预览* 设为 *始终*。

> 注意：不同 macOS 版本需要授予的权限数量并不完全相同。系统越新，通常需要的权限越多。

然后应用会要求你输入登录密码，用于自动解锁锁屏界面。密码会安全地保存在钥匙串中。

最后，点击菜单栏图标，打开 *设备列表*。
BLEUnlock 会开始扫描附近的 BLE 设备。选择你的设备后即可开始使用。

## 选项说明

选项 | 说明
---|---
立刻锁定屏幕 | 无论 BLE 设备是否仍在附近，都立刻锁屏。设备需要先离开再重新靠近，才会再次自动解锁。适合离开座位前强制锁屏。
解锁 RSSI | 触发解锁的蓝牙信号强度。值越大，表示设备必须更靠近 Mac 才会解锁。选择 *禁用* 可关闭自动解锁。
锁定 RSSI | 触发锁屏的蓝牙信号强度。值越小，表示设备必须更远离 Mac 才会锁屏。选择 *禁用* 可关闭自动锁屏。
延迟锁定 | 检测到设备远离后，实际执行锁屏前等待的时间。如果设备在这段时间内重新靠近，则不会锁屏。
无信号超时 | 从最后一次收到信号到执行锁屏的超时时间。如果经常因为“信号丢失”而误锁屏，可以调大这个值。
靠近唤醒 | 当设备靠近且 Mac 处于锁定状态时，唤醒显示器。
唤醒时不解锁 | 无论是通过“靠近唤醒”自动唤醒，还是手动唤醒屏幕，BLEUnlock 都不会在唤醒后立即解锁。这个选项适合与 macOS 自带的 Apple Watch 解锁功能配合使用，或者你希望锁屏更快出现，但不想自动输入密码。
锁定时暂停"播放中" | 在锁定/解锁时，暂停/恢复 *正在播放* 控件可控制的音乐或视频，包括 Apple Music、QuickTime Player 和 Spotify。
用屏保来锁定它 | 如果启用该选项，BLEUnlock 会启动屏幕保护程序而不是直接锁屏。要让它正常工作，需要在系统的“安全性与隐私”里将“进入睡眠或开始屏幕保护程序后要求输入密码”设为“立即”。
锁定时关闭屏幕 | 锁定时立即关闭显示器。
设置密码... | 当你修改了 Mac 登录密码后，需要通过这里重新保存密码。
被动模式 | 默认情况下，BLEUnlock 会主动连接设备并读取 RSSI，这通常更稳定。但如果你同时使用蓝牙键盘、鼠标、触控板、蓝牙个人热点，或者 2.4GHz Wi‑Fi 环境干扰较大，可能会造成蓝牙不稳定。这种情况下可以启用被动模式。
开机启动 | 登录后自动启动 BLEUnlock。
设置最小 RSSI | RSSI 低于该值的设备不会显示在设备扫描列表中。

## 故障排除

### 设备列表里找不到我的设备

如果你的 BLE 设备不是 Apple 设备，BLEUnlock 可能无法读取设备名称。
这种情况下，它会显示为 UUID（一串带连字符的长十六进制字符串）。

要识别具体是哪台设备，可以尝试把设备靠近或远离 Mac，观察 RSSI（dBm 值）是否随之变化。

如果列表里完全没有任何设备，先尝试按下文所述重置蓝牙模块。

### 无法自动解锁

确认 BLEUnlock 已在 *系统设置* / *系统偏好设置* > *隐私与安全性* > *辅助功能* 中启用。
如果已经启用，尝试先关闭再重新开启。

如果系统弹出访问钥匙串中密码的对话框，必须选择 **始终允许**，否则在锁屏时无法自动读取密码。

### 经常出现“信号丢失”

可以调大 *无信号超时*，或尝试启用 *被动模式*。

### 蓝牙键盘、鼠标、个人热点或其他蓝牙设备变得不稳定

首先可以按住 `Shift + Option`，点击菜单栏或控制中心中的蓝牙图标，然后选择 *重置蓝牙模块*。

在 macOS 12 Monterey 中，这个菜单项已经被移除。
可以改为在终端执行：

```sh
sudo pkill bluetoothd
```

这条命令会要求输入你的登录密码。

如果问题仍然存在，建议启用 *被动模式*。

## 关于 MAC 地址

与经典蓝牙不同，Bluetooth Low Energy 设备可以使用 *私有* MAC 地址。
私有地址可能是随机的，并且会定期变化。

现在很多智能设备，无论是 iOS 还是 Android，都会使用大约每 15 分钟变化一次的随机地址，以减少被追踪的可能。

但 BLEUnlock 要持续跟踪一台设备，就必须依赖它的 MAC 地址保持稳定。

幸运的是，对于 Apple 设备，只要它和你的 Mac 使用相同的 Apple ID 登录，系统通常可以把 BLE 地址解析到真实的公共地址。

对于 Android 等其他设备，目前还没有通用的地址解析方式。
如果你的非 Apple 设备会定期更换 MAC 地址，BLEUnlock 就无法稳定支持它。

你可以把 BLEUnlock 在 *设备列表* 中显示的 MAC 地址和设备系统里显示的 MAC 地址进行比较，以确认是否解析正确。

## 在锁定/解锁时执行脚本

当锁定或解锁发生时，BLEUnlock 会执行以下位置的脚本：

```sh
~/Library/Application Scripts/jp.sone.BLEUnlock/event
```

根据事件类型，会传入以下参数之一：

| 事件 | 参数 |
|---|---|
| 因 RSSI 低而被 BLEUnlock 锁定 | `away` |
| 因完全收不到信号而被 BLEUnlock 锁定 | `lost` |
| 被 BLEUnlock 自动解锁 | `unlocked` |
| 被手动解锁 | `intruded` |

> 注意：要让 `intruded` 事件正常工作，需要在系统设置中的“安全性与隐私”里把“进入睡眠后要求输入密码”设为 **立即**。

### 示例

下面是一个示例脚本：当 Mac 被手动解锁时，发送一条 LINE Notify 消息，并附上一张站在 Mac 前的人像照片。

```sh
#!/bin/bash

set -eo pipefail

LINE_TOKEN=xxxxx

notify() {
    local message=$1
    local image=$2
    if [ "$image" ]; then
        img_arg="-F imageFile=@$image"
    else
        img_arg=""
    fi
    curl -X POST -H "Authorization: Bearer $LINE_TOKEN" -F "message=$message" \
        $img_arg https://notify-api.line.me/api/notify
}

capture() {
    open -Wa SnapshotUnlocker
    ls -t /tmp/unlock-*.jpg | head -1
}

case $1 in
    away)
        notify "$(hostname -s) is locked by BLEUnlock because iPhone is away."
        ;;
    lost)
        notify "$(hostname -s) is locked by BLEUnlock because signal is lost."
        ;;
    unlocked)
        #notify "$(hostname -s) is unlocked by BLEUnlock."
        ;;
    intruded)
        notify "$(hostname -s) is manually unlocked." $(capture)
        ;;
esac
```

`SnapshotUnlocker` 是一个用“脚本编辑器”制作的 `.app`，内容如下：

```applescript
do shell script "/usr/local/bin/ffmpeg -f avfoundation -r 30 -i 0 -frames:v 1 -y /tmp/unlock-$(date +%Y%m%d_%H%M%S).jpg"
```

之所以需要这个 app，是因为 BLEUnlock 本身没有相机权限。
把相机权限授予这个 app，就可以绕过这个限制。

## 资助

Apple Developer Program 的年费由捐助承担。

如果你喜欢这个应用，欢迎通过 [Buy Me a Coffee](https://www.buymeacoffee.com/tsone) 或 [PayPal Me](https://www.paypal.com/paypalme/my/profile) 进行捐助，帮助项目持续维护。

## 致谢

- [peiit](https://github.com/peiit): 中文翻译
- [wenmin-wu](https://github.com/wenmin-wu): 最小 RSSI 和移动平均
- [stephengroat](https://github.com/stephengroat): CI
- [joeyhoer](https://github.com/joeyhoer): Homebrew Cask
- [Skyearn](https://github.com/Skyearn): Big Sur 风格图标
- [cyberclaus](https://github.com/cyberclaus): 德语、瑞典语、挪威语（Bokmål）和丹麦语本地化
- [alonewolfx2](https://github.com/alonewolfx2): 土耳其语本地化
- [wernjie](https://github.com/wernjie): 唤醒时不解锁
- [tokfrans03](https://github.com/tokfrans03): 语言修正

图标基于 materialdesignicons.com 提供的 SVG 文件制作，
原始设计由 Google LLC 提供，遵循 Apache License 2.0。

## 许可证

MIT

Copyright © 2019-2022 Takeshi Sone.
