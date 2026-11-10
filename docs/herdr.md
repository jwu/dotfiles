# Herdr app 与 herdr-core

两个程序，一套 daemon：

| 程序 | 来源 | 作用 | 连哪个 daemon |
| --- | --- | --- | --- |
| `herdr-core` | 上游发布，装进 `~/.local/share/herdr-core/versions/<hash>/`、`current` 指过去；命令 `herdr-core` 与 `hc` | daemon + CLI：会话、pane、agent 检测 | 自己就是 server |
| `herdr-app` | macOS cask `herdr-app`（`/Applications/Herdr.app`）；Linux 上游 install（`~/.local/share/herdr-app`） | 桌面窗口：spaces、tabs、layouts、mods | 只连 `herdr-core` |

`herdr-app` 是 `herdr-core` 的窗口。本仓库只托管 `herdr-app` 的配置；`herdr-core` 的二进制与
状态（`~/.local/share/herdr-core/`、`~/.local/state/herdr-core/`、`~/.config/herdr-core/`）
由 app 自己安装与更新，不归这里管，也不进源树。

历史上还有两个程序，2026 年 11 月已卸载，本仓库不再安装或托管它们：`herdr` 0.9.5（Herdr 1，
自带 daemon 的 TUI）与 Sheprd（原 Herdr UI / `herdr-gpui`，`so.pen.herdr-gpui`）。`herdr-core`
是另一个 daemon（Herdr 2），与它们不共享会话，`herdr` 与 Sheprd 的目录、pi 集成扩展与 skill
都已清除。

## 安装

| 平台 | `herdr-app` |
| --- | --- |
| macOS | cask `herdr-app`（`bootstrap/macos.sh` 的 `CASKS`） |
| Linux | `curl -fsSL https://releases.herdr.dev/app/install.sh \| sh`（`run_onchange_before_14-herdr.sh.tmpl`） |
| Windows | `irm https://releases.herdr.dev/app/install.ps1 \| iex`（`bootstrap/windows.bat` 的 `:HERDR_APP`） |

macOS 的 cask 是 arm64-only：Intel Mac 得自己从源码构建。

Linux 与 Windows 的安装器都是 per-user 的：二进制落进 `~/.local/bin`（macOS 的 app 落
`/Applications/Herdr.app`），不碰 `sudo`、不写 shell rc（`PATH` 里没有时只打印一句提示）。所以
Linux 那份走 `run_onchange_before_14-herdr.sh.tmpl`，与 scrapling、dev-runtimes 同层；Windows
那份同样 per-user（`%LOCALAPPDATA%\Programs\herdr-app`），进 `:HERDR_APP`。

装过之后本仓库不再代劳升级：`herdr-app` 归它自己的应用内更新器，macOS 侧 Homebrew 那份跑
`brew upgrade --cask`。所以 `run_onchange_before_14-herdr.sh.tmpl` 在 `command -v herdr-app`
为空时才下载，重跑 bootstrap 也不会乱动已装的版本。

## 配置文件

`herdr-app` 的 home 三家一致。`src/mods.rs` 的 `app_dir()` 是 `$HERDR_APP_HOME`，否则
`$XDG_CONFIG_HOME/herdr-app`，否则 `~/.config/herdr-app`，没有 Windows 特例。所以
`dot_config/herdr-app/` 一份源就够，`.chezmoiignore` 不需要排它。

| 文件 | 权限 | 位置 | 谁写 |
| --- | --- | --- | --- |
| `settings.json` | 0644 | 三平台 `~/.config/herdr-app/` | Herdr app：Settings 保存时自动写，保存即热重载 |
| `themes/<name>.json` | 0644 | 三平台 `~/.config/herdr-app/themes/` | 自己写；`atom-one-dark.json`、`win98.json` 由 app 重写 |
| `layouts/<name>.json` | 0644 | 三平台 `~/.config/herdr-app/layouts/` | 内置的 `main`、`terminals`、`win98` 每次启动整份替换；`terminals-one-half-dark.json`、`main-mine.json` 是源里的 clone |
| `mods/<name>/main.js`、`mods/<name>/mod.json` | 0644 | 三平台 `~/.config/herdr-app/mods/` | 自己 clone 再改的 mod（`spaces-mine`、`agents-mine`）；上游 mod 每次启动整份替换 |

