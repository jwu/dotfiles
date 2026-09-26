# 在另一台机器上接入 dotfiles

> **读者：运行在 macOS 或 Windows 机器上的 coding agent。**
> 这份文档是自包含的。你不需要看到过铺设这个仓库的那次会话，但你需要能读
> `README.md`（那里有完整的设计推导），以及能在这个仓库里执行 git 与 shell 命令。
>
> 写这份文档的机器是 **Linux（Arch）**，那里的迁移已经**完成并验证**：67 个文件由 chezmoi
> 管理，`chezmoi diff --include=files` 为 0，二次 apply 输出 0 行。**把那台机器当作参考实现**，
> 当本文与现状冲突时，以 `README.md` 和实际的源文件为准。
>
> **macOS 已于 2026-09-26 接入完成**（Apple Silicon，macOS 27.0，提交 `ac55046`..`e489f45`）。
> 那次接入的结论已经回写进本文：§5 原来列的三处缺口全部修掉，并新记录了两处当时才发现的
> 系统性问题。Windows 侧尚未开始。
>
> 该区间的 hash 在 2026-09-26 的历史重写后已更新（git 个人层被摘出仓库并从历史里抹掉）；
> 若你手上的 clone 是重写之前拉的，需要重新 clone 或 `git fetch && git reset --hard origin/main`。

---

## 0. 先读这三件事

1. **`README.md`** —— 仓库的完整设计。至少读「仓库边界」「源布局与来源映射」「模板化的文件」
   「属性前缀会进源路径」「脚本层：`run_` 前缀」几节。
2. **本文第 2 节的铁律** —— 违反它会造成不可逆的数据丢失。
3. **你所在平台的现状** —— 那台机器上的家目录配置，很可能和你将要 apply 的源**不一致**。

---

## 1. 背景（30 秒）

`jwu/dotfiles` 是一个 chezmoi 源仓库，取代了原先的 `jwu/configs`、`jwu/desktop-settings` 和
`jwu/install-arch`（这三个已退役，本地目录已删，GitHub 上仍存在）。

职责被切成三层：

| 层 | 手段 | 需要 root |
| --- | --- | --- |
| 配置同步 | `chezmoi apply`（67 个 Linux 目标 + 3 个 macOS + 10 个 Windows） | 否 |
| 装机（一次性） | `bootstrap/<platform>.sh` | 是 |
| 运行时动作 | 6 个 `run_*` 脚本，按内容 hash 记账 | 否 |

**关键**：源里 macOS / Windows 的那 13 个配置，是在 Linux 机器上**从旧仓库的副本复制进来的**，
不是从你那台机器的家目录导入的。所以它们**可能比你的家目录旧**。

---

## 2. 铁律：对账之前不要 `apply`

```bash
# 错的顺序（会覆盖机器上更新的配置）
chezmoi init --apply

# 对的顺序
chezmoi init
chezmoi diff --include=files      # 先看会改什么
```

原因：`apply` 是「让家目录匹配源」。如果源里的那一份比你家目录旧，apply 就会用旧内容**覆盖**
你机器上更新的配置。Linux 那边已经证实过这种漂移真实存在——`~/.config/git/config` 比仓库版本
多出 `gh auth login` 写入的 credential 段。

**每一条 diff 都要判断方向，不能默认「源是对的」。**

---

## 3. 步骤

### 3.1 安装 chezmoi

**macOS**

```bash
brew install chezmoi
```

**Windows**（PowerShell，任选其一）

```powershell
winget install twpayne.chezmoi
# 或： scoop install chezmoi
```

### 3.2 克隆到固定路径

路径**不能随意选**：`pi-config` 的 `settings.json` 用绝对路径指向 `~/bin/pi-config/extensions`
（见 §5.3），而 `run_once_after_50-pi-config.sh` 只会 clone 到 `~/bin/pi-config`。

```bash
# macOS
mkdir -p ~/bin
git clone git@github.com:jwu/dotfiles.git ~/bin/dotfiles

# Windows（%USERPROFILE%\bin\dotfiles，与原来的 configs 布局一致）
git clone git@github.com:jwu/dotfiles.git "$env:USERPROFILE\bin\dotfiles"
```

### 3.3 写 `sourceDir`

源不在 chezmoi 的默认位置（`~/.local/share/chezmoi`），所以要显式告诉它。**这是必须的**，
Linux 那边第一次不带 `--source` 跑 `chezmoi apply` 就报过
`stat /home/jwu/.local/share/chezmoi: no such file or directory`。

**macOS** — `~/.config/chezmoi/chezmoi.toml`：

```toml
sourceDir = "/Users/<你的用户名>/bin/dotfiles"
```

**Windows** — `%USERPROFILE%\.config\chezmoi\chezmoi.toml`（用正斜杠或转义反斜杠）：

```toml
sourceDir = "C:/Users/<你的用户名>/bin/dotfiles"
```

验证：`chezmoi source-path` 应输出你刚写的路径。

### 3.4 对账（这一步是本次任务的核心）

```bash
chezmoi diff --include=files
chezmoi managed --include=files      # 源认为它管着哪些文件
```

