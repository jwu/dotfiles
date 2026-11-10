# 端口 → 进程

需求很短：一条命令知道 3000 端口被谁占了，再一条把它关掉，macOS 与 Linux 上行为一致。

## 候选

| 工具 | 规模 | 结论 |
| --- | --- | --- |
| [`killport`](https://github.com/jkfran/killport)（Rust，MIT） | 1.8k stars，crates.io 12 万下载，2026-11 仍在推提交 | 选中，见下 |
| `kport`（Rust） | crates.io 564 下载 | TUI 形态讨巧，但用户基数和维护都太小 |
| `kill-port`（npm） | 572 stars，需要 Node | 不看容器；为一件小事引入 Node 运行时 |
| `leftopen`（Swift） | 144 stars，macOS 菜单栏 + CLI | 只 macOS，这台之外的三台 Linux 用不上 |
| 系统自带 `lsof` / `fuser` / `ss` | 零安装 | 保留作「查细节」，但不是完整答案，见下 |

`killport` 在 homebrew-core 里，所以 macOS 侧是一个 bottle、无依赖；`--dry-run` 正好是
「查」的那一半，`-s sigterm` 能把默认的硬杀换成温和终止，容器模式认得出 Docker / OrbStack /
Podman / Colima，并且会跳过 `docker-proxy`、`OrbStack Helper` 这类端口转发进程。

## 为什么不是 `fuser -k` + `lsof`

这套零安装方案能用，但两处不对：

- `fuser -k` 发的是 SIGKILL，进程没有收尾机会；而「端口被占」十次有八次是自己刚起的那
  个 dev server，硬杀会留下锁文件、半写的数据库、不退出的子进程。
- macOS 上容器的端口对外露出的是 `OrbStack Helper` 或 `docker-proxy`，按端口杀只会杀掉
  转发进程，容器本身还活着。`killport` 先找容器、找到就只动容器。

所以分工是：`lsof -nP -iTCP:<port> -sTCP:LISTEN` 看 PID 与启动命令（`killport --dry-run`
的输出只有进程名），动手交给 `killport`。

## 落点

| 平台 | 位置 | 来源 |
| --- | --- | --- |
| macOS | `bootstrap/macos.sh` 的 `PACKAGES` | `brew install killport`（2.0.2），zsh 补全由 bottle 装进 `$(brew --prefix)/share/zsh/site-functions` |
| Linux | `run_onchange_before_12-dev-runtimes.sh.tmpl` 的 `install_killport()` | `cargo install --locked killport`，落在 `~/.cargo/bin` |
| Windows | 没有 | 没需求，也没有 Windows 机器要验证 |

Linux 走 cargo 而不是包管理器是无奈：`archlinux.org` 的官方仓库里没有这个包，AUR 里三条
同名条目全是别人的 fork（版本停在 1.0.0、0 votes、维护者不是上游作者），装那个不如自己编
上游的 crate。它放在 `12-dev-runtimes` 里而不是 `bootstrap/arch.sh`，正好借用同一份脚本已经
装好的 cargo；用 `step_optional` 是因为首次编译要几分钟，编不过（网络、磁盘）也不该拖住
整条 apply。

## 用法

```sh
killport --dry-run 3000     # 查：Would kill process 'node' listening on port 3000
killport 3000               # 杀，默认 SIGKILL
killport -s sigterm 3000    # 温和终止
killport 3000 8080 9090     # 多个端口
killport --mode container 3000   # 只动容器，不动原生进程
```

## 坑

- 默认信号是 SIGKILL。先 `--dry-run` 看一眼，或者养成 `-s sigterm` 的习惯。
- 退出码 **2** 是「端口上没人」，不是出错；写进脚本时加 `--no-fail`。1 才是真错误
  （权限不足之类）。
- `--dry-run` 只说进程名，给不出 PID 和启动参数；要这些还是 `lsof`。
- 容器端口上，`lsof` 与 `killport` 看到的是不同的进程，一个说转发器、一个说容器——两边
  都对，只是回答的不是同一个问题。

## 验证

本机（2026-11-10，macOS 27 / arm64）实测：

```
$ brew install killport        # 2.0.2，13 files / 4.4MB
$ killport --dry-run 7000
Would kill process 'ControlCenter' listening on port 7000        # rc=0
$ killport --dry-run 9999
No service found using port 9999                                 # rc=2
```

Linux 侧的 `cargo install` 路径**未实测**（没有在这台机器上跑过）——手工验的时候记得
`chezmoi state delete-bucket --bucket=scriptState` 之前先看它到底有没有编过。
