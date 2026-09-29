# niri-session-mng

把当前 niri 会话存成一份 JSON 快照，下次在一个干净的会话里照它重建。

```bash
niri-session-mng save                # 采集当前会话
niri-session-mng show                # 打印快照
niri-session-mng restore --dry-run   # 只打印恢复计划
niri-session-mng restore             # 按快照重建
```

实际恢复按阶段执行：先启动所有 Ghostty 窗口并完成 cwd / 前台命令注入，再启动其他应用，
最后统一整理所有窗口的位置与宽度。为避免误操作破坏现有工作区，真正执行 restore 前要求桌面上
最多只有一个 Ghostty 窗口；超过一个会警告并拒绝。`restore --dry-run` 不受此限制。

只处理 `~/.config/niri-session-mng/config.toml` 白名单里的 app（ghostty / Chrome / Chromium /
zed / obsidian / Godot / Blender）。命令不绑键位，按需手动跑。

## 每个 app 恢复什么

| app | 恢复 | 靠谁 |
| --- | --- | --- |
| ghostty | 位置、列宽、shell 的工作目录 | 自己（`cd` 打进 shell） |
| ghostty 里的前台命令 | 见 `[rerun]` | 自己（打进 shell） |
| google-chrome | 位置；窗口与 tab | Chrome 的 `--restore-last-session` |
| chromium | 位置；窗口与 tab | Chromium 的 `--restore-last-session` |
| zed | 位置；项目 | Zed 的 autorestore |
| obsidian | 位置；vault | Obsidian 自己 |
| Godot Editor | 位置；项目 | 从运行中的 Godot 进程参数 / cwd 采集项目目录，并按窗口标题匹配；以 `--editor --path` 重开，没识别到则进项目管理器 |
| Blender | 位置 | 启动 Blender 默认场景；不恢复当前 `.blend` 文件 |

`[rerun]` 是「当时跑的命令 → 恢复时怎么跑」的表。默认两条：

- `"pi" = ["pi", "--continue"]` —— pi 按目录组织会话（`~/.pi/agent/sessions/` 下的目录名就是
  cwd，斜杠换成横线）。目录对了，`--continue` 就恢复到那个目录最近的会话。
- `"bun run dev" = [...]` 之类 —— 命中的命令原样重跑。

匹配先看整条命令行，再退回程序名，所以 `pi --model x` 也能命中 `"pi"`。

## 终端：cwd 和命令都得"打"进去

鬼后面这几条 ghostty 的实测行为，决定了终端只能这么恢复：

1. **`gtk-single-instance` 默认 `detect`**：只要命令行**带任何参数**（`--working-directory=`、
   `-e` 都算），ghostty 就**放弃单实例**，每个窗口一个进程。想保住单实例，启动命令行必须干净。
2. **cwd 不能靠启动参数传**：niri 的 spawn 会带 `DESKTOP_STARTUP_ID` / `XDG_ACTIVATION_TOKEN`，
   ghostty 据此认定"从启动器拉起"，`working-directory` 默认走 `home`；而且
   `window-inherit-working-directory = true` 会让新窗口继承**上一个聚焦窗口**的 cwd。
   两条加起来，`cd x && exec ghostty` 里的 `cd` 对窗口 cwd **无效**。

所以终端的恢复是：**裸启动 `ghostty`（一个参数都不带，加入单实例），再用虚拟键盘把
`cd <cwd>` 和前台命令打进那个新 shell**。实测可行，且 ghostty 全程只有一个进程。

注入用 `wtype`，两个坑：

- `wtype -k Return` **在这个版本的 wtype 上无效**（见下），换行必须作为文本的一部分发出去。
- 文本开头的字符容易丢（wtype 连接建立那一拍），所以习惯性垫一个空格。

## 窗口 ↔ shell：为什么绕道 waybar

niri 每个窗口只报一个 `pid`，而 ghostty 单实例下多个窗口共用一个进程，光靠 pid 分不出谁是谁。
能区分的只有 `title`，而标题会被 TUI 盖掉（pi 的 spinner、vim 的 `~`）。

waybar 的 `niri-windows` 模块已经填过这个坑：shell 在 `precmd` 里把自己的 pid 用不可见的 tag
字符写进标题，模块解析后缓存到 `~/.cache/waybar-niri-windows/announced.json`。TUI 盖掉标题
之后缓存还记得。

`save` 直接读这份缓存，沿用模块的校验（宣告的 pid 必须是该窗口 pid 的后代），再读
`/proc/<shell>/cwd` 和它前台进程组（`tpgid`）的 `cmdline`。**所以只有当窗口里真的有一个 shell
时才采得到 cwd 和前台命令** —— 见下面「世代问题」。细节见 [`waybar.md`](waybar.md)。

