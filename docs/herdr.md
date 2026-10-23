# Herdr 与 Herdr UI

Herdr 是两个程序、两处配置：

| 程序 | 来源 | 作用 |
| --- | --- | --- |
| `herdr` | `~/.local/bin/herdr`（0.9.5） | daemon + TUI：会话、pane、agent 检测 |
| `herdr-gpui` | Linux：Arch 包 `herdr-gpui` → `/usr/bin/herdr-gpui`；macOS：`/Applications/Herdr.app`（bundle id `so.pen.herdr-gpui`） | 原生 GUI 窗口，画字的是它 |

GUI 不是 daemon 的一部分：它单独连 `~/.config/herdr/herdr-client.sock`，字体、主题、布局全在它自己的配置里。改字体只动 GUI 那份，`herdr` 的 TUI 不受影响。

Linux 那台为对齐 Ghostty 的字体观感做过一轮实测，结论是：**字重和字号能追上，hinting 追不上**。原因在下面；macOS 那套取值见「平台分派」。

## 配置文件

`~/.config/herdr/` 下只有两个文件该进版本控制：

| 文件 | 权限 | 谁写 |
| --- | --- | --- |
| `config.toml` | 0644 | daemon：`herdr config reset-keys`、Settings 面板 |
| `config-gpui.local.toml` | 0600 | GUI：Settings 保存时自动写，保存即热重载 |

其余全是运行时产物：

- `config-gpui.toml` —— 72 KB 的托管默认值，首行写着 `DO NOT EDIT -- WILL BE OVERWRITTEN`，每次启动刷新
- `*.lock`、`*.sock`、`*.log`、`session.json`、`session-snapshots/`
- `~/.local/state/herdr/` —— 窗口状态、agent 检测缓存、GPUI 日志

两个受管文件都由程序回写：Herdr UI 的 Settings 面板、`Herdr config set`、以及对话框里的「Do not ask again」，都直接写 `config-gpui.local.toml`；`herdr config reset-keys` 会备份并重写 `config.toml`。所以 `chezmoi apply` 覆盖掉 GUI 里的改动是正常现象——**要留下的设置必须写回源**：在 GUI 里试好后跑 `chezmoi add`，或者直接改源再 apply。改完 `config.toml` 用 `herdr server reload-config` 让运行中的 server 重读。

源路径：

```
dot_config/herdr/config.toml
  → ~/.config/herdr/config.toml

dot_config/herdr/private_config-gpui.local.toml.tmpl
  → ~/.config/herdr/config-gpui.local.toml
```

`config-gpui.local.toml` 在原机上是 0600，所以带 `private_` 前缀。

`~/.agents/skills/herdr-gpui-browser/SKILL.md` 也不托管：文件头带 `herdr-gpui-managed-skill` 标记，Herdr UI 会自己刷新它，纳进来只会制造 diff。

## 平台分派

两份配置全平台托管，`~/.config/herdr/` 在 Linux / macOS / Windows 上路径相同，`.chezmoiignore` 不再按 OS 忽略它。

但字体值不同：Linux 那台对齐的是 Ghostty，macOS 跟系统字体。于是 `config-gpui.local.toml` 是模板，按 `.chezmoi.os` 分两套：

| 段 | macOS | Linux |
| --- | --- | --- |
| `[terminal]` | FiraMono 16 | FiraMono 18、`weight = "medium"`、`line_height = 1.2` |
| `[sidebar]` / `[tabs]` | FiraMono 14 | FiraMono 16，CJK fallback 到 Sarasa Mono |
| `[ui]` | PingFang SC 14 | FiraMono 16，CJK fallback 到 Sarasa Mono |

macOS 那套沿用这台 Mac 的 Ghostty：`font-size = 16`、中文回退 `PingFang SC`（见 `dot_config/ghostty/config`）。Windows 没有实测值，走 Linux 那一支。

字体键的可用性是 GPUI 的，两个平台一样；下面的实测数值来自 Linux 那台。

## Shift+Enter：为什么要取消默认的 `[pane_keys]`

