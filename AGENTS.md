# dotfiles

用 [chezmoi](https://www.chezmoi.io/) 管理的机器配置与装机脚本**唯一真源**：一套源同时
驱动 Linux（Arch）、macOS 与 Windows。

## 快速上手

### 入口

- `README.md` —— 项目简介、快速上手与文档索引；给人读
- `docs/design.md` —— 仓库的完整设计推导，**遇到结构性问题先读它**
- `TODO.md` —— 有意留下的开放事项，不是未完成的施工清单
- `docs/onboarding-a-machine.md` —— 新机器接入说明，给那台机器上运行的 agent 读
- `bootstrap/arch.sh`、`bootstrap/macos.sh`、`bootstrap/windows.bat` —— 装机入口，唯一需要 root 或终端的一层（Windows 那份两者都不需要）
- `run_*.sh` —— chezmoi 在 apply 期间执行的动作脚本
- `.chezmoiignore` —— 决定哪些源文件**不**落到家目录

### 常用命令

```bash
chezmoi diff --include=files     # 看配置层会改什么；判据是必须为空
chezmoi apply -v                 # 应用；再跑一次必须零输出
chezmoi status                   # A/M/D 与待跑脚本的紧凑视图
chezmoi managed --include=files  # 源目前管着哪些目标
chezmoi execute-template < f.tmpl | diff - ~/path   # 单独渲染一个模板并比对
chezmoi state delete-bucket --bucket=scriptState    # 清脚本记账，见「提交」
```

## 技术栈

- **chezmoi** —— 唯一的配置管理手段，不要引入 stow / dotbot / 手写 install 脚本
- **POSIX shell / bash** —— 脚本层；macOS 侧必须兼容系统自带的 bash 3.2
- **Go text/template** —— chezmoi 的模板语法
- **pacman + yay**（Arch）与 **Homebrew**（macOS）—— 装机层
- 被部署的配置本体：TOML、KDL、Lua、CSS、YAML

## 目录结构

```
dotfiles/
  ├── .chezmoiignore          # 目标路径的排除规则（本身是模板）
  ├── bootstrap/              # 装机入口：唯一需要 root / 终端的层
  │   ├── arch.sh
  │   ├── macos.sh
  │   └── windows.bat
  ├── run_*.sh                # chezmoi 动作脚本，按前缀决定触发时机
  ├── scripts/                # run_* 的辅助文件与被编译的源码，不部署到家目录
  ├── dot_*/                  # chezmoi 源（dot_ = 目标名前置一个点）
  ├── private_*/              # 0700 / 0600 的目标（git 不记录目录权限，只能写进文件名）
  ├── AppData/                # Windows 专有目标
  ├── private_Library/        # macOS 专有目标
  ├── docs/                     # 中文设计记录，按主题一份文件
  │   └── design.md               # 设计推导与实施记录
  ├── AGENTS.md                 # 本文件：协作规则
  ├── README.md                 # 项目简介、快速上手与文档索引
  └── TODO.md                   # 有意留下的开放事项
```

## 工作流程

`改动源` → `chezmoi diff --include=files` → `apply` → 再 `apply` 确认 no-op → 提交。

任何改变仓库结构的改动，先看 `docs/design.md` 有没有对应章节需要同步——它是设计真源，
文档与源不一致时以源为准，但要把文档修回来。

## 协作规则

### 编辑

- **注释一律用简洁英文**，只留代码说不出的东西：一个非显然的约束，或一个指向。
- **繁琐的信息写进 `docs/`**：实测数据、被拒绝的方案、上游 bug、机器特有的怪癖、
  「为什么不用那个显然的做法」。写进 `docs/<主题>.md`，注释里指向它：

  ```sh
  # Wayland client-side decorations only; see docs/alacritty.md.
  ```

- 配置或脚本里超过几行的注释，通常意味着该有一个 `docs/` 文件了。
- `README.md` 与 `docs/` **保持中文**：它们是设计记录，不是代码。
- 改完模板要渲染比对，不要凭想象：

  ```bash
  chezmoi execute-template < dot_zshrc.tmpl | diff - ~/.zshrc
  ```

- 模板空白是精确调过的：`{{ if }}` / `{{ end }}` 独占一行时自身贡献一个换行（充当空行），
  而 `-}}` 会吃掉**所有**连续空白，不是一个换行。用错就丢空行。

### 创建

- 源文件必须遵守 chezmoi 命名：`dot_` 加前置点、`private_` 0600/0700、`executable_` 755、
  `.tmpl` 模板。
- **属性前缀会进源路径**，所以源路径与目标路径不一定逐字对应；`include` 之类必须写源路径
  （`docs/chezmoi-notes.md` 里有踩过的例子）。
- 动作脚本必须带 `run_` 前缀。没有合法前缀的 `*.sh` 会被当成目标文件，在家目录里创建出来。
- 新的推导写 `docs/<主题>.md`，不要再开一层文档目录。

### 搜索

- 找文件用 `fd`，找文本用 `rg`，不要 `find` / `grep -r`。
- chezmoi 的怪癖先查 `docs/chezmoi-notes.md`——那里专门记「看起来会工作、实际不会」的地方。
- 各主题的既有推导按名字对应：`docs/waybar.md`、`docs/lockscreen.md`、`docs/niri.md`、
  `docs/ghostty*.md`、`docs/rime/`、`docs/alacritty.md`、`docs/shell.md`。
- 外部知识库：暂无。

### 提交

- 提交信息用**英文**，说明**为什么**而不是改了什么。风格看 `git log`：短句、conventional
  前缀（`feat:` / `fix:` / `refactor:` / `docs:` / `chore:` / `style:` / `ignore:`）。
- 一次提交一个主题，允许细分——历史里有大量单主题的小提交。
- 提交前必须：

  ```bash
  chezmoi diff --include=files    # 必须为空
  chezmoi apply -v                # 跑两次，第二次必须零输出
  ```

- `run_onchange_` 脚本内容一变就会重跑，这是刻意的。失败的脚本会被一并记进
  `scriptState` 而**不会**自动重试，修好后要先清记账：

  ```bash
  chezmoi state delete-bucket --bucket=scriptState
  ```

- 平台不适合的 `run_*` 脚本必须 `exit 0`，不能让它在别的 OS 上失败：chezmoi 是 fail-fast，
  一个注定失败的脚本会永远拖住后续每一次 apply。

### 严禁

- 严禁让仓库里的脚本引用、clone 或依赖已退役的 `configs` / `desktop-settings`（已删除）。
  `pi-config` 是唯一允许 clone 的外部仓库。
- 严禁把 `bootstrap/`、`docs/`、`scripts/` 从 `.chezmoiignore` 里去掉——那会在家目录
  里造出 `~/bootstrap/arch.sh` 这类文件。
- 严禁跳过对账直接 `apply` 到一台尚未接入的机器：`apply` 会让家目录匹配源，源里那份可能更旧。
- 严禁把个人身份写进仓库：邮箱、姓名、工作目录。git 的个人层在 `~/.gitconfig`，每台机器手工维护。
- 严禁为了「整齐」去翻译用户可见的字符串：`dot_config/waybar/**` 的 `format` /
  `tooltip-format`、`gpu-watch.c` 的 `emit_off()` 消息、`update-rime-dict.sh` 的 `--help`、
  图标里的「中」字、Rime 的选项名。改这些就改了用户看到的东西。
- `private_dot_pi/private_agent/{agents,skills,prompts}/**` 是 pi 的提示词内容，不是注释，
  不要按注释规范去动它。

### 以下操作必须先征求用户同意

- 对一台**尚未对账**的机器执行 `chezmoi apply`。
- 大规模移动或重命名源文件。
- 删除文件、`chezmoi forget`、`git filter-repo`、force push。
- `git commit` 与 `git push`。
- 修改 `bootstrap/` 或 `.chezmoiignore` 的排除规则。