## workspace 按「序号」而不是 index

niri 的 workspace index 是动态的：空的会被删掉，后面的 index 整体前移。实测在一个有 4 个
workspace 的会话里 `focus-workspace 9`，niri 只新建**一个** workspace（落在第 5 个位置），并不
会把 1..9 都填出来。

所以快照记的是 **rank**（该 output 的第几个 workspace），恢复时按 rank 重建。

## 现状（2026-09-29，交接点）

**已经做完并 apply 的**：

- 配置加了 `terminal = true`；`dot_local/bin/executable_niri-session-mng` 里加了
  `terminal_command()` / `build_terminal()` / `wait_for_prompt()` / `type_command()`。
- 端到端跑通过一次：`restore` 后 `win24` 标题变成 `π - dotfiles`，说明"裸启动 + 注入"链路成立。
- 重启实测：**ghostty 确实只有一个进程**（5 个窗口共用 pid 1668）✓，大部分窗口恢复正确 ✓。

**当前代码里已知的问题与待复测项**：

1. **注入长文本曾掉字符**。旧版 `type_command()` 把 `cd <cwd> && <命令>` 一次性交给 wtype，实测
   会中间丢键：
   - 本机报过 `cd /home/jwu/work  pi --continue`（`&&` 变成了两个空格）→ `cd: too many arguments`
   - 也见过标题停在 `' cd /home/jwu/dev/ai-canvas && bun r'`（尾部 `un dev` 丢了），命令没执行
   **放大的因素**：`&` 在 US 布局是 Shift+7 的组合键，最容易掉。

   本机 `wtype 0.4-2` 已支持 `-d <ms>`，所以先不换工具、不改命令拆分：`type_command()` 用
   `wtype -d 10`。对照测试中，默认 0ms 的 wtype 曾把 `WTYPE_OK` 截成 `WTYPE_`；加 `-d 10`
   后，在新建 Ghostty 窗口里完整输入了含 `&&` 的 `cd /home/jwu/dev/ai-canvas && bun run dev`。
   `ydotool type -d 30` 也能完整输入，但需要额外运行 `ydotoold`，当前没有证据表明值得切换。
   这些测试尚未复测真正的「第一个恢复窗口」启动竞态。

2. **Chrome 窗口配对**：`--restore-last-session` 一次恢复多个窗口时，Chrome 决定它们的创建顺序，
   不能仅按窗口 id 配对。现在会先刷新新窗口标题并按快照中的 title 一对一匹配，剩余未匹配的
   再按快照顺序与窗口 id 升序兜底。标题重复或 Chrome 改了标题时，兜底配对仍可能不准确。

**尚未处理 / 待确认**：

- `wait_for_prompt()` 目前是「等 title 非空 + `PROMPT_SETTLE = 1.5s`」。够用，但没有真正的
  "shell 到提示符"信号，慢启动的 shell 理论上会漏。先观察。
- 浮动窗口只回到 workspace，位置不恢复。
- 只处理平铺窗口的列序；同一列多窗口的**列内顺序**不保证。

## 世代问题（容易踩）

`save` 采不到「没有 shell 的窗口」。所以：

- **旧版 restore 出来的终端**（用 `--working-directory=` + `-e` 启动的那些）里面**没有 shell**，
  重新 `save` 时它们只会被记成「cwd = `$HOME`、没有前台命令」，再 restore 就是空壳。
- 判断办法：`ps -o args -p <ghostty_pid>`，命令行里带 `--working-directory=` 或 `-e` 的就是旧世代。
- 因此**第一次用新机制 save 之前**，终端最好是手动开的（或在上一轮由新机制恢复的）。

## 排查用的实测结论（都验证过，别再重跑）

- `niri msg -j workspaces` / `windows` / `outputs`：布局的唯一来源，**用 JSON**，人类可读输出不稳。
- `set-column-width` 只认**纯整数**逻辑像素（`800`）。`800px` 是解析错误（被 `check=False` 吞掉，
  窗口停在 preset 宽度），`50%` 是比例。
- ghostty 的 master fd 可以通过 `/proc/<ghostty_pid>/fd/<n>` 以 `O_WRONLY` 打开写入（`ptrace_scope=1`
  也放行，同 uid 且进程 dumpable），`fdinfo` 里的 `tty-index` 就是对应的 pts 号。
  **这条没走**：虚拟键盘方案更简单，不需要碰 ghostty 的私有 fd。
- niri 实现了 `zwp_virtual_keyboard_manager_v1`，`wtype` 可用。
