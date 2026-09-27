# Windows 的 shell 层：scoop + Clink 的 session.cmd + 用户环境变量

这份文档解释 Windows 上「终端怎么起来、Clink 怎么加载、环境变量放哪、别名在哪」的最终形态，
以及为什么不再需要原来 `jwu/configs` 那套手写脚本。`bootstrap/windows.bat`、`.chezmoiignore`
和 `AppData/Local/clink/**` 的选择都出自这里。

## 起点：旧 configs 的做法

`jwu/configs` 的 Windows 流程是：

```
clone configs → win/install.bat（把便携工具下载到 %USERPROFILE%\bin）
             → win/config.bat（生成 alacritty/nvim/neovide/wezterm 的指针文件）
             → 终端用 cmd /k init.bat 拉起；init.bat 负责 chcp、PATH、doskey 别名、clink inject
```

`config.bat` 已被 chezmoi 的真实内容取代。剩下的 `install.bat` / `init.bat` / `cmds/*.cmd` 在
下一节被逐个替换，`win/` 目录现在整个删除。

## 现在分四层

### 1. 工具 → scoop

`bootstrap/windows.bat` 里是一份 scoop 清单，不再有自定义下载器：

| 来源 | 包 |
| --- | --- |
| `main` | `clink` `clink-completions` `starship` `fzf` `zoxide` `fd` `bat` `delta` `ripgrep` `eza` `uutils-coreutils` |
| `extras` | `alacritty` |
| `nerd-fonts` | `FiraMono-NF` |

- `uutils-coreutils` 把 `ls`/`cat`/`cp`/`rm`/`mv`/`ln`/`pwd` … 逐个 shim 到 PATH（**没有** `coreutils`
  这个多合一命令），所以旧别名里 `coreutils X` 这层间接不再需要。
- `FiraMono-NF` 在 Win10 1809+ 上是 **per-user** 安装（`%LOCALAPPDATA%\Microsoft\Windows\Fonts`
  + HKCU），所以**不再需要管理员**。旧的 `win/cmds/addfonts.cmd` 写 `%SystemRoot%\Fonts` 与
  HKLM，那才是唯一需要提权的东西。
