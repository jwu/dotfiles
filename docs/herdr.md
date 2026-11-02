# Herdr 与 Herdr UI

Herdr 是两个程序、两处配置：

| 程序 | 来源 | 作用 |
| --- | --- | --- |
| `herdr` | 上游 `install.sh` → `~/.local/bin/herdr`（0.9.5） | daemon + TUI：会话、pane、agent 检测 |
| `herdr-gpui` | Linux：上游 Arch 包 → `/usr/bin/herdr-gpui`；macOS：`/Applications/Herdr.app`（bundle id `so.pen.herdr-gpui`） | 原生 GUI 窗口，画字的是它 |

GUI 不是 daemon 的一部分：它单独连 `~/.config/herdr/herdr-client.sock`，字体、主题、布局全在它自己的配置里。改字体只动 GUI 那份，`herdr` 的 TUI 不受影响。

Linux 那台为对齐 Ghostty 的字体观感做过一轮实测，结论是：**字重和字号能追上，hinting 追不上**。原因在下面；macOS 那套取值见「平台分派」。

## 安装

两个程序各装各的，都用上游自己的安装方法：

| 程序 | macOS | Linux | Windows |
| --- | --- | --- | --- |
| `herdr`（daemon） | `curl -fsSL https://herdr.dev/install.sh \| sh` | 同左 | `irm https://herdr.dev/install.ps1 \| iex` |
| `herdr-gpui`（UI） | `brew install penso/tap/herdr-gpui` | `curl -fsSL https://herdrui.dev/install.sh \| sh` | `irm https://herdrui.dev/install.ps1 \| iex` |

daemon 的 `install.sh` 是 per-user 的：二进制落进 `~/.local/bin`，不碰 `sudo`、不写 shell rc
（`PATH` 里没有时只打印一句提示）。所以它走 `run_onchange_before_14-herdr.sh.tmpl`，与
scrapling、dev-runtimes 同层。UI 不同：Linux 侧的 `install.sh` 要 `sudo pacman -U`，只能留在
`bootstrap/arch.sh` 的 `install_herdr_ui`；macOS 侧是 tap 里的 cask，进 `bootstrap/macos.sh` 的
`CASKS`；Windows 侧两个 installer 都是 per-user，进 `bootstrap/windows.bat` 的
`:HERDR_DAEMON` / `:HERDR_UI`。

装过之后本仓库不再代劳升级：daemon 归 `herdr update`（认 channel，默认不打断正在跑的
server），UI 归 App Updates 面板（Homebrew 认领的那份自己跑 `brew upgrade --cask`，pacman
那份走 PolicyKit）。所以 `run_onchange_before_14-herdr.sh.tmpl` 只在 `command -v herdr` 为空时下载，
重跑 bootstrap 也不会把 preview 通道降级回 stable。两个程序的版本不需要一致：UI 只是 daemon
的 client。

## agent 集成

Herdr 的 pane 列表里能显示 agent 状态（working / waiting / idle），靠的是每个 agent 一份
`herdr integration`。pi 那份是一个扩展文件：

```
herdr integration install pi
  → ~/.pi/agent/extensions/herdr-agent-state.ts
```

这个文件归 herdr 所有：文件头带 `HERDR_INTEGRATION_ID=pi` / `HERDR_INTEGRATION_VERSION=9`，
`herdr update` 之后上游会提升版本号，任何一次 install 都整份覆盖。所以它**不进源树**——
chezmoi 托管同名文件只会和上游版本打架。改为由 `run_after_52-herdr-pi-integration.sh.tmpl`
声明：每次 apply 跑一次 `herdr integration status`，看到 `pi: current` 就静默退出，
`not installed` 或版本过期就重装。这样 `herdr update` 提升集成版本、手工
`herdr integration uninstall pi`、文件被删，都在下一次 apply 自愈。

顺序有意义：`herdr integration install` 要求 `~/.pi/agent/extensions/` 已经存在（否则报
`pi extension directory not found ... install pi first`），而那个目录由 chezmoi 从
`private_dot_pi/private_agent/extensions/` 铺出来。所以脚本是 `after_` 而不是 `before_14`，
编号排在 `run_once_after_50-pi-config.sh.tmpl` 之后。

本仓库只管 pi：claude / codex / opencode 的集成在这台机器上是 `herdr` 自己装上的，它们的
配置也不归这里管。手工查看：`herdr integration status`；只想看落后的：
`herdr integration status --outdated-only`。

## 配置文件

两个程序的配置各管一处：

