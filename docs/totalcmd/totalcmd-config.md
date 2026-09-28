# Total Commander 配置说明

## 落地方式

`%APPDATA%\GHISLER\wincmd.ini` 由 chezmoi 的 `create_` 目标落地——**只在目标不存在时写
一次**，之后这个文件归 Total Commander 自己管：

```
AppData/Roaming/GHISLER/create_wincmd.ini   →   ~/AppData/Roaming/GHISLER/wincmd.ini
```

不把它当作 managed 文件，原因不是「含本机路径」，而是 **TC 会持续重写同一个文件**。它的
`Savepath` / `Savepanels` / `SaveCommands` / `SaveHistory` 默认全开，面板路径、搜索历史、
插件 checksum，以及按屏幕分辨率命名的窗口几何节（`[2560x1440 (8x16)]`）都是 TC 写回去的。
作为 managed 文件纳入的话，每次 `chezmoi apply` 都会把这些抹掉，`wincmd.ini` 因此和
`~/.pi/agent/settings.json` 属于同一类东西，见 [`../design.md`](../design.md) 的
「pi 的可变状态」。

于是仓库里的这份只是**新机器/重装的起点**：它只含偏离 TC 默认值的几项设置与三个手工定制
的节，其余交给 TC 的默认值，窗口布局和历史留给新机器自己长。已有机器上目标文件已存在，
chezmoi 不会碰它，源与磁盘此后各自演化。

> TC 自己支持把节重定向到别的 ini（`AlternateUserIni` 与 `RedirectSection`，官方帮助
> "Using multiple ini files" 一节，明确说这是为了「让主 ini 只读」和「把目录/命令行历史
> 这类易变数据分出去定期删除」）。理论上能让稳定配置受管、易变状态自由，但没有采用：
> 主 ini 的骨架一旦漏掉某个节，那个节就会留在别处被 TC 回写，`apply` 照样会抹掉它。

## 配置说明

以下是在 UI 里点出来的部分，截图的文字内容已并入本节。

### 杂项（`配置 > 杂项`）

在「重新定义热键 (Keyboard remapping)」里选 Hotkey，逐条添加：

| 按键 | 命令 |
| --- | --- |
| `Alt + D` | `cm_EditPath` |
| `F2` | `cm_RenameOnly` |

同页「Get confirmation before」的五项——删除非空目录、覆盖文件、覆盖/删除只读文件、
覆盖/删除隐藏或系统文件、鼠标拖放复制——都保持勾选（TC 默认如此，未写进基线）。

### 快速搜索（`配置 > 快速搜索`）

「Quick search (current dir)」选**字母 - 带有搜索对话框**。TC 的默认是 `CTRL+ALT+字母`
（`AltSearch=0`），这一项要手动改（`AltSearch=3`）；它只在你显式唤出搜索时才拦截按键，
不像 `Alt+字母` 那一档会一直抢按键。

「Exact name match」两项都保持 TC 默认：`Beginning` 勾选、`Ending` 不勾。

### 操作（`配置 > 操作`）

「Mouse selection mode」选**使用鼠标左键（Windows 标准）**。TC 的默认是右键（NC 风格，
`UseRightButton=1`），所以这一项也在基线里（`UseRightButton=0`）；同时
**取消勾选** `Rubber band selection`（`UseRubberBandSelection=0`，TC 默认是勾选）。

同页其余勾选状态都保持默认，未写进基线：`Select only the file name when renaming`
（这一项**是**被勾选的，但 TC 默认是 `RenameSelOnlyName=0`，即连扩展名一起选，所以它
同样进了基线）、`Auto-complete paths`、`Auto-append suggested name`、
`Directory history thinning`、`Extra lines below cursor`、`Also select directories`、
`NTFS daylight saving correction`、两条 `Calculate space occupied by subdirectories`
（空格键选择时、复制删除前），以及「Save on exit」的四项（目录、面板、命令行、目录历史）。

「Calculate space occupied by subdirectories」右侧的 `Everything` **不勾**
（`EverythingForSize=0`）。

