# 串流

Mac mini 是无头机器：唯一的输出是 `HDMI-A-3` 上那块 3.5 寸 480x320 小屏（EDID 里声明
支持 1920x1080，由屏自己缩放）。要远程看到 niri 桌面**并且听到声音**，用
**Sunshine（服务端）+ Moonlight（客户端）**。

这份文档记的是「为什么选它」和「踩到的坑」；操作细节在各文件的注释里。

## 选型

### niri 实际支持什么

远程方案的能力边界由合成器实现了哪些协议决定。niri 26.04 的二进制里能捞到这些
（`strings /usr/bin/niri | grep -oE '(zwlr|zwp|ext|zxdg)_[a-z_]+_v[0-9]+'`）：

| 协议 | niri | 用途 |
| --- | --- | --- |
| `zwlr_screencopy_manager_v1` | ✅ | 抓屏（grim、wayvnc、Sunshine 都走它） |
| `zwlr_virtual_pointer_manager_v1` | ✅ | 注入鼠标 |
| `zwp_virtual_keyboard_manager_v1` | ✅ | 注入键盘 |
| `zwlr_output_manager_v1` | ✅ | 运行时改输出配置 |
| `zwlr_export_dmabuf_manager_v1` | ❌ | —— |
| `ext_image_copy_capture_manager_v1` | ❌ | —— |

### 排除掉的方案

- **Wayland portal 路线（RustDesk 之类）**：需要 `xdg-desktop-portal` 的 ScreenCast /
  RemoteDesktop 后端，这台机器只有 `xdg-desktop-portal-gtk`，两者都不提供；niri 也没有
  libei（输入注入的另一条路）。排除。
- **RDP（gnome-remote-desktop）**：绑定 gnome-shell，与 niri 无关。排除。
- **wayvnc**：**可行**（正是靠上表前三行），实测抓屏、RFB 握手、`grim` 截图链路全通；
  期间还借它验证了虚拟键盘能穿透 `hyprlock` 的 `ext-session-lock`。排除它的原因是
  **没有音频**，且这台机器只有 2 核，wayvnc 只有软件 x264，1080p 软编会吃满 CPU。
  包还在机器上，留作备选。
- **niri 的 headless 虚拟输出**：本来想再加一块专供远程的虚拟屏，**做不到**。headless
  后端（`src/backend/headless.rs`）的源码注释写明是 *"test"* 用途、*"missing some
  crucial parts like dmabufs"*；而且后端在启动时三选一（`Tty` / `Winit` / `Headless`），
  运行中无法新增输出，也没有 `--headless` 开关。排除。
- **vkms**（`modprobe vkms` 造一块真虚拟 DRM 输出）：技术上可行，但那是软件帧缓冲，
  niri 每帧要 CPU 拷贝十几 MB，在 2 核上会直接吃掉编码算力。排除。

### Sunshine 走的是 screencopy

Sunshine 在 Linux 有 4 条抓屏路径（`kms` / `wlr` / `x11` / `portal`）。它的 `wlr` 分支
名字容易误导：用的是 `zwlr_screencopy_manager_v1`，**不是**
`zwlr_export_dmabuf_manager_v1`。日志里能直接看到：

```
Info: Screencasting with Wayland's protocol
Info: [wayland] Found interface: zwlr_screencopy_manager_v1(32) version 3
Info: [wayland] Found interface: zwp_linux_dmabuf_v1(42) version 5
Info: Found H.264 encoder: h264_vaapi [vaapi]
```

所以它不需要 KMS 提权、不需要 portal。日志里那串 `Failed to gain CAP_SYS_ADMIN` 是 KMS
分支的噪音，Sunshine 自己标了 *"Ignore any errors mentioned above, they are not
relevant."*。

编码走 VAAPI 的 **i965** 驱动（Ivy Bridge 不支持 iHD）。HEVC / AV1 在这代硬件上都没有
可用 profile，会打印 `No usable encoding profile found` 后回退 H.264 —— 所以
**Moonlight 里的编解码器要设成 H.264**。

## 坑：prep-cmd 的 undo 不会触发

Sunshine 允许每个应用带 `prep-cmd`（`do` / `undo`），串流开始改分辨率、结束改回来。
`do` 正常执行，但 **`undo` 不会**：

```
[11:53:01] Info: Executing Do Cmd: [niri-stream-res up high]
[11:53:01] Info: CLIENT CONNECTED
[11:55:47] Info: CLIENT DISCONNECTED      ← 之后没有任何 Undo
```

