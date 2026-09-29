# 锁屏

Linux 侧锁屏统一走 `~/.local/bin/niri-lock`（源是 `dot_local/bin/executable_niri-lock.tmpl`）：
默认用 **hyprlock**；`hyprlock` 不在时回退
到 `swaylock`，这样锁屏不会因为缺包而静默失败。`Mod+L` 调用这个脚本，反向的 `niri-unlock`
见下面的「远程解锁」一节。

## 熄屏

没有空闲自动锁屏：会话只在 `Mod+L` 时锁上。锁屏期间 `niri-lock` 自己拉起一个
`swayidle -w timeout 60`，空闲到点就 `niri msg action power-off-monitors`；swayidle 每次活动
后重新计时，所以只要还锁着，每段新的空闲都会再熄屏一次。计时器挂在锁屏进程的生命周期
上，解锁（锁屏进程退出）时 `trap ... EXIT` 杀掉它并点亮显示器 —— 熄屏倒计时从「锁上」
那一刻开始算，而不是从最后一次输入算。

点亮不需要额外机制：niri 收到按键/鼠标移动时自己激活显示器（`src/input/mod.rs` 的
`should_activate_monitors`），锁屏时它的 IPC 也照样接受 `PowerOffMonitors` /
`PowerOnMonitors`（同文件的 `allowed_when_locked`）。所以 niri 的 `spawn-at-startup` 里不再
有 swayidle。

`Mod+Alt+L` 那条恢复绑定直接跑 `swaylock -f`，绕过 `niri-lock`，那条路径没有熄屏计时。

### Mac mini 例外：不装这个计时器

`niri-lock` 是 `.tmpl`，按 `.chezmoi.hostname` 分岔：`archlinux-macmini` 渲染出的脚本
**不含** swayidle 段，锁屏期间显示器一直亮着。那台机器 2026-09-25 手工移除过计时器，接入
比对时把这个差异固化进模板 —— 否则每次 `apply` 都会照源把计时器带回来。其余主机渲染出的
仍是上面的 60 秒版本。

## hyprlock 配置

样式拆成四份文件，都在 `dot_config/hypr/`：

| 文件 | 作用 |
| --- | --- |
| `hyprlock-large.conf` | 完整 [Style-10][MrVivekRajan/Hyprlock-Styles]，按 2560x1440 设计，**默认** |
| `hyprlock-medium.conf` | 与 large 同一套元素，按 1366x768 设计：字号收小，位置改成输出尺寸的百分比 |
| `hyprlock-small.conf` | 紧凑样式，按 480x320 设计：只留时间 + 一个不带底框的密码提示 |
| `hyprlock.conf` | 只有一行 `source`，指向 large —— 给裸跑 `hyprlock` 一个默认 |

四份文件里**所有 widget 的 `monitor` 都留空**，也就是“整份文件作用于当前所有显示器”。
挑哪一份是 `niri-lock` 在锁屏前做的，**默认 large**：这个仓库面向普通桌面显示器，另两份
是给装不下完整布局的屏幕用的。取当前**最宽**的那块屏：宽度 ≥ 1600 用 large，900–1599 用
medium，< 900 用 small；读不到输出信息就保留默认，不猜。阈值写在 `niri-lock` 的
`FULL_MIN_WIDTH` / `MEDIUM_MIN_WIDTH`。

时间/日期走 `label { text = cmd[update:1000] ... }`，**本来就是实时的**。

### 为什么按样式分文件，而不是在配置里按显示器写

hyprlock 的 `font_size` **是绝对像素**；而 `monitor` 只做字符串匹配 —— 精确等于端口名，
或匹配 EDID 描述前缀，**分辨率完全不参与匹配**：

```cpp
// src/renderer/Renderer.cpp -- widget 与显示器的匹配条件
if (!c.monitor.empty()
    && c.monitor != POUTPUT->stringPort
    && !POUTPUT->stringDesc.starts_with(c.monitor)
    && !("desc:" + POUTPUT->stringDesc).starts_with(c.monitor))
    continue;
```

`COutput` 手里就有分辨率（`Vector2D size`），但这个条件一次都没用上。

（`position` / `size` 本身是支持百分比的：v0.9.6 的 `CLayoutValueData::getAbsolute` 把带
`%` 的值按 `(v / 100) * viewport` 换算，`viewport` 就是那块屏的尺寸，medium 这档用的正是
这一点。但百分比只能挪位置、缩放框，**`font_size` 仍是绝对像素**，而且小屏要的不是「把
完整布局等比缩小」，是只留时间那种信息裁剪 —— 所以样式仍然按文件分。）

