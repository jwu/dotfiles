# Alacritty

`dot_config/alacritty/alacritty.toml.tmpl` 用 `{{ if eq .chezmoi.os }}` 分成两段，
因为 macOS 与 Linux 那两份是**各自独立维护的配置**，不是同一份的新旧版本：

- **macOS**：绑定 `cmd+n` / `cmd+w`，字号 16，与那台机器的 ghostty 一致。
- **Linux**：对着 `~/.config/ghostty/config.ghostty` 重写过，字号 13.5。

任一份覆盖另一份都会破坏它所在平台的行为，所以只能分叉——这也是模板里两段都很长
的原因。

## Linux 侧：与 ghostty 的逐项对齐

| 项 | ghostty | Alacritty | 备注 |
| --- | --- | --- | --- |
| `term` | `xterm-256color` | `[env] TERM` | |
| 字号 | 13.5 | `font.size` | |
| 字体 | FiraMono Nerd Font | 同 | 中文回退由 fontconfig 决定；本机 `fc-match "monospace:lang=zh-cn"` 首选 Sarasa Mono SC，与 ghostty 的顺序一致，所以不重复声明 |
| 粗体用亮色 | `bold-color = bright` | `draw_bold_text_with_bright_colors` | |
| 色板 | `palette 0-15` | `[colors.normal]` / `[colors.bright]` | |
| 光标 | `cursor-style = block` + blink | `[cursor]` | `blink_timeout = 0` 表示一直闪，与 ghostty 相同 |
| 失焦 | `unfocused-split-opacity` | `unfocused_hollow = false` | ghostty 不用「光标变空心」表达失焦，Alacritty 默认会，所以关掉 |
| padding | `window-padding-x/y = 2` | `[window] padding` | `dynamic_padding` 近似 `padding-balance` |
| 透明度 | `background-opacity = 1.0` | `opacity` | |
| 回滚 | `scrollback-limit`（约 15,000 行） | `history = 15000` | |
| 选区 | `selection-background` | `[colors.selection]` | |
| 搜索 | `search-background` / `search-selected-*` | `[colors.search.matches]` / `.focused_match` | |
| 复制即选中 | `copy-on-select = clipboard` | `[selection] save_to_clipboard` | |
| 自动重载 | 内置 | `live_config_reload` | |

Alacritty 独有的界面元素（搜索输入栏、hint 标签、vi 模式指示）ghostty 没有对应项，
沿用同一套主题色。

## Wayland 下的窗口装饰

Linux 那份**刻意不设** `decorations`：它在 Wayland 下不生效，而 niri 不提供服务端
装饰，于是 Alacritty 会走 winit/sctk-adwaita 的客户端装饰（Adwaita 风格标题栏 +
阴影）。实测把 `decorations` 设为 `"None"` 仍会创建 CSD frame——`WAYLAND_DEBUG` 里
照样出现 5 个 subsurface。

可调的只有 `decorations_theme_variant`（Dark/Light）。本机 `color-scheme =
'default'`、`gtk-theme = 'Adwaita'`，不显式设 Dark 的话标题栏是浅色的，和 `#282c34`
的内容反差明显。

按钮布局与标题字体不在这里配，读的是 `org.gnome.desktop.wm.preferences` 的
`button-layout` / `titlebar-font`（本机：`appmenu:close` / `Adwaita Sans Bold 11`）。

## 剪贴板

`save_to_clipboard = true` 对应 ghostty 的 `copy-on-select = clipboard`。

OSC 52 未显式设置，保持 Alacritty 默认的 OnlyCopy：允许远端写入剪贴板，但不允许
读取。ghostty 的 `clipboard-read = ask` 需要一个弹窗确认的中间态，Alacritty 没有。

## bell

不需要 `[bell]` 段：Alacritty 的默认值已经等价于 ghostty 的 `bell-features = false`
——visual bell duration = 0（不闪）、`bell.command = None`（不发声）。

## 键位

ghostty 的 `ctrl+v=paste_from_clipboard` 对应 `Ctrl+V → Paste`。

`ctrl+shift+v=unbind` 无法真正「透传」：Alacritty 尚未实现 kitty 键盘协议，发不出带
Shift 修饰的 CSI-u 序列，只能把 Ctrl+V 的编码（`0x16`）送给应用——而 pi 的
pasteImage 正是靠这个。

Windows 那份（`AppData/Roaming/alacritty/alacritty.toml`）把新建/退出绑成 Windows
习惯的 `Ctrl+N` / `Ctrl+W`。代价是这两个键不再送到 shell：Clink 的 readline 里
`Ctrl+W`（删前一个词）与 `Ctrl+N`（下一条历史）被 Alacritty 拦截。这是有意取舍——
用 Clink 的删词/翻历史换 Windows 式快捷键；要两全只能用 `Ctrl+Shift+N` /
`Ctrl+Shift+W`。

## 与 ghostty 的已知差异（在这个文件里消除不掉）

- **无原生分屏/标签**：`cmd+d` / `cmd+shift+d` / `cmd+shift+方向键`、
  `split-divider-color`、`unfocused-split-opacity` 都没有对应能力。
- **标题栏不可用 CSS 定制**：ghostty 的标题栏是 GTK headerbar，可用
  `gtk-toolbar-style` / `gtk-custom-css` 改几何与配色（见
  [ghostty-titlebar.md](ghostty-titlebar.md)）。Alacritty 的标题栏由
  winit/sctk-adwaita 绘制，只有 `decorations_theme_variant` 可调，没有配色、高度、
  圆角、按钮形状的配置项。
- 无字体 fallback 列表、`font-thicken`、`window-title-font-family`。
- 无 `shell-integration-features`（no-cursor / ssh-env / ssh-terminfo）。
- 无 `clipboard-trim-trailing-spaces`。
- `workdir` / `shell` 未固定，沿用 `$SHELL`，与 ghostty 相同。
- 关闭窗口无确认：两边一致（ghostty `confirm-close-surface = false`）。
- macOS 专属键位（`cmd+n` / `cmd+w` / `cmd+shift+arrow`）不适用于 Linux。
