# chezmoi 的坑

这一页记录的是「看起来会工作、实际不会」的那几处。设计推导看 [`design.md`](design.md)。

## `.chezmoiignore` 匹配的是**目标**路径

不是源路径。所以里面写 `README.md` 指的是家目录下的 `~/README.md`——不加这一行，
`chezmoi apply` 会真的在 `~` 下创建 `README.md`。

## 源里以点开头的条目不算目标

chezmoi 忽略源目录中名字以 `.` 开头的条目（`.chezmoi*` 系列除外），所以仓库根的
`.pi/` 这类目录既不会被部署，也不会出现在 `chezmoi managed` 里。

推论：**不要**为了「排除」它而往 `.chezmoiignore` 里写 `.pi`。那一行匹配的是目标路径，
排除掉的是家目录的 `~/.pi`（那份真源在 `private_dot_pi/`），等于凭空卸掉一整套 pi 配置。

## 排除要双向做

只写「非 Linux 时排除 macOS / Windows 目标」是不够的，反过来同样需要。否则在 macOS
上整套 Linux 目标仍然是 managed 状态，`apply` 会把 hyprland / niri / waybar /
swaylock / fcitx5 一整套铺进家目录。

## 排除整棵子树，而不是逐个文件

只忽略文件是不够的：chezmoi 仍会为**空的父目录**创建目录。macOS 上
`~/.local/share/applications` 就是这么被创建出来的，直到把 `.local` 整棵子树排除才
消失——源里有那个目录，与它的文件是否被忽略无关。

## `apply <target>` 撞上不存在的父目录会直接失败

给单个目标做局部 apply 时，chezmoi 会先 stat 它的父目录；父目录不存在就直接报错退出，
它**不会**顺手把父目录建出来：

    chezmoi: .config/fontconfig/fonts.conf: stat /home/jwu/.config/fontconfig: no such file or directory

先 `mkdir -p ~/.config/fontconfig` 再 apply 即可。不带 target 的整体 apply 没有这个问题。
（与上一节的区别：那是「空目录被凭空创建」，这是「目录不存在就报错」。）

## 属性前缀会进源路径

chezmoi 依据权限位给源文件加前缀，所以源路径与目标路径不一定逐字对应。典型后果：
`run_onchange_after_40-fcitx5.sh.tmpl` 的 `include` 写目标路径 `profile` 会直接渲染
失败，必须写源路径 `private_profile`。

完整清单见 [`design.md`](design.md) 的「属性前缀会进源路径」。

## `create_` 是「一次性初始化」，不是真源

`settings.json`、`mcp-adapter.json` 这种会被工具自己回写的文件用 `create_` 前缀：chezmoi 只在**目标
不存在**时渲染并写入，目标一旦存在就不再碰它。它既不是「纳入真源」（那会在每次 apply 抹掉
工具写进去的东西），也不是「排除」（新机器上就没有基线）。

两个后果要记着：

- 源与磁盘会静默漂移，`chezmoi diff --include=files` 为 0 **不代表**目标内容等于源。
- 改源里的这类文件不会传到已有机器，得手工同步。

## git 不记录目录权限

所以家目录上的 `0700` / `0600` 除了写进源文件名（`private_` 前缀）没有别处可以
表达。chezmoi 的默认值是目录 `0755`、文件 `0644`——`~/.pi` 里躺着 `auth.json`，
`~/Library` 是 macOS 的私有目录，两者都不该被放宽。

## 失败的 `run_` 脚本会被记账

