# Input Source Pro 配置说明

Input Source Pro 是一个 macOS 输入法自动切换工具。

它的配置由应用自己持久化，**不在本仓库里**：规则的真身在 Core Data 数据库
`~/Library/Application Support/Input Source Pro/Main.sqlite`（表 `ZAPPRULE`、
`ZKEYBOARDCONFIG` 等），而 `~/Library/Preferences/com.runjuu.Input-Source-Pro.plist`
里混着窗口位置（`NSWindow Frame SUUpdateAlert`）与 Sparkle 更新状态
（`SULastCheckTime` 每次检查都会变）。两者都不适合交给 chezmoi：

- 数据库是 Core Data 管的，内部有模型元数据（`Z_METADATA`）与主键分配表
  （`Z_PRIMARYKEY.Z_MAX`）要保持一致，还被 WAL 与应用内存缓存持有；
- plist 由 `cfprefsd` 缓存，直接改文件会被缓存盖回去。

所以本仓库只存应用**自己导出的 JSON**，并用它官方的 URL scheme 做一次性恢复，
见「新机器恢复」。

本文的界面描述依据 2.9.0 (605) 的截图；落地时机器上是 2.12.0。

## 安装方法

使用 Homebrew 安装：

```bash
brew install --cask input-source-pro
```

## 通用

「通用」页（`通用` 分组）：

| 项 | 值 |
| --- | --- |
| 默认输入法 | 适用于所有应用和网站 → `ABC` |
| 输入法恢复策略 | 切换回应用或网站时 → **总是切换至默认输入法**（不是「恢复上次使用的输入法」） |
| 默认功能键 | 将 F1、F2 等用作标准功能键，而不是媒体键 → 关闭 |
| 提示触发规则 | 长按鼠标左键时显示 ✅、切换输入焦点时显示 ✅（需要增强模式）；切换输入法时显示 ☐、切换应用时显示 ☐ |

选「总是切换至默认输入法」是这套规则的前提：焦点一换就回到 `ABC`，中文只在需要时手动切。

## 应用规则

「应用规则」页给单个应用覆盖上面的全局设置。截图（2.9.0）里列出的应用：

```
Google Chrome   Logseq   Neovide   Numbers 表格   Obsidian   WezTerm   Zed
屏幕共享   微信   日历   访达   音乐   预览   飞书
```

而 2.12.0 的 `ZAPPRULE` 表里只有 6 条：

| 应用 | 固定输入法 |
| --- | --- |
| 飞书（`com.electron.lark`） | 简体拼音 |
| 微信（`com.tencent.xinWeChat`） | 简体拼音 |
| Google Chrome | `ABC` |
| Zed | `ABC` |
| Obsidian | 简体拼音 |
| Neovide | `ABC` |

也就是这个页面的价值在于**例外**：列出来的是要单独定的应用，其余走全局规则。清单本身会
随时间变，所以真正需要留档的是这条判据，不是某一版列表。

右侧详情里是每个应用的默认输入法、功能键（「使用全局设置」）、输入法恢复策略（与全局
一致），「隐藏输入法提示」与「强制使用英文标点符号」默认不勾。底部「添加运行中的应用」
保持勾选。

另外「颜色方案」页不在截图里，但 2.12.0 的 `ZKEYBOARDCONFIG` 把
`com.apple.keylayout.ABC`、简体拼音、`im.rime.inputmethod.Squirrel.Hans` 都设成了黑底
白字（`000000ff` / `ffffffff`）。

## 新机器恢复

应用自己提供了搬运途径，不需要碰数据库：

1. **老机器**：用应用界面里的「导出设置」导出一份 JSON。
2. 把该文件放进仓库：`dot_config/inputsourcepro/settings.json`，它会部署到
   `~/.config/inputsourcepro/settings.json`。
3. **新机器**：`chezmoi apply` 时由 `run_once_after_80-inputsourcepro.sh.tmpl` 调官方
   URL scheme 导入：

   ```bash
   open "inputsourcepro://import?path=$HOME/.config/inputsourcepro/settings.json"
   ```

用 `run_once_` 而不是 `run_onchange_`：这是**恢复**，不是真源。规则平时在应用界面里改，
每次源变动都重新导入会把「上次导出之后」的改动冲掉。导入前应用自己还会把当前设置备份成
`settings-backup-<时间戳>`，所以误导入可以退回。

代价是 `run_once_` **会被提前消耗**：它在应用就绪之前跑过一次，就再没有第二次机会。所以
`input-source-pro` 必须留在 `bootstrap/macos.sh` 的 `CASKS` 里——否则新机器上先 `apply`
再装应用，这条恢复就永远不会执行。已经 apply 过的机器上想手动补一次：

```bash
chezmoi state delete-bucket --bucket=scriptState   # 清掉记账再 apply
# 或者直接跑上面那条 open 命令
```

导出的 JSON 顶层是 `schemaVersion` / `exportedAt` / `appRules` / `browserRules` /
`keyboardConfigs` 等。`exportedAt` 每次导出都会变，所以「重新导出」本身就是一次真实的
diff。本仓库是公开的，提交前值得看一眼导出的内容——`appRules` 只有 bundle id 与输入法
id，但 `browserRules` 按 schema 带 URL 与样本值，将来加了浏览器规则就可能带出域名。

## 隐藏顶部语言栏（可选）

如果想隐藏 macOS 顶部的语言指示栏（显示当前输入法的那个），可以执行以下命令并注销重新登录：

```bash
defaults write kCFPreferencesAnyApplication TSMLanguageIndicatorEnabled 0
```

注销重新登录后生效。
