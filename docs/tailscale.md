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

## 组网现状（2026-10-29 实测）

Tailnet 名 `jwu`（GitHub 身份登录，MagicDNS 后缀 `tailxxxx.ts.net`）。下面是 **peer relay 上线前**
`macbook-m3` 上的 `tailscale status` 与逐台 `tailscale ping`（当前状态见本文后面的「结果」）：

```
100.125.255.124  macbook-m3         macOS  基准机
100.121.5.100    archlinux-com      Linux  直连 10.30.40.x:41641   13ms
100.87.214.67    aliyun-ecs-sz      Linux  深圳 ECS，中继候选
100.79.18.17     archlinux-macbook  Linux  relay sfo   1.2–2.2s
100.65.139.110   archlinux-macmini  Linux  relay sfo   1.8–2.4s
100.100.231.1    mac-mini-m4        macOS  relay sfo   0.75–2.4s
100.77.166.83    jwu-home-win11     Windows relay sfo  1.2–3.0s
100.114.57.30    iphone-15-pro      iOS    —
```
`tailscale netcheck` 在 `macbook-m3` 上：

```
UDP: true
IPv4: 110.86.x.x:59083    IPv6: no, but OS has support
MappingVariesByDestIP: true          ← 对称 NAT
PortMapping:                         ← 空：无 UPnP / NAT-PMP / PCP
Nearest DERP: sfo 185.7ms / lax 188.5ms / hkg 188.6ms
```

三个条件叠在一起，打洞注定失败：对称 NAT（对每个目标换源端口，双方都猜不到对端的）、路由器
没开任何端口映射、`en0` 只有 `fe80::` 没有全局 IPv6。只有同 LAN 的 `archlinux-com` 能直连。

剩下的全是 `relay sfo`，而秒级的 `tailscale ping` 不是 185ms 的 DERP RTT 能解释的——那条跨境
链路有丢包与重排。要治只有三条路，见下节。

## 中继：peer relay 优先，自建 DERP 是兜底

### 三条路

| 方案 | 本机往返 | 控制面改什么 | 主机要准备什么 |
| --- | --- | --- | --- |
| peer relay | **31.8ms**（实测 `ping`，0% 丢包） | 一条 `tailscale.com/cap/relay` grant | tailscale + 一个 UDP 端口 |
| 自建 derper | 同 | `derpMap` 里手写 region 900–999 | tailscale + Go + 域名 + 证书 + 80/443 |
| 等 IPv6 | 最优（可直连） | 无 | 运营商下发前缀 |

官方文档的排序也是这个：`custom DERP servers` 页面开头就写「DERP 中继慢时，通常应该先查为什么
打不通，或者改用 peer relay」，并且自定义 DERP 至今标注 **alpha**、需要自己编译及维护。

### 落点：深圳阿里云 ECS

`aliyun-ecs-sz`（`47.112.x.x`，Debian 13，2 核 / 1.7G）：本机 `ping` **31.8ms**、0% 丢包，
比 sfo 的 185ms 好一个数量级。它已经加入 tailnet，`tailscale ip -4` = `100.87.214.67`。

这台机器的坑在于**阿里云是 1:1 NAT**：`eth0` 只有内网 `172.28.x.x`，公网地址在网关。
tailscaled 自报的 endpoint 因此没有公网地址，别的设备连不上它的中继端口。必须显式广告：

```sh
sudo tailscale set \
  --relay-server-port=40000 \
  --relay-server-static-endpoints=47.112.x.x:40000
```

`tailscale debug prefs` 会回显 `RelayServerPort: 40000` 与 `RelayServerStaticEndpoints`，
`ss -lnup` 能看到 tailscaled 在 `0.0.0.0:40000` 上收发。

#### 装上 tailscale 后阿里云控制台的「远程连接」失效

2026-10-29 实测踩到。tailscale 默认 `--netfilter-mode=on`，会在 `INPUT` 头部挂 `ts-input` 链，
其中一条是

```
ip saddr 100.64.0.0/10 iifname != "tailscale0" drop
```

阿里云的元数据（`100.100.100.200`）、内网 DNS（`100.100.2.136` / `100.100.2.138`）、云助手 agent
全在 `100.100.0.0/16`，正好落在 `100.64.0.0/10` ��个 CGNAT 段里。于是它们的回包被当成“伪造的
tailnet 源地址”丢掉：云助手掉线 → 控制台远程连接不可用。

迷惑之处在于**只有内部服务受影响**：公网 SSH 照旧、出网 HTTP 照旧、DNS 因 systemd-resolved
缓存命中也看不出问题。定位靠两个数字，不需要 tcpdump：

```sh
curl -s --max-time 5 -w ' [%{http_code}]\n' http://100.100.100.200/latest/meta-data/instance-id
# 装之前 200；装之后 000
sudo nft list chain ip filter ts-input | grep drop
# counter 在持续上涨
```

