# niri 配置

`dot_config/niri/config.kdl` 里的输入与光标部分有几处和上游默认值不同，
起因是 `focus-follows-mouse` 这条规则的行为，下面记录推导过程。

## focus-follows-mouse 只在「跨进新窗口」时触发

niri 的 focus-follows-mouse 不是「指针在哪个窗口上就聚焦哪个」，而是「指针这次
移动从哪个窗口跨到了哪个窗口」。源码 `src/niri.rs` 的 `handle_focus_follows_mouse()`：

```rust
// 移动前的指针位置下的内容
let current_focus = self.contents_under(pointer.current_location());
...
if let Some(window) = &new_focus.window {
    if !self.layout.is_overview_open() && current_focus.window.as_ref() != Some(window) {
```

`new_focus` 是移动后的位置，`current_focus` 重新按移动前的位置算，两者窗口不同才
切换焦点。于是：

| 情况 | 结果 |
| --- | --- |
| 焦点在 a，指针已经停在 b 上，在 b 内部移动 | 前后都是 b → 不聚焦 |
| 指针移到 a（恰好是当前焦点窗口） | 前后不同 → 激活 a，无变化 |
| 指针从 a 移入 b | 前后不同 → 聚焦 b |

所以「指针先回到焦点窗口，再移到目标窗口」才能聚焦，直接动是不行的。

这是上游有意为之，不是配置错误。作者在 #2856 / #2078 的回复是：焦点跟随鼠标只在
指针移入新窗口时触发，其他合成器也这样，而且这样更不烦人。PR #2857 想删掉这个比较
被拒；社区要求的开关（对应 sway 的 `focus_follows_mouse = always`、Hyprland 的
`mouse_refocus`）目前 niri 没有。26.04 与 main 的这段逻辑一致。

`max-scroll-amount="25%"` 是另一层限制：即使触发了，要激活的窗口若会让工作区滚动
超过 25% 也照样放弃。

## warp-mouse-to-focus

用来绕开上面那条：焦点变化时把指针挪进焦点窗口，指针和焦点不再错位，下一次移动
就是正常的跨窗口，focus-follows-mouse 能正常触发。

niri 的焦点动作会调用 `maybe_warp_cursor_to_focus()`（`src/input/mod.rs`），
覆盖 `focus-column-*`、`focus-window-*`、`focus-workspace-*` 等，也就是键盘切焦点和
`niri msg action` 都会生效。三种模式（`src/niri.rs` 的 `CenterCoords`）：

| 配置 | 行为 |
| --- | --- |
| `warp-mouse-to-focus` | 指针在焦点窗口外才移动，且只调整越界的那一根轴 |
| `warp-mouse-to-focus mode="center-xy"` | 需要时把指针移到窗口中心 |
| `warp-mouse-to-focus mode="center-xy-always"` | 每次切换焦点都强行居中 |

两个已知不生效的场合：

- 键盘焦点在 layer shell 上（waybar、fuzzel 之类）时不 warp，
  `move_cursor_to_focused_tile()` 里有 `keyboard_focus.is_layout()` 判断。
- 新窗口自动弹出抢焦点不走 `State::focus_window()`，因此不 warp，那个场景仍然要
  点一下或者用一次键盘切焦点来同步。

## 光标隐藏

`cursor` 是顶层节点，两个开关都默认关闭：

```kdl
cursor {
    hide-when-typing
    hide-after-inactive-ms 2000
}
```

- `hide-when-typing`：打字时隐藏，指针一动或一点击就恢复。
- `hide-after-inactive-ms`：默认 `None`（永不隐藏），这里设成 2 秒。

niri 没有「手动隐藏光标」的 action 或 bind，这两个自动规则就是全部。

Ghostty 侧的 `mouse-hide-while-typing = true` 只覆盖它自己的窗口，niri 那条是全
会话生效的。另外 Ghostty ≥ 1.0.0 实现了 OSC 22 指针形状（用 CSS 光标名），程序可以
`\e]22;none\a` 隐藏、`\e]22;default\a` 恢复，适合在编辑器里临时藏起来，不属于常驻规则。

## 一份 config 管两台机器：output 段按端口名并存

