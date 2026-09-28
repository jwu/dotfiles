# 休眠与唤醒（MacBookPro14,2）

这台机器**合盖必死**：锁屏后合盖，翻开是全黑无背光、机器像没醒，只能长按电源。
根因是 2016–2017 带 T1 芯片的 MacBook Pro 的 Alpine Ridge Thunderbolt 3 控制器
把机器从 S3 里反复拽出来。修复落在 `bootstrap/arch.sh` 的一个 step 上，实体是
`scripts/apple-macbook-suspend-fix.sh`（DMI 门控、幂等）与它部署的
`/usr/local/bin/apple-alpine-ridge-wakeup`。

## 症状与现场

- 设备：`MacBookPro14,2`（2017 13"，Kaby Lake，Iris Plus 650，**T1**，无 T2）。
  `lspci` 里有两组 Alpine Ridge：NHI `8086:15d2`、xHCI `8086:15d4`、桥 `8086:15d3`。
- 日志：全局只有**一次** `PM: suspend entry (deep)`（2026-09-28T00:32:48），此后没有
  任何 `PM: resume` / `System resumed`，66 秒后就是新的 boot —— 也就是强重启。
  `journalctl -b` 的历史里每次「翻开后打不开」都终结在 suspend entry 那一行。
- 平时不总是发作，是因为外屏在线时 logind 按 docked 走
  `HandleLidSwitchDocked=ignore`（编译默认，`/etc/systemd/logind.conf` 全被注释掉），
  合盖根本不进 S3，只剩 niri 自己 `disconnecting connector: "eDP-1"`。
  `card1-DP-2/status` 为 `connected` 时合盖是安全的，拔掉外屏才会踩到。
- ACPI 报 `(supports S0 S3 S4 S5)`，`/sys/power/mem_sleep` 是 `s2idle [deep]`。

## 根因

Alpine Ridge 的 NHI/xHCI **每 ~45 秒发一次 PME**，把机器从 deep S3 唤醒；logind 看到
盖子仍然关闭，于是再 suspend 一次。这个循环可以跑几小时，机身持续发热，直到
Thunderbolt 的 resume 路径彻底挂死：

```text
tb_cfg_read/write: -108
pcieport ... Unable to change power state from D3cold to D0
not ready 1023ms after resume; giving up
```