它也不支持逗号列表、通配符、正则，更没有「默认/兜底」语义：`monitor =` 留空表示**所有**显示器，表达
不了「除了上面提过的之外」。后果是三条一起成立的：

- 一套数值不可能同时适配 480x320 和 2560x1440（旧的单套值按 ~1920x1080 写，`font_size=90`
  的星期标签在 480 宽的屏上几乎占满，`position=0,350` 的偏移把文字推出屏幕，`x=820` 的
  电源按钮在 480 宽上完全不可见）；
- 想让某块屏不叠加另一套布局，两块屏就必须各自点名 `monitor`，于是配置和硬件绑死：换
  HDMI 口（`HDMI-A-3` → `HDMI-A-2`）匹配就失效、那块屏变黑；
- **没被点名的显示器，在那块屏上一个 widget 都不会画（黑屏）**。但密码仍能盲打解锁 ——
  认证在 session lock 层，与有没有 input-field 组件无关。

`monitor =` 留空 = 作用于所有显示器，这条规则反过来给了出路：**把选择挪到文件层面**。
每份文件整体就是一个样式，内部全部留空，由 niri-lock 按当前最宽的屏挑一份。文件本身
就是声明，配置里不再出现端口名。

hyprlock 的 `source` 不能用来做条件选择（`handleSource` 走的是 `glob()`，只认 `~` 和通配
符，不展开其它环境变量），所以选择只能在锁屏脚本里做。`hyprlock.conf` 保留一行
`source`，是为了让裸跑 `hyprlock` 也有内容，而不是读到空配置。

**取舍**：两块屏同时插着时只有一份样式生效，另一块屏不会有 widget。只要两块屏同时在线
又需要不同布局，就只能在同一个文件里按名字区分 —— 这是上面那个 `if` 决定的。当前假设
是「基本不会同时插」。

（也试过用 `hyprlock.conf.tmpl` + 生成脚本在锁屏前按分辨率拼配置，能覆盖多屏并存的情况，
但链路太长（模板 / 生成器 / niri-lock 三处协作），已经 revert。git 历史里有完整实现。）

### 中屏布局（1366x768）

元素与 large 完全相同（星期、日期、时间、用户框、密码框、三个电源按钮），字号收小到能看清
（星期 52 / 日期 26 / 时间 15，用户框 16、按钮 34），位置**全部写成输出尺寸的百分比**。这档存在的理由就是
large 的固定像素偏移在 1366x768 上会溢出：90px 的星期名配 `position = 0, 350`，字会被顶
出屏幕上沿；底部按钮行也往密码框那一列挤。

垂直位置都是相对屏幕中心的百分比（y 正向朝上，与 large 一致）：

| 元素 | 偏移 | 1366x768 上的区间（行高按 1.2×字号估） |
| --- | --- | --- |
| 星期 | `+37%` | 69-131 |
| 日期 | `+28%` | 153-185 |
| 时间 | `+22.5%` | 202-220 |
| 用户框（240x48） | `-20%` | 514-562 |
| 密码框（320x48） | `-32%` | 606-654 |
| 按钮行（34px，距底 5%） | `5%` | 709-750 |

最紧的一对（日期到时间）还剩 17px，其余更松；换成 1280x800 / 1280x1024 / 1024x768 只会
更宽（百分比跟着高度走，字号不变）。

按钮横向用 `-8%, 0, 8%` 而不是 large 的 `±160px`：1366 宽下中心间距 109px，与 large 在
2560 宽上的视觉密度相当；最窄的 900 宽屏上，三个 34px 图标之间也还有 38px 空隙。

框和字号的尺寸（`size = 320, 48`、`font_size`）故意留在像素上：百分比框会连文字一起缩小，
正好抵消掉「中屏」这档的意义。

### 小屏布局（480x320）

屏幕中心 `(240, 160)`，**`position` 的 y 正向朝上**（`posFromHVAlign` 里 `valign=top`
对应大 y），`valign` 决定锚点在底/中/顶：

| 元素 | 几何 | 位置（从屏顶算） |
| --- | --- | --- |
| 毛玻璃板 | 320x130 | 69-199 |
| 时间 | 60px | 中心 134 |
| 密码提示 / 圆点所在区 | 300x50 | 218-268 |