`config.kdl` 里同时留着四块 `output`：`DP-3`（Dell U2722DX）、`DP-2`（这台 MacBook 外接
的 Dell S2716DG）、`eDP-1`（笔记本内置 Retina）和 `HDMI-A-3`（那台 Mac mini 上 480x320
的小 HDMI 屏）。niri 对当前不存在的输出名只是不匹配，不报错也没有副作用，所以两台机器
共用一个文件：Mac mini 上前三条规则空转，笔记本上第四条空转。

`DP-3` 与 `DP-2` 同时存在，是因为这台 MacBook 的外接屏与源里最早的记录（`DP-3` / 型号
U2722DX）对不上，实际接在 `DP-2` 上的是一块 Dell S2716DG。两条并列留着，插哪一块就
哪一条生效。

### 双屏布局：两块屏的 position 都要显式写

`eDP-1` 在原点 `position x=0 y=0`（逻辑 1600x1000），`DP-2` 在
`position x=-480 y=-1440`（逻辑 2560x1440）：水平方向外接屏中心 `-480 + 2560/2 = 800`
正是内屏中心（`1600/2`），竖直方向 `-1440 + 1440 = 0` 正好贴在内屏顶边，即外接屏居中
正上方。

关键在于**没有 `position` 的输出会被 niri 自动摆到其它输出的右边**。只给 `DP-2` 写
position 时，`eDP-1` 会被丢到 `2080,0`，相对关系就错了（实测）。两块屏都写死位置，布局
才与描述一致。负坐标合法，niri 不会把整个布局平移回非负象限。

### 切屏用 focus-monitor-previous，不用方向式 action

`Mod+Grave` 绑了 `focus-monitor-previous`，`Mod+Ctrl+Grave` 绑了
`move-window-to-monitor-previous`（把当前窗口送过去）。两屏时两者都是 toggle（实测
`eDP-1 → DP-2 → eDP-1`），也完全不依赖两块屏的相对位置。

实测（niri 26.04）确认了「送过去」的落点：窗口从 `eDP-1` 的 `ws 3` 出发，执行
`move-window-to-monitor-previous` 后落在 `DP-2` 当时正在显示的 `ws 5`，即**目标屏的
active workspace**，而不是同名或新建的 workspace；焦点跟随窗口一起过去，再执行一次
就回到原屏的 active workspace。

备选的 `focus-monitor-up` / `focus-monitor-down` 在本机同样能工作（外接屏在内屏上方，
方向与物理位置一致），但有两个缺点：`Mod+Up/Down` 已经被 `focus-window-up/down` 占用，
换到 `Mod+Shift+方向` 又与 niri 「Mod+Shift+方向 = move-column-to-monitor-*」的惯例
相反；而且布局一旦改成左右并排，上下方向就拐了弯。`previous` 两个话题都不会碰到。

`move-column-to-monitor-*`（整列而非单窗口）没有绑定。

`HDMI-A-3` 那块屏用的本来就是它的 preferred mode，`mode` 与 `scale 1` 都等于 niri 默认值，
仍显式写出来，是为了让「这块屏走原生分辨率、不缩放」成为配置里看得见的事实，而不是依赖
默认行为。当初是在接入比对时补回来的：源里的 `eDP-1` 会把 home 目录那份本机声明替掉。

## 触控板手感

`dot_config/niri/config.kdl` 的 `touchpad` 段按 macOS 的手感调过一轮，取舍记录如下。

### 加速度用 adaptive，不用 flat

niri 的 `accel-profile` 只有两个合法值，二进制里的报错就是
`invalid accel profile, can be "adaptive" or "flat"`：

| 值 | 行为 |
| --- | --- |
| `flat` | 关掉加速曲线，位移与手指距离成正比，即「和鼠标一致」 |
| `adaptive` | 慢速接近 1:1 便于精调，手指越快增益越高 |

macOS 的触控板是后者，所以触控板 `adaptive`、鼠标保持 `flat`。`accel-speed` 只在
`adaptive` 下才起作用（范围 -1.0~1.0，默认 0.0）。

libinput 1.32 其实有自定义加速度曲线的 API（`libinput_config_accel_create` /
`libinput_config_accel_set_points`），但那是给 compositor 消费的，niri 没接，
只能在上面两档里选。要让曲线形状本身可调，得给 niri 提 feature request。

### 滚动没有惯性

libinput 不做 kinetic scrolling，是明确的设计分工，文档里说：

> libinput expects the caller to be in charge of widget handling, the source
> information is thus enough to provide kinetic scrolling on a per-widget basis.

