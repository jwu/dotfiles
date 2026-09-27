# Dotfiles

我的终端环境。一份 [chezmoi](https://www.chezmoi.io/) 源，描述三台机器——Arch Linux 的桌面
工作站、macOS、Windows——`git pull` 之后一条 `chezmoi apply`，它们就变成这里描述的样子。

## 配了什么

### Arch Linux —— 一整套 Wayland 桌面

- **桌面**：niri（平铺合成器，主用）与 Hyprland，含窗口规则、手势、触控板与输入设备调校
- **终端**：Ghostty 为主；Alacritty 按它逐项对齐字体、色板、光标、内边距与键位
- **状态栏**：Waybar，带自定义模块——GPU 使用率与温度、磁盘温度、网络、蓝牙、**每个窗口**的 CPU
- **锁屏**：hyprlock，按当前屏幕尺寸从三套样式里挑一套，闲置一分钟后熄屏
- **输入法**：Fcitx5 + Rime（雾凇拼音），含按键补丁、候选窗配色与托盘图标
- **命令行**：zsh + Oh My Zsh、starship、zoxide、fzf，以及 `eza` / `bat` / `fd` / `ripgrep` / `delta` 的配置
- **工具**：yazi、gitui、glow
- **编辑器**：Neovim + Neovide
- **杂项**：GTK4 全局直角微调、xwayland-satellite（跑 X11 应用）

### macOS —— 与 Linux 共用一份源

- **终端**：Ghostty 与 Alacritty，各有适配这份系统的配置（字号、原生标签页、`cmd+n` / `cmd+w`）
- **窗口管理**：AeroSpace
- **输入法**：Squirrel（鼠须管）
- **Shell**：zsh，含 Apple Silicon 的 PyTorch MPS 变量与 Homebrew 的 nvm
- **编辑器**：Neovim + Neovide、Zed
- **共用**：yazi、gitui、glow、git 配置

### Windows —— 终端与 Shell 增强

- **终端**：Alacritty、WezTerm，都起一个普通的 `cmd.exe`
- **Shell**：Clink 增强的 CMD（Alacritty / WezTerm 执行 `session.cmd` 注入，Win+R 的 cmd 没有），配 starship、fzf、zoxide、eza、uutils coreutils
- **输入法**：Weasel（小狼毫）
- **编辑器**：Neovim + Neovide、Zed
- **共用**：yazi、gitui、glow

### 三台共用

pi 的 agent 配置（`agents` / `skills` / `prompts` / `themes` / 键位）、git 的公共设置
（delta、OneHalfDark、`gh` 凭据助手）、FiraMono Nerd Font 与 One Dark 配色。

---

## 快速开始

### 新机器

装 chezmoi 这一步不可能由 chezmoi 自己完成，所以入口脚本独立于源之外：

```bash
# Linux
sh -c "$(curl -fsLS https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/arch.sh)"

# macOS（Homebrew 要先装好）
bash -c "$(curl -fsLS https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/macos.sh)"
```

```bat
:: Windows（curl 是系统自带的；无需管理员）
curl -fsSL https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/windows.bat -o "%TEMP%\dotfiles-bootstrap.bat"
"%TEMP%\dotfiles-bootstrap.bat"
```

三个脚本做同一件事：装 chezmoi → clone 到 `~/bin/dotfiles`（Windows 是 `%USERPROFILE%\bin\dotfiles`）
→ 写下 chezmoi 的 `sourceDir` → 装工具 → `chezmoi init --apply`。Windows 那份还负责三个用户级环境变量
（Clink 由终端执行 `session.cmd` 注入，不写 cmd 的 AutoRun）。

Linux 与 macOS 的 bootstrap 是各自平台上**唯一**需要 root 或终端的地方（`chsh` 走 PAM、
`/etc/shells` 要改、TTY 字体与 `drivetemp` 要 root）。Windows 那份**不需要任何提权**：scoop
与它装的 Nerd Font 都是 per-user。把这类动作集中在这里，`chezmoi apply` 才能不需要密码、
也不需要终端——CI、包装脚本、agent 里都能直接跑。

### 已经接入的机器

```bash
git -C ~/bin/dotfiles pull
chezmoi diff --include=files    # 先看会改什么
chezmoi apply -v
```

> **别跳过 `diff`。** `apply` 的语义是「让家目录匹配源」，所以源里那份若是旧的，它会用旧内容
> 覆盖你家目录里的新内容。一台尚未对账过的机器，完整流程见
> [`docs/onboarding-a-machine.md`](docs/onboarding-a-machine.md)。

## 日常

| 命令 | 作用 |
| --- | --- |
| `chezmoi diff --include=files` | 配置层会改什么。干净的判据是**必须为空** |
| `chezmoi apply -v` | 应用改动。再跑一次，第二次应当零输出 |
| `chezmoi status` | A / M / D 与待跑脚本的紧凑视图 |
| `chezmoi managed --include=files` | 源目前管着哪些目标 |
| `chezmoi execute-template < f.tmpl \| diff - ~/path` | 单独渲染一个模板并比对 |
| `chezmoi cd` | 进入源目录 |

改完配置源、准备提交之前：

```bash
chezmoi diff --include=files    # 必须为空
chezmoi apply -v                # 跑两次，第二次必须零输出
```

`run_*` 脚本按前缀决定触发时机：`run_once_` 只跑一次，`run_onchange_` 在内容变化时重跑，
`run_after_` 保证在所有文件落盘之后。一个**失败**的脚本也会被记进 `scriptState` 而不再重试，
修好之后要先清记账：

```bash
chezmoi state delete-bucket --bucket=scriptState
```

## 它是怎么组织的

```
dotfiles/
  ├── .chezmoiignore     # 决定哪些源文件不落到家目录（本身是模板）
  ├── bootstrap/         # 装机入口：唯一需要 root / 终端的层
  ├── run_*.sh           # chezmoi 在 apply 期间执行的动作
  ├── scripts/           # run_* 的辅助文件与被编译的源码，不部署到家目录
  ├── dot_*/             # chezmoi 源：dot_ = 目标名前置一个点
  ├── private_*/         # 0700 / 0600 的目标
  ├── AppData/           # Windows 专有目标
  └── docs/              # 设计记录与踩坑
```

职责切成三层：

| 层 | 手段 | 需要 root |
| --- | --- | --- |
| 配置同步 | `chezmoi apply`：源里 80 个文件，按平台筛出该机器要的那些（macOS 30 个 / Linux 70 个） | 否 |
| 装机（一次性） | `bootstrap/<platform>.sh` | 是 |
| 运行时动作 | `run_*` 脚本，按内容 hash 记账 | 否 |

chezmoi 的源路径与目标路径不一定逐字对应：`dot_` 加前置点、`private_` 是 0600/0700、
`executable_` 是 755、`.tmpl` 是模板。**这些属性前缀会进源路径**，所以 `include` 之类要写源
路径而不是目标路径——踩过的例子记在 [`docs/chezmoi-notes.md`](docs/chezmoi-notes.md)。

完整的设计推导——源布局、四处模板化、git 配置的公共层与个人层、`pi` 的可变状态、fcitx5 的
运行时边界、各平台接入的经过——都在 [`docs/design.md`](docs/design.md)。

## 文档

- [`docs/design.md`](docs/design.md) — 仓库的设计推导与实施记录。遇到结构性问题先读它。
- [`docs/onboarding-a-machine.md`](docs/onboarding-a-machine.md) — 在一台新机器上接入的完整流程，给那台机器上的 agent 读。
- [`docs/chezmoi-notes.md`](docs/chezmoi-notes.md) — chezmoi 的坑：目标路径匹配、双向排除、空父目录、目录权限、脚本记账，以及**家目录里不纳入源的清单**。
- [`docs/chezmoi-migration.md`](docs/chezmoi-migration.md) — chezmoi 方案成型之前的评估记录：边界划分、源目录布局、四处模板化。
- [`docs/alacritty.md`](docs/alacritty.md) — Alacritty 与 Ghostty 的逐项对齐，以及 Wayland 下的窗口装饰。
- [`docs/shell.md`](docs/shell.md) — zsh 配置里的两个坑：nvm 的两种装法与 Apple Silicon 的 MPS 变量。
- [`docs/windows-shell.md`](docs/windows-shell.md) — Windows 的 shell 层：scoop、Clink 的 `session.cmd` 接线、用户环境变量、批处理必须 CRLF。
- [`docs/waybar.md`](docs/waybar.md) — 模块基线与行高约定、配色、`cffi/niri-windows`、GPU 与磁盘取值脚本。
- [`docs/lockscreen.md`](docs/lockscreen.md) — hyprlock / swaylock、熄屏计时、按屏幕尺寸挑样式。
- [`docs/niri.md`](docs/niri.md) — focus-follows-mouse、`warp-mouse-to-focus`、光标隐藏。
- [`docs/wayland-attach.md`](docs/wayland-attach.md) — 从 ssh / tty 附加到 niri 会话：`wattach` / `wdetach` / `wstat`、变量来源与存活校验。
- [`docs/ghostty.md`](docs/ghostty.md) — quick terminal 的 `global:` 绑定、`bold-is-bright` 的迁移。
- [`docs/ghostty-titlebar.md`](docs/ghostty-titlebar.md) — GTK 标题栏几何、undershoot 线、配色预设。
- [`docs/ghostty-gl-version.md`](docs/ghostty-gl-version.md) — Intel HD 4000 上保住硬件渲染的 MESA override。
- [`docs/gtk4.md`](docs/gtk4.md) — GTK4 全局 CSD 直角微调。
- [`docs/bluetooth.md`](docs/bluetooth.md) — BlueZ OBEX agent 单槽位与冲突诊断。
- [`docs/xwayland-satellite.md`](docs/xwayland-satellite.md) — X11 弹窗焦点、Steam 顶栏菜单闪退、AUR `-git` 包的取舍。
- [`docs/ime-icons.md`](docs/ime-icons.md) — Fcitx5 托盘图标的覆盖规则与状态对应。
- [`docs/rime/rime-config.md`](docs/rime/rime-config.md) — Rime 词库、补丁写法、`__patch` 的坑。
- [`docs/zed/`](docs/zed/)、[`docs/aerospace/`](docs/aerospace/)、[`docs/obsidian/`](docs/obsidian/)、[`docs/totalcmd/`](docs/totalcmd/)、[`docs/inputsource-pro/`](docs/inputsource-pro/) — 各 GUI 应用的配置说明。

源码里的注释保持简短；推导写在上述文档里。

## 参考

- 终端与 CLI 工具：[`docs/reference-terminal.md`](docs/reference-terminal.md)
- 桌面应用与工具：[`docs/reference-desktop.md`](docs/reference-desktop.md)