时间背后的板是 `shape`（白 7% + 1px 白边 10%）。密码输入**不带底框**：`inner_color` /
`outer_color` 全透明、`outline_thickness = 0`，只有 `🔒 Enter Pass` 提示和打字时画出的圆点，
直接浮在背景上。提示字 `rgb(200,200,200)` 在这张背景上约 6.4:1，够看。

两者间距 19px，顶部留白 69px、底部留白 52px。字号由 `size.y / 4` 推导（50/4 ≈ 12px），
所以提示和失败信息都跟着区域尺寸走。

因为不画边框，`fail_color`（它只给 outline 上色）在这个字段上没有效果，失败反馈只能靠
`fail_text`。

### 背景是实测对比度挑的，不是按比例挑的

时间文字是 `rgba(226,232,240)`，WCAG AA 要求对比度 ≥ 4.5:1。按 hyprlock 的实际处理链
（`gain()` 曲线 + 模糊）算出来的时间区结果：

| 壁纸 | 比例 | 时间区背景均值 | 对比度 |
| --- | --- | --- | --- |
| `ristretto-0-launch` | 1.50（与小屏一致，零裁剪） | RGB(94,51,24) | **8.7:1** ✓ |
| `vantablack-1-twisted-stairs` | 1.78（大屏上下裁 7.8%） | RGB(19,19,19) | **15.1:1** ✓ |
| `ristretto-1-color-curves` | 1.78 | RGB(177,124,70) | 2.9:1 ✗ |
| `osaka-jade-3-mountain-moon` | 1.78 | RGB(154,202,148) | 1.5:1 ✗ |

**不要按宽高比自动挑图**：`osaka-jade` 的 1.78 正好匹配大屏，但白字对比度只有 1.5:1，
挑中它直接看不清。大屏用的是对比度最高的那张。

大屏试过换成小屏那张暖橙图，但大屏文字是**大字号配 0.70 透明度**，叠在偏亮的暖橙上有效
对比度只剩约 3.2:1 —— 刚过 AA 大文本的 3:1，够不到 4.5:1。而 hyprlock 没有「压暗背景」
的手段：

- `background` 的 `brightness` **只在 `> 1.0` 时**参与乘法
  （`Shaders.hpp` 的 `FRAGBLURPREPARE`：`if (brightness > 1.0) pixColor.rgb *= brightness;`），
  所以 `< 1.0` 的值是彻底的空操作。旧配置里从上游抄来的 `brightness = 0.8172` 从未生效，
  已经删掉。
- `background` 的 `color` 只是**纹理加载失败时的兜底色**，不与图混合。
- 用一层半透明黑色 `shape` 当遮罩也不行：widget 排序用的是 `std::ranges::sort`（不是
  stable sort），同 `zindex` 的相对顺序没有保证，遮罩会随机盖住文字。

顺带记一笔：`contrast` / `brightness` / `vibrancy` **只在 `blur_passes > 0` 时**才被应用。

### 大屏那套只改了一处

字号与间距全部保留 Style-10 原值（90/40/20、350/250/190）。唯一改动是底部三个按钮的
定位：原来用 `halign=left/right` 配 `x=±820`，那是照 1920 宽写死的，屏一宽就挤到中间偏
左；现在三个统一 `halign=center`、只差 x 偏移（±160），任何宽度下都在底部居中且等距。

`onclick` 也从 `reboot now` / `shutdown now` 换成了 `systemctl reboot` / `poweroff` ——
前者在 Arch 上并不存在。

其它沿用的本地改动：文字 `font_family` 用 `Adwaita Sans Bold`（上游是没装的
`SF Pro Display Bold`）；图标 label 用 `FiraMono Nerd Font Propo`（原因见下节）；
Style-10 的头像 `image` 已删掉（没有头像，注释块也一并删了）。

### 其它坑

- **`#` 要写两遍**：hyprlang 把裸 `#` 当行内注释起始，所以 Pango 标记里的颜色要写
  `##ff8a80`（`placeholder_text` 里的 `##ffffff99` 同理）。
- **`fail_text` 用 `$ATTEMPTS` 而不是 `$FAIL`**：后者是 `g_pAuth->getCurrentFailText()`，
  即 PAM 的原始错误文字，太长；`$ATTEMPTS` 才是失败次数。
- **`fail_text` 的字号**由 `size.y / 4` 推导（小屏 46/4 ≈ 11px），不会撑破布局。
- **没有 `fail_transition` 这个参数**：v0.9.6 的 `ConfigManager.cpp` 里没有注册它（失败
  过渡由 animation 的 `inputFieldColors` 节点控制）。

## 装什么、拷什么

