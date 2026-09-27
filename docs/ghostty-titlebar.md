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

需求是「处于 ssh 会话时，标题栏显示 ssh 信息」。Ghostty 做不到按 ssh 状态改标题栏
**颜色**：颜色全部来自应用级静态 `gtk-custom-css`（即上面那几份 `titlebar-colors-*.css`）；
GTK CSS 没有按标题内容匹配的选择器，Ghostty 也没把「是否在 ssh」暴露给 UI——v1.3.1 的
`src/apprt/gtk`（`window.zig` / `surface.zig` / `App.zig` / `window.blp`）里搜不到任何 ssh
状态。

于是只在**内容**上做文章：`dot_zshrc.tmpl` 里定义 `_ghostty_ssh_title`，本地敲 `ssh` 时把
标题写成 `🖥 <目标>`。

**难点是顺序。** `preexec_functions` 里同时有 oh-my-zsh、starship 和 Ghostty 自己的
钩子，最后执行的赢。Ghostty 的钩子不是 `.zshrc` 时注册的：`.zshenv` 注入的
`_ghostty_deferred_init` 在**第一次 precmd** 才定义 `_ghostty_preexec`、追加到数组末尾，
而它的 `functions[_ghostty_preexec]+="..."` 会把标题设成整条命令。所以 `.zshrc` 里写死的
一次性注册会被它盖掉（实测出来标题正好是完整命令行）。

办法是注册一个 precmd 钩子，每次把 `_ghostty_ssh_title` 移到 `preexec_functions` 末尾：
集成只在 deferred init 里追加一次，之后不再动这个数组，所以稳定。其余几点：

- ssh 是前台阻塞进程，钩子设一次标题就够；ssh 退出后由 Ghostty 自己的 `precmd` 把标题
  设回 cwd，不需要我们收尾。
- 目标是从命令行里跳过 `ssh` 选项取到的那个词，所以 `ssh -p 22 host` 显示 `host`，
  `ssh user@host` 原样显示（保留 `~/.ssh/config` 里的别名，不解析成真实主机名）。
- 图标 `🖥`（U+1F5A5）走 fontconfig 回退到 `Noto Emoji`，所以是**单色**、与文字同色（加
  `VS16` 无效）；想要彩色就换成 `💻`（走 `Noto Color Emoji`）。改 `_ghostty_ssh_title`
  里的 `printf` 即可。

标题栏文字本身仍是 `titlebar-colors-*.css` 里定的主题色——上游一天不提供 ssh 状态，就
一天没法只让这段信息变色。

本地钩子只能管「敲下 ssh」到「远程启动 pi」这段：pi 是 TUI，会用自己的 OSC 2 把标题设成
`π - <目录>`。这一段由 pi-config 的 `terminal-signals` 扩展接手——它在 `SSH_CONNECTION`
存在时把 `🖥 <远程主机名>` 前缀进 pi 的标题，所以远程跑 pi 时标记仍在。别的远程程序（如
nvim）还是会覆盖标题，目前不管。
