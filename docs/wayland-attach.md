# 从 ssh / tty 附加到 niri 会话

`dot_zshrc.tmpl` 里 Linux 段的 `wattach` / `wdetach` / `wstat`，跟同一份文件里的
`pon` / `poff` / `pstat` 是一套的写法：前者开关代理，后者开关「这个 shell 看不看得
见座位上的图形会话」。

## 要解决的问题

ssh 进来（或坐在 tty 上）的 shell，环境里没有 `WAYLAND_DISPLAY`，`XDG_SESSION_TYPE`
是 `tty`。于是：

```console
$ grim /tmp/a.png
(compositor doesn't support the screencopy protocol / cannot connect to display)
$ niri msg outputs
Niri is not running
```

会话本身活得好好的，只是这个 shell 不知道往哪个 socket 说话。手工补四个变量就能用，
但 socket 名里带 niri 的 pid、重启一次就变，所以值得包成命令。

```sh
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export NIRI_SOCKET=/run/user/1000/niri.wayland-1.1607.sock
```

## 为什么是 zsh 函数，不是 `~/.local/bin` 里的脚本

环境变量不能跨进程传递：子进程改了 `export`，父 shell 一无所知。一个独立可执行脚本
只能把 `export ...` 打印到 stdout 让调用方 `eval`，那是 `ssh-agent` 的做法，代价是
用户每次都得记住 `eval "$(wattach)"`。

`pon` / `poff` / `pstat` 本来就在 `dot_zshrc.tmpl` 里，直接同进程改环境的函数最省事，
也省掉「脚本 + 同名函数包装 + `command` 绕过函数」那层绕。代价是这个工具只能在 zsh
里用（本机 `SHELL=/usr/bin/zsh`，ssh 进来也是 zsh）。

## 变量从哪来

`systemctl --user show-environment` 是主来源。niri-session 启动时把合成器的环境导入
systemd 用户管理器，所以那份拷贝里本来就有整套东西：

```console
$ systemctl --user show-environment | grep -E 'WAYLAND|DISPLAY|NIRI'
DISPLAY=:0
NIRI_SOCKET=/run/user/1000/niri.wayland-1.1607.sock
WAYLAND_DISPLAY=wayland-1
XDG_CURRENT_DESKTOP=niri
XDG_SESSION_CLASS=user
XDG_SESSION_ID=2
XDG_SESSION_TYPE=wayland
```

坑：**不支持按变量名单独查询**，`systemctl --user show-environment WAYLAND_DISPLAY`
会以 1 退出并抱怨 `Too many arguments`。只能整份读进来再筛。整份输出里 `LS_COLORS`
之类的值用 systemd 的 `$'...'` 引号，本工具关心的那几个变量（路径、`:0`、`wayland-1`）
永远不会命中那种写法，所以没有做反转义。

别从 `/proc/<niri-pid>/environ` 读：本机 `/proc` 有 hidepid，同一个用户也读不到，
实测 `Permission denied`。

## 探测顺序与存活校验

1. 先信 systemd 那份的 `NIRI_SOCKET`；
2. 只在对它做存活校验之后；
3. 校验不过就扫 `$XDG_RUNTIME_DIR/niri.*.sock`（按 mtime，取最新的）。

第 3 步不是多余的：**niri 若绕开 niri-session 重启，systemd 那份会指向死掉实例的
socket**，名字里的 pid 是旧的。存活校验就是干这个的——socket 名由
`niri.<display>.<pid>.sock` 组成，取倒数第二段当 pid，`kill -0` 看进程还在不在，
再比对 `/proc/<pid>/comm` 是不是 `niri`，挡掉 pid 回收后的误判。

`DISPLAY` 不单独探测，直接抄会话环境里的值。niri 自己集成 xwayland-satellite 并导出
`$DISPLAY=:0`（见 [`xwayland-satellite.md`](xwayland-satellite.md)），不需要去翻
`/tmp/.X11-unix` 或猜 Xwayland 的 pid。

覆盖的变量：`WAYLAND_DISPLAY`、`NIRI_SOCKET`、`XDG_SESSION_TYPE=wayland`、
`XDG_SESSION_CLASS=user`，加上会话真有就一并抄来的 `DISPLAY`、`XDG_SESSION_ID`、
`XDG_CURRENT_DESKTOP`、`DBUS_SESSION_BUS_ADDRESS`。

## 撤销：为什么要存 undo

`wdetach` 把 shell 恢复成附加前的样子，而不是简单地 `unset` 一批变量。区别在于
`XDG_SESSION_TYPE`：ssh 会话原本是 `tty`，这是有意义的值，一律清成未设置会让别的
工具猜错。所以 `_wattach_apply` 第一次附加时把每个变量的原值（有值就
`export K=<引号转义后的值>`，没值就 `unset K`）拼成一段 shell 代码存进 `WATTACH_UNDO`，
`wdetach` 直接 `eval` 它。

两个由此而来的约束：

- **已经在附加状态的 shell 再次 `wattach`，不会覆盖 `WATTACH_UNDO`**。否则 undo 会把
  「附加后」的值记成原值，`wdetach` 就变成原地踏步。
- 没有附加过的 shell 上跑 `wdetach` 直接报错退出。在本地图形 shell 上误按 `wdetach`
  属于此类，报错比照着 `WATTACH_UNDO` 这个空变量乱清一气安全。

undo 是一段存在环境变量里的 shell 代码，只在同一个 shell 里由自己写入、自己 `eval`，
不落盘、不跨用户。

## 命令形式

```sh
wattach foot             # 在图形会话的环境里开一个终端
wattach grim /tmp/a.png  # 单条命令，不留痕
```

这一支在**子 shell** 里 export，再 `exec` 目标命令：调用方 shell 的环境不受影响，
退出码照常传回。子 shell 里 `_wattach_apply` 的 stdout 被丢弃，免得 `[niri] Attached
to ...` 那行横幅混进命令自己的输出（比如接管道的时候）。裸调用的 `wattach` 才在父
shell 里 export，并打印那行横幅。

## 被拒绝的做法

- **写死 socket 路径**：名字里的 pid 每次重启都变。
- **独立可执行脚本 + `eval "$(wattach)"`**：见上，多一层记忆负担，本仓库也没有先例。
- **`machinectl shell` / `systemd-run --user --scope` 切进会话**：对「跑一条命令」可行，
  但对「让当前 shell 看见会话」无用——它要的正是改变调用方自己的环境。
- **`systemctl --user import-environment`**：方向反了，那是把本 shell 的环境推给
  systemd，不是把会话的环境拉进来。
- **从 `/proc/<pid>/environ` 读图形会话的环境**：hidepid 拦着，读不到。

## 限制

- 只认 niri。`docs/` 里其它合成器（hyprland、sway）的 socket 命名与 liveness 判据都不同，
  没做。
- 同用户有多个图形会话时只取一个（systemd 那份只有一个 `NIRI_SOCKET`，扫描取最新），
  多座位场景没考虑。
- 不处理「跟着 ssh 断开而退出」的问题：`wattach foot` 起的窗口会随 ssh 会话结束收到
  SIGHUP。需要常在就自己 `nohup` / `setsid`。

## 验证

```sh
wstat                    # 会话存在 + 本 shell 是否已附加
wattach
env | grep -E 'WAYLAND|NIRI|DISPLAY'
grim /tmp/a.png          # 真的连上了才算数
niri msg outputs
wdetach                  # XDG_SESSION_TYPE 应回到 tty
wdetach                  # 再跑一次应报错并返回 1
```