之后翻开盖子无任何反应。同型号、同内核大版本的完整记录见
[omacom/omarchy#12194][issue-12194]；本机 `/proc/acpi/wakeup` 与它的复现步骤逐条对上：

```console
$ cat /proc/acpi/wakeup
RP05  S3  *enabled   pci:0000:00:1c.4     # TB root port
RP09  S3  *enabled   pci:0000:00:1d.0     # TB root port
XHC2  S3  *enabled   pci:0000:06:00.0     # TB xHCI
XHC3  S3  *enabled   pci:0000:7c:00.0     # TB xHCI
RP12  S3  *enabled   pci:0000:00:1d.3     # Wi-Fi PME
SPIT  S3  *enabled   spi:spi-APP000D:00   # 必须保留
LID0  S4  *enabled   platform:PNP0C0D:00  # 必须保留
$ cat /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed
1                                          # NVMe 那半也没做
```

## 修复

三段，全部幂等，照 [PR #12211][pr-12211] 的做法（那边是 Limine，这里是 GRUB）：

1. **关掉唤醒源**，只关 `RP05 RP09 XHC2 XHC3 RP12`。`LID0` 与 `SPIT`（Apple SPI
   键盘/触控板）必须留着，否则盖子和键盘都唤不醒机器。
   - ACPI 侧写 `/proc/acpi/wakeup`（写节点名就是 toggle），**每次开机都会 reset**，
     所以由 `apple-alpine-ridge-wakeup.service` 这个 oneshot 在 boot 时重放。
   - PCI 侧 `8086:15d2` / `8086:15d4` 的 `power/wakeup=disabled`：udev 规则管开机与
     热插拔，helper 直接写 sysfs 让当前这次也立刻生效（不用 `udevadm trigger` 整条
     PCI 总线重放 add 事件）。
2. **`pcie_port_pm=off`**：Alpine Ridge 端口从 D3 回不来，每个端口要各等 ~1s，多个端口
   串起来就是黑屏几十秒。写进 `/etc/default/grub` 的 `GRUB_CMDLINE_LINUX_DEFAULT` 后
   `grub-mkconfig`，**这一段要重启才生效**。
3. **NVMe `d3cold_allowed=0`**：Apple NVMe 是另一个 resume 会掉总线的设备，Omarchy 对
   同一批型号也是这么做的（`fix-suspend-nvme.sh`）。

Omarchy 的 20 秒 lid-suspend 延迟（S3 resume ~7s，快速合盖再打开会睡在盖子已开的
状态）没有搬过来，见下面「遗留」。

## 实测（2026-09-29）：挂死修好了，自动唤醒没修好

八次手动挂起（`systemctl suspend` / `rtcwake -m mem`）实测：

- **不再挂死**：8/8 都正常 resume 回锁屏。对照修复前「66 秒后就是一次新 boot」，
  `pcie_port_pm=off` 这一半有效。
- **仍然自动醒**：每次都睡 **45–48 秒**被唤醒，八次高度一致（48/48/45/45/47/46/45/46）。

### `_L32` / `_L33`：`/proc/acpi/wakeup` 之外的第二条 TB 通路

`/proc/acpi/wakeup` 里 `RP05` / `RP09` 的 `_PRW` 返回 `0x69`，禁掉它对 TB 的 PME 没用，
因为 Apple 的 SSDT 给同一个根端口**另开了一条 level-triggered GPE**：

```text
SSDT5: Scope (\_SB.PCI0.RP05) { Scope (\_GPE) { Method (_L32, ...) { ... \_SB.PCI0.RP05.UPSB.AMPE () } } }
SSDT5: Scope (\_SB.PCI0.RP09) { Scope (\_GPE) { Method (_L33, ...) { ... \_SB.PCI0.RP09.UPSB.AMPE () } } }
```

- GPE `0x32` = `RP05`（`pci:0000:00:1c.4`），GPE `0x33` = `RP09`（`pci:0000:00:1d.0`）
- GPE `0x17` = `SPIT`（apple-spi-topcase，内置键盘/触控板；`_L17` 只做 `Notify`）
- GPE `0x69` = 这些 `_PRW` 的通用 wake 号，**不是** TB 事件实际走的那条

`/proc/acpi/wakeup` 只反映 `_PRW`，看不见 `_L32` / `_L33`，所以上面 1 号修复从原理上
就够不着它。

### 但它也不是唤醒源：唤醒完全不经过 ACPI

`suspend` 前后逐项对比 `/sys/firmware/acpi/interrupts/*`：

| 做的改动 | 结果 |
| --- | --- |
| 只 mask `gpe32` / `gpe33` | 仍 48 秒醒 |
| **128 个 GPE 全部 mask** | 仍 46 秒醒，且 `sci` / `gpe_all` / `ff_pwr_btn` / `ff_rt_clk` 增量**全为 0** |
| 断网（消掉 NetworkManager 的 45s DHCP 事务） | 仍 46 秒醒 |
| unbind `thunderbolt`（`05:00.0` / `7b:00.0`） | 仍 48 秒醒 |
| `d3cold_allowed=0`（TB 设备 + 根端口，重启后重测） | 仍 46 秒醒 |

**机器被唤醒，却没有产生任何 ACPI 事件。** 这条路径是纯硬件的 PCIe Native PME 一类，
`/proc/acpi/wakeup`、GPE mask、驱动 unbind 都拦不住，`acpi_mask_gpe=` 内核参数同理
（已确认该参数存在于本内核：`vmlinuz` 解压后有 `acpi_mask_gpe=`），不必再试。

未 mask 时挂起前后的增量是 `gpe07 +148` / `sci +149`，那是 **resume 之后 EC 的正常活动**，
不是唤醒源——全 mask 时它变成 0，机器照样醒。

### 顺带的副作用（都是未修的状态）

- **外接屏（USB-C DP-alt）在 resume 后会失效**：`card1-DP-2` 变 `disconnected`，USB 上多一个
  `1-7: USB 2.0 BILLBOARD [2109:0103]`（DP-alt 协商失败的告示设备），
  `card1-DP-2/waiting_for_supplier` 非空（DRM device-link 在等 TB 控制器）。
  日志停在 `tb_cfg_read: -108` → `tb_dp_port_is_enabled` → `tb_tunnel_discover_dp`。
  **软件恢复不了**：重载 `thunderbolt` 模块、`pci rescan`、`force`（本内核 i915 没这个节点）
  都无效，只能**拔插 USB-C 线**或重启。
- 每次 resume 后 `0000:06:00.0` / `0000:7c:00.0`（TB xHCI）从总线消失，NHI 变成
  `Unknown header type 7f`（`lspci` 读不到配置空间），即 `Unable to change power state
  from D3cold to D0` 的同一件事。
- 手工 unbind NHI 之后 `bind` 回不来（`Invalid argument`），重载 `thunderbolt` 模块与
  `pci rescan` 都无效，**只能重启**。别再拿 unbind 当 sleep hook 用。

## 明确不要做的事

- **不要切 `s2idle`**。deep S3 在这套固件上是工作的；s2idle 是发热路径，
  [omacom/omarchy#12194][issue-12194] 说得直白，而
  [discussions#7920][disc-7920] 给 `MacBookPro13,1` 的「confirmed fix」恰恰是
  `mem_sleep_default=s2idle`。**两台机器的结论相反**，不要跨型号抄。本机保持 deep。
- **不要 `pm_async=0`**。它在某些 T2 机器上正确，在这里会把 D3 超时串行化成约 60 秒
  黑屏。
- **不要 blacklist `thunderbolt`**。能停掉 `tb_cfg_*` 的 WARN 刷屏，但 USB-C dock 与
  DP-alt 一起废掉；USB-C 充电不受影响，所以很容易误判为「没坏」。
- **不要靠关掉 lid suspend 绕过去**。`HandleLidSwitch=ignore` 能止血（合盖只关内屏），
  但代价是永远不能省电，且照样要面对「手动 suspend 会死」。修根因之后合盖是真正可用的。

## 落点

| 文件 | 作用 |
| --- | --- |
| `scripts/apple-macbook-suspend-fix.sh` | root 安装器：DMI 判 `MacBookPro13,[123]` / `MacBookPro14,[123]`，装 udev 规则与 service，改 GRUB 参数 |
| `scripts/apple-alpine-ridge-wakeup.sh` | 部署到 `/usr/local/bin/apple-alpine-ridge-wakeup`，boot oneshot 的实际动作 |
| `bootstrap/arch.sh` | `install_apple_suspend_fix` step：sudo 调用安装器 |

非 MacBook 的机器上安装器直接 `exit 0`（DMI 不匹配），所以 mac mini 跑同一份
bootstrap 不会受影响。

已经接入对账的机器不需要重跑 bootstrap，手工执行同一条命令即可：

```bash
sudo ~/bin/dotfiles/scripts/apple-macbook-suspend-fix.sh
```

## 验收

1. 安装后立刻可查（不用重启）：
   ```bash
   awk '/^(RP05|RP09|XHC2|XHC3|RP12|LID0|SPIT)[[:space:]]/ { print $1, $3 }' /proc/acpi/wakeup
   # 前五个变成 *disabled，LID0 / SPIT 仍是 *enabled
   for p in /sys/bus/pci/devices/*; do
     case "$(cat "$p/device" 2> /dev/null)" in
       0x15d2 | 0x15d4) echo "$p $(cat "$p/power/wakeup")" ;;
     esac
   done   # 两个都应是 disabled
   cat /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed                 # 0
   ```
2. 重启后 `cat /proc/cmdline` 里出现 `pcie_port_pm=off`。
3. 拔掉外屏（否则 docked 判定会让你测不到 suspend），锁屏，合盖放置十几分钟：
   ```bash
   journalctl -b | grep -E 'Lid |PM: suspend entry|PM: suspend exit|Waking up'
   ```
   判据是**只有一次** `PM: suspend entry (deep)`，期间没有 `Waking up`，机器摸起来是凉的；
   翻开盖子后日志出现 `Lid opened.` 与 `PM: suspend exit`，回到锁屏。

   **这条截至 2026-09-29 未通过**：挂起确实不再挂死，但 45–48 秒后必定自动醒一次（见上）。
   1 / 2 两条现在是过的，第 3 条不是。测试时务必人别碰机器，否则分不清是人为唤醒还是自动唤醒。

## 遗留

- **45 秒硬件唤醒没有解决**，而且已经排除掉所有软件手段（GPE mask、`_PRW`、驱动 unbind、
  `d3cold_allowed=0`、`acpi_mask_gpe=`）。剩下没试的方向，按可能性排：
  1. sleep hook 里 `remove` 根端口（`00:1c.4` / `00:1d.0`）：比 unbind 更彻底，但 unbind
     已经是不可恢复的，remove 大概同样要重启才收得回来，风险高。**未实验。**
  2. ACPI 表覆盖（往 initramfs 塞改过的 SSDT，删掉 `_L32` / `_L33`）：只在唤醒真走这两条
     GPE 时才有意义，而实测否定（全 mask 仍醒），**预计无用**。
- **外接屏在每次 suspend 后都要手动拔插 USB-C 线**才能回来（见上面「副作用」）。这一条比
  45 秒唤醒更影响日常使用，但目前没有不重启的恢复手段；如果要拿 suspend 当常规操作，
  得先解决 TB 在 S3 里掉电的问题。
- **没有搬 Omarchy 的 lid debounce**（[#12193][issue-12193] / [PR #12210][pr-12210]：
  logind 改 `HandleLidSwitch=ignore`，自己延迟 3 秒、确认盖子还关着且没有外屏再
  `systemctl suspend`）。本机若出现「2 秒内合盖再打开、面板黑着」再补；现在 logind
  还是默认 `suspend`。
- 同批机器的另外几个已知坑与本机可能相关，但都没动：
  BCM4350 Wi-Fi 的 suspend 失败（omarchy#7180、#12314）、T1 Touch Bar 显示子设备
  resume 后不亮（omarchy#7950）、`Fix Thunderbolt suspend on the MacBookPro14,1`
  （omarchy#10758）。

[issue-12194]: https://github.com/omacom/omarchy/issues/12194
[pr-12211]: https://github.com/omacom/omarchy/pull/12211
[issue-12193]: https://github.com/omacom/omarchy/issues/12193
[pr-12210]: https://github.com/omacom/omarchy/pull/12210
[disc-7920]: https://github.com/omacom/omarchy/discussions/7920