Herdr UI 在 PR #518 里给所有平台加了一条默认映射 `[pane_keys] "shift-enter" = "alt-enter"`，为的是让没启用键盘协议的 prompt_toolkit 类程序也能换行。代价是启用 kitty 键盘协议的 pane 收到 `CSI 13;3u`（真正的 Alt+Enter），而不是 `CSI 13;2u`（Shift+Enter）。

pi 就是这样：它启动时 push kitty 协议（`ESC[>7u`），而 `alt+enter` 在 pi 里绑的是 `app.message.followUp`（排队后续消息），于是 Shift+Enter 既不换行也不提交。上游记在 penso/herdr-gpui#575（open，P1），Herdr UI 20261020.1 仍复现。

所以源里写：

```toml
[pane_keys]
"shift-enter" = ""
```

空字符串表示取消默认，Shift-Enter 原样送达 pane，pi 重新把它识别为 Shift+Enter。副作用是普通 shell 里 Shift-Enter 不再被改写成 Alt-Enter：zsh 插入换行，bash 无绑定。临时替代方案是 `Ctrl+J`（pi 默认的第二个换行键）。

上游修好后整段删掉即可。`herdr-gpui config check` 不会为此报错，`herdr-gpui config get pane_keys` 可以确认是否生效。

## 字体：四个 section，只有 terminal 能设字重

`config-gpui.local.toml` 的四个段落吃不同的键（`[terminal]` 的 `weight` 只在 Linux 那套里用得上，macOS 侧没设）：

| 段 | family | size | fallback | weight | line_height |
| --- | --- | --- | --- | --- | --- |
| `[terminal]` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `[sidebar]` | ✓ | ✓ | ✓ | — | — |
| `[tabs]` | ✓ | ✓ | ✓ | — | — |
| `[ui]` | ✓ | ✓ | ✓ | — | — |

`weight` 是 `[terminal]` 独占（`config-gpui.toml` 的注释原文：`Only [terminal] takes this key`）。sidebar / tabs / ui 永远是 Regular 400，没有配置层解法。

### 为什么不能用 `family = "FiraMono Nerd Font Medium"` 绕过

字体的 name 表里有两个族名字段：

```
FiraMonoNerdFont-Medium.otf
  nameID 16 (typographic family) = "FiraMono Nerd Font"
  nameID  1 (family)             = "FiraMono Nerd Font Medium"
  OS/2 usWeightClass             = 500
```

`fontdb` 建索引时**优先读 nameID 16**，只有它为空才退回 nameID 1（`fontdb-0.23.0/src/lib.rs:1062`）。所以 Medium face 被归到 `FiraMono Nerd Font` 家族下、权重 500；`FiraMono Nerd Font Medium` 这个名字在索引里根本不存在。

cosmic-text 通过 fontdb 找字体，因此这条绕过路径不通。想给 sidebar 加粗只剩两条路：等上游给这三个段加 `weight` 键，或者自造一份改过 nameID 16 的字体副本（本机没做）。

## fontconfig 在这里基本不生效

这一节只对 Linux 那台成立；macOS 的 Herdr UI 根本不经过 fontconfig。

Herdr 走 `fontdb` 的 `fontconfig` feature，但那个后端只用来**枚举字体目录**（`fontdb-0.23.0/src/lib.rs:501`）和读泛型别名（`serif` / `sans-serif` / `monospace`）。`<match>`、`<edit>`、`hinting`、`hintstyle`、`autohint`、家族重定向全都不读。

所以 `~/.config/fontconfig/fonts.conf` 里为 Chrome 调的那套（见 `docs/fontconfig.md`）对 Herdr 一个字都不生效。反过来也意味着 Herdr 的 hinting 完全由它自己的光栅器决定，外部没有开关。

## 字号与行高：points 与逻辑像素

下面这组换算只对 Linux 那台成立（96 dpi、`xft_scale = 1.0`）。

Ghostty 的 `font-size` 单位是 points，Herdr 的 `size` 是逻辑像素。在 96 dpi、`gtk-xft-dpi` 未设置（Ghostty 的 `xft_scale = 1.0`）时：

```
Ghostty 13.5pt × 96/72 = 18px em
```

