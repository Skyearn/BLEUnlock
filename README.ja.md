# BLEUnlock

![CI](https://github.com/Skyearn/BLEUnlock/workflows/CI/badge.svg)
![Github All Releases](https://img.shields.io/github/downloads/Skyearn/BLEUnlock/total.svg)

BLEUnlockはiPhone, Apple Watchやその他のBluetooth Low Energyデバイスの距離によってMacをロック・アンロックする小さなメニューバーユーティリティーです。

このドキュメントは [English](README.md) と [Simplified Chinese (简体中文)](README.cn.md) でも利用できます。

> このリポジトリは、Takeshi Sone 氏が作成したオリジナルの [ts1/BLEUnlock](https://github.com/ts1/BLEUnlock) を元にした fork です。BLEUnlock を MIT ライセンスで公開してくれた Takeshi Sone 氏と、元プロジェクトに貢献してきたすべてのコントリビューターに感謝します。

## 特徴

- iPhoneアプリは必要ありません
- 定期的に信号を送出するBLEデバイスなら何でも使えます ([静的なMACアドレス](#macアドレスについて)である必要があります)
- BLEデバイスがMacの近くにあればMacのロック画面を自動的に解除します
- BLEデバイスがMacから離れると画面をロックします
- ロック・アンロック時にスクリプトを実行することができます
- BLEデバイスがMacに近づくと画面スリープを解除することができます
- BLEデバイスがMacから離れる/近づくと音楽や動画の再生を一時停止/再生することができます
- パスワードはキーチェーンに安全に保管されます

## 必要なもの

- Bluetooth Low EnergyをサポートするMac
- macOS 10.13 (High Sierra) 以上
- iPhone 5s以上, Apple Watch (すべて), または定期的に信号を[静的なMACアドレス](#macアドレスについて)から送信するBLEデバイス

## インストール

### ~~Homebrew Caskを使う方法~~

~~`brew install bleunlock`~~

> このfork版ではHomebrew Caskを管理していないため、以下の手動インストールを利用してください。

### 手動でインストールする方法

[Releases](https://github.com/Skyearn/BLEUnlock/releases)からzipファイルをダウンロードし、解凍してアプリケーションフォルダに移動します。

> 注意: このforkはApple Developer Programに加入していないため、配布用のApple Developer ID署名および公証を行えません。そのため、初回起動時にmacOSがアプリをブロックする場合があります。
>
> macOSによってBLEUnlockの起動がブロックされた場合は、次の手順を試してください。
> 1. `BLEUnlock.app` を `/Applications` に移動します。
> 2. Controlキーを押しながらアプリをクリックし、**開く** を選びます。
> 3. それでもブロックされる場合は、**システム設定** -> **プライバシーとセキュリティ** を開き、ページ下部で BLEUnlock に対して **このまま開く** を選びます。
> 4. もう一度アプリを起動し、確認ダイアログで **開く** を選びます。
> 5. 起動後は、Bluetooth、アクセシビリティ、キーチェイン、通知などの権限を順に許可してください。
>
> 更新時の再許可をできるだけ減らすため、常に `/Applications/BLEUnlock.app` を上書きし、別のフォルダにあるコピーは起動しないことをおすすめします。

## セットアップ

初回起動時、以下の許可を要求します。適切に許可してください。

許可 | 説明
---|---
Bluetooth | 当然ながら、Bluetoothへのアクセスが必要です。
アクセシビリティ | ロック画面を解除するために必要です。システム環境設定の画面で左下のロックアイコンをクリックしてアンロックし、BLEUnlockをオンにしてください。
キーチェイン | (要求されない場合もあります) 要求された場合、必ず**常に許可**を選んでください。ロック中に必要になるためです。
通知 | (任意) BLEUnlockはロック中に通知メッセージを表示します。正しく動作しているか確認するのに役立ちます。Big Sur以降、デフォルトでロック画面ではメッセージが表示されません。メッセージを表示するには*通知*環境設定パネルで*プレビューを表示*を*常に*に設定してください。

|　必要になる許可はmacOSのバージョンが上がるにつれ増えています。古いmacOSをお使いの場合は上に挙げた許可が表示されない場合があります。

次にあなたのログインパスワードを聞いてきます。これはロック画面を解除するために必要です。キーチェインに安全に保存されます。

最後に、メニューバーアイコンから*デバイス*を選択してください。近くにあるBLEデバイスのスキャンが始まります。使いたいデバイスを選べば完了です。

## オプション

### 今すぐロック
BLEデバイスが近くにあるかどうかに関わらず、画面をロックします。BLEデバイスが一度遠ざかり、再び近づくと解除されます。席を離れる前に確実にロックするのに有効です。

### アンロック設定
アンロック設定には、アンロックのロジックとRSSI設定がまとめられています。ロジックでは、選択したデバイスの*いずれか*が近づいたときにアンロックするか、*すべて*が近づいたときだけアンロックするかを選べます。RSSIは、MacをアンロックするためにBLEデバイスがどの程度近づく必要があるかを決めます。*無効にする*を選ぶと自動アンロックを無効にできます。

### ロック設定
ロック設定には、ロックのロジックとRSSI設定がまとめられています。ロジックでは、選択したデバイスの*いずれか*が離れたときにロックするか、*すべて*が離れたときだけロックするかを選べます。RSSIは、BLEデバイスがどの程度離れたらロックするかを決めます。*無効にする*を選ぶと自動ロックを無効にできます。

### ロックするまでの遅延

BLEデバイスが遠ざかってから実際にロックをするまでの時間です。BLEデバイスがこの時間内に再び近づくと、ロックは行われません。

### 無信号タイムアウト

最後に信号を受信してからロックするまでの時間です。意図せず「デバイスからの信号がありません」でロックされる場合、この値を増やしてください。

### 画面スリープから復帰

ロック中にBLEデバイスが近づいてきたとき、ディスプレイをスリープ画面から復帰させます。

### アンロックせずに画面復帰

ディスプレイがスリープから復帰したとき（「画面スリープから復帰」による自動または手動に関わらず）、Macをアンロックしません。
これはApple WatchやTouch IDなどのよりセキュアなアンロック機構を使用したい場合に、「画面スリープから復帰」と共に使用すると素早く画面にアクセスできます。

### ロック中 "再生中" を一時停止

ロック時に音楽や動画の再生を一時停止し、ロック解除時に再開します。対応しているのはApple Music, QuickTime Player, Spotifyなど、*再生中*ウィジェットやキーボードの⏯キーで制御できるアプリです。

### スクリーンセーバーでロック

ロック時にスクリーンセーバーを起動します。このオプションが正しく動作するには、*セキュリティとプライバシー*システム環境パネルで*スリープとスクリーンセーバーの解除にパスワードを要求*を*すぐに*に設定する必要があります。

### ロック時画面をスリープ

ロック時にロック画面を表示せずディスプレイをスリープします。

### パスワードを設定...

Macのログインパスワードを変更したときに、このオプションを使って変更してください。

### パッシブモード

デフォルトでBLEUnlockはBLEデバイスに接続を確立し信号強度を読み取ろうとします。これはサポートされているデバイスでは最も安定して信号強度を読み取ることができる方法です。しかしながら、キーボード、マウス、トラックパッドや特にインターネット共有など、他のBluetooth機器を使用している場合、このモードが干渉することがあります。2.4GHz帯のWiFiも干渉する可能性があります。Bluetoothが不安定になる場合は、パッシブモードを有効にしてください。

### 最小RSSIを設定

このRSSI未満のデバイスはデバイススキャンリストに表示されません。

## トラブルシューティング

### デバイスがリストに表示されない

Apple製以外のBLEデバイスでは、BLEUnlockはデバイスの名前を取得できない場合があります。その場合、デバイスはUUID（ハイフンで区切られた長い16進数）で表示されます。

デバイスを識別するには、Macから遠ざけたり近づけたりして、信号強度（dB値）がそれに応じて変化するかどうかを確認してください。

もしリストに何も表示されない場合、下記のBluetoothモジュールのリセットを試してください。


### アンロックされない

*システム環境設定* > *セキュリティとプライバシー* > *アクセシビリティ* でBLEUnlockがオンになっているか確認してください。すでにオンになっている場合、一度オフにしてもう一度オンにしてみてください。

もしキーチェインの許可を求められた場合、*常に許可*を選択してください。ロック中に必要になるためです。

### "デバイスからの信号がありません" が頻繁に発生する場合

*無信号タイムアウト*を大きくしてください。それでも解決しない場合、*パッシブモード*を試してください。

### Bluetoothキーボード、マウス、インターネット共有その他Bluetoothがおかしくなった

メニューバーもしくはコントロールセンターにあるBluetoothアイコンをShift+Option+クリックし、表示される*Bluetoothモジュールのリセット*をしてみてください。

macOS 12 Montereyでは、上記のオプションはなくなっています。
代わりに、ターミナルで以下のコマンドを入力してBluetoothモジュールをリセットしてください。

```
sudo pkill bluetoothd
```

このコマンドは、ログインパスワードを要求します。

それでも問題が繰り返し起こる場合、*パッシブモード*をオンにしてください。

## MACアドレスについて

クラシックBluetoothと違い、Bluetooth Low Energyデバイスは*プライベート*MACアドレスを使うことができます。プライベートアドレスはランダムで、時間が経つと変わることがあります。

最近のスマートデバイスは、iOSとAndroidともに、15分ほどで変わるランダムアドレスを使う傾向にあります。おそらくトラッキング防止のためだと思われます。

一方で、BLEUnlockは、BLEデバイスをトラッキングするために、MACアドレスは静的である必要があります。

幸運なことに、Appleのデバイスでは、Macと同じApple IDでサインインしていれば、真の（パブリック）MACアドレスが取得できます。

デバイスがローテーションするプライベートアドレスを使っている場合は、*システム設定* > *Bluetooth*（古いmacOSでは *システム環境設定* > *Bluetooth*）で一度Macとペアリングしてみてください。システム上で接続・信頼済みになると、macOSがそのデバイスをより安定して認識し、BLEUnlock側でも同じデバイスとして見えやすくなることがあります。

これは試してみる価値のある回避策です。私の RedMagic スマートフォンでは有効でしたが、ローテーションするプライベートアドレスを使うすべての機器で安定して使えることまでは保証できません。

ペアリング自体がバッテリー消費を大きく増やすことは通常ありません。消費への影響が大きいのは、その後の頻繁なアクティブ接続やポーリングであり、この一度きりのペアリング操作ではありません。

## ロック・アンロック時にスクリプトを実行する

BLEUnlockはロック・アンロック時に以下のスクリプトを実行します。

```
~/Library/Application Scripts/jp.sone.BLEUnlock/event
```

スクリプトにはイベントに応じて以下の引数の一つが渡されます。

|Event|Argument|
|-----|--------|
|信号強度のためBLEUnlockによりロックされた|`away`|
|無信号のためBLEUnlockによりロックされた|`lost`|
|BLEUnlockによりアンロックされた|`unlocked`|
|手動でアンロックされた|`intruded`|

> 注意: `intruded` イベントが正常に働くには、システム環境設定の *セキュリティとプライバシー* で *スリープとスクリーンセーバの解除にパスワードを要求* を **すぐに** に設定してください。

### サンプル

例としてLINE Notifyにメッセージを送るスクリプトを示します。
手動でアンロックされた場合Macの前にいる人の写真を添付します。

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

`SnapshotUnlocker` はスクリプトエディタで作った .app で、内容は以下のとおりです。

```
do shell script "/usr/local/bin/ffmpeg -f avfoundation -r 30 -i 0 -frames:v 1 -y /tmp/unlock-$(date +%Y%m%d_%H%M%S).jpg"
```

このappはBLEUnlockにカメラのパーミッションがないため必要となります。このappにパーミッションを与えることによりパーミッションの問題を回避できます。

## Forkについて

このforkは Takeshi Sone 氏によるオリジナルの [ts1/BLEUnlock](https://github.com/ts1/BLEUnlock) をベースにしており、このリポジトリ独自の変更とリリースを継続しています。

オリジナルプロジェクトを公開してくれた Takeshi Sone 氏、そして修正、翻訳、改善案を提供してくれたすべての貢献者に感謝します。

## クレジット

- [Takeshi Sone](https://github.com/ts1): BLEUnlock のオリジナル作者とプロジェクトの基盤
- [peiit](https://github.com/peiit): 中国語のローカリゼーション
- [wenmin-wu](https://github.com/wenmin-wu): 最小RSSIと移動平均
- [stephengroat](https://github.com/stephengroat): CI
- [joeyhoer](https://github.com/joeyhoer): Homebrew Cask
- [cyberclaus](https://github.com/cyberclaus): ドイツ語, スウェーデン語, ノルウェー語 (Bokmål) およびデンマーク語のローカリゼーション
- [alonewolfx2](https://github.com/alonewolfx2): トルコ語のローカリゼーション
- [wernjie](https://github.com/wernjie): アンロックせずに画面復帰

アイコンはmaterialdesignicons.comからダウンロードしたSVGファイルをもとにしています。これらはGoogleによってデザインされApache License version 2.0でライセンスされています。

## ライセンス

MIT

Copyright © 2019-2022 Takeshi Sone.
