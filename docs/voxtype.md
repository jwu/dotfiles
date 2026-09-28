# voxtype 语音输入

按住 F9 说话，松手后中/英文文本落到光标处。识别、分词、输出全在本机完成。

## 为什么是 voxtype

`omarchy` 用 `voxtype` + Hyprland 键位实现听写，那套配置可以直接参考，但**键位那部分
不能照搬**：niri 不支持按键释放事件（`niri validate` 会拒绝 `release` 属性），而
push-to-talk 依赖"松开即停"。

因此改用 voxtype 自己的 evdev 监听器（`[hotkey] enabled = true`）。它是旁路读取，
不吞按键——所以按下的键仍会传给焦点应用，这也是 F12 被换成 F9 的原因（F12 在浏览器
里是开发者工具，会跟着弹出来）。

## 引擎选择

装好当天用同一段音频横评了四个中文引擎：

| 引擎 | 中文（"欢迎大家来体验达摩院推出的语音识别模型"） | 英文（11s 的 jfk.wav） | 5.5s 音频耗时 | 体积 |
| --- | --- | --- | --- | --- |
| SenseVoice small | 打摩院 ❌ | fellow**mer** ❌ | 0.09s | 229 MB |
| **Paraformer-zh** | 达摩院 ✅ | `andsomyfellowamericans...`（无空格） | 0.09s | 233 MB |
| Dolphin base | 打磨院 ❌ | 乱码 | 0.06s | 100 MB |
| Cohere q4f16 | 达摩院 ✅ | 全对 ✅ | 0.93s | 1.5 GB |

横评结论：**Paraformer-zh**。中文最准，比 Cohere 快约 10 倍，常驻内存也小得多（Cohere 是
2.2 GB）。代价是它作为字符级模型，**英文输出不带词间空格**——由下面的过滤器解决；
中文则本来就不需要空格（但也没有标点）。当前配置使用 **Paraformer-zh**；英文输出由 `wordseg-rs` 补空格。


切换引擎（模型都在 `~/.local/share/voxtype/models/`，需要时手工下载）：

```bash
voxtype setup --download --model cohere-transcribe-q4f16
# 改 config.toml 的 engine 与对应段，然后：
systemctl --user restart voxtype
```

## 英文连写：wordseg-rs

voxtype 自身不提供英文分词，只提供 `[output.post_process]`：把识别结果经 stdin 喂给
一条命令，取 stdout 作为最终文本。

过滤器来自已归档的 `voice-input` 那套逻辑（`english_spacing.py` + vendored wordninja 2.0.0）：
只处理 **7 个以上连续 ASCII 字母**，用词频动态规划切成词，中文原样透传。为了去掉
Python 解释器与伴随文件，把它重写成 Rust（独立项目 wordseg-rs，已发布到 crates.io；词表在编译期由 `build.rs` 解压
烘焙进二进制，因此没有运行时依赖）。

与 Python 版逐字节对拍过，确保替换后切词结果不变：

| 样本 | 结果 |
| --- | --- |
| 手工样本（中英混说、数字、撇号、大小写、空串、短串） | 14/14 一致 |
| 随机拼词（从词表抽 2–7 个词拼接，300 条） | 300/300 一致 |

已知代价：词频分词不认识专有名词，`Kubernetes` 会被切成 `Ku berne tes`。这是算法固
有的，Python 版同样如此。

## 输出模式：为什么不是直接打字

最初的 `type` 模式（wtype 逐键模拟）会被 **fcitx5 拦截**：合成的按键被当成输入编码，
文本要再过一遍输入法才落下。

`paste` 模式改为整段文字经剪贴板 + 模拟粘贴键送出，输入法不参与。粘贴键取
**ctrl+shift+v**，因为主要使用场景是 ghostty 里的 TUI（终端认这个）；GUI 应用认
ctrl+v，两者不能同时满足，改 `paste_keys` 即可切换。`restore_clipboard = true`
让 voxtype 在粘贴后把原剪贴板内容还回去。

> 该问题在 voxtype 文档里对应 IBus/读入顺序的条目；这里遇到的虽是 fcitx5，解法相同。

## OSD 位置：为什么是右下角

1.1.0 起录音时会浮出一个波形 OSD，默认 `frontend = "gtk4"`。AUR 包只带 `gtk4` 与
`quickshell` 两个波形前端，`native` 没打进包——选它会打一条 warn 并悄悄回退到 gtk4。

**gtk4 的 `bottom-center` 不贴底**。`src/bin/voxtype_osd_gtk4.rs` 把 `bottom-center` 和
`top-center` 塞进同一个 `centered` 分支：