- `bootstrap/arch.sh` 的 `PACKAGES` 里有 `hyprlock`（`extra`）和 `adwaita-fonts`（星期/日期/
  时间那几行用 `Adwaita Sans Bold`）；图标字体的 `otf-firamono-nerd`、🔒 用的
  `noto-fonts-emoji` 本来就在列表里。
- 文件本身由 chezmoi 部署：`dot_config/swaylock/backgrounds/` → `~/.config/swaylock/backgrounds/`
  （swaylock 与 hyprlock 共用），以及 `dot_config/hypr/hyprlock{,-small,-medium,-large}.conf`
  与 `dot_local/bin/executable_niri-lock.tmpl`。

## 图标右边被切掉（坑）

hyprgraphics 的 `TextResource.cpp` 按 **logical extents** 开纹理再画：

```cpp
cairo_image_surface_create(CAIRO_FORMAT_ARGB32, logical.width, logical.height);
cairo_move_to(CAIRO, -logical.x, -logical.y);
pango_cairo_show_layout(CAIRO, layout);
```

而等宽 `FiraMono Nerd Font` 给所有字形固定 0.8em 的 advance（50px 字号 = 40px），图标 ink
却更宽，于是右边一律被切：

| 字形 | ink | logical | 右边溢出 |
| --- | --- | --- | --- |
| `󰜉` mdi-restart | 46 | 40 | 6 |
| `󰐥` mdi-power | 45 | 40 | 5 |
| `󰤄` mdi-night | 45 | 40 | 5 |
| `` fa-user | 62 | 40 | 22 |

用**比例版** `FiraMono Nerd Font Propo` 后 advance 与 ink 基本一致（0-2px），且不引入额外
空白、不影响居中。换等宽字体里的任何图标都救不了（全都是同一个 0.8em advance）。

（`$USER` 那个 label 后面跟着空格和文字，溢出落在 logical 框内，所以看不出被切。）

## 背景能不能实时？

**不能是「桌面实时画面」**：`ext-session-lock` 期间 compositor 停止渲染原会话，没有帧可抓
（锁定时 `niri msg action screenshot-screen` 不产出文件，解锁后才产出）。所以 `background`
只能是静态图，`path = screenshot` 也只是锁定前那一下的截图 + 模糊。

能实时的是**锁屏客户端自己产出的内容**：`label` 的 `cmd[update:N]`，以及 `background`/`image`
的 `reload_time` + `reload_cmd`（重画一张 PNG 再让 hyprlock 重载）。要在锁屏上看窗口状态，
就是这条路：定时或按 niri 事件重跑渲染器 → `SIGUSR2` 让 hyprlock 重载；注意它上一张还
pending 时会 `Refusing to load`，刷新别太密。

## 恢复绑定

niri 里：

```
Mod+Alt+L allow-when-locked=true { spawn-sh "pkill -x hyprlock; pkill -x swaylock; sleep 0.3; swaylock -f"; }
```

`allow-when-locked` 让它在锁定时也能触发；杀掉卡死的 locker 后用最简单的 swaylock 接管。
锁屏客户端死掉时 niri 会留一个红屏（见 niri FAQ），这条绑定就是为那条路径准备的。

## 从 ssh 锁屏：不脱会话就会掉进上面那个红屏

`wattach niri-lock` 会让 hyprlock 变成 ssh 会话的后代。退出 ssh 时 sshd 给会话的前台
进程组发 SIGHUP，hyprlock 跟着死；而 niri 不会因为锁屏客户端消失就解锁（故意的，客户端
崩了不能暴露桌面），于是会话卡在「锁着但没人管」的红屏上 —— 也就是上一条绑定专门要救的
那条路径。实测的症状是 `loginctl show-session` 报 `LockedHint=yes`，而 `hyprlock` /
`swaylock` / `swayidle` 一个都不在。

所以从 ssh 锁屏要让它脱离会话：

```sh
wattach -d niri-lock              # 等价于 wattach setsid -f niri-lock
```

`setsid -f` 让 niri-lock 以 `systemd(1)` 为父进程独立成会话，ssh 断开时收不到 SIGHUP。
验证方式是看进程树里没有 sshd：

```sh
pstree -sp $(pgrep -x hyprlock)
```

红屏状态下从 ssh 解不开锁，最终仍要有人在键鼠前输密码；ssh 那边能做的只是再起一个锁屏
客户端，niri 会用它替换掉死掉的那个。这不是锁屏特有的问题，任何「要活过我退出 ssh」的
GUI 程序都一样，见 [`wayland-attach.md`](wayland-attach.md)。

