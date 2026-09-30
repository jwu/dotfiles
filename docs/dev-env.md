# 开发运行时

`rustup`、`nvm` + Node LTS、`uv`、`bun` 这四个工具在 2026-09-30 之前**没有任何一处**
安装步骤：`bootstrap/arch.sh` 只装了 Arch 的 `rustup` 包（**没有 toolchain**），
`macos.sh` 与 `windows.bat` 一个都没有，而 `dot_zshrc.tmpl` 早就在给 `~/.cargo/bin` 与
`$BUN_INSTALL/bin` 加 PATH——那两条 PATH 指向的是不存在的目录。

实际撞到的两处症状，都不是「装不上」，而是**装了没初始化**：

- `rustup` 是 Arch extra 的包，`/usr/bin/cargo` 在，但 `rustup default stable` 之前它只是
  一个会报错的转发器；
- `nvm` 在 Arch 上根本没有安装步骤，于是 `$NVM_DIR/nvm.sh` 不存在，`dot_zshrc.tmpl` 的
  Linux 分支静默跳过，**`npm` 缺失**——而 `run_once_after_50-pi-config.sh.tmpl` 的
  `ensure_pi()` 遇到缺 npm 只打印一行警告就返回，脚本照旧 clone、照旧以 0 退出。
  pi CLI 没装成，装机日志里却不像失败。

参考的清单来自 `jwu/dev-settings` 的 `mac/setup_dev.sh` 与 `win/setup_dev.bat`。它**只是
清单参考**：那个仓库只有 mac 与 win 两份、均是一次性交互式脚本（`read -p`、`set -e`、
结尾 `pause`），与本仓库「`bootstrap/` 是唯一需要终端的层」的分层相反，而且 `AGENTS.md`
只允许 clone `pi-config`。内容重新实现，不做依赖。

## 落点

| 平台 | 位置 | 来源 |
| --- | --- | --- |
| Linux、macOS | `run_onchange_before_12-dev-runtimes.sh.tmpl` | 各工具的官方 per-user 安装器 |
| Windows | `bootstrap/windows.bat` 的 `:SCOOP_DEV_RUNTIMES`、`:DEV_RUSTUP` | scoop（`uv`、`bun`、`nodejs-lts`）与官方 `rustup-init.exe` |

编号 12 是有意的：`run_once_after_50-pi-config.sh.tmpl` 要 `npm` 才能装 pi CLI，而
`before_*` 先于所有文件部署、也先于 `after_*`，所以只要 12 < 50 就够。副作用是
`bootstrap/arch.sh` 的 `install_wordseg()` 不必再自己补 toolchain——它跑在
`chezmoi init --apply` **之后**，那时这个脚本已经执行过了。那一段仍保留，作为「这台机器
既没有 cargo 也没有 rustup」的兜底。

用 `run_onchange_` 而不是 `run_once_`：两者的判据其实很接近——`run_once_` **也会**在内容变化
时重跑（本项目一度以为不会，见 `design.md` 里 2026-09-30 的更正）。差别只在「把内容改回一个
曾经跑过的版本」：`run_once_` 认得那个版本的旧记录、不再跑，`run_onchange_` 只看「与上次是否
相同」、仍会跑。

选 `run_onchange_` 是因为这份清单会演进，而前缀本身就是一句说明：「内容变了就重跑」。代价是改这份脚本里
的任何东西（包括注释）都会让所有机器重跑一次它；因为每一步都先探测再决定，重跑只是几次
`command -v`。

## 为什么不是 pacman

Arch extra 里四个包**全都有**（2026-09-30 查询）：

| 包 | 版本 | 装到哪 |
| --- | --- | --- |
| `rustup` | extra/1.29.1 | `/usr/bin/{cargo,rustc,rustup}` + `/etc/profile.d/rustup.sh` |
| `nvm` | extra/0.40.7 | **`/usr/share/nvm/nvm.sh`** + `init-nvm.sh` |
| `uv` | extra/0.12.20 | `/usr/bin/uv`、`/usr/bin/uvx` |
| `bun` | extra/1.4.2 | `/usr/bin/bun` |