| 文件 | 权限 | 位置 | 谁写 |
| --- | --- | --- | --- |
| `config.toml` | 0644 | Unix `~/.config/herdr/`；Windows `%APPDATA%\herdr\` | daemon：`herdr config reset-keys`、Settings 面板 |
| `config-gpui.local.toml` | 0600 | Unix `~/.config/herdr/`；Windows `%APPDATA%\herdr\` | GUI：Settings 保存时自动写，保存即热重载 |

**daemon 的路径也分平台**：`src/config/io.rs` 的 `platform_config_dir()` 在 Windows 用
`APPDATA`，所以 `~/.config/herdr/config.toml` 在 Windows 上没人读。这条是实测出来的——先把
键位写进 `~/.config/herdr/config.toml`，`herdr config check` 照样通过，但按键不生效；改到
`%APPDATA%\herdr\config.toml` 后重载 client 才起作用。GUI 同理：Windows 上它把托管默认值刷进
`%APPDATA%\herdr\config-gpui.toml`，overrides 也读 `%APPDATA%\herdr\config-gpui.local.toml`。
实测本机 `%APPDATA%\herdr\` 里有 73 KB 的 `config-gpui.toml`、`.local.toml` 与两个 `.lock`。

其余全是运行时产物：

- `config-gpui.toml` —— 72 KB 的托管默认值，首行写着 `DO NOT EDIT -- WILL BE OVERWRITTEN`，每次启动刷新
- `*.lock`、`*.sock`、`*.log`、`session.json`、`session-snapshots/`
- `~/.local/state/herdr/` —— 窗口状态、agent 检测缓存、GPUI 日志

两个受管文件都由程序回写：Herdr UI 的 Settings 面板、`Herdr config set`、以及对话框里的「Do not ask again」，都直接写 `config-gpui.local.toml`；`herdr config reset-keys` 会备份并重写 `config.toml`。所以 `chezmoi apply` 覆盖掉 GUI 里的改动是正常现象——**要留下的设置必须写回源**：在 GUI 里试好后跑 `chezmoi add`，或者直接改源再 apply。改完 `config.toml` 用 `herdr server reload-config` 让运行中的 server 重读。

源路径：

```
dot_config/herdr/config.toml
  → ~/.config/herdr/config.toml                        (Linux / macOS)

AppData/Roaming/herdr/config.toml
  → %APPDATA%\herdr\config.toml                        (仅 Windows)

AppData/Roaming/herdr/stop-pane.ps1
  → %APPDATA%\herdr\stop-pane.ps1                      (仅 Windows)

dot_config/herdr/themes/one-dark
  → ~/.config/herdr/themes/one-dark                    (Linux / macOS)

dot_config/herdr/private_config-gpui.local.toml.tmpl
  → ~/.config/herdr/config-gpui.local.toml             (Linux / macOS)

AppData/Roaming/herdr/private_config-gpui.local.toml
  → %APPDATA%\herdr\config-gpui.local.toml             (仅 Windows)
