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
| yazi / gitui | 仓库包 | **没有包**，`cargo install yazi-fm yazi-cli gitui` |
| glow | 仓库包 | `glow`（apt 有） |

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

cargo / rustup 不需要这样嵌：`dot_zshrc.tmpl` 末段本来就有 `export PATH=~/.cargo/bin:$PATH`，
而 rustup 用 `--no-modify-path` 安装，两边正好对上。代价是它们**只在交互式 zsh 里可见**：
`ssh host 'cargo --version'` 拿到的是 `command not found`，因为非交互 shell 不读 `.zshrc`。

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
  ver=$(gh release view --repo twpayne/chezmoi --json tagName -q .tagName)   # v2.73.3
  curl -fsSL -o /tmp/chezmoi_linux_amd64.tar.gz \
    "https://github.com/twpayne/chezmoi/releases/download/$ver/chezmoi_${ver#v}_linux_amd64.tar.gz"
  scp /tmp/chezmoi_linux_amd64.tar.gz <host>:/tmp/
  # ECS
  tar -xzf /tmp/chezmoi_linux_amd64.tar.gz -C /tmp chezmoi
  install -m 0755 /tmp/chezmoi ~/.local/bin/chezmoi
  ```

  注意 asset 名带版本号（`chezmoi_2.73.3_linux_amd64.tar.gz`），`releases/latest/download/...`
  那种写法在这里既被墙、也会 404。

  `bootstrap/debian.sh` 认 `CHEZMOI_BIN=/tmp/chezmoi` 这个入口。
- **`raw.githubusercontent.com` 上的安装脚本不能当作可靠依赖。** `run_once_before_10-shell-tools`
  （Oh My Zsh）与 `12-dev-runtimes` 里的 nvm 都从那里拉脚本；失败时它们会记进
  `FAILED_STEPS` 然后**继续**，不会中断 apply，但这一步不会生效。
- **bun 装不了。** `bun.sh/install` 的脚本本身 200，它下载的二进制在 GitHub release 上。
  这台机器上 bun 是可选工具，先跳过；需要时改用 npm 包 `bun`（走 npmjs，通）或从
  `codeload` 的源码构建。
- **scrapling 会顺带下载 Chromium**（playwright 的 CDN），国内速度未知，第一次 apply 时留出
  时间；失败也不阻塞后面的脚本。

## 首次安装用的镜像变量

下面四个镜像**不进仓库**：另外三台机器不需要，硬编码进去反而会把它们的下载绕到国内。
只在 ECS 的 shell 里 export（或写进本机 `~/.config/uv/uv.toml`），首次安装用一次；
`run_onchange_` 的脚本内容不变就不会重跑，所以不需要常驻。

| 工具 | 变量 / 文件 | 值 | 实测 |
| --- | --- | --- | --- |
| rustup | `RUSTUP_DIST_SERVER` | `https://mirrors.aliyun.com/rustup` | 官方源 30 分钟只下 33 MB，镜像 1.9 MB/s |
| rustup | `RUSTUP_UPDATE_ROOT` | `https://mirrors.aliyun.com/rustup/rustup` | 同上 |
| nvm 的 Node | `NVM_NODEJS_ORG_MIRROR` | `https://mirrors.aliyun.com/nodejs-release` | **不要带尾斜杠**，nvm 会再拼 `/`，双斜杠 404 |
| uv / PyPI | `~/.config/uv/uv.toml` 的 `[[index]]` | `https://mirrors.aliyun.com/pypi/simple/` | 官方 PyPI 直连时 `uv tool install scrapling` 跑了 1h45m 未完成 |
| playwright | `PLAYWRIGHT_DOWNLOAD_HOST` | `https://cdn.npmmirror.com/binaries/playwright` | 官方 CDN 15 分钟无字节，镜像 120 MiB 分钟级 |

`uv.toml` 的形状：

```toml
[[index]]
url = "https://mirrors.aliyun.com/pypi/simple/"
default = true
```

PyPI 的**索引**不是瓶颈（三个源都是 0.2–1.1 s），慢的是包体下载与 playwright 的 Chromium，
所以 uv 镜像的必要性要等真的卡住才看得出来。

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
| `10-shell-tools` | `raw.githubusercontent.com` 被重置时回退到 `git clone`（这次改造加的）；实测它曾把 `~/.oh-my-zsh/custom/` 当成「已安装」，现在看 `oh-my-zsh.sh` |
| `12-dev-runtimes` | rustup 需要 `RUSTUP_DIST_SERVER`，Node 需要 `NVM_NODEJS_ORG_MIRROR`；bun 的二进制在 GitHub release 上，被 `timeout` 截断后按 optional 跳过 |
| `13-scrapling` | 需要 uv 的 PyPI 镜像 **和** `PLAYWRIGHT_DOWNLOAD_HOST`，两者都上才跑通 |
| `14-herdr` | 已装（herdr daemon 在这台机上跑着），`command -v herdr` 命中后跳过 |
| `20` / `30` / `90` | headless 短路，`exit 0` |
| `40-fcitx5` | 没装 fcitx5，脚本自己 `exit 0` |
| `60-zed-cli` | 没有 zeditor，脚本自己 `exit 0` |
| `50-pi-config` | npm 走 `registry.npmjs.org`（通），`~/bin/pi-config` 早已存在 |
| `70-aerospace` / `80-inputsourcepro` | darwin 专属，Linux 上渲染为空 |

失败的 `run_*` 会被记进 `scriptState` 且**不会重试**，修好后：

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply -v
```