```rust
let centered = matches!(cfg.position, BottomCenter | TopCenter);
if centered {
    let monitor_height = focused_monitor_height_px().unwrap_or(1080);
    let top_px = (cfg.top_margin.clamp(0.0, 1.0) * monitor_height as f32) as i32;
    window.set_anchor(Edge::Top, true);
    window.set_margin(Edge::Top, top_px);   // margin_px 在这条路径上没人用
}
```

两个后果：

- OSD 停在 `top_margin × monitor_height` 处（默认 0.85），**与屏幕高度无关**——实测在
  eDP-1（逻辑 1600×1000）与 DP-2（2560×1440）上，波形都落在逻辑 y≈884–931。
- `focused_monitor_height_px()` 的名字骗人：它取的是 `display.monitors()` 里**第一个**非零
  高度的 monitor，不是焦点的那个。本机拿到 eDP-1 的逻辑高 1000；两次 `top_margin` 取值做
  回归，斜率 ≈ 976。

要在 DP-2 上贴底需要 `top_margin = (1440-48-24)/1000 = 1.37`，被 `clamp(0.0, 1.0)` 截断，
所以 `bottom-center` 在那块屏上**永远**到不了底部；两块屏高度不同，一个数值不可能同时满足。

`margin_px` 只在四个 corner 位置生效（那条分支是正常的 `anchor + margin_px`）。因此配置选
`bottom-right`：实测面板落在 DP-2 的 x 2136–2536 / y 1368–1416，正是「右下各留 24px」。
代价是水平居中没了；如果更想要「顶部居中且在两块屏上位置一致」，那要改用 `top-center` +
`top_margin ≈ 0.05`（waybar 逻辑高约 35，`0.05 × 1000 = 50` 正好在它下方）。

`native` frontend 的实现其实是对的（`BottomCenter => (Anchor::BOTTOM, 0, margin, 0, 0)`），
等它进包就能换回去。1.1.1-rc4 没有改 gtk4 这一段。

## 键盘权限：uaccess 而非 input 组

evdev 监听要读 `/dev/input/event*`。加进 `input` 组是最常见的做法，但那是**永久**授权；
`TAG+="uaccess"` 只对本地登录会话生效，权限面更小。规则文件按**设备名**匹配，所以换
键盘要改这个文件并重跑 bootstrap 的对应步骤。

规则里列了外接的 ROG OMNI RECEIVER / MOSART 两把键盘，以及 MacBook 内建的
`Apple SPI Keyboard`（`ATTRS{name}` 精确匹配，`ID_INPUT_KEYBOARD=1` 已确认）。最后这把
原先由已卸载的 voice-input 用 `setfacl -m u:<用户>` 授权，本仓库改用 `uaccess`，省掉
用户名硬编码。删掉那两条旧规则、只留本文件后重新 `trigger`，`getfacl /dev/input/event5`
仍有 `user:jwu:rw-`，说明 uaccess 确实接住了。

## voice-input 已卸载

听写最初由本地项目 `voice-input`（Python + FunASR）承担。逐条能力被 voxtype + wordseg-rs
取代后整个卸载：服务与 unit、`~/.local/bin` 下的脚本、`~/.local/share/voice-input`、
`~/.local/share/pi-voice-funasr`、`~/.cache/voice-input`、whisper 模型目录、
`~/dev/voice-input`，以及 `/etc/udev/rules.d/` 下它装的两条规则。腾出约 3.6 GB。

同批退役的还有 `pi-voice-input` / `pi-funasr-server` / `pi-whisper-server` 三个 user 服务
（F12 + FunASR / Whisper）。它们不在本仓库里，是手装的，删掉不影响 chezmoi 对账。

## 音频设备

用系统默认源（`device = "default"`）。

默认源由 `priority.session` 决定，候选有两个：

| 源 | `priority.session` | 说明 |
| --- | --- | --- |
| 内建声卡 `alsa_input.pci-*` | 2200 | 本仓库抬高（见下）；ALSA `Internal Mic` jack on，实测可录 |
| 蓝牙 `bluez_input.*` | 2010 | WirePlumber 硬编码；A2DP 播放时是**静音回环占位源**，不是麦克风 |

曾经为了绕开"默认源漂到离线蓝牙设备"，用 `~/.asoundrc` 固定到内建声卡——结果录到的是
没有麦克风的设备，只有静音。教训仍然成立：**先确认麦克风真实存在，再谈设备固定**。
（后来实测 `Internal Mic` 是好的；当年失败的是 `front-mic` / `rear-mic` 那两条 route。）

### 蓝牙 A2DP 的"假麦克风"会抢走默认源