根因在 `src/process.cpp`：`undo` 的循环写在 `terminate_process_group(...)` **之后**，
只有应用进程被终止时才跑。而 Sunshine 在客户端断开后**故意让应用活着**（为了 Moonlight
能重连），所以对「桌面串流」这种没有 `cmd` 的应用，`undo` 永远不会执行，屏幕就停在
串流分辨率上。

### 解法：看门狗

不依赖 Sunshine 的 `undo`。`up` 时额外起一个脱离进程组的看门狗，盯 Sunshine 自己的
日志（`CLIENT CONNECTED` / `CLIENT DISCONNECTED` 计数），判断本次会话已结束后还原分辨率。

日志比其他信号可靠：它记的是 Sunshine 自己的判断，客户端正常退出还是掉线都一样。

## 两种连接方式

Moonlight 里两个应用，对应两种分辨率：

| 应用 | prep-cmd | 行为 |
| --- | --- | --- |
| `Desktop` | `niri-stream-res up high` | 切到客户端请求的分辨率；面板没有该模式时用最大的模式 |
| `Low Res Desktop` | `niri-stream-res up native` | 切回输出的 preferred mode（480x320） |

小屏会话零开销（不切分辨率、不起看门狗）；大屏会话按需切换、断开后自动还原。

## 脚本：niri-stream-res

`dot_local/bin/executable_niri-stream-res` 配 `dot_config/sunshine/apps.json`。
脚本里**没有任何机器特定值** —— 输出、模式、兜底全部运行时决定，所以一份副本在多台
Linux 上通用。这一点和 `niri-lock` 不同：那个必须按 `.chezmoi.hostname` 分岔（熄屏
策略是机器属性），这里没有这种属性可依赖，硬编码反而会限制它。

- **输出**：`NIRI_STREAM_OUTPUT` 优先；否则恰好一块输出就用它；多块则跟随焦点输出
  （`niri msg focused-output`）。
- **还原点**：`up` 时先读**当前实际模式**存进 `$XDG_RUNTIME_DIR`，还原时读它 —— 比写死
  一个预期值准，也比写死较真。没有记录时退回输出的 preferred mode。
- **客户端分辨率**：从 `niri msg outputs` 的可用模式里精确匹配；匹配不到就用最大模式。
- **看门狗**：
  - 基线在 `up` **最开头**读取。Sunshine 可能在脚本切分辨率的间隙就写下
    `CLIENT CONNECTED`，晚读会把这次连接算进基线，导致永远不还原。
  - 重连会重置空闲计时器（`grace` 秒内没有新连接才还原）。
  - 日志轮转或 Sunshine 重启时重新取基线，避免增量变负后读错状态。
  - `down` 真被调用时先杀掉看门狗，不会重复还原。

可调：`NIRI_STREAM_GRACE`（默认 8s）、`NIRI_STREAM_POLL`（默认 4s）、
`NIRI_STREAM_FALLBACK_MODE`。

## 部署

- **入库**：`executable_niri-stream-res`、`dot_config/sunshine/apps.json`。
  `.local` 整个子树本来就是 Linux-only，脚本不用额外排除；`.config/sunshine` 需要加进
  `.chezmoiignore` 的 Linux-only 段。
- **不入库**：`sunshine_state.json`（配对状态）、`credentials/`（Web UI 凭据）、
  `sunshine.log`、`apps.json.bak.*`。前两个是机器特定的运行状态。
- **包与权限**由 AUR 的 `sunshine-bin` 负责：`.install` 自动
  `setcap cap_sys_admin,cap_sys_nice+p /usr/bin/sunshine`，并放 udev 规则把
  `/dev/uinput`、`/dev/uhid` 放宽给 `input` 组 + `uaccess`。**不需要手工加组**。
- **avahi** 提供 mDNS 发现（`_nvstream._tcp`）；`avahi-daemon.service` 与 `.socket` 都
  enable 了（`sunshine` 自己的 systemd 用户单元保持 disabled，按需手动起）。

## 运维

```bash
systemctl --user start app-dev.lizardbyte.app.Sunshine.service   # 手动起，未 enable
systemctl --user stop  app-dev.lizardbyte.app.Sunshine.service
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service -f

niri-stream-res status                    # 输出 / 当前模式 / preferred / 记录值 / 看门狗
tail -20 ~/.cache/niri-stream-res.log     # 看门狗自己的判断过程

niri msg output <output> mode <mode>      # 卡住时手动救回
```

Web UI 在 `https://<host>:47990`，首次用 `sunshine --creds <user> <pass>` 设凭据。
提交配对 PIN 时需要 `pairing_id` 和 `name` 两个字段（`GET /api/pin` 拿），只给 `pin`
会被 `400` 拒掉。
