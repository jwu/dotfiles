# Ulanzi Vibe Key (AU05)

`fff1:00dd` 的手持宏键盘：旋钮 + 三颗机械键，顶部麦克风阵列。这台机器上把它当作
**voxtype 的听写按钮**：按住最上面的麦克风键说话，松开出文字。剩下两颗键与旋钮维持
设备固件里的原配置，不参与桌面映射。

## 设备形态与接口

```
┌─────────────┐
│  麦克风阵列   │
│   ○ 旋钮     │   左转 / 右转 / 按下
├─────────────┤
│   🎤 键1     │   语音键 —— 发 F9
│   ⟳ 键2     │   发 Enter
│   ✕ 键3     │   发 Esc
└─────────────┘
```

四个 USB 接口：

| 接口 | 类 | 用途 |
| --- | --- | --- |
| 0 / 1 | USB Audio 1.0 | 内置麦克风，48 kHz，`alsa_input.usb-AU05_*` |
| 2 | HID（键鼠） | 键盘 / 鼠标滚轮 / Consumer Control，除语音键外都走这里 |
| 3 | HID vendor（Report ID `0x55`） | 官方 Ulanzi Studio 写固件配置用；不定期发心跳 |

GitHub 上的 [`kubja/ulanzi-vibekey`](https://github.com/kubja/ulanzi-vibekey) 逆向了这套
协议，`docs/hardware_protocol.md` 是主要参考。本仓库的做法与它不同：它自己当驱动重新做
语音输入，这里只复用 voxtype。

## 原始报文实测

用 `sudo python3` 直接读 `/dev/hidraw4`（接口 2）与 `hidraw5`（接口 3），记录如下。

**按键（Report ID `0x03`，标准 HID 键盘报文）**

| 报文 | keycode | 物理键 |
| --- | --- | --- |
| `03 00 00 42` | `0x42` = F9 | 🎤 语音键 |
| `03 00 00 28` | `0x28` = Enter | ⟳ 键、旋钮按下 |
| `03 00 00 29` | `0x29` = Esc | ✕ 键 |
| `03 00 00 00` | —— | 全部释放 |

**旋钮（Report ID `0x02`，按鼠标滚轮上报）**

| 报文 | 含义 |
| --- | --- |
| `02 00 00 00 01 00` | 右转（wheel +1） |
| `02 00 00 00 ff 00` | 左转（wheel −1） |

旋钮**按下**不走这条路：固件把它映射成 Enter，报文与 ⟳ 键逐字节相同。

**vendor 通道（Report ID `0x55`）**：只有约 10 秒一次的心跳，没有按键事件。

### 旋钮按下和 ⟳ 键在 HID 层面不可区分

实测两次按下，报文一模一样：

```
⟳ 键      03 00 00 28 00 00 00 00 00
旋钮按下  03 00 00 28 00 00 00 00 00
```

`0x28` 是**键盘** Report（`0x03`）里的 Enter，不是鼠标 Report（`0x02`）的按钮位，说明固件把
旋钮按下直接映射成了一个 Enter 按键。没有任何字段能区分这两颗，所以 Linux 侧无法把它们映射
到不同动作。

要区分只有固件一条路：在 Ulanzi Studio 里改掉其中之一。更一般地，**若打算让 AU05 承担键位
映射（而不只是语音键），先把这些键改成不常用的 keycode**（例如 F13–F24）——发 Enter / Esc
时既没法与主键盘区分，也没法与另一个物理控件区分，任何按设备的映射都会互相打架。

### 语音键不是被丢弃的 `0x01`

上游文档说语音键发 keycode `0x01`（HID 规范里的 ErrorRollOver，内核故意丢弃），因此必须
绕开 evdev、直接读 raw HID。**本机实测不是这样**：语音键发的是干净的 `0x42`（F9），走
标准键盘通道。原因是这台设备的按键映射由 Ulanzi Studio 写进固件，语音键已经被改成了
F9 —— 用户当初就是为了让 voxtype 能用它触发才这么设的。

所以本仓库不需要 raw HID 驱动，voxtype 自己的 evdev 监听器就能接住。**但换一台没有配过
固件的 AU05 时不一定成立**：出厂状态下语音键很可能就是 `0x01`。判据很简单，按一次语音
键、看 `/dev/hidraw4` 上有没有 `03 00 00 01 …`。

## 为什么必须 keepalive

固件在主机空闲约 4 秒后会重启 USB 收发器。实测（`dmesg`）：

```
usb 1-6: USB disconnect, device number 29
usb 1-6: new full-speed USB device number 30 using xhci_hcd
```

插着不管时，`/dev/input/event*` 编号不断变化、`hidraw` 节点反复重建、USB 麦克风跟着
消失又出现。对一个"按住说话"的按钮来说，按键正好落在重连窗口里就丢了。

**修法是让一个进程持有它的 HID 接口**，不写任何 USB 命令。实测打开 `hidraw4` +
`hidraw5` 后，107 秒内零断连（`keepalive` 一退出，4 秒循环立刻回来）。

`scripts/ulanzi-au05-keepalive.c` 就做这一件事：按 sysfs 的 `uevent` 找到两个接口
（按 `0000fff1:000000dd` 匹配，不绑序列号），持有并读掉数据；设备不在或重枚举时每秒重试。
它只读、不 grab，所以按键和旋钮照常到达焦点应用。手法来自 `kubja/ulanzi-vibekey`。

## 权限：uaccess

voxtype 要读 `/dev/input/event*`，keepalive 要读 `/dev/hidraw*`，两者都以普通用户身份跑。
`scripts/71-ulanzi-au05.rules` 给这两个子系统加 `uaccess`（仅登录会话有效），按 USB id
匹配而不是名字 —— AU05 在 sysfs 里的名字 `AU05 AU05 Keyboard` 和别的键盘的通用名一样靠
不住。`bootstrap/arch.sh` 的 `install_ulanzi_au05_udev` 负责安装，uaccess 在设备重枚举后
依然有效。

## 麦克风优先级

AU05 是手持设备，插着时比笔记本内置麦更合适，所以：

| 源 | `priority.session` | 由谁设 |
| --- | --- | --- |
| AU05 内置麦 | 2300 | `51-ulanzi-au05-priority.conf` |
| 内建声卡 | 2200 | `50-bluetooth-loopback-priority.conf` |
| 蓝牙（含 A2DP 假麦克风 loopback） | 2010 | WirePlumber 硬编码 |

voxtype 用 `device = "default"` 跟随默认源，所以不需要把带序列号的设备名写进配置：插上
AU05 就自动用它，拔掉回落到内建麦。蓝牙排在最后（原因见 `docs/voxtype.md`
里"A2DP 的假麦克风"一节）。

两条规则分别写在两个 `.conf` 里：WirePlumber 加载 `wireplumber.conf.d/` 下的文件时，同名
数组键是**追加**的，实测重载后两个优先级同时生效。

## 落地

| 内容 | 位置 | 由谁部署 |
| --- | --- | --- |
| C 源码 | `scripts/ulanzi-au05-keepalive.c` | 仓库 |
| 二进制 | `~/.local/bin/ulanzi-au05-keepalive` | `run_onchange_after_90-ulanzi-au05.sh.tmpl` 用 gcc 编译 |
| user unit | `~/.config/systemd/user/ulanzi-au05-keepalive.service` | chezmoi（`dot_config/systemd/user/`） |
| udev 规则 | `/etc/udev/rules.d/71-ulanzi-au05.rules` | `bootstrap/arch.sh` 的 `install_ulanzi_au05_udev` |
| 麦克风优先级 | `~/.config/wireplumber/wireplumber.conf.d/51-*.conf` | chezmoi |

## 排查

```bash
systemctl --user status ulanzi-au05-keepalive     # 服务是否在跑
journalctl --user -u ulanzi-au05-keepalive -f
sudo dmesg -T | rg "usb 1-6"                      # 应该看不到 disconnect 循环
getfacl /dev/hidraw4 /dev/input/event20           # 应有 user:<你>:rw-
pactl get-default-source                          # 插着 AU05 时应该是 alsa_input.usb-AU05_*
journalctl --user -u voxtype -f                   # 按语音键应出现 Recording → Transcribed
```

| 现象 | 通常是什么 |
| --- | --- |
| 设备仍每几秒断连 | keepalive 没跑，或 hidraw 没有 uaccess（`getfacl` 里没有你的用户） |
| 按语音键 voxtype 无反应 | udev 规则没装 / voxtype 没打开 `AU05 AU05 Keyboard`；`journalctl -u voxtype` 里看 `Opened keyboard` 与 `on N device(s)` |
| 语音键发的是 `03 00 00 01` 而不是 F9 | 这台设备没配过固件；需要在 Ulanzi Studio 里把它设成 F9，或改用 raw HID 驱动 |
| 录出来是静音 | 默认源漂到了蓝牙 loopback；`pactl get-default-source` 确认是 AU05 还是内建 |
