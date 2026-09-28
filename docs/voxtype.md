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
Python 解释器与伴随文件，把它重写成 Rust（独立项目 `~/dev/wordseg-rs`，词表在
编译期由 `build.rs` 解压烘焙进二进制，因此没有运行时依赖）。

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

## 键盘权限：uaccess 而非 input 组

evdev 监听要读 `/dev/input/event*`。加进 `input` 组是最常见的做法，但那是**永久**授权；
`TAG+="uaccess"` 只对本地登录会话生效，权限面更小。规则文件按**设备名**匹配，所以换
键盘要改这个文件并重跑 bootstrap 的对应步骤。

规则里只列了这台机器的两把键盘。`Apple SPI Keyboard` 那类需要 `setfacl` 的特殊条目不
在这里——用不到，且会引入用户名硬编码。

## 音频设备

用系统默认源（`device = "default"`）。

这台机器上**唯一的麦克风是 AirPods**（台式机内建声卡的 `front-mic` / `rear-mic` 都是
`not available`）。曾经为了绕开"默认源漂到离线蓝牙设备"的问题，用 `~/.asoundrc` 固定
到内建声卡——结果录到的是没有麦克风的设备，只有静音。教训：**先确认麦克风真实存在，
再谈设备固定**。

WirePlumber 会把默认源指向优先级更高的蓝牙设备（AirPods 2010 > 内建 2009），即使耳机
离线。目前无害（离线时本来也没有麦可用），但其他录音应用会受影响。

## 文件与归属

| 内容 | 位置 | 由谁部署 |
| --- | --- | --- |
| voxtype 配置 | `~/.config/voxtype/config.toml` | chezmoi（`dot_config/voxtype/config.toml.tmpl`） |
| 分词过滤器 | `~/.local/bin/wordseg-rs` | 独立项目（`~/dev/wordseg-rs`），已发布到 crates.io；`bootstrap/arch.sh` 用 `cargo install` 装 |
| 键盘 udev 规则 | `/etc/udev/rules.d/70-voxtype-uaccess.rules` | `bootstrap/arch.sh` 的 `install_voxtype_udev` |
| 程序本体 | `voxtype-bin`（AUR） | `bootstrap/arch.sh`，必要时 `yay -S voxtype-bin` |
| 用户服务 | `~/.config/systemd/user/voxtype.service` | `voxtype setup systemd`（**不**由 chezmoi 管） |
| 模型 | `~/.local/share/voxtype/models/` | `voxtype setup --download --model <名字>` |

**注意**：`voxtype config set`、`voxtype setup systemd` 都会就地改文件。改了之后要么
手工同步回本仓库，要么重新 `chezmoi apply` 覆盖回来——配置以仓库为真源，unit 以
`setup systemd` 为真源。

## 排查

```bash
voxtype status                    # idle / recording / transcribing
journalctl --user -u voxtype -f   # 实时日志：Recording → Transcribed → Post-processed → Text pasted
voxtype config                    # 打印解析后的最终配置
```

| 现象 | 通常是什么 |
| --- | --- |
| 按 F9 没反应、日志无记录 | udev 规则没生效，或键盘设备名变了 |
| 有日志但识别成"没有没有" | 麦克风采到静音：设备选错，或耳机没连 |
| 英文连写没分开 | `[output.post_process]` 命令失败（cargo 没编译？），看日志的 `Post-processed` |
| 文字没进输入框 | 粘贴键与目标应用不匹配，换 `paste_keys` |
