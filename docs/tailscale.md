# Tailscale

这个仓库对 Tailscale 只做两件事：装它，和把「不该开的功能」钉死。**没有配置文件可纳管**——
下面第一节就是为什么。踩过的坑在最后。

## 没有配置文件

Tailscale 的真源在控制面，不在磁盘上：

| 位置 | 内容 | 为什么不进仓库 |
| --- | --- | --- |
| `/var/lib/tailscale/tailscaled.state`（Linux） | 节点身份、私钥、当前 tailnet 地址 | 就是密钥本体 |
| `~/Library/Preferences/io.tailscale.ipn.macsys.plist`（macOS） | 偏好设置与缓存的 profile | App 自己会回写，属「本机 UI 状态」 |
| 控制面 | ACL、设备列表、MagicDNS、tag | 不是文件 |

所以 `chezmoi managed` 里永远不会出现 Tailscale 的条目，和 `docs/design.md` 说的「pi 的可变
状态」「fcitx5 的运行时边界」是同一类问题。想真正把 ACL 当代码管，那是 Terraform 的
`tailscale` provider，不是 chezmoi 这一层的事。

## 落点

| 层 | 位置 | 内容 |
| --- | --- | --- |
| 装机 | `bootstrap/arch.sh` 的 `PACKAGES` + `install_tailscale` | `tailscale`、`openssh` 两个包，`systemctl enable --now tailscaled` |
| 装机 | `bootstrap/macos.sh` 的 `CASKS` | `tailscale` 这一个 cask |
| 装机 | `bootstrap/windows.bat` 的 `INSTALL_TAILSCALE` | winget 装 MSI，注册 `Tailscale` 服务 |
| 策略 | `run_onchange_after_15-tailscale.sh.tmpl`（仅 darwin） | `tailscale set --ssh=false` |

**加入 tailnet 不在任何一层里**：`tailscale up` 要开浏览器走 SSO，产出的是这台机器独有的节点
身份。它必须人工做一次，脚本只负责在它已经做过之后把策略钉住。

**Windows 没有策略层**，因为那层要防的东西在这个客户端上根本不存在。1.104.2 实测：

```
$ tailscale set --ssh=true
The Tailscale SSH server is not supported on windows          ← exit 1
$ tailscale debug prefs | grep RunSSH
  "RunSSH": false                                              ← 字段在，恒为 false
$ tailscale set --ssh=false                                   ← exit 0，但只是 no-op
```

所以 `bootstrap/windows.bat` 只装不钉。**不要为了和另两处对称而补一行 `set --ssh=false`**：
它不会失败，但会让下一个读这个文件的人以为这条策略在 Windows 上需要维护。

### 为什么 Linux 侧的 set 在 bootstrap 而不在 run 脚本

同一个动作在 macOS 上不需要特权（CLI 通过本地 socket 跟 daemon 说话，权限由 macOS 管），
在 Linux 上要 root。`chezmoi apply` 全程保持 root-free、不依赖 TTY，这是 `AGENTS.md` 明写的
边界，所以 Linux 侧只能放进 `install_tailscale`。两个脚本做的是同一件事，位置不同是权限差异
导致的，不是设计重复。

`run_onchange_after_15` 在两个平台上都不会报错：macOS 上执行，Linux 上渲染为空。

## Tailscale SSH 一律关闭

装好后第一件事是把 Tailscale SSH 关掉，用系统 sshd。理由不是洁癖：

2026-10-25，Erica Windisch（Cyberdione Labs）发布 **Tailworm** 报告，针对 tailscale 1.104.2
与 headscale 0.29.5 列出 11 项发现，未走协调披露。最严重的一条在 Tailscale SSH 的 Unix
socket 转发：`tailscaled` 以 root 处理转发，于是攻击者能让 root 进程去连只有 root 能碰的
socket，进而在目标机拿到 root，甚至窃取 enrollment key 把攻击者自己的机器注册成受信节点。

攻击链需要**同时**满足：攻击者已控制一台设备、该设备在 ACL 里被允许 SSH 到目标、该规则允许
port forwarding。所以它是「被攻陷后的横向移动 + 提权」，不是从公网直接打进来。发布当时官方
没有公告、没有 CVE、没有修复版本，工程 VP Mike Shaver 在 Reddit 上回应「不建议所有人关闭
Tailscale SSH」。

本仓库的取舍：不评估「默认 ACL + 允许转发」这种组合的风险收益，直接不用 Tailscale SSH。
系统 sshd 本来就要装（`openssh`），功能是全集，`scp`/`sftp`/端口转发都正常——Herdr UI 的
文件复制依赖这些。

顺带两条相关的取舍：

- **不用 headscale**：同一份报告说 headscale 0.29.5 上转发开关关不掉，每条 SSH 授权都等价于
  目标机的 root。自建的收益不值得这个前提。
- **ACL 用 per-pair 而不是通配**：报告的实测里，写成单点对单点的授权规则自己就阻断了扩散。
  这是唯一能靠配置拿到的防护，比 `src: ["*"]` + `dst: ["*:*"]` 强得多。

## 组网现状（2026-10 实测）

| 节点 | tailnet 地址 | 系统 | 连接 |
| --- | --- | --- | --- |
| `macbook-m3` | 100.125.255.124 | macOS 27 | 基准机 |
| `archlinux-com` | 100.121.5.100 | Arch Linux | 直连 `10.30.40.109:41641`，`tailscale ping` **6ms** |
| `jwu-home-win11` | — | Windows 11 | 2026-10-27 装好客户端与服务，尚未 join |

