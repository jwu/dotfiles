# chezmoi 的坑

这一页记录的是「看起来会工作、实际不会」的那几处。设计推导看 [`design.md`](design.md)。

## `.chezmoiignore` 匹配的是**目标**路径

不是源路径。所以里面写 `README.md` 指的是家目录下的 `~/README.md`——不加这一行，
`chezmoi apply` 会真的在 `~` 下创建 `README.md`。

## 排除要双向做

只写「非 Linux 时排除 macOS / Windows 目标」是不够的，反过来同样需要。否则在 macOS
上整套 Linux 目标仍然是 managed 状态，`apply` 会把 hyprland / niri / waybar /
swaylock / fcitx5 一整套铺进家目录。

## 排除整棵子树，而不是逐个文件

只忽略文件是不够的：chezmoi 仍会为**空的父目录**创建目录。macOS 上
`~/.local/share/applications` 就是这么被创建出来的，直到把 `.local` 整棵子树排除才
消失——源里有那个目录，与它的文件是否被忽略无关。

## 属性前缀会进源路径

chezmoi 依据权限位给源文件加前缀，所以源路径与目标路径不一定逐字对应。典型后果：
`run_onchange_after_40-fcitx5.sh.tmpl` 的 `include` 写目标路径 `profile` 会直接渲染
失败，必须写源路径 `private_profile`。

完整清单见 [`design.md`](design.md) 的「属性前缀会进源路径」。

## `create_` 是「一次性初始化」，不是真源

`settings.json`、`mcp.json` 这种会被工具自己回写的文件用 `create_` 前缀：chezmoi 只在**目标
不存在**时渲染并写入，目标一旦存在就不再碰它。它既不是「纳入真源」（那会在每次 apply 抹掉
工具写进去的东西），也不是「排除」（新机器上就没有基线）。

两个后果要记着：

- 源与磁盘会静默漂移，`chezmoi diff --include=files` 为 0 **不代表**目标内容等于源。
- 改源里的这类文件不会传到已有机器，得手工同步。

## git 不记录目录权限

所以家目录上的 `0700` / `0600` 除了写进源文件名（`private_` 前缀）没有别处可以
表达。chezmoi 的默认值是目录 `0755`、文件 `0644`——`~/.pi` 里躺着 `auth.json`，
`~/Library` 是 macOS 的私有目录，两者都不该被放宽。

## 失败的 `run_` 脚本会被记账

失败的脚本也会进 `scriptState`，于是它**不会**因为「上次失败」而自动重跑——只有
内容变化才会。修好之后要先清记账：

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply -v
```

`run_*` 脚本都幂等，重跑一遍是安全的。

## fail-fast

任一 `run_*` 脚本失败会中止整个 apply，后面的脚本不再执行。所以平台不适合的脚本必须
**`exit 0`**，而不是让它失败：`run_onchange_` 只按内容记账，一个注定失败的脚本会永远
拖住后续每一次 apply。

## `sourceDir` 必须显式写

源在 `~/bin/dotfiles`，不是 chezmoi 的默认位置（`~/.local/share/chezmoi`），所以每台
机器都要有 `~/.config/chezmoi/chezmoi.toml`：

```toml
sourceDir = "/Users/<user>/bin/dotfiles"
```

它是 chezmoi 自己的配置（鸡生蛋：chezmoi 不可能管自己的源在哪），不由本仓库管理。