对**每一个**有差异的文件，判断方向：

| 情况 | 判据 | 处理 |
| --- | --- | --- |
| 家目录版本更新 | 家目录的 mtime 更晚，或内容里含本机特有的东西（路径、凭据、hostname） | **`chezmoi add <文件>`** 收进源，把家目录版本变成真源 |
| 源版本更新 | 源里的内容确实是你想要的、家目录那份是旧的残留 | 保留源版本，稍后 `apply` 覆盖 |
| 只在家目录存在 | `chezmoi managed` 里没有，但文件确实是你维护的配置 | `chezmoi add` 纳入（注意先读 §4 的排除清单） |
| 只在源里存在 | 文件在家目录不存在 | 正常（平台专有文件，如 macOS 的 `dot_aerospace.toml`） |

**把你判断出的漂移清单连同证据（mtime、diff 摘要）报告给用户**，`chezmoi add` 之前请用户确认。
不要自己替用户决定哪一份是他想要的。

### 3.5 补齐平台缺口（见 §5）

§5 列出的缺口要**在 apply 之前处理掉**，否则 apply 会失败（chezmoi 是 fail-fast：一个 `run_*`
脚本失败，后面所有脚本都不再执行）。

macOS 侧的那几处已经修好了，所以现在照本文执行不会再撞上它们。§5 保留下来是为了记录问题的
形状（Windows 侧可能还有同类问题），以及那两处当时才发现的系统性不一致。

### 3.6 apply 与验证

```bash
chezmoi apply -v
```

- macOS 上不会遇到 sudo：所有需要 root 的动作都在 `bootstrap/` 里，而 `run_*` 脚本不需要 root。
- 若某个 `run_*` 失败，**不要**简单重跑：chezmoi 会把**失败的**脚本也记进 `scriptState`，
  失败的脚本不会自动重试。修好之后要先清记账：

  ```bash
  chezmoi state delete-bucket --bucket=scriptState
  chezmoi apply -v
  ```

验证：

```bash
chezmoi diff --include=files        # 应为 0
chezmoi apply -v                    # 再跑一次，应输出 0 行（彻底 no-op）
```

### 3.7 把改动回写到仓库

你在对账时可能 `chezmoi add` 了新文件、修了脚本。这些改动**属于仓库**，要提交：

```bash
cd ~/bin/dotfiles
git pull --ff-only          # 先拉，避免和 Linux 机器的改动打架
git add -A
git commit -m "<平台>: <做了什么>"
git push
```

**提交信息用英文**，风格参考 `git log`：短句、说明「为什么」而不是「改了什么」。

如果 `git pull` 出现冲突：**停下来报告用户**，不要自作主张地解决——两边都可能是对的。
`git push` 若报 SSL 错误，见 §6。

---

## 4. 不要纳管的东西

`README.md` 里「pi 的可变状态」「fcitx5 的运行时边界」两节有完整清单。摘要：

| 类型 | 例子 | 原因 |
| --- | --- | --- |
| 凭据 | `~/.pi/agent/auth.json` | 密钥 |
| 工具自己写的状态 | `~/.pi/agent/mcp.json`、`extensions/*.json`、`settings.json` | pi / 插件会改写，纳入后 `apply` 会抹掉 |
| 运行时产物 | `~/.local/share/fcitx5/rime/`（156 MB，含词库、`build/`、用户词频） | 不是配置 |
| 缓存与历史 | `sessions/`、`*-cache.json`、`install/`、`npm/` | 不是配置 |
| 本机 UI 状态 | `totalcmd/wincmd.ini`（已在旧仓库标记为手动配置） | 含窗口布局与安装路径 |
| git 个人层 | `~/.gitconfig` 及其 `includeIf` 引用的 `~/.gitconfig-<身份>` | 含邮箱、人名与 `~/dev/<雇主>/` 这样的工作目录结构。仓库只管公共层 `~/.config/git/config`（`[init]`/`[core]`/`[delta]`/`[i18n]`/`[credential]`），个人层手工维护 |

另外：**`~/.config/chezmoi/chezmoi.toml` 不由本仓库管理**（鸡生蛋：chezmoi 不可能管自己的源在哪）。

---

## 5. 平台缺口

### 5.1 已在 macOS 接入时修掉的三处

这一节原来叫「已知的平台缺口」。三处现在都已修复，列在这里是为了记录它们长什么样：

| 原缺口 | 修法 | 提交 |
| --- | --- | --- |
| `20` 脚本在 macOS 上 `gcc -ldl` 失败（macOS 没有 `libdl`，而 gpu-watch 读的是 NVIDIA GPU） | 脚本顶部加 `{{ if ne .chezmoi.os "linux" }}` 短路，`exit 0` | `73edcc4` |
| `30` 脚本要求 niri / waybar / Wayland | 同上 | `73edcc4` |
| `bootstrap/` 只有 Arch 版 | 新增 `bootstrap/macos.sh` | `ac55046` |

两点经验值得留着，因为 Windows 侧还会遇到同类的：

- 短路**必须 `exit 0`**。`run_onchange_` 只按脚本内容记账，非零会让 chezmoi 中止整个 apply，
  而一个注定失败的脚本会永远拖住后续每一次 apply。