WirePlumber 0.5 的 `bluetooth.autoswitch-to-headset-profile` 默认开启（"always show
microphone for Bluetooth headsets"）。**设备即使跑在 A2DP（无麦克风），它也会造一个
loopback 源**（`scripts/monitors/bluez/create-loopback-node.lua`），`priority.session`
硬编码 2010，刚好压过内建麦原始的 2009，于是成为默认源。

实测（K13 音箱连着）：

| 录 3 秒默认源 | 结果 |
| --- | --- |
| 蓝牙 loopback | peak 0，全零静音 |
| 内建声卡 | peak 32767，正常 |

voxtype 用 `device = "default"` 跟着默认源走，于是按 F9 只录到静音，日志出现
`Recording error: No audio was captured`，或把静音识别成"没有没有"。

修法：用 `monitor.alsa.rules` 把内建麦抬到 **2200**，压过蓝牙的 2010。**没有**关
`autoswitch-to-headset-profile`——蓝牙设备真的切到 HFP（有麦克风）时仍会暴露真实采集
源，应用显式选它时照样优先。规则见 `dot_config/wireplumber/`。

> 别用通用 `node.rules`：WirePlumber 0.5 已删掉这个顶层键，写了会被静默忽略；可用的是
> `monitor.alsa.rules` / `monitor.bluez.rules`。而 `monitor.bluez.rules` 走 `name-node`
> hook，管不到 `create-loopback-node.lua` 直接建的 loopback 节点，所以降权 loopback 走
> 不通，只能反过来抬内建麦。

## 文件与归属

| 内容 | 位置 | 由谁部署 |
| --- | --- | --- |
| voxtype 配置 | `~/.config/voxtype/config.toml` | chezmoi（`dot_config/voxtype/config.toml.tmpl`） |
| WirePlumber 默认源规则 | `~/.config/wireplumber/wireplumber.conf.d/50-bluetooth-loopback-priority.conf` | chezmoi（`dot_config/wireplumber/`） |
| 分词过滤器 | `~/.local/bin/wordseg-rs` | 独立项目（源码不在本机），已发布到 crates.io；`bootstrap/arch.sh` 用 `cargo install` 装 |
| 键盘 udev 规则 | `/etc/udev/rules.d/70-voxtype-uaccess.rules` | `bootstrap/arch.sh` 的 `install_voxtype_udev` |
| 程序本体 | `voxtype-bin`（AUR，当前 1.1.0） | `bootstrap/arch.sh`，必要时 `yay -S voxtype-bin` |
| 用户服务 | `~/.config/systemd/user/voxtype.service` | `voxtype setup systemd`（**不**由 chezmoi 管） |
| 模型 | `~/.local/share/voxtype/models/` | `voxtype setup --download --model <名字>` |

**注意**：`voxtype config set`、`voxtype setup systemd` 都会就地改文件。改了之后要么
手工同步回本仓库，要么重新 `chezmoi apply` 覆盖回来——配置以仓库为真源，unit 以
`setup systemd` 为真源。

## 排查

```bash
voxtype status                    # idle / recording / transcribing
journalctl --user -u voxtype -f   # 实时日志：Recording → Transcribed → Post-processed → Text pasted
voxtype config                    # 打印解析后的最终配置（只列部分段）
voxtype config schema             # 每个可设置键的类型与当前值
voxtype setup check               # 依赖、驱动链、模型的体检
pactl get-default-source          # 默认录音源；连着蓝牙音箱时应是内建声卡，而不是 bluez_input.*
```

`voxtype config` 和 `config schema` 都不完整：前者不打印 `[paraformer]` 与
`[output.post_process]`，后者漏了 `paste_keys` / `type_delay_ms` / `restore_clipboard`
（`config get output.paste_keys` 甚至报 unknown key）。这三个键在 1.1.0 里确实生效——
二进制里有 `OutputConfig.paste_keys` 与 `VOXTYPE_PASTE_KEYS`，`voxtype config` 打印的
`[output]` 段也带出了 `type_delay_ms` / `restore_clipboard` 的值。别把「没列出来」当成
「没生效」。

| 现象 | 通常是什么 |
| --- | --- |
| 按 F9 没反应、日志无记录 | udev 规则没生效，或键盘设备名变了 |
| 有日志但识别成"没有没有"、或 `No audio was captured` | 默认源被蓝牙 A2DP 假麦抢走（`pactl get-default-source` 是 `bluez_input.*`），或耳机没连 |
| 英文连写没分开 | `[output.post_process]` 命令失败（cargo 没编译？），看日志的 `Post-processed` |
| 文字没进输入框 | 粘贴键与目标应用不匹配，换 `paste_keys` |
| `voxtype setup check` 报不在 `input` 组 | 忽略：权限走 uaccess，本来就不需要那个组 |