Tailnet 名 `jwu.github`（GitHub 身份登录，MagicDNS 后缀 `tail0886d3.ts.net`）。两台都在公司网
但跨子网（`10.41.x.x` / `10.30.40.x`），Tailscale 仍然打出了直连。家里那几台尚未加入。

`tailscale netcheck` 在 `macbook-m3` 上的结果：

```
UDP: true
IPv4: 218.107.213.115       IPv6: no
MappingVariesByDestIP: true          ← 对称 NAT
Nearest DERP: sfo 165ms / lax 169ms / hkg 179ms
```

`MappingVariesByDestIP: true` 是对称 NAT，最难穿透的一类。家里宽带如果也是（光猫 + CGNAT 很
常见），两端都是对称 NAT 时会全程走 DERP。SSH 能用，但 Herdr UI 的终端输入会有明显延迟。真要
治，只有两条路：国内 VPS 自建 DERP，或者两边都有 IPv6。

## 踩过的坑

### Windows：全程只有一处需要提权

`winget install --id Tailscale.Tailscale -e` 装的是 per-machine MSI，会弹一次 UAC。这是
`bootstrap/windows.bat` 里**唯一**需要管理员的一步——脚本其余部分（scoop、Nerd Font、Herdr）
都落在 `%LOCALAPPDATA%`。宁可破一次这条边界，也不引入第二条安装路径：

- scoop 的 `extras/tailscale` 是便携版，**不注册服务**，开机自启和路由都会缺
- 即便只用 CLI，它也要创建 Wintun 虚拟网卡，那同样需要提权

装完 MSI 会把 `C:\Program Files\Tailscale` 追加到**机器级** PATH，但当前进程的 PATH 是启动时的
快照，`where tailscale` 依然为空。所以脚本里用 `%ProgramFiles%\Tailscale\tailscale.exe` 的
全路径判断是否存在，而不是查 PATH；只有新开的终端才看得见 `tailscale` 这个命令。

### `hostnamectl set-hostname` 不会更新 tailnet 里的设备名

Tailscale 只在注册时读一次系统主机名。改完之后要显式覆盖：

```sh
sudo tailscale set --hostname archlinux-com     # 1.58+，不重跑 up
```

`--hostname=""` 表示回落到系统主机名。改名后 MagicDNS 旧名立刻失效，`~/.ssh/config` 里按
**名字**写的 Host 条目会一起失效——按 IP 写的不会。

### macOS 的开机自启有两套开关，而且不同步

- GUI 的 *Start Tailscale when you log in* 走 SMAppService，落到系统登录项
- `defaults read io.tailscale.ipn.macsys TailscaleStartOnLogin` 是另一份记录

实测遇到的情况：登录项里已经有 `Tailscale`，但 defaults 里是 `0`，GUI 勾上后也不立刻同步。
处理顺序是

```sh
defaults write io.tailscale.ipn.macsys TailscaleStartOnLogin -bool true
osascript -e 'quit app "Tailscale"' && open -a Tailscale      # 让它重读
```

然后到「系统设置 → 通用 → 登录项与扩展」确认 `Tailscale` 没被禁用。`Start on login` 只保证
进程起来，不保证立刻连上；要「断网后自动重连」得在 App 里配 VPN On-Demand。

### Dock 图标没有 CLI 开关

GUI 的 *Hide Dock icon* 也落在同一份 plist：`HideDockIcon`（1.104.2 实测已是 `true`）。`tailscale set`
里没有任何 dock/icon 选项，要脚本化只有

```sh
defaults write io.tailscale.ipn.macsys HideDockIcon -bool true
```

但这仍然不进仓库，和 `TailscaleStartOnLogin` 同属上面表格里「本机 UI 状态」那一行。

### 合盖休眠会让这台机器从 tailnet 掉线

作为被连的一方（家里连过来），笔记本合盖就断。`sudo pmset -c disablesleep 1` 或
`caffeinate -s`。

### 反向连接要各自对应用户名

两台机器的本地用户名不同（macOS 是 `zyq`，Arch 是 `jwu`），所以 `~/.ssh/config` 得双向写：

```
# macbook-m3
Host archlinux-com 100.121.5.100 10.30.40.109
    User jwu
    IdentityFile ~/.ssh/id_ed25519_jwu

# archlinux-com
Host macbook-m3 100.125.255.124
    User zyq
    IdentityFile ~/.ssh/id_ed25519
```

顺带一条：`ssh archlinux-com` 报 `Permission denied (publickey)` 时，先看是不是回落到当前
本地用户名（`zyq`）而不是 config 里写的 `jwu`——`~/.ssh/config` 里没有匹配的 Host 块就会这样。

### 国内网络的登录阶段

`tailscale up` 需要能访问 `controlplane.tailscale.com`，这一步在国内经常卡住。绕法是先挂代理
完成登录（tailscaled 认 `HTTPS_PROXY`，走 systemd drop-in），之后数据面走 UDP 直连或 DERP，
不再依赖控制面。

## 没有纳入仓库的东西

`~/.ssh/config`、`~/.ssh/authorized_keys`、`~/.ssh/known_hosts` 全部手工维护：

- `id_*` 是凭据
- `authorized_keys` 是授权策略，各机器不同（公司 Mac 上三把、Arch 上一把），且含他人公钥
- `known_hosts` 是运行时产物

`~/.ssh/config` 本来可以模板化（公共段是 GitHub / hardpixel 的 Host 块，差异段是「互相认识」），
但结论是不值得：这台仓库的既有清单里已经把授权层划归手工维护（见
`docs/onboarding-a-machine.md` §4 的 git 个人层），SSH 走同一套判断。