- `run_onchange_after_40-fcitx5.sh.tmpl` 和 `run_once_after_60-zed-cli.sh` 本来就会优雅降级
  （先 `command -v fcitx5` / `command -v zeditor`，不存在就 `exit 0`）。**不要**给它们加短路，
  那反而会破坏 Linux 侧的行为。
- `bootstrap/macos.sh` 的用法是 `bash -c` 而不是 `sh -c`：macOS 的 `/bin/sh` 是 POSIX 模式的
  bash 3.2，不支持数组和 `local`。

### 5.2 macOS 接入时新发现的两处

这两处不是「某个脚本会失败」，而是**源与机器系统性地不一致**，局部修补挡不住：

**(a) `.chezmoiignore` 只做了单向排除。** 它把 macOS / Windows 目标在 Linux 上排除了，但没有
反过来排除 Linux 目标，所以在 darwin 上整套 hyprland / niri / waybar / swaylock / fcitx5 /
GTK 标题栏 CSS / `niri-*` 脚本（约 50 个文件）仍然是 managed 状态，`apply` 会在 macOS 家目录里
把它们铺开。已加反向排除块。

注意 `~/.local` 是**整棵子树**排除的：只忽略里面的文件仍然会让 chezmoi 创建
`~/.local/share/applications`，因为源里有那个目录，与它的文件是否被忽略无关。

**(b) `.zshrc` 的 nvm 分支指向未安装的 brew formula。** 模板写的是
`$(brew --prefix nvm)/nvm.sh`，但那台机器上 nvm 是 `git clone` 装的，在 `$NVM_DIR`。麻烦之处
在于 `brew --prefix nvm` 对**没安装的** formula 也会打印一个路径**并以 0 退出**，所以它不会
报错，只会让 nvm 静默消失。已改成先探 `$NVM_DIR`、再回落 brew。

### 5.3 Windows 侧的已知问题

**(a) `win/nu/*.nu` 是孤儿，已被跳过。** 它没有任何脚本部署，内含旧机器的真实路径
（`e:\Alacritty\settings\`、`E:\Alacritty\vendor\starship.exe`），且用的是 nushell 旧语法
`let-env`。要纳入必须先确定 nushell 版本与目标位置（`%APPDATA%\nushell\`），**这是重写，不是搬移**。

**(b) `win/*.bat` 与 `win/cmds/*.cmd` 留在仓库里，不会被部署。** 它们属装机层。
`win/init.bat` 已在 Linux 上按新架构重写（clink 显式读 `%LOCALAPPDATA%\clink`、
`STARSHIP_CONFIG` 已删除），但**从未在真实 Windows 上执行过**——你的验证很有价值。

**(c) `pi-config/settings.json` 用绝对路径**指向 `~/bin/pi-config/extensions`（Pi 不展开 `~`）。
Windows 上对应的路径是它自己的写法，`pi-config/install.sh` 里有一处检查会警告路径不符。

---

## 6. 网络

Linux 机器上**直连 GitHub 的 HTTPS 是坏的**（`OpenSSL SSL_read: unexpected eof while reading`），
它给 `github.com` 配了 mihomo 代理：

```toml
[http "https://github.com/"]
	proxy = http://127.0.0.1:7890
```

**这段是机器相关的**，不要盲目复制到你的机器。你那边的 `git push` 若报 SSL/超时错误，
先判断是网络环境问题还是本机代理没开，再决定怎么处理；需要时用一次性 `git -c http.proxy=...`
而不是写进配置。

---

## 7. 回报格式

完成（或卡住）后，按下面结构回报，这样在 Linux 机器上能直接核对：

```markdown
## 平台
macOS 15.x / Windows 11（写明版本）

## 执行到哪一步
3.1 … 3.7 中的哪一步完成/卡住

## 对账结果
| 文件 | 方向 | 依据（mtime / 内容摘要） | 处理 |
| --- | --- | --- | --- |
| ~/.zshrc | 家目录更新 | 家目录 09-27，源 09-25 | chezmoi add |
| …      |            |                        |          |

## 我改动的仓库内容
<列出新增/修改的源文件；给出 commit hash>

## 验证
- chezmoi diff --include=files: <数字>
- 二次 chezmoi apply -v 输出行数: <数字>
- 失败的 run_* 脚本（如有）: <名字 + 原因>

## 未解决 / 需要用户决定
<例如：win/nu 是否重写、某处漂移不确定哪份是对的>
```

**最后**：回到 Linux 机器时，那边的 agent 会做三件事——`git pull` 看你推的改动、
核对源文件是否仍然自洽（Linux 上 `chezmoi diff --include=files` 必须回到 0）、
以及检查你新加的短路是否破坏了 Linux 分支（20/30 脚本在 Linux 上仍应正常构建）。

---

## 8. 一句话总结

**先 `diff` 对账，再 `apply`；判断方向，不要默认源是对的；需要 root 的动作用 bootstrap；
`run_*` 脚本失败后要清 `scriptState` 才能重试；改完推回仓库。**