失败的脚本也会进 `scriptState`，于是它**不会**因为「上次失败」而自动重跑——只有
内容变化才会。修好之后要先清记账：

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply -v
```

`run_*` 脚本都幂等，重跑一遍是安全的。

## fail-fast

任一 `run_*` 脚本失败会中止整个 apply，后面的脚本不再执行。所以平台不适合的脚本必须
**`exit 0`**，而不是让它失败：`run_onchange_` 只按内容记账，一个注定失败的脚本会永远
拖住后续每一次 apply。

## `sourceDir` 必须显式写

源在 `~/bin/dotfiles`，不是 chezmoi 的默认位置（`~/.local/share/chezmoi`），所以每台
机器都要有 `~/.config/chezmoi/chezmoi.toml`：

```toml
sourceDir = "/Users/<user>/bin/dotfiles"
```

它是 chezmoi 自己的配置（鸡生蛋：chezmoi 不可能管自己的源在哪），不由本仓库管理。

## 家目录里不纳入源的清单

`/collect` 会扫出「家目录有、源没管」的文件。递归全扫撞上的几千个运行时数据不必逐个
判断：命中下表的一律跳过。判据只有两类——**它不是配置**，或者**它是这台机器的身份**。

### 工具自己生成 / 重写

纳进来会与工具持续抢同一份文件，每次 apply 都在制造漂移。

| 路径 | 原因 |
| --- | --- |
| `~/.config/gh/config.yml` | `gh` 自行重写 |
| `~/.config/gh/hosts.yml` | 同上，且含 OAuth token |
| `~/.config/user-dirs.dirs`、`user-dirs.locale` | `xdg-user-dirs-update` 生成 |
| `~/.config/nvim/lazy-lock.json` | lazy.nvim 生成 |
| `~/.local/share/applications/mimeapps.list` | 桌面环境运行时生成 |
| `~/.config/fcitx5/config` | fcitx5 自己写；同目录只有 `profile` 与 `conf/classicui.conf` 是纳管的补丁 |
| `~/.config/Thunar/uca.xml` | 还是 Thunar 自带的示例动作，且它会写回 |
| `~/.config/godot/editor_settings-*.tres` | 编辑器设置，含窗口布局 |
| `~/.config/warp-terminal/user_preferences.json` | Warp 自行重写 |

`~/.config/chezmoi/chezmoi.toml` 也在这里：由 `bootstrap/<platform>` 写，见上一节。

### 运行时状态 / 缓存

| 路径 | 原因 |
| --- | --- |
| `~/.config/{chromium,google-chrome}/**` | 浏览器 profile，含 Cookies 与 Login Data |
| `~/.config/dconf/user` | 二进制状态库 |
| `~/.config/chezmoi/chezmoistate.boltdb` | chezmoi 记账库 |
| `~/.config/{fcitx,ibus}/**` | dbus / socket 句柄 |
| `~/.config/{btop,go,nautilus,systemd,yay}/` | 空目录，工具首次运行才填 |
| `~/.config/comfy-cli/**` | `recent_workspace` 之类由 comfy-cli 写回，且含本机路径 |

### 构建产物 / 下载物

| 路径 | 原因 |
| --- | --- |
| `~/.config/waybar/waybar-niri-windows.so{,.version}` | `scripts/` 里源码的编译产物 |
| `~/.local/bin/gpu-watch` | `scripts/gpu-watch.c` 的编译产物 |
| `~/.local/bin/gh`、`~/.local/bin/bluetuith` | 下载的独立二进制 |
| `~/.local/bin/steam-progress` | 一次性调试脚本（无 shebang，绑 Steam 的日志格式） |
| `~/.local/share/applications/*.desktop` | Steam 等游戏启动器生成 |
| `*.bak.2026*` | 旧 `configs` 仓库的 `install.sh` 留下的备份（`~/.config/**` 与 `~/.local/bin/` 里各有几十个） |

### 凭据 / 机器身份

| 路径 | 原因 |
| --- | --- |
| `~/.pi/agent/auth.json` | 凭据 |
| `~/.gitconfig` | 个人层（邮箱、姓名），每台机器手工维护 |
| `~/.config/Moonlight Game Streaming Project/Moonlight.conf` | 含客户端私钥、内网与公网地址、MAC、对端主机名；且 Moonlight 会写回 |
| `~/.config/mcp/mcp.json` | pi-mcp-adapter 的用户全局共享层；里面列的是本机 venv 里的 comfy-mcp 绝对路径 |

清单是**判据的实例**，不是穷举。新装一个软件、位置对不上的，按同样两条判据判断：会被
工具重写的不进，带机器身份的不进。
