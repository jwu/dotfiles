# 阿里云 ECS（Debian 13，无 GUI）

第四台接入的机器：`jwu@47.112.x.x`（深圳），Debian GNU/Linux 13 (trixie)，x86_64，
没有桌面、没有 X/Wayland、没有 systemd 用户会话的图形部分。它和前三台的区别只有两点，
但这两点都碰到了仓库的既有假设：

1. **发行版不是 Arch。** `bootstrap/arch.sh` 用 pacman，`run_*` 脚本里的 Linux 分支默认
   pacman / AUR / Wayland 都在。
2. **Linux 但没有 GUI。** `.chezmoiignore` 原来的判据只有 OS，没有「同一个 OS 里有没有桌面」
   这一维，于是 niri / waybar / fcitx5 的配置会落进一个没人读的 home 目录。

结论：新增一个**按机器开关的 `headless` 数据变量**，而不是再增加一个 OS 分支。

## `headless` 开关

在 `~/.config/chezmoi/chezmoi.toml` 的 `[data]` 里设：

```toml
sourceDir = "/home/jwu/bin/dotfiles"

[data]
headless = true
```

- 模板里读它用 `{{ if index . "headless" -}}`，**不用** `{{ if .headless }}`：后者在没设这台
  变量的机器上会直接报 `map has no entry for key "headless"` 并中止 apply，而 `index` 对缺失
  key 返回 nil，落到 else 分支，也就是「缺省 = 有桌面」。三台 GUI 机器因此完全不受影响。
- 它排除的目标写在 `.chezmoiignore` 的 headless 块里：Linux-only 桌面清单的一份镜像，外加
  GUI 终端与编辑器（alacritty、ghostty、neovide、zed）。TUI 程序（nvim、yazi、gitui、glow）
  与 starship / zoxide / git / herdr / pi 全部保留。
- 它跳过三个 `run_*` 脚本：`20-build-gpu-watch`（waybar 的 GPU 模块）、
  `30-build-niri-windows`（waybar 的 CFFI 插件）、`90-ulanzi-au05`（USB 小键盘的用户服务）。
  `40-fcitx5` 与 `60-zed-cli` 不用改：它们本来就 `command -v` 探测后再决定，缺程序时 `exit 0`。

判断清单本身**重复了一份**而不是抽成模板变量。抽出来试过：`{{ $x := list ... }}` 定义行会
给 `.chezmoiignore` 的渲染结果多塞一个空行，而这份文件的空白是逐字节比对过的。24 行重复
换来零风险，代价是改桌面清单时要同步两处，注释里写了这一句。

## 与 Arch 的差异

| 项目 | Arch | Debian 13 |
| --- | --- | --- |
| 包管理 | `pacman` / `yay`（AUR） | `apt`，源是 `mirrors.cloud.aliyuncs.com` |
| chezmoi | `extra` 仓库 | **没有包**，见下一节 |
| `fd` | `fd` | 包 `fd-find`，命令 `fdfind` |
| `bat` | `bat` | 包 `bat`，命令 `batcat` |
| delta | `git-delta` | `git-delta`（命令仍是 `delta`） |

`dot_zshrc.tmpl` 直接调 `fd` 与 `bat`（`FZF_DEFAULT_COMMAND`、`FZF_CTRL_T_OPTS`、
`MANPAGER`），而 `~/bin` 在 PATH 最前面：
`bootstrap/debian.sh` 的 `link_debian_names()` 在 `~/bin/fd`、`~/bin/bat` 建符号链接。
手工接入时等价于：

```bash
mkdir -p ~/bin
ln -sf "$(command -v fdfind)" ~/bin/fd
ln -sf "$(command -v batcat)" ~/bin/bat
```

`~/bin` 不在 chezmoi 的源里（源里只有 `dot_local/bin`，且 headless 下整块 `.local` 被排除），
所以这些链接不会被 apply 回收。

## 网络：哪些通、哪些不通

这台机器在国内，GitHub 的不同端点表现不一致。下表是 2026-10-29 实测（`curl -m 20`）：

