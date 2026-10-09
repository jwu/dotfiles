# PixPin 配置说明

PixPin（bundle id `com.depthpicture.PixPin`）是截图 / 贴图工具。macOS 版由 Homebrew cask
`pixpin` 安装，已列进 `bootstrap/macos.sh` 的 `CASKS`；本机原先是用 dmg 手装的，纳入 cask
后由 brew 接管更新。

界面描述依据 3.5.5.1。

## 哪些文件归仓库管

应用把全部状态放在 `~/Library/Application Support/PixPin/`：

| 路径 | 内容 | 处置 |
| --- | --- | --- |
| `Config/PixPinConfig.json` | 动作、快捷键、系统开关 | **托管** |
| `LocalStorage.data` | Qt `QSettings` INI：配置窗口的位置与大小、截图矩形 | 不托管 |
| `History/`、`Data/PinWindowd.sqlite` | 截图历史、贴图窗口 | 不托管 |
| `Crashpad/`、`pixpin.log`、`Temp/`、`OcrModel/` | 崩溃上报、日志、临时文件、OCR 模型 | 不托管 |

判据与 Input Source Pro 那份 plist 相同：`LocalStorage.data` 开头就是

```ini
ConfigurationWindowMaximized=false
ConfigurationWindowNormalPosition=@Point(896 406)
ConfigurationWindowNormalSize=@Size(768 600)
HistoryShotRectDatas=@ByteArray(…)
```

拖动设置窗口或截一张图就会变，属于状态而非配置。`Config/PixPinConfig.json` 里只有设置项，
只在真的改设置时才写，所以可以托管。

源路径：

```
private_Library/private_Application Support/PixPin/Config/PixPinConfig.json
  → ~/Library/Application Support/PixPin/Config/PixPinConfig.json
```

`Application Support` 那一节也带 `private_` 前缀，不是风格：`~/Library/Application Support`
是 macOS 的私有目录（`0700`），而 chezmoi 的目录权限只能由源名里的前缀表达（git 不记录目录
权限）。少了这个前缀，apply 会把它放宽成 `0755`——`chezmoi status` 会以 ` M Library/Application
Support` 的形式报出来。

## PixPinConfig.json 的格式

单行紧凑 JSON，无尾随换行；key 形如 `Action.Screenshot#s.mac`：

- `#s.mac` 是平台后缀——这份存储按平台分桶，Windows 版对应另一套 key。本仓库只放 macOS
  这一份，跨平台共用一份源没有意义。
- 每项是 `{"t": <unix 秒>, "v": …}`，`t` 是应用写入该项的时间戳。
- `v` 里除 `shortCut` 外都是系统预置动作的定义（`index` 顺序、`script` 入口、
  `isSystemAction`、`showOnTray`、`type: 256`），不会手工改。

源里存的是**原样字节**，不做 `jq -S` 规范化：应用写回时也是单行，两边格式一致时
`chezmoi diff` 只会因真实设置变化而报警；把源格式化成多行，反而让每次 GUI 改动都多出一层
格式噪声。要读它用 `jq -S . <文件>`。

## 当前值（2026-10-09）

8 个系统动作里只有一个绑了快捷键：

| 动作 | `script` | `shortCut` |
| --- | --- | --- |
| Screenshot | `pixpin.screenShotAndEdit()` | `Ctrl+Shift+A` |
| Custom screenshot | `pixpin.openCustomScreenShot()` | 空 |
| Screenshot and copy | `pixpin.screenShot(ShotAction.Copy)` | 空 |
| Pin | `pixpin.pinFromClipBoard()` | 空 |
| Restore last closed | `pixpin.restoreLastClosedPin()` | 空 |
| Switch pin group | `pixpin.switchPinGroup()` | 空 |
| Close all pin window | `pixpin.closeAllPin()` | 空 |
| Pin selected file | `pixpin.pinSelectedFile()` | 空 |

系统开关：`System.Run After Boot` = `true`，`System.DesktopToolBar` = `2`（后者在界面上对应
哪一项没有核对过）。

## 改完设置之后

PixPin 会把新值直接写回 `Config/PixPinConfig.json`，此时 `chezmoi diff` 会报这个文件。把本机
那份回抄进源：

```bash
cp "$HOME/Library/Application Support/PixPin/Config/PixPinConfig.json" \
   "$(chezmoi source-path)/private_Library/private_Application Support/PixPin/Config/PixPinConfig.json"
```

反方向（源 → 本机）由 `chezmoi apply` 完成，但 **apply 前先退出 PixPin**：应用在内存里持有
配置，退出时会把自己那份写回，覆盖掉 apply 刚写进去的内容。也因此这份托管是单向的——源是
新机器的起点与改动记录，不是运行时真源。

## 常见的误判

- 不要试图用 `defaults` 读写 `~/Library/Preferences/com.depthpicture.PixPin.plist`：那个
  plist 是空的（42 字节的 `{}`），真配置全在 `Config/PixPinConfig.json` 里。
- `History/` 下的 `*.his` 单个就有几 MB，`Crashpad/` 每次启动都新建 run 目录，都不适合进
  git。