所以要和 Ghostty 对齐，`[terminal] size` 应该是 18，不是默认的 16。

行高同理。Ghostty 用字体自己的 hhea 度量，FiraMono 是 `(935 - (-265)) / 1000 = 1.2`；Herdr 默认是 `20/14 ≈ 1.43`。`line_height = 1.2` 才是同一行距。

实测（DP-3 2560×1440 scale 1，FiraMono Nerd Font）：

| | Ghostty | Herdr 改前 | Herdr 改后 |
| --- | --- | --- | --- |
| cell 宽 | 10.8 px | 10 px | 11 px |
| cell 高 | 22 px | 25 px | 21–22 px |
| 字重 | Medium 500 | Regular 400 | Medium 500（仅 terminal） |

## CJK：cosmic-text 的硬编码 fallback 是比例字体

不设 `fallback` 时，cosmic-text 按 unicode script 查自己硬编码的列表（`cosmic-text-0.19.0/src/font/fallback/unix.rs:67`），Han 落到：

```rust
_ => &["Noto Sans CJK SC"],
```

那是**比例字体**，不是等宽。Ghostty 走 fontconfig 拿到的是 `Sarasa Mono SC`，两边中文的宽度和字重都不一样。

Herdr 的 `fallback` 键能覆盖它，四个段都要写：

```toml
fallback = ["Sarasa Mono SC", "Noto Sans Mono CJK SC"]
```

Nerd Font 图标不用写进去 —— Herdr 会自动回退到已安装的 Nerd Font 家族。显式写 `Symbols Nerd Font Mono` 反而会弹 `Configured fonts not installed` 警告：本机只有 `Symbols Nerd Font`（没有 Mono 变体），而 `fontdb` 只认族名精确匹配。

## 改不了的部分：GPUI 的文本渲染

`herdr-gpui`（20261020.1）用的是 Zed 的 GPUI —— `gpui-pre-wgpu 0.3.6` + `cosmic-text 0.19` + `swash 0.2.10` + `wgpu`，和 Ghostty 的自绘渲染器不是一回事（表里是 Linux 那台的 Ghostty；macOS 版走 CoreText）：

| | Ghostty | Herdr (GPUI) |
| --- | --- | --- |
| 光栅器 | FreeType | swash / skrifa |
| hinting | `FT_LOAD_TARGET_LIGHT`（只垂直） | `HintingMode::Smooth { lcd_subpixel: Some(Horizontal), preserve_linear_metrics: true }`（`swash-0.2.10/src/scale/hinting_cache.rs:27`） |
| atlas 采样 | 自己的 atlas，像素精确对齐 | wgpu sampler 用 `FilterMode::Linear`（`gpui_wgpu/src/wgpu_renderer.rs:1232`） |
| 亚像素定位 | 无 | `SUBPIXEL_VARIANTS_X = 4`，每个字形按 ¼ px 偏移存四份 |

后两行是"边缘发虚"的直接来源：字形落在半像素位置时会被双线性插值，Ghostty 不做这一步。这些是 `gpui_wgpu` 的编译期行为，`config-gpui.toml` 里没有任何开关。

同样无效的还有 Ghostty 的 `font-thicken`：上游文档写明只支持 macOS，Linux 上是个空转的键。Ghostty 在 Linux 上的"厚"全部来自它选了 Medium face —— 这也是为什么 Herdr 的 `weight = "medium"` 能补上大部分观感。

## 验证

```bash
# 实际 cell 尺寸（只在 client 连接时记一行，改配置后不会重连）
rg 'cell_width' ~/.config/herdr/herdr-server.log | tail -1

# GPUI 实际打开的字体文件
lsof -p "$(pgrep -x herdr-gpui)" | rg -i '\.(otf|ttf|ttc)'

# daemon 配置的诊断（不含 GUI 那份）
herdr config check

# macOS 的 GUI 那份（Linux 用 herdr-gpui config check）
/Applications/Herdr.app/Contents/MacOS/Herdr config check
```

配置写错时 GUI 会弹一张可关闭的警告卡片，例如 `Configured fonts not installed:` —— 那是唯一的 GUI 侧反馈渠道。
