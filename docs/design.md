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
字体、drivetemp、mihomo 的 AUR 包与 drop-in 与面板、sudoers 的免密窗口（见下）。macOS 侧只有两处：`chsh`，以及首次把 Homebrew 的 zsh 加进 `/etc/shells`。
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
  chrome-flags.conf                    ← 本机手写，无旧仓库来源（见「浏览器代理」）
  chromium-flags.conf                  ← 同上
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
  mimeapps.list                        ← 本机手写，无旧仓库来源（见「浏览器代理」）
  neovide/config.toml                  ← configs: common/.config/neovide/
  nvim/init.lua                        ← configs: common/.config/nvim/
  starship.toml.tmpl                   ← configs: linux/ + mac/ 合并
  swaylock/config.tmpl                 ← configs: linux/.config/swaylock/
  swaylock/backgrounds/*.webp          ← configs: linux/backgrounds/（6 张）
  waybar/*                             ← configs: linux/.config/waybar/
  yazi/{yazi.toml,theme.toml}          ← configs: common/.config/yazi/
  zed/settings.json                    ← desktop-settings: zed/settings.json
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
  create_mcp-adapter.json              ← 新机器的初始 mcp-adapter.json（同上）
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

阶段 1 与平台搬入已完成（见「实施状态」）。源里共 **80 个文件** = 70 个 Linux 目标 +
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

实际采用的方案是**把 credential 段模板化**：Linux 用 `.chezmoi.homeDir` 拼出的绝对路径，
其余平台用 PATH 上的 `gh`。

```ini
# dot_config/git/config.tmpl
[credential "https://github.com"]
	helper =
	helper = !{{ if eq .chezmoi.os "linux" }}{{ .chezmoi.homeDir }}/.local/bin/gh{{ else }}gh{{ end }} auth git-credential
```

选择的理由：Linux 那边的 gh 是 `~/.local/bin` 下的便携版，绝对路径正是 `gh` 自己会回填的
内容，`diff` 稳定且保持为空，硬编码 `/home/jwu` 同时消除。macOS 的 gh 来自 Homebrew
（`/opt/homebrew/bin/gh`），Windows 的来自 `~/bin`，两者都在 PATH 上，写死绝对路径反而
会绑死 brew 前缀（Apple Silicon 与 Intel 不同）。代价是 chezmoi 与 `gh` 名义上共管一个
文件——若 `gh` 某次改了格式，`chezmoi diff` 会显示差异，`chezmoi apply` 规范化回去，功能
不受影响。

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

`gh` 回填 credential 段时走的是 git 的 global 写入路径：`~/.gitconfig` 存在就写它，不存在
才落到 `~/.config/git/config`。所以个人层建好之后，`gh auth login` 不再污染仓库管的公共层，
两次 apply 之间的 `diff` 也不会因为一次登录而变脏。macOS 那台实测过写入落点
（`git config --global --add` 写的是 `~/.gitconfig`）。

## pi 的可变状态

`~/.pi/agent/` 下的文件分三类：

| 类型 | 文件 | 处置 |
| --- | --- | --- |
| 静态资源（pi 只读） | `agents/`、`skills/`、`prompts/`、`themes/` | **已纳入**，源是真源 |
| 人工维护的配置 | `keybindings.json`、`APPEND_SYSTEM.md` | **已纳入**，源是真源 |
| 会被 pi 回写 | `settings.json`、`mcp-adapter.json` | **已纳入**，但用 `create_` 前缀 |
| 工具独占写入 | `extensions/*.json`（pi-ask 写回） | **排除** |
| 凭据与运行时 | `auth.json`、`sessions/`、`models-store.json`、`*-cache.json`、`install/`、`bin/`、`npm/` | **绝不纳入** |

`settings.json` 会被 pi 写入 `lastChangelogVersion`（看过哪版 changelog）、
`defaultProvider` / `defaultModel` / `defaultThinkingLevel`（`/model` 切换），`mcp-adapter.json` 会被
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

### 项目级：仓库根的 `.pi/`

仓库根的 `.pi/` 是 pi 的**项目级**配置，只在把本仓库当工作目录时加载，不进家目录，
与上面那份 `~/.pi/agent/` 是两套互不相干的东西。它放两个方向相反的命令：

- `prompts/apply.md` —— `/apply`，源 → 家目录：先把本地源同步到 `origin`，再把会话改动
  落源，`diff` → 等确认 → `apply`，跑两次验证 no-op
- `prompts/collect.md` —— `/collect`，家目录 → 源：把家目录侧的改动回收进仓库

`/apply` 落源前先 `git fetch --prune origin` 并同步：这仓库同时驱动多台机器，落在过期基线
上的提交会变成分叉。能快进走 `--ff-only`，分叉走 `--rebase`，任何冲突都**中止整个命令**，
要求先把 git 解决干净——不带着冲突去 `apply`。`/collect` 不参与这一步。两个命令都刻意不含
提交动作，提交仍由人显式跑 `/commit`。

`/collect` 的判据是 `chezmoi status` 的**第一列**——它表示家目录相对 chezmoi 上次写入的
差异，所以第一列非空即家目录侧漂移（`/apply` 的活），第一列为空、第二列为 `M` 才是源侧
改动。回收靠 `chezmoi re-add`，它自己会跳过模板，`create_` 文件连 `status` 都不显示，
构建产物（`~/.local/bin` 下那类）也不是受管目标，因此手工要做的只剩两件：把模板漂移
**语义合并**回模板（而不是把渲染结果整份写进去），以及判断家目录里未被管理的新配置
要不要纳入。

它不需要在 `.chezmoiignore` 里排除：chezmoi 本来就忽略源目录里以点开头的条目。反过来，
往那里加 `.pi` 是错的——`.chezmoiignore` 匹配目标路径，加进去会连 `~/.pi` 一起踢出管理
范围。见 [`chezmoi-notes.md`](chezmoi-notes.md)。

项目级配置要等 project trust 授予之后才加载，所以首次用到 `/apply` 的机器要先信任本仓库。

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
（这些应用在 Windows 上读 `%APPDATA%` / `%LOCALAPPDATA%`，不读 `~/.config`）。
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

它**不调用** `pi-config/install.sh`（该脚本已删除）：`settings.json` 与 `mcp-adapter.json` 都是 chezmoi
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

**这台机器加了一个例外**：`/etc/sudoers.d/00-global-timestamp`（`0440 root:root`）：

```ini
Defaults timestamp_type=global
Defaults timestamp_timeout=10
```

它把凭据缓存从「按 TTY 隔离」放宽成「全机共享」，于是任意终端 `sudo -v` 之后 10 分钟内，
**所有进程**——包括没有 TTY 的 agent 工具——都能免密 sudo。代价是比默认隔离宽：要收回成默认，
删掉那个文件即可；要再临时授权，重复 `sudo -v`。

**它由 `bootstrap/arch.sh` 的 `install_sudo_window` 安装，而不是 chezmoi 的文件层。** 三层原因：
chezmoi 根本没有 `absolute_` 这类属性（官方 attributes 表里只有 `after_`…`symlink_` 那十几个，
源里的路径一律相对 home）；普通 `chezmoi apply` 写不了 `/etc`，会 fail-fast 拖停整个 apply，
而 `sudo chezmoi apply` 会把家目录文件的 owner 变成 root；同时 `chezmoi diff` 会永远非空，
破坏「diff 必须为空」这条对账判据。官方 FAQ 对 home 之外的文件的立场也是「可行但强烈不建议」，
推荐做法就是 `run_` 脚本 + sudo。

代价是它只在新机器 bootstrap 时落地：已经对账的机器（本机）要手工装一次，之后源里改了
也不会自动同步。脚本本身幂等，内容一致时直接跳过。

一个坑：`sudo tee` 写出来的 `sudoers.d` 文件默认是 `0644`，**运行时 sudo 会接受，但
`visudo -c` 报 `bad permissions, should be mode 0440`**——目录里的文件要恰好 `0440` 才两边都
干净。

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
| `private_dot_pi/private_agent/create_mcp-adapter.json` | `~/.pi/agent/mcp-adapter.json` | 取本机现状：chrome-devtools 用 `--wsEndpoint ws://127.0.0.1:9222/devtools/browser/pi-agent`，不是 pi-config 里的 `--autoConnect` |

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

### pi-mcp-adapter 改读 `mcp-adapter.json`（2026-09-27）

`pi-mcp-adapter` 升级后不再读 `~/.pi/agent/mcp.json`，改读 `~/.pi/agent/mcp-adapter.json`，并在
启动时打印迁移提示。源文件跟着从 `create_mcp.json` 重命名为 `create_mcp-adapter.json`，对应目标
变为 `~/.pi/agent/mcp-adapter.json`。

改名对已有机器无影响：`create_` 只在目标不存在时写入，而磁盘上那份已按提示手工改名，
`chezmoi diff --include=files` 因此没有输出。内容这次**没有**跟随磁盘——后者多了
`open-pencil`，且 `chrome-devtools` 换成了 `--autoConnect`，源里维持 `blender` +
`chrome-devtools`（`--wsEndpoint ws://127.0.0.1:9222/devtools/browser/pi-agent`）两条。

顺带把 `run_once_after_50-pi-config.sh.tmpl` 的提示文本与各文档里的旧名一起改掉；脚本
内容一变，这个 `run_once_` 会在下次 apply 重跑一遍（只做幂等的 clone / pull）。

本节之前的各节里的 `mcp.json` 都是改名前的名字，与 `mcp-adapter.json` 是同一个文件。

### 2026-09-27 macOS 增量同步：zellij 与 gh helper

macOS 那台在 `505a4fa` 之后一直没再 apply，累积了一批源改动：`ghostty` 的
`auto-update-channel = tip`、zed 的字体 fallback、Rime 的 `squirrel.custom.yaml`、pi 的
`prompts/commit.md`、`.zshrc` 的 Apple Silicon MPS 变量与 nvm 分支，以及 `~/.config/zed`、
`~/.pi`、`~/Library/Rime` 的权限收敛。同步时修掉两处仓库侧的问题：

- **zellij 整体移除。** 唯一的源文件 `dot_config/zellij/config.kdl` 是 Linux 专用
  （`default_shell "/usr/bin/zsh"`、`copy_command "wl-copy"`），却因为 `.chezmoiignore`
  只在 Windows 侧排除而会落到 macOS 家目录，而 macOS 从来没装过 zellij。它也不再被
  使用，所以直接删源，并同步 README 的工具列表与 `.chezmoiignore` 的排除项。
  **Linux 那台的 `~/.config/zellij/config.kdl` 是 chezmoi 早先放下的，删源条目不会回收
  它**，要手工删。
- **gh credential helper 不再假定非 Windows 平台都有 `~/.local/bin/gh`。** macOS 的 gh
  来自 Homebrew，旧模板渲染出的 `~/.local/bin/gh` 并不存在，helper 会直接失败。改为只有
  Linux 用 `{{ .chezmoi.homeDir }}/.local/bin/gh`，其余平台用 PATH 上的 `gh`。

另外两处收尾：`run_once_after_60-zed-cli.sh.tmpl` 补了非 Linux 短路（它写的是 Arch 的
`/usr/bin/zeditor`，在 macOS 上只能靠 `command -v` 落空后打印一行再跳过）；这台机器缺
`~/.config/chezmoi/chezmoi.toml`，按「现有机器需要先写 sourceDir」补回了
`sourceDir = "/Users/jwu/bin/dotfiles"`。

留意：`~/.local/share/chezmoi` 不存在意味着脚本记账（`scriptState`）也一并丢了，这次
apply 把 6 个 `run_*` 全部重跑了一遍。它们都幂等，重跑的代价是 Oh My Zsh 插件与
`~/bin/pi-config` 各拉一次 `git pull`。

### 2026-09-27 浏览器代理：chrome/chromium flags 与 mimeapps

本机 `~/.config/` 下三份文件一直没在源里，这次收进来：

| 源 | 目标 | 说明 |
| --- | --- | --- |
| `dot_config/chrome-flags.conf` | `~/.config/chrome-flags.conf` | Arch 的 `google-chrome-stable` wrapper 读它 |
| `dot_config/chromium-flags.conf` | `~/.config/chromium-flags.conf` | 同一机制的 chromium 版，内容与上一份逐字相同（除首行） |
| `dot_config/mimeapps.list` | `~/.config/mimeapps.list` | 默认浏览器与几个 `x-scheme-handler` 指向 `google-chrome.desktop` |

**口径是「所有 Linux 主机都带代理行」，不是只在本机渲染。** 三份都是普通文件而不是模板，
因为这次没有按机器分岔的需求。这与 [`onboarding-a-machine.md`](onboarding-a-machine.md) §6
对 gitconfig 代理的态度不同——**那一条仍然只属于本机**，没有跟着进仓库。差别在代价：
gitconfig 的代理写错只会让 `github.com` 的拉取失败，而 chrome 这份的 `--proxy-bypass-list`
只放行内网，一旦那台机器上没跑 mihomo，浏览器会**完全上不了网**。新机器若不用这套代理，
删掉 `--proxy-server` 与 `--proxy-bypass-list` 两行即可。

三份都在 `.chezmoiignore` 的 Linux-only 块里排除：`*-flags.conf` 由 Arch 的 wrapper 读，
macOS 与 Windows 的 Chrome 不认这些文件名，`mimeapps.list` 是 XDG 的东西。

顺带清掉两处残留：`~/.config/zellij/config.kdl`（zellij 移除时留下的孤儿，见上一节）与
`~/.oh-my-zsh.bak.1790327059`、空的 `~/.config/gtk-3.0/`。当时 **`zellij` 二进制还装着**，上一节
「不再被使用」只对 macOS 成立；删掉的是那份 `default_shell` / `copy_command` 两行配置。
同一天稍后把包也卸了：`pacman -Rns zellij`，52 MiB，无反向依赖。

### 2026-09-27 metacubexd 老方案残留清理

这台机器的代理现在是**系统级 mihomo**：`mihomo.service`（AUR 的 `mihomo-bin` 包，见「mihomo：哪些能管，哪些不能」）读
`/etc/mihomo/config.yaml`，其中 `external-controller: "0.0.0.0:9090"` 加 `external-ui: ui/xd`，
于是 `http://127.0.0.1:9090/ui/` 直接提供 MetaCubeXD 面板——`/etc/mihomo/ui/xd` 就是那个面板的
构建产物（Nuxt 静态站，8.1M，`<title>MetaCubeXD</title>`）。订阅来自 `config.yaml` 顶部的
`#!MANAGED-CONFIG`（wgetcloud，10 天自动更新一次）。**`/etc/mihomo/ui` 不能删**，面板靠它。

那套「源码跑 Nuxt server 再派生子进程 mihomo」的 All-in-One 方案同时退役，它留下的三份
残留这次清掉：

| 清掉的东西 | 当时的角色 |
| --- | --- |
| `~/.config/systemd/user/metacubexd.service` | 用户级 unit，disabled 且从未自启，只在 09-25 手工跑过约 3.5 小时 |
| `~/.config/metacubexd/env` | 600，`CONTROL_TOKEN` / `CLASH_SECRET` / `MIHOMO_BIN` 等 |
| `~/.local/share/metacubexd/` | 48M，含一份自带的 mihomo 二进制副本、空的 `profiles/`、`cache.db` |

判定它已废弃的依据是 unit 的 `ExecStart` 指向 `/home/jwu/src/metacubexd`，而那个源码目录
已经不存在——现在再拉起它也只会失败。

**9090 的对外暴露同时收紧了。** `/etc/systemd/system/mihomo.service.d/override.conf` 原本两行都
拼成 `EexcStart=`（systemd 实报 `Unknown key 'EexcStart' in section [Service], ignoring`），改成
正确的

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/mihomo -d /etc/mihomo -ext-ctl 127.0.0.1:9090
```

之后 `external-controller` 收到 `127.0.0.1:9090`，`ss` 从 `*:9090` 变 `127.0.0.1:9090`，
从局域网地址 `192.168.3.81:9090` 已拒绝连接，面板与本机代理不受影响。
**用 drop-in 而不是改 `config.yaml` 是有意的**：那份 config 是机场给的完整订阅，每次手工更新
都会整文件覆盖，`external-controller: "0.0.0.0:9090"` 会被带回来；命令行覆盖与订阅无关。

**`allow-lan` 是有意保留的**：`allow-lan: true` + `bind-address: "*"` 让 `7890` 对整个局域网
开放（实测局域网地址上可作代理使用）。这是订阅的内容，服务层不碰它；唯一被钉住的设置是
`mixed-port`，见下一节。

### mihomo：哪些能管，哪些不能

服务栈是 AUR 的 `mihomo-bin` + `clash-geoip`，外面套三处本地策略。**两者都不在官方仓库**：
`pacman -Sl extra` 查不到，包名直接进 `pacman -S` 只会得到 `target not found`（2026-09-27
用 `--print` 干跑实测）。`mihomo-bin` 声明 `Provides: mihomo`，与源码包 `mihomo`（AUR，
21★）互相 `Conflicts`，只能装一个；本机装的是 `mihomo-bin 1.19.31-1`。**`bootstrap/arch.sh`
的 `install_mihomo` 因此从 `pacman -S` 改成了 `yay -S`**——这条线原来会失败，不只是本机偏差。

geodata 也一并交代：`mihomo-bin` 的包内容只有 `config.yaml`、二进制与两个 unit，**不带任何
geodata**；本机生效的 `/etc/mihomo/geoip.metadb` 是手工放的。`clash-geoip`（AUR，PKGBUILD
实测）装的正是 `/etc/clash/Country.mmdb`，即 `install_mihomo` 那条软链的目标，所以那条链只在
装了 `clash-geoip` 之后才有对象。

**配置本体不能进仓库**：
`/etc/mihomo/config.yaml` 是机场给的完整订阅，445 KB，顶行的 `#!MANAGED-CONFIG` 里就带着
订阅链接（含用户 ID），正文另有 32 处 `password` / `uuid` / `secret` / `psk` 节点凭据。仓库是
public，所以它和 `~/.gitconfig` 一样留在本机。

能管的部分靠两种手段，区别在于**能否抵挡订阅覆盖**：

| 手段 | 管什么 | 抗订阅覆盖 |
| --- | --- | --- |
| drop-in 里的命令行 flag | `external-controller`（`-ext-ctl`）、面板目录（`-ext-ui`）、配置目录（`-d`） | 是 |
| `ExecStartPre` 补丁脚本 | `mixed-port`（mihomo 没有对应 flag，只能改文件） | 是（每次启动重打） |
| 直接改 `config.yaml` | 其余全部：`allow-lan`、`bind-address`、`mode`、`dns`… | 否 |

**`config.yaml` 里的 `external-controller` / `external-ui` 已删除**，controller 地址与面板目录
完全由 drop-in 的 flag 提供。删而不是留着当兜底，是因为**订阅本身不含这两行**——它们是早先
手工加进 config 的本地值，而订阅刷新是整文件替换，任何手工值都活不过下一次刷新：

| 现在写成什么 | 下次刷新订阅后 |
| --- | --- |
| 删掉 | 仍然没有 → 自洽，持久 |
| `127.0.0.1:9090` | 被抹掉 → 只活到下次刷新 |
| `"0.0.0.0:9090"`（原本） | 同样被抹掉 |

所以「留在 config 里当兜底」是伪兜底；真要长期有值，只能让 overlay 每次重写，而那是给一个
flag 已经提供的东西再加一处来源。删掉后日志仍是 `RESTful API listening at: 127.0.0.1:9090`
（实测 config 缺该键时 flag 照常补位），而 flag 一旦丢失，后果是 controller **不启用**
（fail-safe 且可察觉），不是暴露到局域网。

`/etc/systemd/system/mihomo.service.d/override.conf`（由 `bootstrap/arch.sh` 的
`install_mihomo_overlay` 写入）：

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/mihomo -d /etc/mihomo -ext-ctl 127.0.0.1:9090 -ext-ui ui/xd
ExecStartPre=+/usr/local/bin/mihomo-overlay
```

`+` 前缀按 AUR 的 `mihomo` 源码包写：它的 unit 是 `User=mihomo`，而 `config.yaml` 是
`root:root`，服务写不了自己的配置；`+` 让这一条以 root 跑（systemd 262 实测可用）。本机装的
是 `mihomo-bin`，它的 unit **没有** `User=`（本就以 root 跑），所以 `+` 在这里无害但不起作用；
保留它是为了让两种包都成立。

补丁脚本是仓库里的 `scripts/mihomo-overlay.sh`，装到 `/usr/local/bin/mihomo-overlay`。它只钉
`mixed-port: 7890`——理由是与纳管的 `chrome-flags.conf` / `chromium-flags.conf` 强耦合，订阅
若把端口换掉，浏览器代理会**整体断掉**且很难查。脚本幂等，键缺失时不凭空添加。

面板（MetaCubeXD）**不由仓库部署**：mihomo 内置了这个能力——`external-ui` 指向的目录不存在时，
它自己去 `MetaCubeX/metacubexd` 的 gh-pages 分支下载解压。临时实例 + 临时目录实测三点：

- **不是启动阻塞路径**：先 `RESTful API listening`，之后才 `External UI downloading ...`；
- **幂等**：目录已存在就 `UI already exists, skip downloading`；
- **走它自己的规则引擎**：`[TCP] mihomo --> github.com:443 doesn't match any rule using DIRECT`，
  所以下载能吃配置里的代理——这比 bootstrap 里裸 `curl` 直连更稳，何况 bootstrap 阶段还没有代理。

产物与 releases 的 `compressed-dist.tgz` **逐字节相同**（`diff -rq` 无输出，160 个文件 / 8.1M，
`_nuxt` 构建 hash 一致），所以内置能力完全够用，仓库不再重复实现一遍。

`Country.mmdb` 由 bootstrap 重新指到 `clash-geoip` 的副本（`/etc/clash/Country.mmdb`，上游
地理库更新更勤）。
