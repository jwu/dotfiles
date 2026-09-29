# fcitx5

## 环境变量：Wayland 下不设 GTK_IM_MODULE / QT_IM_MODULE

`dot_config/environment.d/fcitx5.conf` 只保留两项：

```
XMODIFIERS=@im=fcitx   # X11 / XWayland 应用的 XIM 入口（Steam 等）
INPUT_METHOD=fcitx
```

**不要**再加 `GTK_IM_MODULE=fcitx` / `QT_IM_MODULE=fcitx`。它们会把 GTK / Qt 应用从
Wayland 原生 text-input 强制切到 fcitx5 的 immodule（DBus）路径；fcitx5 自己也会在
日志里建议：Wayland 输入法前端可用时 unset 这两个变量。

### 症状与实测（2026-09-29）

现象：ghostty 窗口里输入中文，preedit（拼音串）正常，**候选窗不出现**；同一时刻
Chrome / Zed 里候选窗正常。

判据是 fcitx5 记录的「当前焦点输入上下文」（`/controller` 的 `DebugInfo`）：

| 应用 | 焦点 IC 的 frontend | program | 候选窗 |
| --- | --- | --- | --- |
| Chrome / Zed | `wayland_v2` | 正确 | 正常 |
| ghostty（`GTK_IM_MODULE=fcitx`） | `dbus` | 空 | 不显示 |
| ghostty（`env -u GTK_IM_MODULE ... ghostty`） | `wayland_v2` | 正确 | 正常 |

ghostty 是 GTK4 应用，`GTK_IM_MODULE=fcitx` 让它走 immodule（DBus）路径；那条路径下
classicui 拿不到正确的光标矩形，候选窗就不显示（`niri msg layers` 与 X11 侧都找不到
候选窗窗口 —— Wayland v2 路径的候选窗走 `zwp_input_popup_surface_v2`，本来也不在
layer 列表里）。

### 上游状态

fcitx5 5.1.22 → 5.1.23（2026-09-28 升级，当天 12:42 重启后生效）之后该路径的候选窗
失效；同一份环境变量在 5.1.22 下正常，所以这是 5.1.23 的回归，不是环境变量本身写错。

`/var/cache/pacman/pkg/fcitx5-5.1.22-1-x86_64.pkg.tar.zst` 还在，需要复现时可用它降级
验证。即使上游修好，也没必要把这两个变量加回来：它们想要的「让所有应用用上 fcitx5」
在 Wayland 会话里本来就由原生 text-input 提供。
