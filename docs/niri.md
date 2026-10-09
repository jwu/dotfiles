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
| `Mod+Shift+A` | flameshot overlay：拖出框后还能拖 8 个手柄调，`方向键` / `Shift+方向键` 逐像素移动与缩放选区 |
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

wlr 后端走 `zwlr_screencopy_manager_v1`（niri 实现了它，见 docs/streaming.md）。改完必须
`systemctl --user restart xdg-desktop-portal`，否则它不会重新读配置。

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

