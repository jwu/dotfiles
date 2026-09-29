# fcitx5

## GTK 输入法模块：全局使用 fcitx immodule

`dot_config/environment.d/fcitx5.conf` 设置 `GTK_IM_MODULE=fcitx`，让 GTK 应用使用
fcitx5 的 GTK immodule（DBus frontend）。`QT_IM_MODULE` 不设置；X11 / XWayland 应用仍由
`XMODIFIERS=@im=fcitx` 提供 XIM 入口。

### Ghostty 候选窗位置（2026-09-29）

在本机 Ghostty 1.3.1、fcitx5 5.1.23、niri 26.04 下，未设置 `GTK_IM_MODULE` 时，Ghostty
使用 `wayland_v2` 原生 text-input。pi 和普通 shell 的底部输入行都会遇到候选窗遮挡：Niri
在窗口内没有足够空间把候选窗放到光标下方时，会将它翻到上方。

用 `env GTK_IM_MODULE=fcitx ghostty` 单独启动 Ghostty 后，fcitx5 DebugInfo 确认焦点 IC 改为
`frontend:dbus`（`program` 为空）；候选窗正常出现，且用户实测不再遮住输入行。因此选择全局
设置 GTK immodule。该设置是否影响其他 GTK 应用，仍应以本机逐个实测为准。

### 历史记录：候选窗曾经消失（原因未确定）

此前在 Ghostty 中确实记录过一次不同症状：拼音 preedit 正常，但候选窗不出现；当时观察到
`GTK_IM_MODULE=fcitx` 对应 `frontend:dbus`、`program` 为空，而 unset 后走 `wayland_v2`、候选窗可见。
当时还观察到 fcitx5 从 5.1.22 升至 5.1.23 后出现该现象，并怀疑 DBus 路径上的光标矩形处理，
但没有证实根因。

本次在相同版本上重新单独启动 Ghostty，`GTK_IM_MODULE=fcitx` 的 DBus 路径候选窗正常，旧现象
未能复现。因此保留这条历史记录，但不再把它归因于 fcitx5 5.1.23 回归；**候选窗偶发消失的原因
仍未查明**，也不能据此断言该变量在所有情况下都稳定。

`QT_IM_MODULE` 不随之开启：本次验证只覆盖 GTK/Ghostty；Qt Wayland 应用继续使用原生
text-input。