其余的运行时产物不托管：

- `~/.local/state/herdr-core/` —— daemon 的会话与 agent 检测状态
- `~/.config/herdr-app/` 下的 `AGENTS.md`、`keys.json`、`frame/`、`view.json`、
  `shared.json`、`data/`、`seen.json`、`installed.json`、`window.json`、`windows.json`
  —— 生成物或点击状态。`layouts/.state/<name>.json` 记的是尺寸、显示/隐藏与**主题选择**，
  文档原文是 don't edit those files。`mods/` 下只有源里那几份 clone 的自定义 mod 托管；
  `mods/<name>/gpui-kit.d.ts`（每次启动重写）与 `jsconfig.json`（首次生成）由 app 写，不进源

受管文件由程序回写：Herdr app 的 Settings 与主题选择器写 `settings.json` 和 `layouts/.state/`。
所以 `chezmoi apply` 覆盖掉 GUI 里的改动是正常现象——**要留下的设置必须写回源**：在 GUI 里
试好后跑 `chezmoi add`，或者直接改源再 apply。保存即热重载，不用重启。

源路径：

```
dot_config/herdr-app/settings.json.tmpl
  → ~/.config/herdr-app/settings.json                  (三平台)

dot_config/herdr-app/themes/one-half-dark.json
  → ~/.config/herdr-app/themes/one-half-dark.json      (三平台)

dot_config/herdr-app/layouts/terminals-one-half-dark.json
  → ~/.config/herdr-app/layouts/terminals-one-half-dark.json   (三平台)

dot_config/herdr-app/layouts/main-mine.json
  → ~/.config/herdr-app/layouts/main-mine.json         (三平台)

dot_config/herdr-app/mods/spaces-mine/{main.js,mod.json}
  → ~/.config/herdr-app/mods/spaces-mine/              (三平台)

dot_config/herdr-app/mods/agents-mine/{main.js,mod.json}
  → ~/.config/herdr-app/mods/agents-mine/              (三平台)
```

`main-mine` 是 `main` 的 clone，把 sidebar 的 spaces/agents 指向 `spaces-mine`、
`agents-mine` 两个 clone mod。新机器 apply 之后用 `ctrl-shift-l` 或 Settings 切到
`Main Mine` 一次；当前用哪份 layout 记在 `shared.json`（点击状态），不归源管。

## Herdr app：settings.json 与主题

`~/.config/herdr-app/settings.json` 是「这个人」的偏好，不是某个 layout 的外观：

```json
{
  "zoom": 1,
  "sounds": { "enabled": true },
  "font": "FiraMono Nerd Font",
  "font_size": 16,
  "font_ligatures": false,
  "ui_font": "PingFang SC",
  "minimum_contrast": 1,
  "appearance": "dark",
  "theme": "one-half-dark"
}
```

- `theme` 是主题名，或 `{ "light": ..., "dark": ... }` 跟随系统 / `appearance`。这里写单名，
  配合 `appearance = "dark"` 固定暗色
- 主题的解析顺序是 layout 的 `theme` → `settings.json` 的 `theme` → 内置 `graphite` / `paper`
- GUI 的主题选择器会绕过这套优先级：选中的值写进 `layouts/.state/<layout>.json` 的
  `theme` 字段，**覆盖任何 layout 与 settings**，而且那个文件是点击状态，不托管、不该手改。
  新机器没有 `.state`，所以源里的 `theme` 会生效
- `font` / `font_size` 是终端字体（px @ zoom 1），`ui_font` 是 mods 画字用的字体。字体文件
  `.ttf` / `.otf` 放 `mods/<name>/fonts/` 或 home 下的 `fonts/`
- `minimum_contrast` 是终端文字对比度下限，`1` 是默认
- 没有 `fallback` 键：CJK 与图标的回退由 app 自己处理

### themes/*.json

```json
{
  "background": "#282c34",
  "foreground": "#abb2bf",
  "selection": "#3b3f4c",
  "cursor": "#dcdfe4",
  "ansi": ["#181a1f", "... 16 个"],
  "colors": { "canvas": "#21252b", "chrome": "#21252b", "...": "..." }
}
```