没走这条路有三个原因，其中第一个是决定性的：

1. **`extra/nvm` 装在 `/usr/share/nvm`，不是 `$HOME/.nvm`。** `dot_zshrc.tmpl` 的 Linux
   分支只探 `$NVM_DIR/nvm.sh`，选 pacman 就得再加一路探测。`docs/shell.md` 已经为
   macOS 记过一次同一个形状的坑（`brew --prefix nvm` 对未安装的 formula 也返回 0），
   不想为同一件事再欠一笔。
2. 三个包要 sudo，只能进 `bootstrap/`，于是 Linux 侧与 macOS 侧变成两套逻辑；
   Windows 侧又是第三套。per-user 装法则三平台同语义：装进 `$HOME`，PATH 由
   `dot_zshrc.tmpl` 提供。
3. `nvm install --lts`、`uv`/`bun` 的安装器本来就不需要发行版配合。

代价要记着：这四个工具**不在 `pacman -Syu` 的覆盖范围内**，版本由脚本里的 tag 决定
（nvm 现在 pin 在 `v0.40.7`）。升级是手动的。

落点定下来之后还漏了一处收尾：`bootstrap/arch.sh` 的 `PACKAGES` 里仍旧跟着装 Arch 的
`rustup` 包，与 per-user 安装重复。这个重复会真的制造分叉——pacman 的 `/usr/bin/rustup` 先
存在时，`install_rustup()` 的「命令不存在才装」判据直接短路，那台机器就留在 Arch 的 rustup +
`/usr/bin/cargo`（proxy）上，只有没装过该包的机器（本机就是）才走官方安装器。已把 `rustup`
从 `PACKAGES` 摘掉（2026-09-30），新机器只剩一条路。

**已经装过该包的机器不会被自动卸载**：`/usr/bin/rustup` 还在，`install_rustup()` 仍短路。
要退出分叉得手工 `pacman -Rns rustup`，之后 dev-runtimes 才会在下次 apply 时装官方那份装到
`~/.cargo/bin`（`dot_zshrc.tmpl` 把 `~/.cargo/bin` 排在 PATH 前，两套并存时生效的是官方那份，
但 toolchain 仍会写进 pacman rustup 的 `~/.rustup`）。

## Windows 侧

`run_*.sh` 在 Windows 上会被渲染成空字符串（`exec(3)` 不认 shebang，失败发生在解释器
起来之前，见 `design.md` 的 (c) 条），所以这一层没法复用同一份脚本，只能进
`bootstrap/windows.bat`。scoop 的 shim 落在一个已经配好的 PATH 上，所以 `uv`、`bun`、
`nodejs-lts` 直接进 `SCOOP_DEV`。

`rustup` 是例外，仍走官方 `rustup-init.exe`：Windows 上「把 `%USERPROFILE%\.cargo\bin`
加进用户 PATH」这件事正是它做的。Unix 那侧相反——PATH 由 `dot_zshrc.tmpl` 独占，所以
脚本显式传 `--no-modify-path`。

Windows 上 Node 用 scoop 的 `nodejs-lts` 而不是 NVM for Windows：这一层需要的只是
`npm` 能给 pi CLI 用，而 scoop 的 shim 无需再管环境变量。`pi` 本身在 Windows 上仍是
手工装（`docs/onboarding-a-machine.md`）。

## 三处坑

### installer 会改写 shell 配置

uv 的安装器默认往 `~/.zshenv` / `~/.zshrc` 追加 PATH 行，它认 `UV_NO_MODIFY_PATH=1`
（`--no-modify-path` 已废弃，会打印弃用警告）。