## 远程解锁：`niri-unlock`

从另一个 tty 或 ssh 里：

```sh
niri-unlock
```

hyprlock 和 swaylock **都**把 `SIGUSR1` 当作「解锁并退出」，所以对正在跑的 locker 发这个
信号就是解锁。两条路径都有源码依据：

```cpp
// hyprlock src/core/hyprlock.cpp
static void handleUnlockSignal(int sig) {
    if (sig == SIGUSR1) {
        Log::logger->log(Log::INFO, "Unlocking with a SIGUSR1");
        g_pAuth->enqueueUnlock();
    }
}
...
registerSignalAction(SIGUSR1, handleUnlockSignal, SA_RESTART);
```

```c
// swaylock main.c
void do_sigusr(int sig) { (void)write(sigusr_fds[1], "1", 1); }
static void term_in(int fd, short mask, void *data) { state.run_display = false; }
...
sigaction(SIGUSR1, &sa, NULL);
/* 主循环退出后 */
ext_session_lock_v1_unlock_and_destroy(state.ext_session_lock_v1);
```

实测（hyprlock）日志是连续三行 `Unlocking with a SIGUSR1` → `Unlocking session` →
`Unlocked, exiting!`，随后 hyprlock 与 niri-lock 都正常退出，`loginctl` 的 `LockedHint`
转回 `no`。`SIGUSR2` 是另一个用途（强制刷新 label 定时器），就是上面「背景能不能实时？」
用的那个。

### 红屏：没有 locker 可发信号时

`niri-unlock` 发现没有 locker 在跑时，先确认会话真的处于锁定状态（`LockedHint=yes`），
再起一个 `niri-lock`，等它就绪后解锁 —— 实测从红屏恢复到解锁 396 ms。那个 `LockedHint`
守卫不是多余：没有它，在已经解锁的会话上跑 `niri-unlock` 会先锁上再解开，白闪一下。

「等它就绪」也不是可有可无的：hyprlock 的 `registerSignalAction(SIGUSR1, ...)` 在
`acquireSessionLock()` **之后**才执行，而 `SIGUSR1` 的默认动作是**终止进程**。抢在它拿到
锁之前发信号，等于把刚起的 locker 杀掉，又回到红屏。判据用 `/proc/<pid>/status` 的
`SigCgt` 第 9 位（`SIGUSR1` 是信号 10）：

```console
$ grep SigCgt /proc/$(pgrep -x hyprlock)/status
SigCgt:	0000000300000a00        # 0xa00 = bit9 + bit11 = SIGUSR1(10) + SIGUSR2(12)
```

同一份 `SigCgt` 里 **SIGHUP / SIGTERM 都没有被捕获**，这补上了「从 ssh 锁屏」那个坑的
另一半：ssh 断开时 SIGHUP 直接终止 hyprlock，它没有机会做任何善后，所以只会留下红屏。

### 其它入口都不通

解锁动作必须由持有锁的客户端发起（`ext-session-lock-v1` 的语义）。niri 的 IPC 里没有
unlock 动作，`loginctl unlock-session` 也没用：niri 不监听 logind 的 Unlock 信号，hyprlock
连 logind 更是只为 inhibit —— `src/core/Dbus.cpp` 里只有一个到
`org.freedesktop.login1.Manager` 的代理，没有对外暴露任何可调用的方法。

### 安全含义

锁屏防物理接触，不防「已经能以你的身份执行代码的人」。任何 ssh 登录你账号的人都能
`niri-unlock`，所以锁屏在「ssh 暴露到公网 + 弱密码」的组合里不构成防线。

## 已知取舍

- hyprlock 锁定期间持续 ~60fps 重绘（GPU 加速），耗电比 swaylock 高。
- `--grace <sec>` **不要用**：niri 下 hyprlock 会收到一个 stray key 事件
  （`ERR: Invalid key down event (stray release event?)`），而 grace 期间任何输入直接解锁，
  实测 4 秒就自己解开了。
- 底部三个 `onclick`（`suspend` / `reboot` / `poweroff`）能否生效取决于 polkit agent。第一个
  按钮在 MacBook 上是 `systemctl hibernate`（其余机器仍为 `suspend`）：这台机器的 deep S3
  会被硬件每 ~45 秒拽醒，而 S4 真正断电。见 [`docs/suspend.md`](suspend.md)。

[MrVivekRajan/Hyprlock-Styles]: https://github.com/MrVivekRajan/Hyprlock-Styles