```

`config-gpui.local.toml` 在原机上是 0600，所以带 `private_` 前缀。

## Windows：Ctrl+C 停不掉 pane 里的服务

Windows 上 pane 的 shell 是 pwsh、机器又是通过 `sshd` 连进来时（`sshd → pwsh → herdr`），
Ctrl+C 停不掉 `npm run dev` 这类前台服务。实测 0.9.5：

- 按 Ctrl+C，pane 里只出现字母 `c`。vite 的 `c` 是「清屏」快捷键，于是服务继续跑、屏幕被清空。
- `herdr pane send-keys <pane> ctrl+c` 写裸 `0x03`，同样无效；pwsh 里的 `ping.exe` 照跑。
- 同样的 `0x03` 写进 Git Bash（MSYS）pane 能中断原生子进程（`ping.exe` 打印 `Control-C` 退出），
  但那是 MSYS 自己把 `0x03` 转成了 SIGINT，与 pwsh 无关。

根因分两层：

1. SSH/ConPTY 把 Ctrl+C 作为裸字节 `0x03` 注入，ConPTY 合成出的 `KEY_EVENT_RECORD` 没有 Ctrl
   修饰位。Herdr 的 `translate_semantic_key_event`（`src/client/input/windows_vti.rs`）先过滤
   控制字符，再回退到 `windows_virtual_key_to_char_code`，`vk + 32` 得到 `Char('c')`。所以键
   绑定 `key = "ctrl+c"` 也匹配不到——它拿到的是无修饰的 `c`。
2. pwsh 的 ConPTY 不把 `0x03` 变成 `CTRL_C_EVENT`，所以往 PTY 里写控制字节也不会中断前台进程。

结论：这条链路上没有「发一个信号」的配置解。可用的办法是按 pane 的 `shell_pid` 杀子进程树：

```toml
# %APPDATA%\herdr\config.toml
[[keys.command]]
key = "prefix+shift+c"
type = "shell"
command = 'powershell -NoProfile -ExecutionPolicy Bypass -File %APPDATA%\herdr\stop-pane.ps1 -PaneId %HERDR_ACTIVE_PANE_ID% >> %TEMP%\herdr-stop.log 2>&1'
```

`stop-pane.ps1` 用 `herdr pane process-info` 拿 `shell_pid`，再对它的直接子进程 `taskkill /F /T`。
验证：在跑服务的 pane 按 `ctrl+b` 然后 `Shift+C`，`netstat -ano | findstr :5173` 应为空；
失败看 `%TEMP%\herdr-stop.log`。

注意这是「杀进程树」，不是优雅中断（vite 不会打印汇总）；在 pi 的 pane 里按会打断它正在跑的
命令，所以只在服务 pane 里按。

`~/.agents/skills/herdr-gpui-browser/SKILL.md` 也不托管：文件头带 `herdr-gpui-managed-skill` 标记，Herdr UI 会自己刷新它，纳进来只会制造 diff。

## 平台分派

daemon 和 Herdr UI 的配置都要分平台：`.chezmoiignore` 在 Windows 上排除
`~/.config/herdr/config.toml` 与 `~/.config/herdr/config-gpui.local.toml`，Windows 的两份在
`AppData/Roaming/herdr/`（`config.toml`、`private_config-gpui.local.toml`，再加
`stop-pane.ps1`）。

字体值三家都不同：Linux 那台对齐的是 Ghostty，macOS 跟系统字体，Windows 只收了 Herdr UI 首次
启动时自己写下的值（没有第二个 Windows 参照物，没做过对齐实测）。于是 Unix 那份是模板，按
`.chezmoi.os` 分两套：

| 段 | macOS | Linux | Windows |
| --- | --- | --- | --- |
| `[terminal]` | FiraMono 16 | FiraMono 18、`weight = "medium"`、`line_height = 1.2` | FiraMono 16 |
| `[sidebar]` / `[tabs]` | FiraMono 14 | FiraMono 16，CJK fallback 到 Sarasa Mono | FiraMono 14 |
| `[ui]` | PingFang SC 14 | FiraMono 16，CJK fallback 到 Sarasa Mono | Microsoft YaHei UI 14 |

macOS 那套沿用这台 Mac 的 Ghostty：`font-size = 16`、中文回退 `PingFang SC`（见 `dot_config/ghostty/config`）。

字体键的可用性是 GPUI 的，macOS 与 Linux 一样；下面的实测数值来自 Linux 那台。

## 主题：为什么 Herdr 里要自带一份

Herdr 内置的 `Atom One Dark` 主题，终端背景是 `#21252b`（从 Herdr 0.9.5 二进制里的主题定义读出，
与 Ghostty 的 `Atom One Dark` 同名同色）。pi 的自定义主题 `one-dark` 里 `toolSuccessBg = bg_d =
#21252b`，于是工具执行块的背景与 Herdr 的终端背景逐字节相同、看上去像是丢了背景。

Ghostty 那边背景是 `#282c34`（`dot_config/ghostty/config` 覆盖了 `One Half Dark` 的底），所以同
一个 pi 主题在 Ghostty 里工具块有可见底色。差异来自终端，不在 pi。

因此 herdr 侧自带一份主题 `dot_config/herdr/themes/one-dark`：

- 格式是 Ghostty 主题格式（`background` / `foreground` / `cursor-*` / `selection-*` /
  `palette = N=#...`），没有 Herdr 私有字段
- 取值抄 Ghostty 实际生效的那套：`One Half Dark` + `dot_config/ghostty/config` 里的 OneDark 覆盖，
  `background = #282c34`
- 配置里写 `~/` 路径而不是主题名。文档只保证「Ghostty theme name、绝对路径、`~/` 路径」三种写法，
  没有写明 `herdr/themes` 搜索目录究竟落在 `$XDG_CONFIG_HOME` 还是 `$XDG_DATA_HOME`，用路径无歧义

改主题颜色时 Herdr UI 会热重载 `config-gpui.local.toml`，不需要重启；pi 的工具块颜色不用动。

Windows 走另一条路。Herdr UI 在 Windows 上把主题设成只读（Settings 里只给 This app /
Follow Herdr，提示原文是 “Herdr's themes are read-only on this platform”），不加载外部主题文件，
所以 `dot_config/herdr/themes/one-dark` 在 Windows 上是死文件。改用：

```toml
# AppData/Roaming/herdr/private_config-gpui.local.toml
theme = "Follow Herdr"
```

跟随 daemon 的内置 `one-dark`。它的 `panel_bg` 是 `#282c34`（`src/app/state.rs` 的
`one_dark()`），和 Ghostty 一致，pi 的 `toolSuccessBg = #21252b` 仍然可见。daemon 侧只需
`%APPDATA%\herdr\config.toml` 里保留 `[theme] name = "one-dark"`，不需要自定义主题文件。

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