bun 的安装器**没有**对应开关：只要 `case $(basename "$SHELL")` 命中 `zsh`，就往
`~/.zshrc` 追加一个 `# bun` 块。而 `~/.zshrc` 是 chezmoi 的目标，让 installer 写它就是
两个所有者争同一份文件。脚本于是传 `SHELL=/bin/sh`——落到 `*)` 分支，只打印两行待添加的
`export`（`dot_zshrc.tmpl` 里已经有了），不碰任何文件。副作用是没生成 zsh completions，
脚本因此显式跑一次：

```bash
"$HOME/.bun/bin/bun" completions > "$HOME/.bun/_bun"
```

### bun completions 那一行一直是坏的

`dot_zshrc.tmpl` 原文：

```zsh
[ -s "~/.bun/_bun" ] && source "~/.bun/_bun"
```

双引号里的 `~` 不展开，所以这个 `-s` 永远为假，completions 一次都没有加载过。已改成
`$HOME/.bun/_bun`。

### nvm.sh 不是 `set -u` 干净的

脚本沿用仓库其它 `run_*` 的 `set -uo pipefail`（实测 nvm 0.40.3 能 source），但
`nvm install` / `nvm alias` 的调用被夹在 `set +u` / `set -u` 之间：机器上可能已经装着
更老的 nvm，那是 `unbound variable` 的经典来源。

## 「缺失才装」是刻意的

判据是「命令不存在才安装」，不是「把机器校准到某种状态」。三个后果：

- 已经装好的工具原样保留，版本不动；
- **nvm 的 `default` alias 不动**。本机是 `24`，新机器会被设成 `lts/*`。这不是漂移：
  alias 属于机器的本地选择，与 `~/.pi/agent/settings.json` 里的 provider 同类。
  `run_` 那种「无差异不写盘」的同步语义在这里不合适；
- 只有在一台机器上**一个 Node 版本都没有**时才 `nvm install --lts` +
  `nvm alias default 'lts/*'`。

## 未纳入

- **`tree-sitter-cli`**：Arch 有 extra 包（已在 `arch.sh` 的 `PACKAGES` 里），macOS 与
  Windows 需要 `cargo install`。本机那份就是这么来的。属于「下一轮再看」。
- **`zig`、`deno`**：仓库里没有任何引用（本机的 `deno` 是手工 brew 装的）。
- **`~/.cargo/bin` 里的零散工具**（`cog`、`gdscript-formatter` 等）：无仓库内引用。
- **`jwu/dev-settings` 仓库本身**：见文首，只作清单参考。

## 验证

本机（2026-09-30，macOS）四个工具**全部已存在**，所以脚本整条走短路分支、零下载、零改动：

```
>>> rustup + stable toolchain
info: using existing install for 'stable-aarch64-apple-darwin'
    rustup: rustup 1.28.2 (e4f3ad6f8 2025-04-28)
>>> nvm + Node LTS
    nvm: 0.40.3; Node already installed, left alone
>>> uv
    uv: uv 0.9.26 (ee4f00362 2026-01-15)
>>> bun
    bun: 1.4.2
```

`nvm` 那行是判据的关键：本机 `~/.nvm/alias/default` 是 `24`，脚本报告「left alone」而不是把它
改成 `lts/*`。随后 `chezmoi apply`（不带 `-v`）零输出、`chezmoi diff --include=files` 为空、
`~/.zshrc` 里只有一处 `# bun`（源里的那个，不是 installer 追加的）。

`run_onchange_` 的语义也实测过：给脚本加一条注释使内容变，`chezmoi status` 立刻列出
` R 12-dev-runtimes.sh`，apply 后重新执行并再次全部短路。

**未验证**的是三条真正的安装路径：rustup 的 curl 安装器、`SHELL=/bin/sh` 让 bun 不写 rc、
`nvm install --lts` + `nvm alias default 'lts/*'`。本机四个工具都在，走不到那些分支，要在新机器
或干净容器里过一遍。Windows 侧的 `:DEV_RUSTUP` 与 `:SCOOP_DEV_RUNTIMES` 同理。