因为惯性要在「内容到顶/到底」时立刻停住，只有应用知道当前滚动容器的边界。
所以 niri 没有实现，`scroll-factor` 只是速度乘数，libinput-config 里也没有
momentum 之类的键；想要惯性只能在应用层，例如 Firefox 的 `general.smoothScroll.*`。
niri 仓库里目前没有 kinetic / momentum 相关的 issue 或 PR。

### Apple SPI 触控板没有压力轴

本机触控板是 `Apple SPI Touchpad`（`applespi`，SPI 总线），`/sys/class/input/*/capabilities/abs`
里只有位置和接触面积（`ABS_MT_TOUCH_MAJOR` / `ABS_MT_WIDTH_MAJOR`），**没有
`ABS_PRESSURE` / `ABS_MT_PRESSURE`**，所以：

- `libinput measure touchpad-pressure` 这类压力调优无效；
- 手掌误触只能靠 `dwt`（打字时）和按接触面积判定，阈值来自 libinput quirk
  `AttrPalmSizeThreshold` / `AttrTouchSizeRange`（`/usr/share/libinput/50-system-apple.quirks`
  里 `MatchBus=spi` + `MatchVendor=0x06CB` 那条，默认 1600 和 150:130）。
  要改就在 `/etc/libinput/local-overrides.quirks` 里覆盖，重启 niri 生效；
- libinput-config 的可用键里也没有压力/手掌阈值。

日志里偶发的 `kernel bug: Touch jump detected and discarded` 是 applespi 驱动侧的
触摸跳变（libinput 会丢弃），属于驱动问题，不是配置能解决的。

### 多指手势不可配

三指纵向 = 切 workspace、三指横向 = 移 view、四指纵向 = 开关 overview 都是硬编码，
没有配置项，外部手势工具也抢不走（设备由 niri grab）。能配的只有把双指滚动绑到 action：

```kdl
Mod+WheelScrollDown { focus-column-right; }
```

### 鼠标滚轮

niri 按 axis source 分派滚动因子（`src/input/mod.rs`）：

```rust
match source {
    AxisSource::Wheel  => config.input.mouse.scroll_factor,
    AxisSource::Finger => config.input.touchpad.scroll_factor,
    _ => None,
}
```

所以滚轮归 `input.mouse.scroll_factor` 管，和高分辨率滚轮（`REL_WHEEL_HI_RES`）配合生效。
`window-rule` 的 `scroll-factor` 会再乘上去，可给单个应用单独调速。
本机鼠标没有 `REL_HWHEEL`，`horizontal=` 用不上。

## 截图与标注

三个键分两条路：

| 键 | 走哪条 |
| --- | --- |
| `Mod+Shift+A` | flameshot overlay：拖出框后还能拖 8 个手柄调，`方向键` / `Shift+方向键` 逐像素移动与缩放选区。`~/.local/bin/niri-flameshot-gui` 把它直接开在焦点屏上，不再弹屏幕选择；只有一个输出时它直接把 `flameshot gui` 交出去 |
| `Print` | niri 自己的截图 UI 框选（按住 `Space` 拖 = 整体移动），保存后由 `~/.local/bin/niri-screenshot-annotate` 把文件交给 satty 标注 |
| `Ctrl+Print`、`Alt+Print` | niri 原生整屏 / 当前窗口，不进标注 |

### 选区手柄只能靠 flameshot

Wayland 客户端不能自己决定窗口位置，所以「在屏幕上就地拖出一块可反复调整的选区」只能由自带
全屏 overlay 的应用实现，flameshot 就是这类。niri 内置截图 UI（`src/ui/screenshot_ui.rs`）
里只有拖选和「按住 Space 整体移动」，没有任何边角 resize 逻辑；slurp 同样没有——它的
`handle_selection_end()` 一松手就提交并退出。所以 `Print` 那条路保留了 niri 的选区体验，
要把框调准则用 flameshot。

### 为什么必须配 portal 后端

flameshot 不自己抓屏：它通过 `org.freedesktop.portal.Screenshot` 拿到整屏，再画自己的
overlay。而 niri 没有自己的 portal 后端，`xdg-desktop-portal-wlr` 的 `wlr.portal` 里
`UseIn=wlroots;sway;Wayfire;river;phosh;Hyprland;` **不含 niri**（本机 `XDG_CURRENT_DESKTOP=niri`），
于是 Screenshot 会落到 gtk 后端，而它要 fork 本机没装的 `gnome-screenshot`。