「File comments > Preferred type」是 `Plain text+UTF16`（TC 默认 `CommentPreferredFormat=4`）。

### 颜色（`配置 > 颜色`）

`Dark mode` 为 `Always disabled`；`Mark color` 天蓝、`Cursor color` 灰，`Font color` /
`Background` / `Background 2` / `Cursor font` 都是 `default`。

TC 的颜色用十进制 Windows `COLORREF`，即 `$00BBGGRR`（不是 RGB）：

| ini | 十进制 | 实际颜色 |
| --- | --- | --- |
| `MarkColor=16744448` | `0x00FF8000` | RGB(0,128,255) 天蓝 |
| `CursorColor=12632256` | `0x00C0C0C0` | RGB(192,192,192) 银灰 |

「Use inverted selection」勾选（`InverseSelection=1`）；「Use inverted cursor」与
「Use Windows theme for cursor」都不勾（`InverseCursor=0`、`ThemedCursor=0`）。
`Define colors by file type...` 勾着但没有配置具体类型。

### 字体

`配置 > 字体` 里是 `Segoe UI` 9pt（主窗口与视图）、`Microsoft Sans Serif`（对话框），
TC 把它们同步写进 `[AllResolutions]` 与当前分辨率节两处。

## 基线里有什么

只写偏离 TC 默认值的项——TC 帮助文档里 `Key=值` 的那个「值」就是默认值，所以只需列出
不同的一侧。基线中 `[Configuration]` 的五行：

| 键 | 基线 | TC 默认 | 依据 |
| --- | --- | --- | --- |
| `UseRightButton` | `0` | `1`（右键 / NC 风格） | 操作页选左键 |
| `RenameSelOnlyName` | `1` | `0`（连扩展名一起选） | 操作页该勾选框已勾 |
| `AltSearch` | `3`（带搜索对话框） | `0`（CTRL+ALT+字母） | 快速搜索页选该档 |
| `UseRubberBandSelection` | `0` | `1` | 操作页该勾选框未勾 |
| `EverythingForSize` | `0` | 未写明 | 操作页 `Everything` 未勾 |

加上三个手工定制的节：`[Shortcuts]`（两条热键）、`[Colors]`（上表两色 + 反色选择）、
`[AllResolutions]`（字体）。

**没有写进基线的**：

- 旧快照里那几十个 `[Configuration]` 键（`Savepath`、`DirTabOptions`、`LogOptions`、
  `CopyComments`、`IconClickSelection`、`UseTrash`…）——逐项对照官方帮助后确认**全部等于
  TC 默认值**，写进去只会让基线与未来的 TC 默认值脱钩。
- `InstallDir`、`firstmnu`、`FirstTime`、`SetEncoding`、`[left]` / `[right]` 的 `path`、
  `[SearchName]` / `[SearchIn]`、`[2560x1440 (8x16)]` 整个节、`[Tabstops]` 的列宽、
  `[FileSystemPlugins64]` / `[ListerPlugins64]` / `[ContentPlugins64]` 的 `$checksum$`、
  `[ButtonbarCache]`——都是本机安装状态或运行时状态，由新机器自己生成。
- `UseEverything`（搜索时是否用 Everything）——旧快照是 `0` 而 TC 默认是 `1`，但截图里
  那个 `Everything` 复选框位于「计算子目录大小」区域，对应的是 `EverythingForSize`，无法
  据此判断这一项，故未纳入。

## 已知偏差与未验证项

旧仓库的 `wincmd.ini` 是 2021 年的快照，其中两处与本文描述的目标状态相反，基线按本文为
准：`UseRightButton`（旧 `1` → 目标 `0`）、`RenameSelOnlyName`（旧 `0` → 目标 `1`）。这说明
那份快照不能直接当基线用。

基线**没有在真实的 Total Commander 上验证过**（写这份文档的机器是 macOS）。若新机器上
TC 报找不到 `wincmd.icon`、语言文件之类的资源，检查是否缺少 `InstallDir`。
