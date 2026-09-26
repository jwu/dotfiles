# dotfiles

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
| `pi-config` | **保留** | `extensions/*.ts`、`tests/`、`package.json`、`tsconfig.json`、`settings.json` |
| `install-arch` | **并入** `bootstrap/` | 它本质是「新机器第一步」，与 `configs` 一起退役 |

`pi-config` 保留后，其 `settings.json` 里
`"extensions": ["~/bin/pi-config/extensions"]` 这个硬编码路径**不需要改**——这正是保留它
而非并入的理由之一。

## 安装入口：`bootstrap/`

装 chezmoi 这一步**不可能**由 chezmoi 自己完成（鸡生蛋），所以入口脚本独立于 chezmoi 源：

```
bootstrap/
└── arch.sh      装 chezmoi → clone 本仓库到 ~/bin/dotfiles → chezmoi init --apply
```

新机器一行式：

```bash
sh -c "$(curl -fsLS https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/arch.sh)"
```

`bootstrap/arch.sh` 由 `install-arch/install.sh` 演化而来，但编排目标从「clone 三个仓库并按序
跑各自的脚本」变成「clone 本仓库 + `chezmoi init --apply`」。之后所有装机动作由 `run_*`
脚本接管，不再需要外部编排器。

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
  fcitx5/profile                       ← desktop-settings: fcitx5/profile
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
AppData/Roaming/alacritty/alacritty.toml   ← configs: win/alacritty.toml
AppData/Roaming/starship.toml              ← configs: win/starship.toml
.chezmoiignore
bootstrap/arch.sh
run_*.sh
```

两处**路径重映射**（源与目标层级不同，不能整体搬）：

- `linux/backgrounds/*.webp` → `~/.config/swaylock/backgrounds/`
- `linux/neovide.desktop` → `~/.local/share/applications/neovide.desktop`

`configs` 的 `common/` 概念在本仓库消失：`common` + `linux` + `mac` 三份塌缩成一份文件加模板分支。

### 已导入的 67 个文件

阶段 1 已完成（见「实施状态」）。当前源里是 67 个文件 + 47 个目录条目，`chezmoi diff`
为空。

## 模板化的文件

| 文件 | 差异 | 处理 |
| --- | --- | --- |
| `dot_zshrc.tmpl` | 26 行（Linux 独有 ZVM / waybar announce / `PI_NERD_FONTS`；macOS 独有 brew nvm 与 `/Applications/*` alias） | `{{ if eq .chezmoi.os "linux" }}` 分支 |
| `starship.toml.tmpl` | 4 行 | 同上 |
| `waybar/modules.json` | 当前是 `__WAYBAR_MODULE_DIR__` 占位符经 `sed` 生成的绝对路径 | `{{ .chezmoi.homeDir }}/.config/waybar` |
| `swaylock/config` | 同理，`__SWAYLOCK_BACKGROUND_DIR__` | `{{ .chezmoi.homeDir }}/.config/swaylock/backgrounds` |
| `git/config.tmpl` | `gh` 写入的 credential 段含 `/home/jwu` | 模板化 `{{ .chezmoi.homeDir }}`，见下 |

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

## pi 的可变状态

`~/.pi/agent/` 下的文件分三类：

| 类型 | 文件 | 处置 |
| --- | --- | --- |
| 静态资源（pi 只读） | `agents/`、`skills/`、`prompts/`、`themes/` | **已纳入**，安全 |
| 人工维护的配置 | `keybindings.json`、`APPEND_SYSTEM.md` | **已纳入** |
| **工具独占写入** | `mcp.json`（用 `/mcp` 装 server 时改写）、`extensions/*.json`（pi-ask 写回）、`settings.json`（本机 provider/模型状态） | **排除**，当纯本机状态 |
| 凭据与运行时 | `auth.json`、`sessions/`、`models-store.json`、`*-cache.json`、`install/`、`bin/`、`npm/` | **绝不纳入** |

`mcp.json` 里现在是 `blender` / `chrome-devtools` / `open-pencil`，这些是用 pi 命令装进的本机
状态；`extensions/eko24ive-pi-ask.json` 有被 pi-ask 写回的历史（见 `pi-config` 的
`"pi-ask: sync config back to schemaVersion 5"` 提交）。所以这三类排除在外，与 `auth.json`
同等对待。

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

`win/config.bat` 不是复制内容，而是**生成引用文件**：`%APPDATA%\alacritty\alacritty.toml` 里写
`import = ["%MY_CONFIGS%\alacritty.toml"]`，nvim / neovide / wezterm 同理。已在「仓库即源」的
方向上，本仓库可以直接接管内容文件，少一层指针。

两处缺口需在迁入前确认：

1. `win/install.bat` 的落地根是 `%USERPROFILE%\bin`（clink 装到 `%USERPROFILE%\bin\clink`），
   便携工具堆在那里，与配置目录分离。
2. **`win/starship.toml`、`win/nu/*.nu`、`win/clink_scripts/*.lua`、`win/cmds/*.cmd` 的落地
   路径在 `install.bat` / `config.bat` 里都没有体现**——目前靠手动复制或 `STARSHIP_CONFIG`
   环境变量指向仓库，需确认后才能定 chezmoi 目标路径。

chezmoi 在 Windows 上以 `%USERPROFILE%` 为家目录，`%APPDATA%` 即 `AppData/Roaming`。
`win/install.bat` 与 `win/config.bat` 本身属装机层，迁入本仓库但保留为手动执行的脚本。

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
| `configs/win/install.bat`、`config.bat` | 迁入 `win/`，手动执行 | Windows 装机层 |

`run_after_fcitx5.sh` 的缩水要点：原脚本做三件事——复制配置、下载 Rime Ice 词库、
`rime_deployer --build` 并重启 fcitx5。复制那半由 chezmoi 接管后，只剩下后两件。**必须用
`after` 前缀**，因为词库重建必须在 `profile` / `classicui.conf` / `*.custom.yaml` 落盘之后
跑。`desktop-settings/AGENTS.md` 要求的「绝不覆盖 `build/`、用户词频和键盘缓存」这条约束
在缩水后仍须保持。

### pi-config 的编排

`pi-config` 是唯一被 clone 的外部仓库，由本仓库脚本触发：

```
run_once_after_install-pi-config.sh
  ├─ [ -d ~/bin/pi-config ] || git clone git@github.com:jwu/pi-config.git ~/bin/pi-config
  ├─ bash ~/bin/pi-config/install.sh     ← 装 npm 插件（settings.json 的 packages）
  └─ 提示运行 /reload 生效
```

`pi-config/install.sh` 本身需要**缩水**：它现在还会部署 `agents/`、`prompts/`、`skills/`、
`themes/`、`extensions-settings/` 到 `~/.pi/agent/`，这些已由 chezmoi 接管，会与
`chezmoi apply` 互相覆盖。缩水后它只负责扩展工程相关的事（npm 插件、`extensions/` 的
`settings.json` 指向关系）。

## 退役计划

| 仓库 / 位置 | 动作 |
| --- | --- |
| `configs` | 配置文件迁入本仓库；`install.sh` / `config.sh` 的非文件动作转成 `run_*` 脚本；`docs/` 整体迁入；`src/gpu-watch.c`、`waybar-niri-windows.sh` 迁入；`win/` 迁入；`common/`、`linux/`、`mac/` 的配置副本删除。**最后删除仓库** |
| `desktop-settings` | `profile`、`classicui.conf`、`themes/`、`rime/*.custom.yaml`、`zed/settings.json`、`aerospace/.aerospace.toml`、`totalcmd/wincmd.ini` 迁入；两个 shell 脚本迁入为 `run_*`；`*-config.md` 迁入 `docs/`。**最后删除仓库** |
| `pi-config` | 删除 `agents/`、`prompts/`、`skills/`、`themes/`、`extensions-settings/`、`APPEND_SYSTEM.md`、`keybindings.json`；`install.sh` 缩水。**保留仓库** |
| `install-arch` | 演化为 `bootstrap/arch.sh`，**删除仓库** |
| `configs/linux/config.sh:299` | 现在靠 `$ROOT_DIR/../desktop-settings` 定位 fcitx5 脚本，迁入后改为直接引用本仓库的 `run_after_fcitx5.sh` |
| 家目录 96 个 `*.bak.*` | `backup_file()` 机制随两个仓库退役，一次性清理 |

顺带修一处 bug：`desktop-settings/AGENTS.md` 提到 `obsidian/template-vault/`，该目录不存在。

## 实施状态

### 已完成：阶段 0-1 + 基线

- chezmoi `v2.72.2`（pacman，`extra` 仓库）已装
- 源目录 `~/bin/dotfiles` 已 `init`；`.chezmoiignore` 拦住了 `README.md` / `docs` /
  `bootstrap` / `scripts`
- **67 个配置文件已从家目录导入**（66 个首批 + 对账补入的 `niri/config.kdl`），
  `chezmoi diff` 为空
- 3 个含 `/home/jwu` 的文件已模板化（阶段 3 的一部分），全部是等价变换：
  `waybar/modules.json.tmpl`、`swaylock/config.tmpl`、`git/config.tmpl`
- 基线已 commit（`1aabe1e`）并 push 到 <https://github.com/jwu/dotfiles>（public）

两处关键做法：

- 导入用「从家目录读取」而非「从仓库读取」，所以首次 `apply` 是空操作，**不存在覆盖
  风险**。3 个模板化同样是等价变换，`diff` 始终为空，Git credential helper 功能不变。
- 对账用脚本把 `configs` 里所有 `$HOME/*` 写入目标与 `chezmoi managed` 逐条比对，而非
  人工读脚本——`niri/config.kdl` 的遗漏就是这样发现并补上的。

### 待做：阶段 2-6

1. **阶段 2 — 与两个退役仓库对账**。逐个比对源文件与 `configs` / `desktop-settings` 中的
   副本，找出「手改过家目录但没回写仓库」的文件。已知至少 2 处漂移：
   `~/.config/git/config`（多 gh helper）、`~/.pi/agent/settings.json`（本机 provider 状态，
   已决定排除）。**这些文件里可能有仓库版本没有的内容，直接以仓库为准会丢。**
2. **阶段 3 — 模板化（3/5 已完成）**。已模板化 `waybar/modules.json`、`swaylock/config`、
   `git/config`。剩余：合并 `linux/.zshrc` 与 `mac/.zshrc` 成 `dot_zshrc.tmpl`、合并两侧
   `starship.toml`（本机没有 mac 版本，需先从 `configs` 仓库搬入）。每步用
   `chezmoi execute-template < x.tmpl | diff - 目标文件` 验证渲染等价。
3. **阶段 4 — 迁入脚本层**。`bootstrap/arch.sh`、`run_*` 脚本、`win/`、
   `docs/`、`src/gpu-watch.c`、`waybar-niri-windows.sh`。
4. **阶段 5 — pi-config 缩水**，并加 `run_once_after_install-pi-config.sh`。
5. **阶段 6 — 退役两个仓库**并清理 96 个 `.bak`。

## 待确认

1. **`settings.json` 的排除边界**：`pi-config/settings.json` 含 pi 的 npm 插件列表
   （`@eko24ive/pi-ask` 等），这对跨机器一致有值，但它同时含本机 provider/模型状态。
   要不要把「插件列表」单独抽成模板纳入？
2. **家目录里从未被管过的配置**是否一并纳入：`~/.config/chrome-flags.conf`、
   `chromium-flags.conf`、`mimeapps.list`、`nvim/lazy-lock.json`（lazy.nvim 插件锁，纳入后
   可复现插件版本）。`user-dirs.dirs` 由 `xdg-user-dirs` 生成，属工具自管。
3. **`mac/config.sh` 是否整体退役**：它只有 95 行且全是 `cp`，配置迁走后没有内容，
   剩余的 `aerospace reload-config` 可并入 `run_*`。
4. **win 侧本轮是否纳入**：上文两处缺口未确认前，win 覆盖率不完整。
5. **平台特定文件如何搬入**：源里目前只有本机（Linux）存在的配置。`configs` 的
   `mac/.config/ghostty/config`、`win/` 的 15 个文件，`desktop-settings` 的
   `rime/squirrel.custom.yaml`（mac）、`weasel.custom.yaml`（win）、
   `aerospace/.aerospace.toml`（mac）、`totalcmd/wincmd.ini`（win）**本机不存在**，
   无法用 `chezmoi add` 导入，只能从仓库手工搬入源。要在迁脚本阶段一并搬，还是等
   真正用 mac / win 时再补？

## 参考

- 快速上手 <https://www.chezmoi.io/quick-start/>
- 源目录命名与模板函数 <https://www.chezmoi.io/reference/>
- 脚本与前缀 <https://www.chezmoi.io/reference/target-types/#scripts>
- 与其它 dotfile 管理方式的对比 <https://www.chezmoi.io/comparison/>
- 早期评估（`configs` 视角，含 `gh` 抢写与模板化的详细推导）
  `configs/docs/chezmoi-migration.md`