| 端点 | 结果 |
| --- | --- |
| `github.com` 首页 | 200 |
| `git ls-remote https://github.com/...` | 通 |
| `codeload.github.com`（源码 tarball） | 200 |
| `github.com/<repo>/releases/latest` 与 `releases/download/...` | **超时** |
| `raw.githubusercontent.com` | **不稳定**：同一天一次 200、一次 `Connection reset` |
| `registry.npmjs.org` / `pypi.org` | 200 |
| `sh.rustup.rs` / `static.rust-lang.org` | 200 |
| `herdr.dev` / `astral.sh` | 200 |
| `git@github.com:...`（22 端口） | `Permission denied (publickey)`，没配 key |

推论：

- **chezmoi 只能离线装。** `get.chezmoi.io` 的脚本本身拿得到，但它随后去 GitHub release
  下载二进制，那一步超时。在开发机上下好 linux_amd64 包，scp 过去：

  ```bash
  # dev machine (has GitHub access)
  curl -fsSL -o /tmp/chezmoi_linux_amd64.tar.gz \
    https://github.com/twpayne/chezmoi/releases/latest/download/chezmoi_linux_amd64.tar.gz
  scp /tmp/chezmoi_linux_amd64.tar.gz <host>:/tmp/
  # ECS
  tar -xzf /tmp/chezmoi_linux_amd64.tar.gz -C /tmp chezmoi
  install -m 0755 /tmp/chezmoi ~/.local/bin/chezmoi
  ```

  `bootstrap/debian.sh` 认 `CHEZMOI_BIN=/tmp/chezmoi` 这个入口。
- **`raw.githubusercontent.com` 上的安装脚本不能当作可靠依赖。** `run_once_before_10-shell-tools`
  （Oh My Zsh）与 `12-dev-runtimes` 里的 nvm 都从那里拉脚本；失败时它们会记进
  `FAILED_STEPS` 然后**继续**，不会中断 apply，但这一步不会生效。
- **bun 装不了。** `bun.sh/install` 的脚本本身 200，它下载的二进制在 GitHub release 上。
  这台机器上 bun 是可选工具，先跳过；需要时改用 npm 包 `bun`（走 npmjs，通）或从
  `codeload` 的源码构建。
- **scrapling 会顺带下载 Chromium**（playwright 的 CDN），国内速度未知，第一次 apply 时留出
  时间；失败也不阻塞后面的脚本。

## 接入顺序

`bootstrap/debian.sh` 走的是标准流程（装 chezmoi → clone → 写配置 → apt → `chezmoi init --apply`）。
**已经手工 clone 过 `~/dotfiles` 的机器不要直接跑它**：它会 `chezmoi init --apply`，跳过比对。
手工顺序：

```bash
# 1. 先把已有的克隆挪到仓库约定的位置（create_settings.json.tmpl 里
#    extensions 指向 ~/bin/pi-config，脚本也假定 sourceDir = ~/bin/dotfiles）
mv ~/dotfiles ~/bin/dotfiles
git -C ~/bin/dotfiles pull --ff-only

# 2. 装 chezmoi（上一节的离线方式）

# 3. 写 ~/.config/chezmoi/chezmoi.toml：sourceDir + [data] headless = true

# 4. 比对。这台机器上 ~/.config 只有 herdr，`chezmoi diff` 应该全是新增
chezmoi diff --include=files

# 5. 应用，然后二次确认 no-op
chezmoi apply -v
chezmoi apply -v          # 必须零输出
chezmoi diff --include=files   # 必须为空
```

## 已知会失败或跳过的脚本

| 脚本 | 在 ECS 上 |
| --- | --- |
| `10-shell-tools` | Oh My Zsh 走 `raw.githubusercontent.com`，可能失败；失败不阻塞 |
| `12-dev-runtimes` | rustup / uv 通；nvm 的脚本同样走 raw；bun 装不了（见上） |
| `13-scrapling` | 走 PyPI，通；Chromium 下载看运气 |
| `14-herdr` | 已装（herdr daemon 在这台机上跑着），`command -v herdr` 命中后跳过 |
| `20` / `30` / `90` | headless 短路，`exit 0` |
| `40-fcitx5` | 没装 fcitx5，脚本自己 `exit 0` |
| `60-zed-cli` | 没有 zeditor，脚本自己 `exit 0` |
| `70-aerospace` / `80-inputsourcepro` | darwin 专属，Linux 上渲染为空 |

失败的 `run_*` 会被记进 `scriptState` 且**不会重试**，修好后：

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply -v
```
