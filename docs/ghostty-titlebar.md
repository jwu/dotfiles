# Ghostty GTK 标题栏

`config.ghostty` 里的 `gtk-custom-css` 加载 `titlebar.css`（几何）和其中一个
`titlebar-colors-*.css`（配色）。改完用 `Ctrl+Shift+,` 重载，CSS 对已开窗口立即生效。

## 几何

`min-height` 只是容器的下限，容器永远不会比内容矮。Adwaita 有三层相关「地板」：

| 元素 | Adwaita | 这里 |
| --- | --- | --- |
| `headerbar`（容器） | 46px | 22px |
| `button`（图标按钮） | 24px，padding 4px 9px | 18px，padding 1px 4px |
| `windowcontrols button > image`（圆点） | 30px | 18px |

16px 图标和按钮内边距都保留，只去掉多余的高度。

调试：`GTK_DEBUG=interactive ghostty`，选中 headerbar 看实际生效的规则。

## 直角

Adwaita 只圆上面两个角（`window.csd`），并只在窗口平铺/最大化时清零；这里直接清零。全局
那份在 `~/.config/gtk-4.0/gtk.css`，`titlebar.css` 里保留一份是为了这份配置能单独使用。

## Undershoot 线

`gtk-toolbar-style = flat` 时，libadwaita 会给 `AdwToolbarView` 加上 `.undershoot-top`
类，于是终端那块 `GtkScrolledWindow` 顶部的 undershoot 被上色成 1px 硬线 + 4px 渐变——
就是标题栏下面那条暗线。

它不是标题栏的边框，所以：

- 新窗口（终端还没滚出过行）看不到它；
- 一旦有 scrollback（`vadjustment > lower`）就出现，滚回最顶端（`Ctrl+Shift+Home`）又
  消失；
- 换成 `raised` 只是把它换成常亮的同款阴影，`scrollbar = never` 也没用。

把 undershoot 选择器上的 `box-shadow` / `background` 置空即可去掉。

## 配色预设

用 `config.ghostty` 的 `gtk-custom-css` 启用其中一个：

| 文件 | 标题栏 | 文字 | 失焦 |
| --- | --- | --- | --- |
| `titlebar-colors-onedark.css`（当前） | `#282c34` | `#abb2bf` | `#24282f` |
| `titlebar-colors-onedark-purple.css` | `#c678dd` | `#282c34` | `#b26cc7` |
| `titlebar-colors-default.css` | `#222226` | `#ffffff` | `#1e1e22` |

- 紫底对比度约 4.75:1；若文字改用终端前景 `#abb2bf` 只有 1.38:1，会发灰难认，所以刻意
  没用它。
- `default.css` 把 Ghostty 原本自动算出的 chrome 配色（2026-09-22 实测）显式保存下来，
  方便随时切回，也能防止 libadwaita / Ghostty 升级后这套颜色变了。
- 在用户样式表里覆盖 libadwaita 的 `--headerbar-*` 变量无效（实测），所以直接写属性，并
  补 `:backdrop` 保留失焦时略暗的层次。
- `window.csd` 底色跟随标题栏，用来消掉标题栏上方约 2px 的窗口底色色差（终端不透明时不
  外露；开 `background-opacity` 后会从缝隙透出来）。
- 不想要最顶上那 1px 描边时，解开 `window.csd { outline: none }`。
- 另有更暗的紫色方案：标题栏 `#5c3a6e` + 文字 `#abb2bf`（4.31:1），只需改一个变量值。

## 更扁的极端档

`titlebar.css` 里注释掉的极端档把标题栏压到 8px，但只能再省约 10px：再往下是 16px 图标、
窗口标题文字、SplitButton 箭头三块地板。图标尺寸不影响高度，所以没动它。

## 副标题（第二行）：评估过，不启用

标题栏是 `Adw.WindowTitle`，天生有 `title` 和 `subtitle` 两行，但 `subtitle` 只能由
`window-subtitle` 控制（`false` / `working-directory`），内容是当前目录；VT/OSC 层没有设置
它的序列，GTK 层也只有 `closureSubtitle` 一个写入点。所以它既放不了 ssh 信息，也不是个能
自定义的槽位。

试过 `working-directory`：能显示，22px 扁平高度也放得下两行（一开始看不到是旧窗口没重载
配置，不是高度问题）。但路径**永远是绝对路径**——Ghostty 取 OSC 7 的 `uri.path`，URI 的
path 组件总以 `/` 开头（实测发 `kitty-shell-cwd://host/~/foo` 出来是 `/~/foo`；发
`kitty-shell-cwd://host~/foo` 则 host 变成 `host~`、通不过本地主机校验被丢弃），缩不成
`~/`。加上 `headerbar` 那条 `color` 会把它顶上标题色、还得单独写 CSS 调暗，收益不值，所以
不启用。想要 `~/` 只能改上游 `closureSubtitle`，或把目录放进标题（title feature 用 zsh 的
`%(4~|…/%3~|%~)`，本来就缩写）。

## ssh 时的标题

需求是「**只在远程**显示 ssh 标记」。Ghostty 做不到按 ssh 状态改标题栏**颜色**：颜色全来自
应用级静态 `gtk-custom-css`（即上面那几份 `titlebar-colors-*.css`），GTK CSS 没有按标题内容
匹配的选择器，Ghostty 也没把「是否在 ssh」暴露给 UI——v1.3.1 的 `src/apprt/gtk` 里搜不到任何
ssh 状态。所以只能在标题**内容**上做，而且判定要放在**远程**：`SSH_CONNECTION` 只在远端才有。

分两条路，因为两端的标题归属不同：

**远程 zsh**：ssh 过去后 `GHOSTTY_RESOURCES_DIR` 不会被 `ssh-env` 传到远端，Ghostty 的 shell
集成在远程没加载，标题只由 oh-my-zsh 设。omz 的 `omz_termsupport_precmd` 每次 precmd 都读
`ZSH_THEME_TERM_TITLE_IDLE`（默认 `%n@%m:%~`），所以在 `dot_zshrc.tmpl` 里 source omz 之后
按需覆盖它：

```zsh
[[ -n ${SSH_CONNECTION:-} ]] && ZSH_THEME_TERM_TITLE_IDLE='🖥 %n@%m:%~'
```

本地 shell 没有 `SSH_CONNECTION`，格式保持原样，于是标记天然只出现在远程。

**远程 pi**：pi 是 TUI，自己控制标题。pi-config 的 `terminal-signals` 扩展在 `SSH_CONNECTION`
/ `SSH_TTY` 存在时给标题加 `🖥 <远程主机名> ` 前缀。这里有个坑：**pi 核心也有一个
`updateTerminalTitle()`**，把标题设成 `π - <session> - <cwd>`，触发点是 `session_info_changed`
事件；而该事件的扩展 handler 先于核心的 UI handler 跑，所以扩展得**延后一拍**
（`setTimeout(…, 0)`）再重设自己的标题，否则空闲时会被核心盖掉——现象就是「只有对话时才有
标记」，因为工作时 spinner 每 80ms 刷一次。

图标 `🖥`（U+1F5A5）走 fontconfig 回退到 `Noto Emoji`，是**单色**、与文字同色（加 `VS16`
无效）；想要彩色就换 `💻`（`Noto Color Emoji`）。

标题栏文字颜色仍是 `titlebar-colors-*.css` 里的主题色——上游一天不提供 ssh 状态，就一天没
法只给这段信息上色。别的远程程序（如 nvim）照样会覆盖标题，目前不管。
