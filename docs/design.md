# 设计记录

`jwu/dotfiles` 的设计推导与实施记录。

- 项目简介、快速上手与用法：见 [`../README.md`](../README.md)
- 协作规则（含注释规范）：见 [`../AGENTS.md`](../AGENTS.md)

---

用 [chezmoi](https://www.chezmoi.io/) 管理的机器配置与装机脚本**唯一真源**。

本仓库**取代** `configs` 与 `desktop-settings`：这两个仓库的全部内容（配置文件、安装脚本、
装机逻辑、文档）都迁入本仓库，之后不再出现在 `~/bin` 下。`pi-config` 是唯一例外，继续保留，
因为它承载 pi 的 TypeScript 扩展工程与 npm 插件。

由此产生一条硬约束：**本仓库的脚本不得出现对 `configs` / `desktop-settings` 的任何 clone、
路径引用或依赖**。对 `pi-config` 的 clone 是允许且必要的，由本仓库的脚本负责触发。

## 仓库边界

| 仓库 | 状态 | 内容 |
| --- | --- | --- |
| **dotfiles**（本仓库） | 新建，唯一真源 | chezmoi 源（配置 + 模板）+ `bootstrap/` 装机入口 + `run_*` 动作脚本 |
| `configs` | **退役** | 内容全部迁入本仓库后删除，含 `install.sh`、`config.sh`、`win/install.bat`、`docs/` |
| `desktop-settings` | **退役** | 内容全部迁入本仓库后删除，含 `fcitx5/install-linux.sh`、`update-rime-dict.sh`、文档 |
| `pi-config` | **保留** | `extensions/*.ts`、`tests/`、`package.json`、`tsconfig.json` |
| `install-arch` | **并入** `bootstrap/` | 它本质是「新机器第一步」，与 `configs` 一起退役 |

保留它的理由只有一个：`settings.json` 的 `extensions` 字段要**活加载**这份 checkout 里的
`extensions/*.ts`，所以仓库得待在固定路径上。那份 `settings.json` 本身现在由 chezmoi 的
`create_settings.json.tmpl` 渲染（见「pi 的可变状态」），`pi-config` 侧从此只剩 `extensions/`
与它的工程文件。

## 安装入口：`bootstrap/`

装 chezmoi 这一步**不可能**由 chezmoi 自己完成（鸡生蛋），所以入口脚本独立于 chezmoi 源：

```
bootstrap/
├── arch.sh        Linux：装 chezmoi → clone 到 ~/bin/dotfiles → pacman/yay 装包（sudo）→ chezmoi init --apply
├── macos.sh       macOS：装 chezmoi → clone 到 ~/bin/dotfiles → brew 装包（无需 sudo）→ chezmoi init --apply
└── windows.bat    Windows：装 chezmoi（winget→scoop）→ clone → scoop 装工具与字体 → 用户环境变量 → chezmoi init --apply
```

新机器一行式：

```bash
# Linux
sh -c "$(curl -fsLS https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/arch.sh)"
# macOS（Homebrew 本身要先装好）
bash -c "$(curl -fsLS https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/macos.sh)"
```

```bat
:: Windows（在管理员终端里跑第二行）
curl -fsSL https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/windows.bat -o "%TEMP%\dotfiles-bootstrap.bat"
"%TEMP%\dotfiles-bootstrap.bat"
```

`bootstrap/arch.sh` 由 `install-arch/install.sh` 演化而来，但编排目标从「clone 三个仓库并按序
跑各自的脚本」变成「clone 本仓库 + 装包 + `chezmoi init --apply`」。`macos.sh` 是它的 macOS
对应物：包清单演化自已退役的 `jwu/configs` 的 `mac/install.sh`（`ripgrep` 出自同一份仓库的
`mac/install_x86_64.sh`），不是凭空写的。

macOS 那份的用法写 `bash -c` 而不是 `sh -c`：系统的 `/bin/sh` 是 POSIX 模式的 bash 3.2，
不支持数组和 `local`，而脚本两者都用。同理它全文没有 bash 4 才有的 `&>` 重定向。

`bootstrap/windows.bat` 是 Windows 对应物，起点是 `jwu/configs` 的
「clone → `win/install.bat` → `win/config.bat` → 终端拉起 `init.bat`」。现在的分层完全不同：
工具交给 scoop，字体由 scoop 以 per-user 方式装（于是**不需要管理员**），Clink 由终端执行
`session.cmd` 注入（不用 `clink autorun`，因为 `os.setenv` 改不了 cmd 的环境块），环境变量搬进
`HKCU\Environment`，codepage 与别名搬进 Clink Lua——
`win/` 整个目录（`install.bat` / `init.bat` / `cmds/*.cmd`）随之删除。完整推导与踩到的坑
（尤其**批处理必须 CRLF**）见 [`docs/windows-shell.md`](windows-shell.md)。用 `.bat` 而不是
PowerShell 是为了和原来的 Windows 脚本层一致；批处理没有 `curl | sh` 那样的管道形式，所以
入口是「先下到 `%TEMP%` 再执行」两行。

**Linux 与 macOS 的 bootstrap 是各自平台上唯一需要 root 或终端的脚本。** Linux 侧的 sudo
动作：装 41 个包、yay 与 AUR 的 xwayland-satellite-git、`chsh`（走 PAM，同样需要终端）、TTY
字体、drivetemp。macOS 侧只有两处：`chsh`，以及首次把 Homebrew 的 zsh 加进 `/etc/shells`。
**Windows 侧不需要任何提权**：scoop 是 per-user 安装，字体 manifest 也写
`%LOCALAPPDATA%\Microsoft\Windows\Fonts`，所以 `bootstrap/windows.bat` 与 `chezmoi apply`
都既不需要管理员、也不需要终端。`run_*` 脚本只剩不需要 root 的部分——这正是 Oh My Zsh 与
zsh-autosuggestions 在两侧都留在 `run_once_before_10`、而不进 bootstrap 的原因。

这个切分是刻意的，而不是为了好看：sudo 的 `tty_tickets` 让凭据缓存按 TTY 隔离，非 TTY 的
子进程无法输入密码；而 chezmoi 又会在任一 run 脚本失败时中止整个 apply。把 root 工作集中
在 bootstrap，`chezmoi apply` 才能在没有终端的自动化环境（CI、包装脚本、agent）里跑——
实测退出码 0。

`bootstrap/` 和 `docs/`、`scripts/` 一样必须在 `.chezmoiignore` 里排除——否则 chezmoi 会在
家目录创建 `~/bootstrap/arch.sh`。

## 源布局与来源映射

chezmoi 命名规则：`dot_` = 前置点，`executable_` = 可执行位，`private_` = 0600，
`.tmpl` = 模板。「来自」列是迁移期的对账依据，这些文件迁完后原仓库即删除。

```
dot_zshrc.tmpl                         ← configs: linux/.zshrc + mac/.zshrc 合并
dot_aerospace.toml                     ← desktop-settings: aerospace/.aerospace.toml（mac）
dot_omnisharp/omnisharp.json           ← configs: common/.omnisharp/
dot_config/
  alacritty/alacritty.toml             ← configs: linux/.config/alacritty/
  autostart/nm-applet.desktop          ← configs: linux/.config/autostart/
  environment.d/fcitx5.conf            ← configs: linux/.config/environment.d/
  fcitx5/private_profile               ← desktop-settings: fcitx5/profile（600 → private_，见下）
  fcitx5/conf/classicui.conf           ← desktop-settings: fcitx5/classicui.conf
  ghostty/config.ghostty               ← configs: linux/.config/ghostty/
  ghostty/titlebar*.css                ← configs: linux/.config/ghostty/
  git/config.tmpl                      ← configs: common/.gitconfig
  gitui/theme.ron                      ← configs: common/.config/gitui/
  glow/one-dark.json                   ← configs: common/.config/glow/
  gtk-4.0/gtk.css                      ← configs: linux/.config/gtk-4.0/
  hypr/*                               ← configs: linux/.config/hypr/
  neovide/config.toml                  ← configs: common/.config/neovide/
  nvim/init.lua                        ← configs: common/.config/nvim/
  starship.toml.tmpl                   ← configs: linux/ + mac/ 合并
  swaylock/config.tmpl                 ← configs: linux/.config/swaylock/
  swaylock/backgrounds/*.webp          ← configs: linux/backgrounds/（6 张）
  waybar/*                             ← configs: linux/.config/waybar/
  yazi/{yazi.toml,theme.toml}          ← configs: common/.config/yazi/
  zed/settings.json                    ← desktop-settings: zed/settings.json
  zellij/config.kdl                    ← configs: linux/.config/zellij/
dot_local/
  bin/executable_niri-clipboard-history  ← configs: linux/.local/bin/
  bin/executable_niri-lock
  bin/executable_niri-open-terminal-below
  share/applications/neovide.desktop     ← configs: linux/neovide.desktop
  share/fcitx5/themes/jwu/theme.conf     ← desktop-settings: fcitx5/themes/jwu/
  share/fcitx5/rime/default.custom.yaml  ← desktop-settings: rime/
  share/fcitx5/rime/rime_ice.custom.yaml
  share/icons/**                         ← configs: linux/.local/share/icons/
dot_pi/agent/
  agents/*.md                          ← pi-config: agents/
  prompts/commit.md                    ← pi-config: prompts/
  skills/**                            ← pi-config: skills/
  themes/one-dark.json                 ← pi-config: themes/
  keybindings.json                     ← pi-config
  APPEND_SYSTEM.md                     ← pi-config
  create_settings.json.tmpl            ← 新机器的初始 settings.json（`create_`，只落地一次）
  create_mcp.json                      ← 新机器的初始 mcp.json（同上）
# macOS 专有（本机不存在，从仓库搬入）
dot_aerospace.toml                         ← desktop-settings: aerospace/.aerospace.toml
dot_config/ghostty/config                  ← configs: mac/.config/ghostty/config
Library/Rime/squirrel.custom.yaml          ← desktop-settings: rime/squirrel.custom.yaml
# Windows 专有（本机不存在，从仓库搬入）
AppData/Roaming/alacritty/alacritty.toml   ← configs: win/alacritty.toml
# starship 后来不再是 Windows 专有：Windows 也读 ~/.config/starship.toml，
# 于是回到共用的 dot_config/starship.toml.tmpl。见「Windows 接入」
AppData/Roaming/Rime/weasel.custom.yaml    ← desktop-settings: rime/weasel.custom.yaml
AppData/Local/clink/clink_settings         ← configs: win/clink_profile/
AppData/Local/clink/{clink,fzf,zoxide}.lua ← configs: win/clink_scripts/
AppData/Local/nvim/init.lua                ← configs: common/.config/nvim/init.lua
AppData/Roaming/neovide/config.toml        ← configs: common/.config/neovide/
AppData/Local/glow/Config/one-dark.json    ← configs: common/.config/glow/
AppData/Roaming/gitui/theme.ron            ← configs: common/.config/gitui/
AppData/Roaming/yazi/config/*.toml         ← configs: common/.config/yazi/
AppData/Roaming/Zed/private_settings.json  ← Windows 接入时从本机收进（Unix 侧是 dot_config/zed/）
.wezterm.lua                               ← configs: common/.wezterm.lua（仅 Windows）
.chezmoiignore
bootstrap/arch.sh
run_*.sh
```

两处**路径重映射**（源与目标层级不同，不能整体搬）：

- `linux/backgrounds/*.webp` → `~/.config/swaylock/backgrounds/`
- `linux/neovide.desktop` → `~/.local/share/applications/neovide.desktop`

### 属性前缀会进源路径

chezmoi 依据权限位给源文件加前缀，所以**源路径与目标路径不一定逐字对应**。本仓库里目前有
九个，其中 `private_` 那个曾经绊了一下：`run_onchange_after_40-fcitx5.sh.tmpl` 的 `include`
写目标路径 `profile` 会直接渲染失败，必须写源路径 `private_profile`。

| 源路径 | 目标 | 权限 |
| --- | --- | --- |
| `dot_config/fcitx5/private_profile` | `~/.config/fcitx5/profile` | 600 |
| `dot_config/zed/private_settings.json` | `~/.config/zed/settings.json` | 600 |
| `private_dot_pi/private_agent/**` | `~/.pi/agent/**` | 700（目录） |
| `private_Library/Rime/squirrel.custom.yaml` | `~/Library/Rime/squirrel.custom.yaml` | 700（目录） |
| `dot_config/waybar/scripts/executable_disk-temp.sh` | `~/.config/waybar/scripts/disk-temp.sh` | 755 |
| `dot_local/bin/executable_niri-clipboard-history` | `~/.local/bin/niri-clipboard-history` | 755 |
| `dot_local/bin/executable_niri-lock` | `~/.local/bin/niri-lock` | 755 |
| `dot_local/bin/executable_niri-open-terminal-below` | `~/.local/bin/niri-open-terminal-below` | 755 |

后加的三个 `private_` 来自 macOS 接入，它们不是风格选择：git **完全不记录目录权限**，文件也
只记录可执行位，所以家目录上的 `0700` / `0600` 除了写进源文件名没有别处可以表达。chezmoi 的
默认值是目录 `0755`、文件 `0644`，而 `~/.pi` 里躺着 `auth.json`、`~/Library` 是 macOS 的私有
目录，两者都不该被放宽成「本机其他用户可浏览」。代价是同一份源在 Linux 上也会收敛到相同的
权限位——这正是想要的，Linux 侧没有理由比 macOS 更宽松。

`configs` 的 `common/` 概念在本仓库消失：`common` + `linux` + `mac` 三份塌缩成一份文件加模板分支。

### 已导入的文件

阶段 1 与平台搬入已完成（见「实施状态」）。源里共 **77 个文件** = 67 个 Linux 目标 +
3 个 macOS 专有 + 7 个 Windows 专有；5 个模板。`chezmoi diff` 在 Linux 上为空，macOS /
Windows 目标由 `.chezmoiignore` 按 OS 排除。

> Windows 接入又添了 5 个 Windows 目标（yazi / gitui / glow / zed），见「Windows 侧」。

## 模板化的文件

| 文件 | 差异 | 处理 |
| --- | --- | --- |
| `dot_zshrc.tmpl` | 26 行（Linux 独有 ZVM / waybar announce / `PI_NERD_FONTS`；macOS 独有 brew nvm 与 `/Applications/*` alias） | **已完成**：`{{ if eq .chezmoi.os }}` 分支，两侧渲染逐字节一致 |
| `dot_config/starship.toml.tmpl` | Linux / macOS 差 2 行（`>` vs `❯`）；Windows 接入时又多了 `add_newline = false` | **已完成**：三平台一份模板、一个目标（`~/.config/starship.toml`） |
| `waybar/modules.json` | 当前是 `__WAYBAR_MODULE_DIR__` 占位符经 `sed` 生成的绝对路径 | `{{ .chezmoi.homeDir }}/.config/waybar` |
| `swaylock/config` | 同理，`__SWAYLOCK_BACKGROUND_DIR__` | `{{ .chezmoi.homeDir }}/.config/swaylock/backgrounds` |
| `git/config.tmpl` | `gh` 写入的 credential 段含 `/home/jwu` | 模板化 `{{ .chezmoi.homeDir }}`，见下 |
| `alacritty.toml.tmpl` | 两侧是**两份独立配置**而不是新旧版本：macOS 那份绑 `cmd+n` / `cmd+w`、字号 16；Linux 那份对着 `config.ghostty` 重写过，注释全在讲 niri / Wayland / `sctk-adwaita` | `{{ if eq .chezmoi.os }}` 两分支各放全文，两侧渲染逐字节一致 |

waybar 的 `module_path` 和 swaylock 都不展开 `~`（见 `docs/waybar.md`、`docs/lockscreen.md`，
两文件随 `configs` 迁入），必须有绝对路径，`.chezmoi.homeDir` 正好提供这个，且不再需要
`sed` 这一步。

**已完成**：阶段 1 导入时，`waybar/modules.json` 与 `swaylock/config` 存的是**已替换的绝对
路径**（`/home/jwu/...`），因为它们是从家目录读的。两者已加 `.tmpl` 后缀并替换成
`.chezmoi.homeDir`，是等价变换（`diff` 保持为空）。

### `~/.config/git/config` 与 gh 抢写

实测家目录版本比 `common/.gitconfig` 多出 `gh auth login` 自动写入的段：

```
[credential "https://github.com"]
	helper =
	helper = !/home/jwu/.local/bin/gh auth git-credential
```

**`[include]` 分离解决不了这个问题**：`gh` 写的是 git 的默认全局位置
`~/.config/git/config`，不管里面有没有 include，它照样会往这个文件里写，只是把冲突
换了个位置。

实际采用的方案是**把 credential 段模板化**，`/home/jwu` 换成 `.chezmoi.homeDir`：

```ini
# dot_config/git/config.tmpl
[credential "https://github.com"]
	helper =
	helper = !{{ .chezmoi.homeDir }}/.local/bin/gh auth git-credential
```

选择的理由：渲染结果与 `gh` 写入的内容一致，`diff` 稳定且保持为空，硬编码路径同时
消除。代价是 chezmoi 与 `gh` 名义上共管一个文件——若 `gh` 某次改了格式，`chezmoi diff`
会显示差异，`chezmoi apply` 规范化回去，功能不受影响。

同时保持 XDG 路径 `~/.config/git/config` 而**不是** `~/.gitconfig`，否则会在 `~` 下意外
创建 `~/.gitconfig`。

### 公共层与个人层

macOS 接入时发现两个平台其实共用同一批设置，只是各自把「身份」放进了不同的文件：Linux 把
`[user]` 与 `[http] proxy` 硬编码进 `~/.config/git/config`，macOS 用 `~/.gitconfig` 的
`includeIf` 按目录切换身份。同一份 `[delta]` / `[core]` / `[i18n]` 于是被维护了两遍。

现在按 git 自己的读取顺序分层，**并且只纳管公共的那一层**：

| 层 | 文件 | 内容 | 归属 |
| --- | --- | --- | --- |
| 公共 | `~/.config/git/config`（`dot_config/git/config.tmpl`） | `[init]`、`[core]`、`[interactive]`、`[delta]`、`[i18n]`、`[credential]` | 本仓库 |
| 个人 | `~/.gitconfig` | Linux：`[user]` + `[http] proxy`；macOS：`[user] useConfigOnly` + `includeIf` 与两个身份文件 | **每台机器手工维护** |

git 先读 XDG 那份、再读 `~/.gitconfig`，后者覆盖前者，所以个人层天然优先——不需要任何
`[include]` 把两者缝起来，也不存在「谁先加载」的顺序问题。

**个人层不进仓库是刻意的。** 它含邮箱、人名（macOS 这边是 `~/.gitconfig` 加它 `includeIf` 引用
的 `~/.gitconfig-<身份>`）以及 `~/dev/<雇主>/` 这样的工作目录结构，那是本机配置，不是可以
公开的源。曾经把这一层做成 `dot_gitconfig.tmpl` 纳管过，后来用 `chezmoi forget` 摘掉了：它删除
源条目但保留家目录文件，所以那几份文件原样留在家里，只是不再由 chezmoi 过问。新机器上要手工
配一次身份。

`gh` 仍然只往 `~/.config/git/config` 写，所以它回填的 credential 段落在公共层，与机器无关。

## pi 的可变状态

`~/.pi/agent/` 下的文件分三类：

| 类型 | 文件 | 处置 |
| --- | --- | --- |
| 静态资源（pi 只读） | `agents/`、`skills/`、`prompts/`、`themes/` | **已纳入**，源是真源 |
| 人工维护的配置 | `keybindings.json`、`APPEND_SYSTEM.md` | **已纳入**，源是真源 |
| 会被 pi 回写 | `settings.json`、`mcp.json` | **已纳入**，但用 `create_` 前缀 |
| 工具独占写入 | `extensions/*.json`（pi-ask 写回） | **排除** |
| 凭据与运行时 | `auth.json`、`sessions/`、`models-store.json`、`*-cache.json`、`install/`、`bin/`、`npm/` | **绝不纳入** |

`settings.json` 会被 pi 写入 `lastChangelogVersion`（看过哪版 changelog）、
`defaultProvider` / `defaultModel` / `defaultThinkingLevel`（`/model` 切换），`mcp.json` 会被
`/mcp` 改写。这两份用 `create_` 前缀：**只在目标不存在时**渲染一次，之后不再碰。新机器因此
拿到一份能开箱用的配置，本机后来被 pi 改成什么样，都不会在下次 apply 时被抹掉。

代价是源与磁盘会漂移：源里的 `packages` / `defaultTools` 改动**不会**传到已经落地过的机器，
要手工同步。这是刻意的取舍——把它们当纯真源管的话，`/model` 切一次模型就会留下永久非空的
`chezmoi diff`，而每次 apply 都在和 pi 抢同一份文件。

两份源都是**新机器的初始值**，不是任何一台机器的现状：`create_settings.json.tmpl` 的
`packages` 用 npm 包名（`npm:@johnnywu/pi-filechanges` …），因为新机器上还没有 `~/dev/jwu/*`
的 checkout；本机 macOS 是开发机，已经手工把 `packages` 换成那些本地路径，`create_` 不会再
覆盖它。`extensions` 按 `.chezmoi.os` 渲染：Unix 是 `~/bin/pi-config/extensions`，Windows 是
`c:/bin/pi-config/extensions`（pi 会展开 `~`，见 `dist/utils/paths.js` 的 `expandTilde`）。

`extensions/eko24ive-pi-ask.json` 有被 pi-ask 写回的历史（见 `pi-config` 的
`"pi-ask: sync config back to schemaVersion 5"` 提交），它和 `auth.json` 一样不纳入。

## fcitx5 的运行时边界

`~/.local/share/fcitx5/rime/` 实测 **156 MB**，内含下载的词库、编译产物 `build/` 和用户词频
`user.yaml`。`desktop-settings/AGENTS.md` 明确写了这些不进仓库。本仓库只纳入 5 个用户补丁：

```
~/.config/fcitx5/profile
~/.config/fcitx5/conf/classicui.conf
~/.local/share/fcitx5/themes/jwu/theme.conf
~/.local/share/fcitx5/rime/default.custom.yaml
~/.local/share/fcitx5/rime/rime_ice.custom.yaml
```

`conf/cached_layouts`、`conf/notifications.conf` 是 fcitx5 运行时生成，不纳入。
`~/.config/fcitx5/` 与 `rime/` 下现存 50 个 `*.bak.*` 也不纳入。

## Windows 侧

`win/config.bat` 原本不是复制内容，而是**生成引用文件**：`%APPDATA%\alacritty\alacritty.toml`
里写 `import = ["%MY_CONFIGS%\alacritty.toml"]`，nvim / neovide / wezterm 同理。chezmoi 接管
内容文件后这些指针全部失去意义，`config.bat` 已**退役删除**。

### 已确定的目标路径

`init.bat` 揭示了 win 侧的真实模式：它**不复制**配置，而是靠环境变量与参数**原地引用
仓库**：

```bat
clink inject --quiet --profile "%MY_CONFIGS%\clink_profile" --scripts "%MY_CONFIGS%\clink_scripts"
set "STARSHIP_CONFIG=%MY_CONFIGS%\starship.toml"
call "%MY_CONFIGS%\cmds\aliases.cmd"
```

按「改成 chezmoi 复制到位」的决定，已搬入的 10 个文件及目标：

| 源（仓库） | chezmoi 目标 |
| --- | --- |
| `win/alacritty.toml` | `AppData/Roaming/alacritty/alacritty.toml` |
| `win/starship.toml` | 不复存在：并入共用的 `dot_config/starship.toml.tmpl` |
| `win/clink_profile/clink_settings` | `AppData/Local/clink/clink_settings` |
| `win/clink_scripts/{clink,fzf,zoxide}.lua` | `AppData/Local/clink/` |
| `desktop-settings/rime/weasel.custom.yaml` | `AppData/Roaming/Rime/weasel.custom.yaml` |
| `configs/common/.config/nvim/init.lua` | `AppData/Local/nvim/init.lua` |
| `configs/common/.config/neovide/config.toml` | `AppData/Roaming/neovide/config.toml` |
| `configs/common/.wezterm.lua` | `.wezterm.lua`（仅 Windows） |

最后三行原先由 `config.bat` 生成 `dofile` / `include` 指针转发到 `common/`，现在部署的是
真实内容。

`win/init.bat` 一度按新架构重写过，随后判定它不该存在：终端自己执行 `session.cmd`，环境变量进
`HKCU\Environment`，codepage 与别名进 `session.lua`。`win/` 目录已删除，见
[`docs/windows-shell.md`](windows-shell.md)。

### 未纳入，及原因

- **`win/nu/*.nu` 是过时孤儿，跳过**。它没有任何脚本部署，含旧机器的真实路径
  （`e:\Alacritty\settings\`、`E:\Alacritty\vendor\starship.exe`），且用的是 nushell 旧
  语法 `let-env`。重写需要先确定 nushell 版本与目标位置（`%APPDATA%\nushell\`）。
- **`desktop-settings/totalcmd/wincmd.ini` 不纳入**。它含
  `InstallDir=C:\Program Files\totalcmd` 等本机安装状态与窗口布局，且
  `desktop-settings/AGENTS.md` 明确说 Total Commander 属「按文档手动配置」。

`win/` 整个目录后来被删除：`install.bat`（便携工具下载器）与 `cmds/addfonts.cmd` 由 scoop
取代，`init.bat` 由终端的 `session.cmd` + `AppData/Local/clink/session.lua` 取代，
`aliases.cmd`/`timer.cmd` 随之成了孤儿。见 [`docs/windows-shell.md`](windows-shell.md)。

chezmoi 在 Windows 上以 `%USERPROFILE%` 为家目录，`%APPDATA%` 即 `AppData/Roaming`。

### Windows 接入时补的三处

**(a) Unix 目标在 Windows 上仍被 managed，`.chezmoiignore` 只有单向排除。** 和 macOS 那次
（见「已完成：macOS 接入」）同一个形状：Windows 目标在 Linux 上被排除，反过来 Linux/macOS 的
`~/.config` 目标却没在 Windows 上排除。`managed` 从 35 降到 31。其中 nvim / alacritty /
neovide 是**重复**（Windows 的真目标在 AppData 里），yazi / gitui / glow / zed 是**错位置**
（这些应用在 Windows 上读 `%APPDATA%` / `%LOCALAPPDATA%`，不读 `~/.config`），zellij 根本没装。
`.config/ghostty` 是空父目录的特例：它的每个文件都被平台块排除了，只剩目录，chezmoi 仍会创建
`~/.config/ghostty`——所以整目录也要排。

**(b) 启动 clink 的接线原先只存在于生成指针里。** 旧的 `%APPDATA%\alacritty\alacritty.toml`
不止转发内容，还带 `[terminal.shell] program=cmd /s /k init.bat`；`~/.wezterm.lua` 同理带
`default_prog`。这段是 `config.bat` 生成的，退役后就没有落点了。中途试过把它整条去掉：
`clink autorun install` 让 Clink 在每个 cmd 里自己加载，终端只起普通的 `cmd.exe`。但 Clink 的
`os.setenv` 改不了 cmd 自己的环境块，starship 因此拿不到 `STARSHIP_CONFIG`，所以最终仍回到
终端执行 `session.cmd`。详见 [`docs/windows-shell.md`](windows-shell.md)。

**(c) `run_*.sh` 在 Windows 上必然失败：`exec(3)` 不认 shebang。** 实测 `chezmoi apply` 把脚本
写到临时文件后直接 exec，Windows 报 `%1 is not a valid Win32 application`。`.chezmoiignore`
拦不住脚本（脚本没有目标路径），`20`/`30` 那种「`exit 0` 短路」也**执行不到**——失败发生在
解释器起来之前。按 chezmoi 官方做法改成：6 个脚本全部带 `.tmpl`，最外层
`{{ if ne .chezmoi.os "windows" -}} ... {{ end -}}`，Windows 上渲染为**空字符串**，chezmoi
就不执行它。Linux / macOS 的渲染逐字节不变（已逐个比对）。

## 脚本层：`run_` 前缀

语义已在本机实测确认（沙箱验证，非推测）：

| 前缀 | 第 1 次 apply | 第 2 次 apply | 内容改动后 |
| --- | --- | --- | --- |
| `run_once_` | 执行 | 不执行 | 不执行 |
| `run_onchange_` | 执行 | 不执行 | **执行** |
| `run_` | 执行 | 执行 | 执行 |
| `run_after_` | 与文件部署的相对顺序（在所有文件落盘后执行） | | |

前缀可组合，如 `run_once_after_foo.sh`、`run_onchange_after_bar.sh`。**没有合法前缀的
`.sh` 文件会被当成目标文件在家目录创建**（实测：`badprefix_test-c.sh` 被创建成
`~/badprefix_test-c.sh`），所以所有动作脚本必须带前缀。

从两个退役仓库迁入的动作：

| 原位置 | 迁入后 | 说明 |
| --- | --- | --- |
| `configs/linux/install.sh` 的 pacman 装包 | `run_once_before_packages-arch.sh` | 需要 sudo；`before` 保证装机先于配置 |
| `configs/linux/install.sh` 的 `gcc -o gpu-watch` | `run_onchange_after_build-gpu-watch.sh` | `gpu-watch.c` 变更即重编译 |
| `configs/linux/config.sh` 的 CFFI 重编译 | `run_onchange_after_build-niri-windows.sh` | 现有 `wnmw_is_installed` 版本戳比对逻辑，正是 `run_onchange_` 的语义 |
| `configs/linux/config.sh` 的 `sudo sed /etc/vconsole.conf` | `run_once_after_vconsole-font.sh` | 需要 sudo |
| `configs/linux/config.sh` 的 `modprobe drivetemp` + `/etc/modules-load.d` | `run_once_after_drivetemp.sh` | 需要 sudo |
| `configs/linux/config.sh` 的 `rm nvme-temp.sh` | `run_once_after_cleanup-stale.sh` | 一次性清理 |
| `desktop-settings/fcitx5/install-linux.sh` | `run_after_fcitx5.sh` | **必须缩水**，见下 |
| `desktop-settings/fcitx5/update-rime-dict.sh` | 一并迁入，保持手动 | 词库维护工具，不自动化 |
| `install-arch/install.sh` | `bootstrap/arch.sh` | 见「安装入口」 |
| `configs/win/install.bat`、`config.bat` | 转成 `bootstrap/windows.bat` 与 scoop 清单 | Windows 装机层 |

`run_after_fcitx5.sh` 的缩水要点：原脚本做三件事——复制配置、下载 Rime Ice 词库、
`rime_deployer --build` 并重启 fcitx5。复制那半由 chezmoi 接管后，只剩下后两件。**必须用
`after` 前缀**，因为词库重建必须在 `profile` / `classicui.conf` / `*.custom.yaml` 落盘之后
跑。`desktop-settings/AGENTS.md` 要求的「绝不覆盖 `build/`、用户词频和键盘缓存」这条约束
在缩水后仍须保持。

### pi-config 的编排

`pi-config` 是唯一被 clone 的外部仓库，由本仓库脚本触发：

```
run_once_after_50-pi-config.sh
  ├─ 装 pi CLI（npm -g；缺 npm 时只警告）
  ├─ [ -d ~/bin/pi-config ] || git clone git@github.com:jwu/pi-config.git ~/bin/pi-config
  └─ 提示 /reload 生效
```

它**不调用** `pi-config/install.sh`（该脚本已删除）：`settings.json` 与 `mcp.json` 都是 chezmoi
的 `create_` 目标，再复制一遍就是两个所有者争同一份文件（见上节）。clone 目标仍是固定的
`~/bin/pi-config`，因为 `create_settings.json.tmpl` 渲染出的 `extensions` 指向它。

Windows 上由 `bootstrap/windows.bat` 的 `:ENSURE_PI_CONFIG` 步骤 clone 到 `C:\bin\pi-config`，
模板按 OS 渲染对应的 `extensions` 路径；node 与 pi CLI 在那台机器上仍是手工装（bootstrap
不碰 node）。

## 退役计划

| 仓库 / 位置 | 动作 |
| --- | --- |
| `configs` | 配置文件迁入本仓库；`install.sh` / `config.sh` 的非文件动作转成 `run_*` 脚本；`docs/` 整体迁入；`src/gpu-watch.c`、`waybar-niri-windows.sh` 迁入；`win/` 迁入；`common/`、`linux/`、`mac/` 的配置副本删除。**最后删除仓库** |
| `desktop-settings` | `profile`、`classicui.conf`、`themes/`、`rime/*.custom.yaml`、`zed/settings.json`、`aerospace/.aerospace.toml`、`totalcmd/wincmd.ini` 迁入；两个 shell 脚本迁入为 `run_*`；`*-config.md` 迁入 `docs/`。**最后删除仓库** |
| `pi-config` | 删除 `agents/`、`prompts/`、`skills/`、`themes/`、`extensions-settings/`、`settings.json`、`mcp.json`、`APPEND_SYSTEM.md`、`keybindings.json`、`install.sh`；**保留仓库** |
| `install-arch` | 演化为 `bootstrap/arch.sh`，**删除仓库** |
| `configs/linux/config.sh:299` | 现在靠 `$ROOT_DIR/../desktop-settings` 定位 fcitx5 脚本，迁入后改为直接引用本仓库的 `run_after_fcitx5.sh` |
| 家目录 96 个 `*.bak.*` | `backup_file()` 机制随两个仓库退役，一次性清理 |

顺带修一处 bug：`desktop-settings/AGENTS.md` 提到 `obsidian/template-vault/`，该目录不存在。

## 实施状态

### 已完成

**阶段 0-1 + 基线**

- chezmoi `v2.72.2`（pacman，`extra` 仓库）已装
- 源目录 `~/bin/dotfiles` 已 `init`；`.chezmoiignore` 拦住了 `README.md` / `docs` /
  `bootstrap` / `scripts`
- **67 个 Linux 配置从家目录导入**（66 个首批 + 对账补入的 `niri/config.kdl`）
- 基线 commit `1aabe1e` → <https://github.com/jwu/dotfiles>（public）

**阶段 3 模板化（5/5 完成，全部是等价变换）**

| 模板 | 差异来源 | 验证 |
| --- | --- | --- |
| `dot_zshrc.tmpl` | linux + mac `.zshrc`（26 行） | 两侧渲染逐字节一致；`zsh -n` 通过 |
| `dot_config/starship.toml.tmpl` | linux + mac + windows（`add_newline` 与 `>`/`❯`） | 三侧渲染逐字节一致 |
| `dot_config/waybar/modules.json.tmpl` | 原 `__WAYBAR_MODULE_DIR__` 占位符 | `chezmoi diff` 为空 |
| `dot_config/swaylock/config.tmpl` | 原 `__SWAYLOCK_BACKGROUND_DIR__` | `chezmoi diff` 为空 |
| `dot_config/git/config.tmpl` | `gh` 写入的 credential 段 | `diff` 为空，helper 功能不变 |

**平台文件搬入（本机不存在的，从仓库复制而非 `chezmoi add`）**

- macOS：`dot_aerospace.toml`、`dot_config/ghostty/config`（目标名与 Linux 的
  `config.ghostty` 不同）、`Library/Rime/squirrel.custom.yaml`
- Windows：7 个文件，见「Windows 侧」
- `.chezmoiignore` 改为模板，按 OS 排除；Linux 上 mac / win 目标全部不可见
  （`managed` 仍 67 文件、`diff` 为 0）

四处关键做法：

- 导入用「从家目录读取」而非「从仓库读取」，所以首次 `apply` 是空操作，**不存在覆盖
  风险**。
- 模板化用渲染比对验证：Linux 侧看 `chezmoi diff` 为空，macOS 侧用 Go 的 `text/template`
  渲染后与 `configs/mac/` 原件 `diff`（因为 `chezmoi execute-template` 无法覆盖
  `.chezmoi.os`）。
- `dot_zshrc.tmpl` 的空白是精确调过的：`{{ if }}` / `{{ end }}` 独占一行时自身贡献一个
  换行（充当空行），而 `-}}` 会吃掉**所有**连续空白而非一个换行，用错就会丢空行。
- 对账用脚本把 `configs` 里所有 `$HOME/*` 写入目标与 `chezmoi managed` 逐条比对，而非
  人工读脚本——`niri/config.kdl` 的遗漏就是这样发现并补上的。

### 已完成：阶段 2 对账

对 `configs`、`desktop-settings`、`pi-config` 的每个配置源文件与家目录对应文件逐对 `diff`，
结论：**没有「仓库有而家目录没有」的反向漂移**，两个退役仓库的配置可以安全删除。

全部 4 处差异都是预期内的，且方向都是「家目录 ⊇ 仓库」或语义等价：

| 文件 | 差异性质 |
| --- | --- |
| `configs/common/.gitconfig` | 家目录是超集：多出 `gh` 写入的 2 个 credential 段与 `[http]` 代理段；另有缩进风格差异（git 自己重写为 tab）。**无内容丢失** |
| `configs/linux/.config/waybar/modules.json` | 仓库是 `__WAYBAR_MODULE_DIR__` 占位符，家目录是渲染后的绝对路径——语义等价，且该语义已由 `modules.json.tmpl` 继承 |
| `configs/linux/.config/swaylock/config` | 同上（`__SWAYLOCK_BACKGROUND_DIR__`） |
| `pi-config/settings.json` | 家目录多出 `lastChangelogVersion` / `defaultProvider` / `defaultModel` 三个**本机状态**字段；`packages` 插件列表两边都有。已决定整体排除 |

`desktop-settings` 的全部 6 个配置与 `pi-config` 的静态资源（`agents` / `prompts` / `skills` /
`themes`）逐字节一致。

### 已完成：阶段 4 脚本层

`bootstrap/arch.sh` 取代了 `install-arch`：装 chezmoi → clone 到 `~/bin/dotfiles` →
写 `~/.config/chezmoi/chezmoi.toml`（`sourceDir`）→ `chezmoi init --apply`。它只做这些，
因为装 chezmoi 不可能由 chezmoi 自己完成。

六个 `run_*` 脚本接管了原来两个仓库的脚本逻辑：

| 脚本 | 触发时机 | 内容 |
| --- | --- | --- |
| `run_once_before_10-shell-tools.sh` | 只跑一次（文件部署前） | Oh My Zsh、zsh-autosuggestions、陈旧脚本清理（全部无需 root） |
| `run_onchange_after_20-build-gpu-watch.sh.tmpl` | **gpu-watch.c 变化时**（内嵌 `include \| sha256sum`） | gcc 编译 |
| `run_onchange_after_30-build-niri-windows.sh.tmpl` | 构建助手变化时（内嵌 hash）；**不再自动跟随 fork HEAD** | 从 fork 构建 CFFI 模块 |
| `run_onchange_after_40-fcitx5.sh.tmpl` | **fcitx5 五个配置文件变化时**（内嵌 hash） | 下载 Rime Ice 词库、`rime_deployer --build`、重启 fcitx5 |
| `run_once_after_50-pi-config.sh` | 只跑一次 | 装 pi CLI、clone pi-config |
| `run_once_after_60-zed-cli.sh` | 只跑一次 | `zed` → `/usr/bin/zeditor` 符号链接 |

四处设计要点：

- `run_after_40-fcitx5.sh` 的 `after` 是必须的：`rime_deployer` 要在 `profile` /
  `classicui.conf` / `*.custom.yaml` 落盘之后才能在其上构建。它**只保留词库、rebuild 和
  重启**，复制配置那半已由 chezmoi 接管。
- `run_onchange_after_20` 用 `{{ include "scripts/gpu-watch.c" | sha256sum }}` 嵌一个源文件
  哈希，所以「源变则重编」不需要任何额外的状态文件。
- 脚本用 `.tmpl` 后缀拿 `{{ .chezmoi.sourceDir }}`，因为辅助文件
  （`scripts/gpu-watch.c`、`scripts/waybar-niri-windows.sh`）放在被 `.chezmoiignore` 排除的
  `scripts/` 里；不这做它们会被部署到家目录。
- `run_once_after_50-pi-config.sh` **不调用** `pi-config/install.sh`：它复制的东西
  （先是 `agents/` / `skills/` / `prompts/` / `themes/`，后来是 `settings.json` / `mcp.json`）
  全部归 chezmoi，两边会争同一份文件。脚本只负责 clone，npm 插件由 pi 自己按
  `settings.json` 的 `packages` 装。

迁入的文件：`docs/`（含 desktop-settings 的 6 份说明）、`scripts/`（`gpu-watch.c`、
`waybar-niri-windows.sh`、`update-rime-dict.sh`）。`win/config.bat` 退役删除，`win/` 的其余
文件后来也整个删除（见 [`docs/windows-shell.md`](windows-shell.md)）。

**注意 `chezmoi diff` 的语义**：run 脚本会出现在 `diff` 输出里（因为 apply 时会执行它们）。
判断配置层是否干净要用 `chezmoi diff --include=files`。

### 已完成：apply 完整跑通

`chezmoi apply -v` 退出码 **0**，六个脚本全部执行：

| 脚本 | 结果 |
| --- | --- |
| `10-shell-tools` | Oh My Zsh 已装、autosuggestions pull、cleanup —— 全绿 |
| `20-build-gpu-watch` | 编译成功 |
| `30-build-niri-windows` | `cffi/niri-windows module up to date (3f30472)` |
| `40-fcitx5` | 词库已在 → rebuild + `Restarted fcitx5` |
| `50-pi-config` | `Already up to date.` |
| `60-zed-cli` | `~/.local/bin/zed -> /usr/bin/zeditor` |

**再跑一次 `chezmoi apply -v`：退出码 0、输出 0 行**——文件层与脚本层都是彻底的 no-op
（`diff --include=files` 与 `--include=scripts` 均为 0）。这就是最终稳态：日常 apply 只做配置
同步，装包与重建只发生在首次、或相关源文件真的变化时。

期间验证了整条技术链：`.tmpl` 的 `sourceDir` 渲染、`include | sha256sum` 的变更检测、脚本
能 source 到被 `.chezmoiignore` 排除的 `scripts/` 辅助文件、`wnmw_*` 函数与网络比对。

### 首次 apply 的失败（推动了两处修正）

第一次 apply 在 provision 里中止：5 处 sudo 无法在无 TTY 的子进程里提示密码。这直接把
root 动作赶进了 `bootstrap/arch.sh`。也顺带发现 chezmoi 会把**失败的**脚本一并记账（见下
节），所以修完还得手动清一次记账才能重跑。

### 现有机器需要先写 sourceDir

源在 `~/bin/dotfiles`（不是 chezmoi 的默认位置），所以每台机器上都要有一份
`~/.config/chezmoi/chezmoi.toml`：

```toml
sourceDir = "/home/jwu/bin/dotfiles"
```

`bootstrap/arch.sh` 会在新机器上写这个文件，但本机是从 `--source` 参数一路走过来的，所以
一直没写。第一次不带 `--source` 跑 `chezmoi apply` 就报了
`stat /home/jwu/.local/share/chezmoi: no such file or directory`。已补上。

它是 chezmoi 自己的配置（鸡生蛋：chezmoi 不可能管自己的源在哪里），不由本仓库管理。

### provision 需要 TTY（重要约束）

`run_once_before_10-provision-arch.sh` 有 5 处 `sudo`（pacman、`sed /etc/vconsole.conf`、
`tee /etc/modules-load.d`、`modprobe`、`chsh`），所以它**必须在交互式 shell 里由
`chezmoi apply` 触发**。

在无 TTY 的环境（CI、脚本包装、agent 工具）里跑会失败：

```
sudo: a terminal is required to read the password; either use the -S option to read
from standard input or configure an askpass helper
```

`sudo -v` 预先缓存密码**解决不了**：sudo 默认启用 `tty_tickets`，缓存按 TTY 隔离，另一个
TTY 的缓存不生效。

更麻烦的是 chezmoi 的 fail-fast：run 脚本失败会**中止整个 apply**，所以 provision 失败时后
面五个脚本根本不会执行。首次 apply 实测就是这个结果（文件层仍是 0 变更）。

**已解决**：5 处 sudo 动作全部移进了 `bootstrap/arch.sh`（它本来就是装 chezmoi 的入口，已经
需要终端）。现在 `run_*` 脚本里没有任何 `sudo` / `chsh` 调用，`chezmoi apply` 可以在没有
终端的自动化环境里完整跑通——实测退出码 0。

### chezmoi 把失败的脚本也记账

首次 apply 时 provision 因无 TTY 失败（退出码 1），但它的内容 hash 仍然进了
`scriptState`。于是它**不会因为「上次失败」而自动重跑**——只有内容变化才会。

实测：修好 TTY 问题后 `chezmoi diff --include=scripts` 只列出内容被改过的脚本，失败的
provision 不在其中。

所以要让脚本重新执行，得显式清掉记账：

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply -v
```

`run_*` 脚本全部幂等，重跑一遍是安全的。

### 已完成：阶段 5 与阶段 6

**阶段 5 — pi-config 缩水**

`pi-config/install.sh` 现在只部署 `settings.json`（唯一无法交给 chezmoi 的文件，因为它记录本机
的认证、provider 与模型），并检查仓库是否位于 `~/bin/pi-config`（`settings.json` 用绝对路径指向
它的 `extensions/`）。`run_once_after_50-pi-config.sh` 恢复了调用。

这一步在 2026-09-27 被推翻：`settings.json` 与 `mcp.json` 改用 chezmoi 的 `create_` 落地，
install.sh 因此不再被调用，见「pi 的 settings/mcp 纳入 `create_`」。

同时从 `pi-config` 删掉 14 个已迁移的文件（`agents/`、`skills/`、`prompts/`、`themes/`、
`keybindings.json`、`APPEND_SYSTEM.md`）——删除前逐个逐字节比对确认都在本仓库源里。`mcp.json`
与 `extensions-settings/` 保留为参考模板但不再部署：它们是 Pi 自己写入的状态。

**阶段 6 — 退役三个仓库并清理备份**

- 删除前扫描：无活引用（脚本、符号链接、shell 配置全部干净），三个远程仓库都还在。
- 删除 `~/bin/configs`、`~/bin/desktop-settings`、`~/bin/install-arch`。`configs` 的迁移评估
  文档先提交推送（`717ddd7`）才删，保留了当时的决策记录。
- 清理 95 个 `*.bak.*`（`backup_file()` 机制的遗留）。剩下一个
  `~/.oh-my-zsh.bak.1790327059` 是目录且不是那个机制产生的，保留未动。

`~/bin` 现在只剩 `dotfiles`、`pi-config`，以及一个 `pi` 符号链接。

### 已完成：macOS 接入（2026-09-26）

macOS 机器（Apple Silicon，macOS 27.0）按 `docs/onboarding-a-machine.md` 执行完毕，共 7 个提交
`ac55046`..`e489f45`。对账出 12 处差异，方向都不是「源是对的」：

| 类别 | 处理 |
| --- | --- |
| Linux 专有目标在 darwin 上仍被 managed（约 50 个文件） | `.chezmoiignore` 加反向排除块，`managed` 从 69 降到 33 |
| `alacritty.toml` 两侧是两份独立配置 | 合进 `alacritty.toml.tmpl`，两分支渲染逐字节一致 |
| `.zshrc` 的 MPS 变量、`ghostty` 的 `auto-update-channel` | 收回源 |
| `.zshrc` 的 nvm 分支指向未安装的 brew formula | 改成先探 `$NVM_DIR`、再回落 brew |
| `~/.pi`、`~/.pi/agent`、`~/Library`、zed settings 的 0700/0600 | 加 `private_` 前缀 |
| git 配置在两个平台上重复维护 | 拆出公共层纳管；个人层（身份、代理）用 `chezmoi forget` 摘出仓库，见「公共层与个人层」 |

另外补了 `bootstrap/macos.sh`，并给 `20` / `30` 两个脚本加了非 Linux 短路（`exit 0`，因为
chezmoi 的 fail-fast 会让一个注定失败的脚本永久拖住 apply）。

验证：`chezmoi diff --include=files` 为 0、二次 `chezmoi apply -v` 输出 0 行、6 个 `run_*` 全部
`exit 0`、权限目标逐个核对、`zsh -c 'source ~/.zshrc'` 后 nvm 与 node 均可用。

**这组提交对 Linux 侧同样生效**：`~/.pi`、`~/.pi/agent`、`~/Library`、
`~/.config/zed/settings.json` 会收敛到 0700/0600；`~/.config/git/config` 只剩公共层。那边要在
**apply 之前**先手工建好 `~/.gitconfig`（补回 `[user]` 与 `[http] proxy`），否则中间态会丢掉
身份与代理——个人层不在仓库里，chezmoi 补不回来。

### Windows 接入（2026-09-26）

Windows 这台（Windows 11 10.0.26200）此前**从未接过 chezmoi**：scoop 装了 binary，但没有
`%USERPROFILE%\.config\chezmoi\chezmoi.toml`、没有 state，家目录一直跑在旧 `~/bin/configs` 上
（`~/.wezterm.lua`、`%APPDATA%\alacritty\alacritty.toml`、`%APPDATA%\neovide\config.toml`
都是 `config.bat` 生成的指针，clink 由 `init.bat` 注入）。

对账结论：10 个 Windows 目标**都是源更新**，没有任何一份 home 配置更新。其中最旧的是
`AppData/Local/nvim/init.lua`（1645 行，早于仓库的 1718 行：缺 `is_win` 分支、explorer
reveal、render-markdown、gdscript LSP）和 `.pi/agent/themes/one-dark.json`（5 月版）。

源侧为此改了：

| 改动 | 内容 |
| --- | --- |
| `.chezmoiignore` | 加 Windows 反向排除块（含空的 `.config/ghostty`） |
| 新增 Windows 目标 | nvim / neovide 之外再补 yazi / gitui / glow / zed 的 AppData 路径，真内容，不用指针 |
| clink 接线 | 终端起 `cmd.exe /s /k session.cmd`；Clink 由该脚本 `clink inject`，codepage 与别名放进 `session.lua` |
| git 公共层 | credential helper 在 Windows 上用 PATH 上的 `gh`（本机没有 `~/.local/bin`） |
| starship 配置 | 目标从 `%APPDATA%` 改到 `~/.config`（真正的默认），并在 `clink.lua` 里 `os.setenv('STARSHIP_CONFIG', …)` 钉死，免受旧 `init.bat` 残留值影响 |
| `run_*` 6 个脚本 | 全部加 `.tmpl` 外层短路，Windows 渲染为空 |
| `bootstrap/windows.bat` | 新增 Windows 装机入口：scoop 装工具与字体 + 用户环境变量 |
| `win/` 整个目录 | 删除（`install.bat` / `init.bat` / `cmds/*.cmd` 都被取代） |
| `.gitattributes` | `*.bat`/`*.cmd` 用 `-text` 把 CRLF 固化进 blob（cmd 的 `call :label` 需要） |

**未纳入**（本次决定不做）：`~/.config/lsd/config.yaml`（旧 `configs/common` 与 home 都有、
dotfiles 漏了；但 aliases 已改用 eza）、`~/.config/git/ignore`、`~/.config/opencode/`、
`AppData/Local/nvim/lazy-lock.json`、`~/bin/imtip-config/`、`~/bin/dev-settings/`、
`%APPDATA%\Zed\AGENTS.md`。

Zed 的 Windows settings 与 Unix 侧那份已经对齐（补齐 `project_panel` / `outline_panel` /
`collaboration_panel` / `git_panel` 的 dock、`agent` 块、`soft_wrap`、`cli_default_open_behavior`），
只保留一处有意的差异：`ui_font_family` 在 Windows 上是 `Inter`，Unix 上是 `FiraMono Nerd Font`。
共享的 `buffer_font_fallbacks` 里加了 `Microsoft YaHei`，让 Windows 也有显式的中文回退
（在 Unix 上不存在，无副作用）。

验证：`chezmoi apply -v` 退出码 0，**第二次 0 行**；`chezmoi diff --include=files` 为 0；
`chezmoi status` 为 0（6 个 `run_*` 在 Windows 上渲染为空，脚本条目为 0）。
`bootstrap/windows.bat` 在本机跑通（全部步骤 ok），`HKCU\Environment` 里有
`LANG`/`PI_NERD_FONTS`/`FZF_COMPLETE_OPTS`。别名逻辑用 LuaJIT 单独测过（`ls`→`eza`、
`gl`→`git log …`、`pon`/`pstat` 展开）。**未验证**的是真机交互终端里的效果（Clink 只在真实
控制台加载脚本，pipe/重定向的会话观察不到），需要开一次终端确认 starship 提示符、
`chcp`=65001、别名可用。

### git 个人层与历史重写

接入时曾把 git 个人层做成 `dot_gitconfig.tmpl` 纳管，随后判定它不该在仓库里——它含邮箱、
人名与 `~/dev/<雇主>/` 这样的工作目录结构。用 `chezmoi forget` 摘出：它删除源条目但保留
家目录文件，所以那几份文件原样留在家中，只是不再由 chezmoi 过问。个人层现在手工维护在
`~/.gitconfig`，分层见「公共层与个人层」。

因为仓库是 public，又用 `git filter-repo` 把那三条路径连同雇主名从全部历史里抹掉，所以
`43655d4` 及之后的 hash 都是重写后的值。

**force push 不等于在 GitHub 上消失**：旧 commit 在 GitHub 自行 GC 之前仍可按 SHA 读取
（实测 `gh api repos/jwu/dotfiles/contents/...?ref=<旧SHA>` 与 commit 网页都是 200），要立即
失效只能联系 GitHub Support 或删除重建仓库。已决定不再处理。

### pi 的 settings/mcp 纳入 `create_`（2026-09-27）

`pi-config` 缩水后仍留着 `settings.json` 与 `mcp.json`：它们一边被 pi 回写，一边被
`install.sh` 复制进 `~/.pi/agent/`。这次两份都收进本仓库，用 `create_` 前缀落地：

| 源 | 目标 | 说明 |
| --- | --- | --- |
| `private_dot_pi/private_agent/create_settings.json.tmpl` | `~/.pi/agent/settings.json` | `extensions` 按 `.chezmoi.os` 分支 |
| `private_dot_pi/private_agent/create_mcp.json` | `~/.pi/agent/mcp.json` | 取本机现状：chrome-devtools 用 `--wsEndpoint ws://127.0.0.1:9222/devtools/browser/pi-agent`，不是 pi-config 里的 `--autoConnect` |

`create_` 只在目标不存在时写一次，于是：

- 本机 macOS 的 `settings.json`（`packages` 已换成 `~/dev/jwu/*` 本地路径）与 `mcp.json` 原样
  保留，`chezmoi diff --include=files` 仍是 0。
- 新机器拿到 npm 包名版 `packages`，外加 deepseek 的 provider / model / thinking 默认值；
  `lastChangelogVersion` 不写进源，那是纯本机状态。
- 源与磁盘从此会漂移，且没有守卫。要改 `packages` 或 MCP server，得手工同步已有机器。

配套改动：

- `run_once_after_50-pi-config.sh.tmpl` 去掉 `deploy_pi_settings`，不再调用
  `pi-config/install.sh`（那份脚本后来整份删除）。
- `bootstrap/windows.bat` 加 `:ENSURE_PI_CONFIG`，checkout 从手工的 `C:\dev\pi-config` 换成
  `C:\bin\pi-config`；Windows 上 node 与 pi CLI 仍手工装。
- `pi-config` 仓库侧已同步：`e052e6e` 删掉 `settings.json` 与 `mcp.json`，`d5fa157` 连
  `install.sh` 一起删掉——缩水后它只剩路径检查，而路径由 `create_settings.json.tmpl` 定死。
  `create_mcp.json` 里只留 `blender` 与 `chrome-devtools`（`open-pencil` 已去掉）。
- Windows 那台已有的 `settings.json` 指向 `c:/dev/pi-config/extensions`，`create_` **不会**改它。
  迁移时要么手工改这一行，要么删掉该文件让模板按 `c:/bin/pi-config/extensions` 重写。
