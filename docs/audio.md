# audio

MacBookPro14,2 的内置音频在主线内核下**不出声**，而所有"看起来正常"的信号都是真的正常。
这篇记录根因、验证判据、落地方式，以及它什么时候能拆掉。

## 硬件结构

| 部件 | 标识 |
| --- | --- |
| HDA controller | Intel Sunrise Point-LP HD Audio `[8086:9d71]` |
| codec | CS8409（Vendor `0x10138409`，Subsystem `0x106b3600`） |
| 放大器 | MAX98706（寄存器与 MAX98372 文档一致） |
| 子 codec | CS42L83 |

CS8409 自己不做事：它把进来的 HDA 流转成 TDM 数字流送给放大器，**真正的 D/A 由放大器做**。
全部的 I2C 编程与 TDM 设置都经 vendor node `0x47` 用 coef 读写完成
（上游 `snd_hda_macbookpro` 的 `NOTES.md` 有完整说明）。节点链是 `0x02 -> 0x24`、`0x03 -> 0x25`。

## 症状

扬声器没有任何声音，但下面这些**全部成立**：

- `/proc/asound/cards` 里有 `card 0 [PCH]`
- `dmesg` 的 `autoconfig for CS8409` 把 pin 全认对：
  `line_outs=2 (0x24/0x25) type:speaker`、`hp_outs=1 (0x2c)`、`Internal Mic=0x44`、`Mic=0x3c`
- 各输出 pin 的 `Pin-ctls: 0x40`（OUT）
- PipeWire 里有 sink，未静音，音量非零
- `speaker-test` 播放时 `wpctl` 显示 `output_FL/output_FR -> CS8409 Analog:playback_FL/FR [active]`

## 根因

主线 `snd-hda-codec-cs8409` 的 quirk 表**只含 Dell 机型**，没有 Apple 条目，
于是这台机器只走通用 `autoconfig`：pin 认对了，但没有任何代码去初始化放大器。

判据是模块里的 quirk 字符串，这是最省事的确认方式（注意 6.17 之后内核已把
cs8409 从 `sound/pci/hda/` 挪到 `sound/hda/codecs/cirrus/`）：

```bash
zstdcat /usr/lib/modules/$(uname -r)/kernel/sound/hda/codecs/cirrus/snd-hda-codec-cs8409.ko.zst \
  | strings | grep -iE 'apple|macbook|warlock|cyborg'
```

主线只会输出 `CS8409_WARLOCK*` / `CS8409_CYBORG`（全是 Dell）；打上补丁后才出现
`cs8409_apple`、`cs_8409_apple_init`、`cs42l83_apple_pcm_analog_playback` 等符号。

## 三个都成立也不代表会出声的信号

以下三条全是"假阳性"，曾据此误判为「内核已支持、无需补丁」：

1. `snd_hda_codec_cs8409` 模块存在且已加载；
2. `autoconfig` 把扬声器 / 耳机 / 麦克风 pin 全部认对；
3. 播放时 `output_FL` / `output_FR` 路由到 `CS8409 Analog:playback_*` 且状态 `[active]`。

它们只证明**数据流到了 codec**。放大器没被打开时，现象与"一切正常"完全一致。

## 落地方式

### 1. 用户态

```bash
sudo pacman -S --needed wireplumber pipewire-pulse pipewire-alsa alsa-utils
systemctl --user enable --now wireplumber.service pipewire-pulse.socket
```

`pipewire` 本体可能早已被其它包的依赖顺手装进来（这台机器是被 `xdg-desktop-portal` 拉的），
但只有本体时既没有 session manager 也没有 pulse 兼容 socket，`/run/user/<uid>/pulse/` 是空的，
应用照样发不出声。

### 2. DKMS 补丁

```bash
sudo pacman -S --needed dkms linux-headers
yay -S snd-hda-macbookpro-dkms-git
```

上游是 [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)。
6.17 的内核源码目录重构后作者已跟进：`dkms.conf` 的 `BUILT_MODULE_LOCATION` 指向
`build/hda/codecs/cirrus`，装卸脚本也会按内核版本自动分流到 `install.cirrus.driver.pre617.sh`。

### 3. 重启

驱动已在内存里，无法热替换，必须重启才能加载补丁模块。

**先重启再装**：运行中的内核与 `/usr/lib/modules/` 里的目录可能不一致（pacman 升级内核时会删掉旧
目录），此时 DKMS 无法给运行中的内核编译，`dkms install` 只会针对已安装的那个内核版本。

## 生效与验证

```bash
dkms status                        # snd-hda-macbookpro/..., <内核版本>, x86_64: installed
modinfo -n snd_hda_codec_cs8409    # 应指向 /usr/lib/modules/<ver>/updates/dkms/...ko.zst
journalctl -k | grep -i cs8409     # 应有 "Primary cs8409" 与 "Primary patch_cs8409 NOT FOUND trying APPLE"
lsmod | grep cs8409                # 模块体积从约 45K 涨到约 192K
speaker-test -t sine -f 440 -l 1 -p 2
```

`loading out-of-tree module taints kernel` 是 DKMS 模块的正常提示，不是故障。

## 维护与已知限制

- **DKMS 是长期负债**：每次内核升级都会自动重编译。若升级后突然没声音，先查 `dkms status`——
  大概率是补丁对新内核编译失败，静默回落到了主线无声模块。
- **睡眠 / 恢复**：上游 `NOTES.md` 明确写 *"Power down/sleep completely unknown and untested"*。
  合盖唤醒后音频失效属于补丁限制，不是配置错误。
- **耳机**：插拔走 unsolicited response 实现，作者建议插上后等几秒再播放。
- **麦克风**：默认构建不带 `INTERNAL_MIKE_ONLY`；带麦耳机的组合已知有兼容问题。
- **SPDIF**：未实现。

## 什么时候拆掉

上游主线 cs8409 加上 Apple 的 subsystem id（如 `0x106b3600`）之后：

```bash
sudo pacman -R snd-hda-macbookpro-dkms-git
sudo dkms remove snd-hda-macbookpro/0.1 -k $(uname -r)
```

判据与上面相同：模块的 quirk 字符串里出现 `apple`，即可换回主线。