所以 `dot_config/xdg-desktop-portal/portals.conf` 只把那一个接口指给 wlr：

```ini
[preferred]
default=gtk
org.freedesktop.impl.portal.Screenshot=wlr
```

改完必须 `systemctl --user restart xdg-desktop-portal`，否则它不会重新读配置。wlr 后端自己不带
捕获代码，它在更下一层调 grim。

### portal 后端的捕获其实是 grim

xdpw 收到非交互的 Screenshot 请求时执行的是一条固定命令（实测抓到的进程命令行）：

```text
grim -- /tmp/out.png
```

没有 `-o`（输出名）、没有 `-s`、没有 `-l`，所以永远是**整个虚拟桌面**拼成一张图写进临时 PNG
（本机 4096x3904）。grim 才是走 `zwlr_screencopy_manager_v1` 的那一层（niri 实现了它，见
docs/streaming.md）。也就是说 grim 只在这条链的最底层出现，**调用者是 xdpw，flameshot 不知道
它存在**；这条依赖也不是我们选的：`grim` 由 `xdg-desktop-portal-wlr` 拖进来，而后者本来就被
`niri` 包依赖。

`pacman -Qi flameshot` 里那行 `grim: for wlroots wayland support` 是 13 时代的旧文本：
flameshot 曾有 `USE_WAYLAND_GRIM` 编译开关，v13 改成运行时 `useGrimAdapter` 设置并进了配置界面
（PR #3859 / #3919 / #3943），**v14 全部移除**——14.0.0 的源码树里没有 grim 文件，
`strings /usr/bin/flameshot | rg grim` 也是空。上游后来试过用 `FLAMESHOT_USE_GRIM=1` 把 grim
快路径加回来（PR #4944），被关掉的理由是 `We intentionally use the portal backend for
commonality.`

### 这一路为什么慢：整桌面图编解码两次

按 `Mod+Shift+A` 到 overlay 出现实测 1.82s（本机两屏：eDP-1 逻辑 1600x1000 @1.6、
DP-2 2560x1440 @1）：

| 阶段 | 耗时 |
| --- | --- |
| `niri-flameshot-gui` 自己（niri IPC + wayland-info + jq/awk） | 0.04s |
| flameshot 的 Qt/Wayland 启动（拿 `flameshot screen -n 99 -r` 测，它在进 portal 前就报错退出） | 0.07s |
| portal：grim 抓整个虚拟桌面（4096x3904，约 16M 像素）并编码 PNG | ~1.10s |
| flameshot 读回并解码同一张图、裁到单屏、建全屏窗口 | ~0.6s |

那 1.10s 里纯捕获只占 0.17s（同期 `grim -t ppm` 测得），**PNG 编码约 0.94s**；作为对照，
`grim -o DP-2` 单屏只要 0.19s。时间几乎全花在两块屏的拼接图与它的 PNG 编解码上，瓶颈是 portal
的交付形态，不在 flameshot 也不在这个脚本。

没有可调的余地：xdpw 的配置只有 `[screencast]` 段（`man 5 xdg-desktop-portal-wlr`），没有
任何 screenshot 键，无法让它只截一块屏或降压缩级别；`/tmp` 本来就是 tmpfs，那张 PNG 也只有
2.4MB，IO 不是瓶颈。

### flameshot 会自弹屏幕选择，得替它先选

Wayland 下 flameshot 拿的是**整张虚拟桌面**（portal 的 Screenshot 返回所有输出的图），裁到
单屏之前它会先弹一圈屏幕预览让人点，因为 `flameshot gui` 从不预选屏幕：

```cpp
// src/utils/screengrabber.cpp, grabEntireDesktop()
// If monitor was pre-selected skip UI and crop directly
if (preSelectedMonitor >= 0) { ... return cropToMonitor(screenshot, preSelectedMonitor); }
return selectMonitorAndCrop(screenshot, ok);   // createMonitorPreviews()
```

`flameshot screen -n N -e` 是同一套 overlay 编辑器加上预选屏幕（`main.cpp` 把它重写成
GRAPHICAL_MODE + `setSelectedMonitor(N)`，`capturewidget.cpp` 再把 N 传给 `grabEntireDesktop`），
所以 `dot_local/bin/executable_niri-flameshot-gui` 先问 niri 要焦点输出，再把它当 N 传进去。

- 为什么不用配置项 `captureActiveMonitor`（自动用光标所在屏）：它在 Wayland 下被硬编码关掉，
  源码里的理由是 `Capture Active Monitor is not supported on Wayland due to Wayland security
  model.`
- 编号 N 是 **Qt 的 screen index**，也就是 Wayland registry 里 wl_output 全局的注册顺序。niri
  自己的两种列法都不能用：`niri msg --json outputs` 的 JSON 来自 `HashMap<String, Output>`，
  同一个会话里连续两次请求的顺序都可能不同（实测两种顺序各出现三次）；`niri msg outputs`
  人类可读的那份则是 niri 客户端按输出名排序的（`src/ipc/client.rs` 里的
  `sort_unstable_by(|a, b| a.0.compare(&b.0))`），与 Qt 无关。所以脚本改问 `wayland-info`
  （`wayland-utils` 包），它按 registry 顺序枚举，和 Qt 建屏的顺序同源。
- 编号与屏幕的对应关系本身也是实测的：`flameshot screen -n N -r | file -`，不带 `-e` 时不会弹
  任何 UI，PNG 尺寸直接暴露是哪块屏（`-n 0` → 3200x2000 是 eDP-1，`-n 1` → 2560x1440 是 DP-2）。
  那个 3200x2000 来自 wl_output 报的整数 `scale: 2`，与 niri 的 fractional 1.6 无关。
- 只有一个输出时这些换算全都不需要：flameshot 自己就会跳过选择器（`selectMonitorAndCrop` 里
  `screens.size() == 1` 直接裁到 monitor 0），所以脚本先数一下输出个数，是 1 就把
  `flameshot gui` 原样交出去，连 `wayland-info` 都不查。省掉的那次查询只有几毫秒，重点是**单
  显示器的机器不必为了这个键去装 `wayland-utils`**。判断用的是个数不是顺序，所以不会踩上面
  那个随机序的坑。
- 任何一步拿不到编号（没装 `wayland-utils`、niri 没在跑、解析出的名字集合与 niri 的对不上）都
  回退到 `flameshot gui`：宁可多一次点选，也不静默截错屏。

### flameshot 的工具栏位置固定不了

它全部 47 个配置项里没有位置相关的键，那排按钮（源码里的 `UtilityPanel`）位置是按选区/
鼠标算出来以避开选区的。要「位置固定」只能改用 satty 那种窗口内工具栏；用 flameshot 时
就直接上键盘：`P`/`A`/`R`/`C`/`T`/`M`/`B` 选工具，`Ctrl+C` 复制、`Ctrl+S` 保存、`Ctrl+Q`
退出，选区微调用 `方向键` 与 `Shift+方向键`。

### 踩过的坑：工具图标全是空白

flameshot 的图标是内嵌 SVG，要 Qt 的 SVG 图标引擎插件才能渲染。Arch 上 `qt6-svg` 与
`qt6-base` 必须同主次版本：装 flameshot 时它作为依赖把 `qt6-svg 6.12` 拉了进来，而系统的
`qt6-base` 还停在 `6.11`，插件加载直接失败（`/proc/<pid>/maps` 里连 `libQt6Svg` 都没有），
按钮就只剩纯色块。`pacman -Syu` 让两者对齐后恢复。

这是 partial upgrade 的典型后果：只装单个包会把依赖的新版本拖进来，与没升级的其余 Qt 包
错配。同类症状出现时先查 `/proc/<pid>/maps` 里那个插件库在不在。

### satty 侧只负责标注

satty 不含任何抓屏代码，只吃别人给的图。所以 `Print` 是「niri 截图 → 事件流 → satty」的
桥接：`dot_local/bin/executable_niri-screenshot-annotate` 先订阅 `niri msg --json event-stream`，
再触发 `niri msg action screenshot`，收到 `ScreenshotCaptured` 后把 path 交给 satty
（先订阅再触发，事件不会漏；`Esc` 取消则不会产生文件，脚本按超时自行退出）。

配置在 `dot_config/satty/`：`config.toml` 让窗口浮动并按图片尺寸开，`overrides.css` 把工具栏
的最小宽度归零（默认约 955px），否则小选区也会顶出一个屏幕宽的窗口。