修复是把这个自动管理关掉：

```sh
sudo tailscale set --netfilter-mode=off
# Warning: netfilter=off; configure iptables yourself.
```

规则立即移除，元数据恢复 `[200]`，`iptables -S` 回到只剩默认策略。代价是 tailscale 不再替这台
机器管防火墙：伪造源地址的入向包不再被丢，但它们要进 `tailscale0` 仍得通过 WireGuard 解密，
公网暴露面由云安全组兑底。想保留其余规则的话，另一种写法是保持 `on` 并在 `INPUT` 顶部插一条
`-s 100.100.0.0/16 -j ACCEPT` 加 `netfilter-persistent` 持久化——多一套机制，收益不大。

配套两件事：

1. **安全组**放行入向 `UDP 40000`。没放行时包到不了 `eth0`——可以不用 tcpdump，比对
   `/proc/net/snmp` 里 `Udp: InDatagrams` 的计数即可：发包前后不涨就是没通。
2. **ACL grant**（`grants` 数组，`src` 必须含发起方，否则分配不到 relay binding）：

```json
{
  "src": ["100.125.255.124/32", "100.121.5.100/32", "100.79.18.17/32",
          "100.65.139.110/32", "100.100.231.1/32", "100.77.166.83/32"],
  "dst": ["100.87.214.67/32"],
  "app": { "tailscale.com/cap/relay": [] }
}
```

**`src` 不能写裸主机名**。写成 `"src": ["macbook-m3"]` 会被拒：
`Error: src="macbook-m3": invalid address`——ACL 里用名字引用设备必须先在顶层 `hosts` 里
定义别名，否则只认 IP/CIDR、`tag:`、`autogroup:`。

### 结果（2026-10-29）

改完后 `tailscale status` 里四台原本走 DERP 的节点全部切成 peer relay：

```
archlinux-macbook  active; peer-relay 47.112.x.x:40000:vni:1
mac-mini-m4        active; peer-relay 47.112.x.x:40000:vni:2
archlinux-macmini  active; peer-relay 47.112.x.x:40000:vni:3
jwu-home-win11     active; peer-relay 47.112.x.x:40000:vni:4
```

`tailscale ping` 从 0.75–3.0s 降到 **52–76ms**（mac-mini-m4 60–76ms、archlinux-macmini
53–57ms、jwu-home-win11 52–57ms）。`archlinux-com` 依旧直连，不受影响。

### 排查时别被 `Hostinfo.PeerRelay` 骗了

实测踩到：relay 已经生效、`tailscaled` 日志里已经在 `allocated endpoint vni=…`，但
`tailscale debug netmap` 里 `SelfNode.Hostinfo.PeerRelay` 与对端看到的这个字段**都是空的**，
`CollectServices` 也一直是 `false`。两者都不代表失败——判断标准只看 `tailscale status` 的连接
类型和 `tailscale ping` 的 `via peer-relay`。

真正能证明 relay server 在干活的是它自己的日志：

```sh
sudo journalctl -u tailscaled | grep relayserver
# relayserver: listening on udp4:40000 sockets=2
# relayserver: allocated endpoint vni=1 lamportID=1 disco[0]=d:… disco[1]=d:…
```

其中的 `disco[1]` 就是发起方节点的 disco key。

代价与回滚：中继流量走 ECS 出网，按流量计费，且受它的带宽上限约束——SSH / Herdr 这种交互
流量没问题，成 GB 的文件传输会既慢又贵。回滚只要 `sudo tailscale set --relay-server-port=""`
并删掉那条 grant。

### 如果 peer relay 不生效：自建 derper 的额外代价

先说明它不是更好的方案，只是 peer relay 走不通时的备选：

- **非 443 端口会降级成 HTTP**。`derper` 的 `-a` 说明写着「Serves HTTPS if the port is 443
  and/or -certmode is manual」——想用 8443 绕开备案，就必须自己提供证书并走
  `--certmode=manual --certdir=<dir>`，证书文件名是 `<hostname>.crt` / `<hostname>.key`。
- **证书**：`--certmode=letsencrypt` 要 ACME 能访问 80 端口，大陆 ECS 对未备案域名会拦；
  所以现实路径是 DNS-01 签好再喂给 manual 模式。
- **没有官方二进制**，只能 `go install tailscale.com/cmd/derper@<tag>`；开
  `--verify-clients` 时 derper 与旁边 tailscaled 必须同一 revision，否则拒连。
- **不能反代、不能负载均衡**，DERP 在 TLS 内做协议切换；一个 region 放一个节点即可。
- 机房里这台是 1:1 NAT，derper 能工作（源地址不被改写），但必须绑 `0.0.0.0` 而不是公网 IP。

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
Host archlinux-com 100.121.5.100 10.30.40.x
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
