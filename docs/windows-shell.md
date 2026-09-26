# Windows 的 shell 层：scoop + clink autorun + 用户环境变量

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
- `clink-completions` 的 scoop manifest 在 installer 里调 `clink installscripts <dir>`，所以
  `clink.lua` 里「手动遍历 `%USERPROFILE%/bin/clink-completions/`」那段被删掉了。

### 2. Clink 的加载 → `clink autorun install`

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

`AppData/Roaming/alacritty/alacritty.toml` 与 `dot_wezterm.lua` 现在是普通的
`cmd.exe`（`program = "cmd.exe"` / `default_prog = { 'cmd.exe' }`），不再 `cmd /k init.bat`；
显式写 `cmd` 是因为 Alacritty/WezTerm 在 Windows 的默认 shell 不保证是 cmd。

## 踩到的坑：批处理必须 CRLF

cmd.exe 的 `call :label` / `goto :label` 在 **LF-only** 的批处理文件里会找不到标签，报
`系统找不到指定的批处理标签 - XXX`。实测同一个 `bootstrap/windows.bat`：LF 版本在
`scoop buckets` 那步失败，转成 CRLF 后全部通过。

麻烦之处在于 `git` 的 `core.autocrlf=true` 只在检出时转，仓库里存的仍是 LF；而 bootstrap 的
用法是 `curl -fsSL … -o` 下载 **原始 blob**，拿到的就是 LF。所以仓库用 `.gitattributes` 把
CRLF 固化进 blob：

```
*.bat -text
*.cmd -text
```

`-text` 关闭 EOL 转换（而不是 `text eol=crlf`——那仍然存 LF）。CRLF 内容没有 NUL 字节，所以
git 仍按文本 diff，不影响审阅。

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

## 已知遗留

- `LS_COLORS` 在 `clink.lua`（`os.setenv`）与 `dot_wezterm.lua`（`set_environment_variables`）
  里各写了一份。可以收敛成一个用户环境变量，但它很长、`setx` 有长度限制，先用 PowerShell
  的 `SetEnvironmentVariable` 也不省事，暂时没动。
- `~/bin` 下还留着旧的便携版 exe（alacritty/starship/fzf/… ）与 `~/bin/clink`、`~/bin/NerdFont`。
  scoop shims 在用户 PATH 里排在 `~\bin` 前面，所以不会遮蔽；清不清由用户决定。

## 怎么验证

```bat
clink autorun show                 :: AutoRun 指向 …\clink.bat inject --autorun
reg query HKCU\Environment         :: LANG / PI_NERD_FONTS / FZF_COMPLETE_OPTS
scoop list                         :: 工具来自 scoop 而不是 %USERPROFILE%\bin
```

新开一个终端，确认：提示符是 starship、`chcp` 是 65001、`pstat` / `gl` / `ll` 等别名可用。