- `clink-completions` 的 scoop manifest 在 installer 里调 `clink installscripts <dir>`，
  `bootstrap/windows.bat` 再幂等地重申一次；`clink.lua` 里「手动遍历
  `%USERPROFILE%/bin/clink-completions/`」那段因此删掉了。为什么不能只保留它的
  `completions\` 子目录，见下面「踩到的坑：只留 completions 目录吃掉了所有补全」。

### 2. Clink 的加载 → 由终端执行 `session.cmd`

> **最终形态（走过弯路后）**：试过 `clink autorun install`（写 cmd 的 AutoRun）。clink 确实会在
> **每个** cmd 里注入、脚本也确实全部加载（`clink info` 的 `injected : clink_dll_x64.dll`，日志
> `Loaded 24 Lua scripts`，`1+4+19` 对得上），但在 Win11 + ConPTY 终端里 starship 始终没接管
> 提示符——而同一份 `clink.lua` + 同一个 starship 在旧 `init.bat` 下是正常的。关键差别：
> `init.bat` 是被 cmd 用 `/k` 执行的，它的 `set` **落在 cmd 自己的环境块里**，而 Clink 的
> `os.setenv` **不会**（实测同一窗口 `echo %STARSHIP_CONFIG%` 仍为空，只对 Clink 派生的子进程
> 可见）。于是回到旧结构：终端执行
> `cmd /s /k "%LOCALAPPDATA%\clink\session.cmd"`，由该脚本负责 `chcp`、`set STARSHIP_CONFIG`
> 等环境变量、并 `clink inject --quiet --profile/--scripts "%LOCALAPPDATA%\clink"`。
> AutoRun 不再使用（`clink autorun uninstall`）。下面保留 autorun 的记录，作为「试过、为何放弃」。

旧做法是 `clink inject`（**session-only**：只注入当前进程，不落任何持久状态），由终端
`cmd /k init.bat` 触发。官方机制是 `clink autorun install`，它写：

```
HKCU\Software\Microsoft\Command Processor\AutoRun = "…\clink.bat" inject --autorun
```

于是**每个 cmd**（包括 VS Code 终端、Win+R）都有 Clink，不再依赖终端配置。撤销用
`clink autorun uninstall`，`clink autorun show` 看当前值。

`clink.path` 没设时，脚本目录 = **DLL 目录 + profile 目录**（`clink info` 可见），而 profile
目录就是 `%LOCALAPPDATA%\clink`。所以旧 `init.bat` 传的
`--profile/--scripts "%LOCALAPPDATA%\clink"` 是冗余的——那正是默认值。

### 3. 环境变量 → `HKCU\Environment`

`bootstrap/windows.bat` 用 `setx` 写三个用户级变量，所有进程都看得到，而不是只在被脚本拉起的
那个终端里：

```
LANG=en_US.utf8        PI_NERD_FONTS=1        FZF_COMPLETE_OPTS=-e
```

`PATH` 不用动：`HKCU\Environment\Path` 里早就有 `%USERPROFILE%\bin` 与 scoop shims，旧 `init.bat`
里那行是冗余的。

### 4. 会话内的两件事 → `AppData/Local/clink/session.lua`

`chcp` 和 doskey 别名本来是会话级的，没有注册表可以表达，于是放进一个 Clink Lua 脚本
（chezmoi 部署到 `%LOCALAPPDATA%\clink`，由 Clink 自动加载）：

- `os.execute('>nul 2>nul chcp 65001')`：cmd 默认是 OEM 代码页（本机 936），不转 UTF-8 的话
  eza/starship 的中文输出会乱码。`chcp` 改的是共享控制台，所以注入 Clink 的那个 cmd 也一起生效。
  这个写法抄自 `fzf.lua` 自己的 `chcp()`。
- 别名：Clink **没有** `clink.setalias` API，所以用 `clink.onfilterinput` 做命令首词替换
  （`zoxide.lua` 就是这么做的）。因为 scoop 的 uutils-coreutils 已经把 `ln`/`mv`/`rm`/`cp`/`pwd`
  放上 PATH，别名里只保留真正会**改写命令**的那些：`clear` `open` `vi` `gl` `ls` `ll` `la` `lt`
  `pon` `poff` `pstat`。`mkdir`/`rmdir` 也不再别名——它们是 cmd 内建，会盖过 PATH 上的同名 exe。

### 终端

`AppData/Roaming/alacritty/alacritty.toml` 与 `dot_wezterm.lua` 现在都起
`cmd.exe /s /k "%LOCALAPPDATA%\clink\session.cmd"`（`args` 与 `default_prog`）：位置从旧的
`init.bat` 换成了 chezmoi 部署的 `session.cmd`，而那正是让 `set` 落进 cmd 环境块的一层。显式
写 `cmd` 是因为 Alacritty/WezTerm 在 Windows 的默认 shell 不保证是 cmd。

## 踩到的坑：只留 completions 目录吃掉了所有补全

24804d9 为了「lazy」把接线改成：`bootstrap/windows.bat` 用 `clink uninstallscripts` 删掉
scoop 的注册，`session.cmd` 把 `%CLINK_COMPLETIONS_DIR%` 指向包的 `completions\` 子目录，
`--scripts` 只指 `%LOCALAPPDATA%\clink`。补全因此整体消失，实测证据：

- `HKCU\Software\Clink\InstalledScripts` 是空的（注册被删掉了）；
- `%LOCALAPPDATA%\clink\clink.log` 只有 `Loaded 4 Lua scripts`，完整状态应是 24（`1+4+19`，见上面 autorun 时代的记录）；
- 包的 19 个顶层脚本（`git.lua` / `npm.lua` / `pip.lua` / `scoop.lua` / `ssh.lua` /
  `kubectl.lua` …）不再加载，而 `!init.lua` 还负责把 `modules/` 追加进 `package.path`；
- `completions\` 那 48 个脚本大量 `require('arghelper')` / `require('clink_version')`，
  `!init.lua` 没跑 → 连惰性加载也直接失败。

Clink 文档的 [Completion directories](https://chrisant996.github.io/clink/clink.html#completion-directories)
说得很明确：`completions\` 只适合「除了补全不做别的」的脚本，clink-completions 的脚本必须放
普通脚本目录；而且这个 `completions\` 子目录只有在**它所在的包目录被 `clink installscripts`
注册之后**才会被发现。只留子目录等于两头都不要。

修法：`bootstrap/windows.bat` 的 `:CLINK_SCRIPTS` 改成 `clink installscripts`，`session.cmd`
里那行 `CLINK_COMPLETIONS_DIR` 删掉。注册写的是注册表
（`HKCU\Software\Clink\InstalledScripts`），不是 profile 文件，所以 chezmoi 部署的
`clink_settings` 不会把它覆盖回去。

## 踩到的坑：批处理必须 CRLF

cmd.exe 的 `call :label` / `goto :label` 在 **LF-only** 的批处理文件里会找不到标签，报
`系统找不到指定的批处理标签 - XXX`。实测同一个 `bootstrap/windows.bat`：LF 版本在
`scoop buckets` 那步失败，转成 CRLF 后全部通过。

麻烦之处在于 `git` 的 `core.autocrlf=true` 只在检出时转，仓库里存的仍是 LF；而 bootstrap 的
用法是 `curl -fsSL … -o` 下载 **原始 blob**，拿到的就是 LF。所以仓库用 `.gitattributes` 关掉
这两个扩展名的 EOL 转换：

```
*.bat -text
*.cmd -text
```

`-text` 只是**禁止转换**（用 `text eol=crlf` 没用——那仍然把 LF 存进 blob）。blob 里的 CRLF
来自提交时工作区本身就是 CRLF，两件事得同时成立。CRLF 内容没有 NUL 字节，所以 git 仍按
文本 diff，不影响审阅。

`AppData/Local/clink/session.cmd` 是个例外：它的 blob 实际上是 **LF**。它没有
`call :label` / `goto`，LF 照样能跑，`-text` 只保证 git 不去动它。真正需要 CRLF 的只有
`bootstrap/windows.bat`。

## 踩到的坑：默认配置路径不能靠猜

最初假设 starship 在 Windows 上读 `%APPDATA%\starship.toml`，于是把它做成 Windows 专有目标
（`AppData/Roaming/starship.toml`），并从 `init.bat` 里删掉了 `STARSHIP_CONFIG`。结果新终端里
starship 用的是内置默认值（提示符在，但 config 不生效）。

实测（在 `STARSHIP_CONFIG` 与 `HOME` 都清掉的 plain cmd 里）：

- `%APPDATA%\starship.toml` 存在时，`starship print-config` 仍是 `add_newline = true`（**不读**）
- `~/.config/starship.toml` 存在时，`add_newline = false`（**读**）

也就是说 starship 在 Windows 上走的是 `%USERPROFILE%\.config\starship.toml`，不是 Roaming。
旧机器之所以没事，是因为旧 `init.bat` 显式 `set STARSHIP_CONFIG=%MY_CONFIGS%\starship.toml`
指向仓库副本——换掉那套脚本后就暴露了。

修法：Windows 回到与 Unix 同一个目标 `~/.config/starship.toml`，用
`dot_config/starship.toml.tmpl` 的三分支（`add_newline` 只在 Windows 为 `false`；提示符 `>`
只在 Linux，`❯` 给 macOS 与 Windows）渲染，`AppData/Roaming/starship.toml` 删除。
三平台渲染逐字节一致。

**教训**：迁移一个 app 的配置时别假设 Windows 的默认路径，用 `print-config` 或临时文件实测。
`%APPDATA%` 只对一部分 app 成立（alacritty、neovide、Zed、gitui、yazi、Rime），starship 不在其中；
`~/.config` 也不是“Unix 专用”。

而且**光靠默认路径还不够**：旧 `init.bat` 每一次都 `set STARSHIP_CONFIG`，所以任何从旧会话
继承下来的 `STARSHIP_CONFIG`（指向已删的 `~/bin/configs/win/starship.toml`）都会盖过默认路径，
让 starship 退回内置默认值。

这里有一个关键区别：**`init.bat` 是被 cmd 用 `/k` 执行的，所以它的 `set` 真的落在那个 cmd 的
环境块里**；而 clink 的 `os.setenv` **不改 cmd 的环境块**——实测 `clink.lua` 里设过
`STARSHIP_CONFIG`，同一窗口 `echo %STARSHIP_CONFIG%` 仍是空的（只对 clink 自己派生的子进程
可见）。所以环境变量必须两路都做：

- `bootstrap/windows.bat` 用 `setx` 写真正的用户级变量（`LANG` / `PI_NERD_FONTS` /
  `FZF_COMPLETE_OPTS` / `STARSHIP_CONFIG`），cmd 与 starship 都看得到；
- `clink.lua` 再用 `os.setenv` 钉一遍，挡住继承来的旧值（对 clink 派生的子进程有效）。

注意 `setx` 会把引号**当成值的一部分**存起来——从 `cmd /c` 里配要注意（本仓库的 bootstrap
是 `.bat`，`setx VAR "..."` 会正常剥掉引号；实测手工从 git-bash 里调时引号被存进了值里）。

## 已知遗留

- `LS_COLORS` 在 `clink.lua`（`os.setenv`）与 `dot_wezterm.lua`（`set_environment_variables`）
  里各写了一份。可以收敛成一个用户环境变量，但它很长、`setx` 有长度限制，先用 PowerShell
  的 `SetEnvironmentVariable` 也不省事，暂时没动。
- `~/bin` 下与 scoop 重复的便携版 exe（alacritty/starship/fzf/…）、`~/bin/clink` 与
  `~/bin/NerdFont` 已于 2026-09-27 删除；非 scoop 工具（nvim、nvm、mpv、zig、yazi…）保留。

## 怎么验证

```bat
reg query "HKCU\Software\Microsoft\Command Processor" /v AutoRun  :: 应当不存在：AutoRun 方案已弃用
clink installscripts --list        :: 应列出 scoop\apps\clink-completions\current
clink info                         :: scripts 行除了 DLL 与 profile 目录，还应列出包目录
type "%LOCALAPPDATA%\clink\session.cmd"                          :: 终端注入 Clink 的入口
reg query HKCU\Environment         :: LANG / PI_NERD_FONTS / FZF_COMPLETE_OPTS
scoop list                         :: 工具来自 scoop 而不是 %USERPROFILE%\bin
```

新开一个终端，确认：提示符是 starship、`chcp` 是 65001、`pstat` / `gl` / `ll` 等别名可用，
补全也在（`clink.log` 里是 `Loaded 24 Lua scripts` 而不是 4）。