`background` / `foreground` / `selection` / `cursor` / `ansi` 是终端的部分；`colors` 覆盖面板
颜色（`canvas`、`chrome`、`surface`、`popover`、`raised`、`accent`、`working`、`blocked`、
`done` 等），不写就从前面几项推导。内置主题有 `graphite`、`ink`、`moss`（暗）与 `paper`
（亮），另有随包的两份文件 `atom-one-dark.json`、`win98.json`。**这两份会被 app 升级或重写**
（上游会把未编辑过的旧版换成可读性更好的颜色），所以不要纳进源；自己写的
`themes/<name>.json` 会原样保留。

源里这份 `one-half-dark.json` 取自 Ghostty 的 `One Half Dark` 加 `dot_config/ghostty/config`
里的 OneDark 覆盖，让 Herdr app 的终端底色与 Ghostty 一致：pi 的 `toolSuccessBg = bg_d =
#21252b`，终端底色要是 `#21252b`（Atom One Dark），工具块就像丢了背景；`#282c34` 才看得出。
`one-half-dark.json` 比 Ghostty 那份多一段 `colors`，让 Herdr app 的面板（侧栏、标题栏、
popover）也跟着 One Dark。

改主题颜色保存即热重载。GUI 里改完要 `chezmoi add` 回源，否则下一次 apply 会覆盖。

### 内置 layout 与 `terminals-one-half-dark`

`main`（Herdr）自己不带 look，所以 `settings.json` 的 `theme` 就是它的外观，新机器没有
`layouts/.state/` 时也是它。`terminals` 与 `win98` 各带自己的主题：前者 `graphite` 外加
一份 11 项 hex `colors`，后者是一整套 Win98 桌面（`#008080` 桌面底、`PxPlus IBM VGA 8x16`
像素字体、`terminal_opacity 0`）。

内置 layout 是只读的：每次启动整份替换，往 `layouts/terminals.json` 里写字会被挪成
`terminals-edited` 再还原。源要管主题就只能自己 clone 一份。`terminals-one-half-dark.json`
就是 `terminals` 的 clone（`cloned_from` 记着来源与版本）：结构不动，`theme` 换成
`one-half-dark`，并删掉 layout 自带的 `colors` 与 `background`——那两处 hex 的优先级高于
主题，留着的话换了 theme 也不变色。clone 不随上游升级：`terminals` 的结构变了要重新
clone。`win98` 不 clone，配色就是那套皮肤本身。

主题选择器（`app.theme`，或 Settings 里点）把值写进 `layouts/.state/<layout>.json` 的
`theme`，优先级高于 layout 与 `settings.json`，而且是永久的：一旦在那里留了值，源里的
`theme` 对这层就不再生效，直到把那个键删掉。所以源里不留点击状态，靠 `settings.json` 与
clone 的 layout 决定外观。`shared.json` 的 `layout`（当前用哪份）同样是点击状态、不托管，
新机器落在 `main`。

## 平台分派

`herdr-app` 的 `settings.json` 按平台分派，但只有两项：`font_size` 与 `ui_font`。

| 键 | macOS | Linux | Windows |
| --- | --- | --- | --- |
| `font` | FiraMono Nerd Font | FiraMono Nerd Font | FiraMono Nerd Font |
| `font_size` | 16 | 18（Ghostty 13.5pt @96dpi） | 16 |
| `ui_font` | PingFang SC | FiraMono Nerd Font | Microsoft YaHei UI |

macOS 那套沿用这台 Mac 的 Ghostty：`font-size = 16`、中文回退 `PingFang SC`（见
`dot_config/ghostty/config`）。Windows 上模板只把面板字体换成 `Microsoft YaHei UI`，字号沿用
默认 16；herdr-app 在那台机器上没有实测过，等做到 Windows 时再对。

## 验证

```bash
# Herdr app 的配置与窗口
herdr-app status
herdr-app check ~/.config/herdr-app/mods/<name>

# daemon 侧（herdr-core）
hc ls --json
```

配置写错时 `herdr-app` 把错误写进 `settings.error`、`layout.error`、`keys.error`、
`programs.error`（`herdr-app status` 也会列出）。
