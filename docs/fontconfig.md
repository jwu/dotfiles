# 字体渲染与中文回退（fontconfig）

Chrome 里的文字观感能不能对齐 Ghostty——这件事做过两轮实测，结论与踩到的坑记在这里。
第一轮（隔离 Chrome + CDP 截图 + 像素分析）的实验台在 `/tmp/chrome-font-lab`，
第二轮（headless Chrome + CDP 读实际 face）在 `/tmp/cfont`；两者都是临时目录，重启即失，
下面这些数据是那两轮里唯一需要留下来的部分。

## Ghostty 的参数基准

Ghostty **不读 fontconfig 的渲染参数**。`src/config/Config.zig` 里那段注释写得很直白：
`until Ghostty implements Fontconfig support`。它直接用 FreeType 的默认值，也就是
`@"freetype-load-flags"` 的默认：

```zig
hinting = true,
@"force-autohint" = false,
monochrome = false,
autohint = true,
light = true,     // "most common setting in GTK apps and therefore Ghostty's default"
```

映射到 fontconfig 就是 `hinting=true` + `hintstyle=hintslight` + `autohint=true`。
本机发行版默认是 `hinting=True(slight)` + `autohint=False`。
（**后一轮修正**：`autohint` 这一项 Chrome 根本不看，真正决定观感的是 `hintstyle`，
见「hinting：全局也对齐 Ghostty」。）

所以「把 Ghostty 的方案搬到 Chrome」在参数层就落成了两条：`autohint=true`（真正对齐），
以及是否把 `hintstyle` 往 `hintfull` 推（观感更硬更清楚，但**不是** Ghostty 的取值）。

## 落到源里的配置

`dot_config/fontconfig/fonts.conf`（目标 `~/.config/fontconfig/fonts.conf`）：

1. `hinting=true` / `hintstyle=hintslight` / `autohint=true`——全局生效。
   中间有一段时间用的是 `hintfull`（「更清楚」方向，实测像素差异 4.77% vs 1.89%），
   后来统一回了 `hintslight`，理由见「hinting：全局也对齐 Ghostty」。
2. 中文回退改指 Sarasa：`Noto Sans CJK SC → Sarasa Gothic SC`、
   `Noto Sans Mono CJK SC → Sarasa Mono SC`，让网页中文与终端的字体选择一致。

**为什么用 family 名而不是 `lang=zh`**：实测 `lang` 规则对 Chrome 的改动量是 **0**——
Chrome 的字体回退请求不经过带 lang 的 pattern 规则，而 family 名重定向能被接住
（1.80% 像素变化，CDP 确认中文换成了 `Sarasa Gothic SC`）。日/韩/繁的 Noto 变体
一律不动，避免把日韩字形也拉成简体。

## 实测数据

环境：Chrome 153.0.8010.52、Ghostty 1.3.1-arch2、DP-3 2560x1440 scale 1、
测试页 `847x1311`（中英混排 + 字号/字重/背景梯度）。`chroma` 是子像素彩边像素数，
`ink` 是裁剪区墨量、`ink_px` 是明显偏离背景的像素数。

| 变体 | 差异像素 | ink | ink_px | 判定 |
| --- | --- | --- | --- | --- |
| 基线（发行版默认） | — | 10.60 | 7192 | — |
| `--disable-lcd-text` | 0 (0.00%) | 10.60 | 7192 | 无效：本来就没开子像素 AA |
| `--disable-font-subpixel-positioning` | 1.40% | 10.56 | 7149 | 有效，但字距按整数像素重排 |
| `hinting=false`（pattern 或 font 阶段等价） | 2.57% | 10.42 | 7342 | 笔画更糊 |
| `hintfull + autohint` | 4.77% | 10.41 | 6256 | 笔画更硬更贴网格 |
| `hintslight + autohint`（Ghostty 等价） | 1.89% | 10.15 | 6981 | 笔画略细 |
| 字体族重定向探针 | 4.71% | 10.31 | 7124 | 生效（用于验证隔离配置确实进到渲染进程） |
| `Noto Sans CJK SC → Sarasa Gothic SC` | 1.80% | 10.27 | 6994 | 生效 |
| 最终组合（hintfull + autohint + 中文回退） | 5.41% | 10.35 | 6228 | 生效，CDP 确认中文为 Sarasa Gothic SC |
| `lang=zh` → prepend SemiBold | 0 (0.00%) | 10.60 | 7192 | 无效 |
| `family=Sarasa Mono SC` → family `Sarasa Mono SC SemiBold` | 0.08% | 10.60 | 7192 | 生效但只影响显式请求该 family 的元素 |
| `embolden=true`（模拟 `font-thicken`） | 0 (0.00%) | 10.60 | 7192 | 无效，Skia 不读该属性 |

## 第二轮：网页字体栈重定向（Chrome 专属）

第一轮之后观感仍不如 zed 和 ghostty，症状是「太细」。这次问题不在渲染参数，而在
**字体选择层**：网页 CSS 里那一串字体名本机一个都没装，Chrome 只能停在 fontconfig 的
metric 替身上。zed 是 FiraMono Medium、ghostty 是 FiraMono Medium + `font-thicken`，
Chrome 拿到的却是 Courier / Helvetica 的替身，还停在 Regular。

第二轮改用 **headless Chrome + CDP 的 `CSS.getPlatformFontsForNode`** 直接读元素实际用到
的 face——比截图看像素更准，也不需要肉眼。实验台是 `/tmp/cfont`。

### 基线：网页字体栈真实落在哪

（下表是**全新 profile**、没有 Chrome 字体设置时的结果；本机带上那四项设置后会整体后移
一层，见「更前面还有一层」）

| CSS 字体栈 | Chrome 实际 face |
| --- | --- |
| `ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace`（GitHub） | **Liberation Mono** |
| `Menlo`、`ui-monospace`、`"SF Mono"`（单独出现） | Liberation Serif（standard font 兜底） |
| `Consolas`、`"SF Mono", monospace` | Noto Sans Mono（靠 `monospace` 兜底） |
| `Arial`、`Helvetica`、`sans-serif`、`-apple-system … Arial` 栈 | **Liberation Sans** |
| `system-ui` | Noto Sans |
| `"PingFang SC", "Microsoft YaHei", sans-serif` | Liberation Sans |
| `NoSuchFontXYZ`（列表外的未知名） | Liberation Serif |

- 等宽栈停在 **Liberation Mono** 而不是 Noto Sans Mono：GitHub 的栈里显式写着
  `"Liberation Mono"`，它真的装了，Chrome 在那里就停下，轮不到最后的 `monospace` 兜底。
- 正文栈停在 **Liberation Sans**（Arial 的 metric 替身），比 Noto Sans 更细更窄。
- 对未安装的 family，fontconfig 的兜底结果 Chrome **会拒收**，直接落到 standard font
  （Liberation Serif）。所以 `Menlo` 不会自己变成 Noto Sans——这一点是后面方案成立的前提：
  只要把名字重定向到真实存在的 family，Chrome 就接受。

### 落地方式

只影响 Chrome，所以给它一份独立的 fontconfig，靠 `FONTCONFIG_FILE` 指过去：

- **`dot_config/fontconfig/chrome-fonts.conf`** —— `<alias binding="strong">` 把上表的
  family 名逐个重定向，等宽 → `FiraMono Nerd Font`、正文 → `Noto Sans`，字重不动。
  文件既不叫 `fonts.conf` 也不在 `conf.d/` 下，`50-user.conf` 不会加载它。
- **`dot_local/bin/executable_google-chrome-stable`** —— wrapper：导出 `FONTCONFIG_FILE`
  后 `exec /usr/bin/google-chrome-stable "$@"`。`~/.local/bin` 在 PATH 里位于 `/usr/bin`
  之前，所以终端启动也走它；配置文件缺失时自动降级为原样启动。
- **`dot_local/share/applications/google-chrome.desktop`** —— 覆盖系统那份（`dot_local` 在
  `.chezmoiignore` 里已被限定为 Linux）。系统原文件用的是绝对路径
  `/usr/bin/google-chrome-stable`，不覆盖的话从启动器点开就绕过 wrapper 了。

三个文件合起来的判据（CDP 实测）：等宽栈报 `FiraMono Nerd Font` **Medium**，正文栈报
`Noto Sans` Regular。字重分两条链路走，见「字重：正文 Regular，等宽抬一档」。

### 更前面还有一层：Chrome 自己的字体设置

`chrome://settings/fonts` 里那四项存在 profile 的 `Preferences`，**先于 fontconfig 生效**，
而且直接给出 family 名、绕过 Arial 那一层解析。本机的值是：

| 项 | 值 |
| --- | --- |
| Standard | `Noto Sans CJK SC` |
| Serif | `Noto Serif CJK SC` |
| Sans-serif | `Noto Serif CJK SC` ← 衬线体，多半是选错的一格 |
| Fixed-width | `Sarasa Mono SC` |

后果：

- 未安装的 family 不走 fontconfig 兜底，而是落到 Standard（`Noto Sans CJK SC`），
  再被全局规则顶成 `Sarasa Gothic SC Regular`——大部分网页的默认正文其实是 Sarasa。
- `sans-serif` 直接变成 `Noto Serif CJK SC`，网页正文是衬线体。
- 两者都绕开上面的 family 重定向，因为 Chrome 根本不会去问 Arial。

所以完整的目标状态是「Chrome 设置 + 专属 fontconfig」两层：

1. Chrome 的 `sans-serif` 从 `Noto Serif CJK SC` 改回 `Noto Sans CJK SC`（一次性；
   `Preferences` 是应用数据，不进 chezmoi）。
2. Chrome 的 `Fixed-width`（`Sarasa Mono SC`）就是代码块中文的落点，不需要额外处理。

#### 这一层会丢

`Preferences` 是应用数据，不在 chezmoi 里，profile 重建或换 profile 就会回到空。
2026-09-28 复验时 `webkit` 段整个是空的，此时 CDP 读到的实际 face 是：

| 场景 | 无 Chrome 设置时 |
| --- | --- |
| 代码块（GitHub 栈） | `FiraMono Nerd Font Medium` + 中文 `Noto Sans CJK KR` |
| Arial / Helvetica / system-ui | `Noto Sans` + 中文 `Noto Sans CJK KR` |
| `sans-serif` | `Noto Sans` + 中文 `Noto Sans CJK KR` |
| 未知名 family、网页默认 | `Liberation Serif`（衜线兜底） |

中文一律落到 `Noto Sans CJK KR`（韩文字形）——就是上面「未决」那节担心的那件事真的发生了；
未知名 family 也不再是 `Sarasa Gothic SC`，而是退回 `Liberation Serif`。

恢复：**完全退出 Chrome**（不是关窗口），然后改
`~/.config/google-chrome/Default/Preferences` 里的 `webkit.webprefs.fonts`，或者去
`chrome://settings/fonts` 手工填。`fonts` 的键是 `<standard|serif|sansserif|fixed>` 再套一层
script 代码（全局是 `Zyyy`）。必须先退出 Chrome：运行时它会用自己的内存副本把文件覆写回去。
补齐后 CDP 复验，落点就回到上面那张表。

（曾有一版 `chrome-fonts.conf` 把 `Sarasa Gothic SC` 顶到 SemiBold，后来撤了；
`Sarasa Mono SC → SemiBold` 那条留了下来，只作用于等宽。那条规则有个坑值得留档：要匹配的
必须是**全局重定向的结果**而不是输入——
规则按文件顺序执行，`include` 进来的全局规则会先把 `Noto Sans CJK SC` 改成
`Sarasa Gothic SC`，所以按输入名去匹配永远不会命中。）

改完后的实测落点：

| 场景 | face |
| --- | --- |
| 代码块（GitHub 栈等） | `FiraMono Nerd Font` Medium，中文 `Sarasa Mono SC SemiBold` |
| Arial / Helvetica / 微软雅黑栈 / system-ui | `Noto Sans` Regular |
| `sans-serif`、未知名 family、网页默认 | `Sarasa Gothic SC` Regular |

### 字重：正文 Regular，等宽抬一档

字重在两条链路上分开处理，`chrome-fonts.conf` 里各有一条：

- **等宽**：`FiraMono Nerd Font` 加 `weight=medium`，`Sarasa Mono SC` 重定向到
  `Sarasa Mono SC SemiBold`。这是 zed（`buffer_font_weight = 500` + codepoint-map）和
  ghostty（`font-style = Medium` + codepoint-map）的同一套做法，自 52ccc05 起未变。
- **正文**：不加字重，Regular。

正文曾经也抬过一档，实测中英混排不匀：Sarasa 只有 Regular(400) 和 SemiBold(600)、没有
Medium，于是中文(600) 明显比西文(500) 重，同一行里中文会「跳出来」。量化（16px，
`--screenshot` 后比墨量）：Medium/SemiBold **490.5k** vs 全 Regular **400.8k**，差 18%，
不是微小差别。正文因此留在 Regular：网页正文以中英混排为主，中英同重比「跟终端一致」
更重要。

等宽保留抬重是同一取舍的另一端：终端本来就按 ghostty 的 codepoint-map 把中文顶到 SemiBold，
代码块跟终端一致比中英同重更要紧。[`ghostty.md`](ghostty.md) 里那句「选 SemiBold 是为了
中英混排时中文更醒目，代价是比英文略重」描述的正是这个取舍。

### hinting：全局也对齐 Ghostty

Ghostty 和 fontconfig 的关系比第一轮以为的微妙：

- **字体发现确实走 fontconfig**。启动日志自报 `font_backend=.fontconfig_freetype`；
  用 `FONTCONFIG_FILE` 把 `FiraMono Nerd Font` 顶成 `Sarasa Mono SC` 后，
  `ghostty +show-face --string=A` 也跟着输出 `Sarasa Mono SC`。
- **但 hinting 不问 fontconfig**。`src/font/face/freetype.zig` 的 `glyphLoadFlags()`
  只读它自己的 `load_flags`：

  ```zig
  .no_hinting    = !do_hinting,
  .force_autohint = self.load_flags.@"force-autohint",
  .no_autohint   = !self.load_flags.autohint,
  .target = if (load_flags.monochrome) .mono
            else if (load_flags.light) .light
            else .normal,
  ```

  Linux 默认 `freetype-load-flags = hinting,no-force-autohint,no-monochrome,autohint,light`
  → `FT_LOAD_TARGET_LIGHT`。

- 而 fontconfig 的 `hintstyle=hintslight`——Skia、cairo、Pango 都映射到同一个
  `FT_LOAD_TARGET_LIGHT`（Skia 的 `case SkFontHinting::kSlight` 旁边那句注释直接写
  *This implies FORCE_AUTOHINT*）。所以把**全局** `fonts.conf` 设成 `hintslight`，所有读
  fontconfig 的应用就在**字形栅格化**这一层跟 Ghostty 拉齐了，Chrome 也不需要再单独写一条
  覆盖。
  实测（620x50 测试条，`--screenshot` 后比像素）：hintfull → hintslight 有 **9.00%**
  像素差异、墨量 292.6k → 287.2k；但在输入法候选词上（当时 12pt）墨量几乎不动
  （203.7k → 205.1k）。字号越小，这个差别越被稀释。

- **`autohint` 这项对 Chrome 无效**。Skia 只在 Windows / macOS 端口设
  `kForceAutohinting_Flag`，fontconfig 端口不设；FreeType 端口里那个
  `else loadFlags |= FT_LOAD_NO_AUTOHINT` 还包在 `SK_BUILD_FOR_ANDROID_FRAMEWORK` 里。
  所以第一轮设的 `autohint=true` 对 Chrome 是个空操作——真正决定观感的是 `hintstyle`。
  全局 `fonts.conf` 里那条也一样：对 cairo / GTK 类应用可能有效，Chrome 不看。

- **`font-thicken` 在 Linux 上是死配置**。官方文档写明 *This is currently only supported
  on macOS*，所以 `config.ghostty` 里 `font-thicken = true` 与 `font-thicken-strength = 0`
  在 Linux 完全不起作用（而且 `0` 也不是关闭，文档说那是「最轻的加粗」）。
  第一轮那条「复刻 `font-thicken`」的被拒方案，想复刻的东西在 Linux 上并不存在。

**仍然不可比的**：终端是固定网格（每个字形占同一个单元，字形宽度不参与布局），
浏览器是 layout-driven。能对齐的是字形栅格化，行内间距本质上对不上。

### 输入法（fcitx5）：抬过一档字重，又用一个字号换回来

候选窗口不是 Qt / GTK 画的——`libclassicui.so` 链接的是 `libpango` + `libcairo` +
`libfontconfig`，所以它直接吃**全局** `fonts.conf`，没有 Chrome 那种 `FONTCONFIG_FILE` 隔离。

先照着「跟终端一致」抬过一档：原本 `Font=Sarasa Mono SC 12`（Regular）比 Ghostty 的中文
（SemiBold）轻，于是把 `Font` / `MenuFont` 都改成 `Sarasa Mono SC SemiBold 12`。
`pango-view`（同一条 Pango + Cairo 链路）能离线复现候选窗并量化：

| 变体 | 墨量 | 明显笔画像素 |
| --- | --- | --- |
| Regular + hintfull（抬字重前） | 203.7k | 785 |
| Regular + hintslight | 205.1k | 786 |
| SemiBold + hintslight（抬字重后） | 254.8k | 989 |

12pt 下字重的影响远大于 hinting（+25% 墨量 vs ±1%），而这 +25% 正是问题：终端有等宽网格
与行距分担笔画，候选窗里常常只有两三个词、每个词一两个字，笔画一粗就糊。于是**字重回
Regular，把可读性交给尺寸**——`Font` / `MenuFont` 都改成 `Sarasa Mono SC 14`，
`TrayFont` 保持 `Bold` 不动。

写成 `Sarasa Mono SC`（不带字重词）就是 Regular。Sarasa 只给 SemiBold / Light 这些注册了
family 别名（`Sarasa Mono SC SemiBold`），Regular 没有：`fc-match 'Sarasa Mono SC Regular'`
会落到 `Noto Sans Mono`，而 `fc-match 'Sarasa Mono SC'` 正是 `Sarasa-Regular.ttc`。反过来
要抬字重，那个 `SemiBold` 词必须写出来。

代价和 Chrome 那边一样：候选项不再跟 zed / ghostty 的 CJK 字重对齐（它们仍是 Medium +
SemiBold），见「字重：最终回到 Regular」。

### 被拒绝的替代方案

- **嵌进全局 `fonts.conf`**：简单，但 zed、GTK 应用、其它终端会一起变。
- **用 `<test>` 的 `<or>` 折叠 family 列表**：`fc-match` 完全正常，Chrome 段错误，
  见「留下的坑」。
- **靠 `lang` 规则分流**：第一轮已证明 Chrome 的回退请求不带 lang。
- **再试一次 `embolden` 复刻 `font-thicken`**：第一轮已证明 Skia 不读该属性；
  第二轮改用「重定向 family」绕过去（正文的字重最后没有动，见「字重：正文 Regular，
  等宽抬一档」）。

### 未决：全新 profile 下中文会落到 Noto Sans CJK KR

上面的规则只动西文 family 和 Sarasa。在**没有** Chrome 字体设置的新 profile 里，
中文字形回退不经过这些名字，仍走 Chrome 自己的 CJK fallback，落在 **Noto Sans CJK KR**上——
中文会用韩文字形变体渲染。本机 profile 把 Standard 设成了 `Noto Sans CJK SC`，走不到那条
路径；但只要那几个设置被清空就会暴露。要兜住它得连 `Noto Sans CJK JP/KR/TC/HK`
一起重定向到 Sarasa，代价是日韩网页的字形也变成简体变体（第一轮刻意避开的取舍）。没做。

## 被拒绝的方案

- **`--disable-font-subpixel-positioning`**：确实有效（1.40%），但整行字距会被按整数像素
  重排，中文混排行内的疏密肉眼可见地不匀。最终没要。
- **复刻 `font-codepoint-map`**：做不到。真实网页的中文走字形回退，而这条路径既不吃
  `lang` 规则，也只认 family 名；也就是说没法像 Ghostty 那样「按码点区段钉某个 face」。
  能做的只有「网页显式请求某个 family 时把它顶到另一个 family」。
- **复刻 `font-thicken`**：不必——Ghostty 的 `font-thicken` 只支持 macOS，在 Linux 上是死配置；
  fontconfig 的 `embolden` 对 Chrome 实测改动量为 0。
- **`hintfull` vs `hintslight`**：两者都测过。先选了 `hintfull`（更清楚），
  后来又为了跟 Ghostty 统一回到 `hintslight`——见「hinting：全局也对齐 Ghostty」。
- **改日韩字体**：不动。`Noto Sans CJK JP/KR/TC/HK` 保留原样，否则日韩字形会被简体写法顶掉。

## 怎么验证

```bash
# 参数层：hintstyle 1 就是 hintslight（0/1/2/3 = none/slight/medium/full），autohint 应为 True
fc-match -v "Noto Sans CJK SC" | rg -n 'hintstyle|autohint|family'
# 回退层：应返回 Sarasa 而不是 Noto
fc-match "Noto Sans CJK SC"
# Chrome 共用同一份参数（它靠 FONTCONFIG_FILE 指到只多几条 alias 的文件），值应当一致
FONTCONFIG_FILE=~/.config/fontconfig/chrome-fonts.conf fc-match -f '%{hintstyle}\n' 'FiraMono Nerd Font'
# Ghostty 侧：字体发现能读到 face，hinting 来自它自己的 load flags
ghostty +show-face --string="A中"
ghostty +show-config --default | rg 'freetype-load-flags'
```

`Noto Sans` 这个 family 由 `noto-fonts` 包提供（bootstrap 的包清单里有）。缺它的时候
`fc-match 'Noto Sans'` 会落到 `Noto Sans CJK KR`——韩文字形变体，`chrome-fonts.conf` 那批
正文重定向就整体偏了。上面那张落点表以这个包已安装为前提。

**必须重启应用**：fontconfig 的参数在进程启动时读取，已运行的 Chrome 不会变
（Chrome 要整个退出，不是关窗口）。

端到端肉眼验证：重启 Chrome，看中文网页（笔画应比之前更硬、更贴网格，中文换成了 Sarasa）。

### 网页字体栈（headless Chrome + CDP）

第二轮的实际 face，用它就能读出来，不需要肉眼，也不需要像素分析：

```bash
/opt/google/chrome/chrome --headless=new --disable-gpu --no-first-run \
  --user-data-dir=/tmp/cfont/ud --remote-debugging-port=9333 file:///tmp/cfont/test.html
# 另一个终端里，用 CDP 的 CSS.getPlatformFontsForNode 读每个元素的 face
uv run --with websocket-client python /tmp/cfont/probe.py 9333
```

判据：等宽栈应报 `FiraMono Nerd Font` Medium，`sans-serif` / 未知名 family 应报
`Sarasa Gothic SC` Regular，Arial 一类具名 sans 应报 `Noto Sans` Regular。
要走整条链路（wrapper → `FONTCONFIG_FILE` → fontconfig），把第一行换成
`~/.local/bin/google-chrome-stable ...`；要连带验证 Chrome 的字体设置，把那个 profile 的
`Preferences` 里 `webkit.webprefs.fonts` 拷进一个临时 profile：

```bash
python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.config/google-chrome/Default/Preferences')))['webkit']['webprefs']['fonts'])"
```

### 像素级端到端（用当初的实验台）

若 `/tmp/chrome-font-lab` 还在，这是最硬的判据：

```bash
cd /tmp/chrome-font-lab
LAB_REAL_XDG=1 ./lab.sh check base 9979
uv run --with pillow --with numpy python analyze.py report/check shots/fs-base.png check=shots/check.png
```

期望值：与基线差异 ≈ 60090 像素 (5.41%)、ink 10.35、ink_px 6228；若为 0 就是配置没生效。

**`LAB_REAL_XDG=1` 不能省**：实验台为了屏蔽 `~/.config/chrome-flags.conf` 的 proxy flag，把
`XDG_CONFIG_HOME` 指向了空目录；而 fontconfig 是通过 `/etc/fonts/fonts.conf` 里的
`<include prefix="xdg">fontconfig/fonts.conf</include>` 读用户配置的——同一条 include 会把
`~/.config/fontconfig/fonts.conf` 一起屏蔽掉。第一次端到端检验就是这么得到 0 差异的。

落地时还有一个 chezmoi 侧的坑：对单个目标 apply 时若父目录不存在会直接失败，
要先 `mkdir -p ~/.config/fontconfig`，细节见 [`chezmoi-notes.md`](chezmoi-notes.md)。

## 怎么回滚

删掉 `dot_config/fontconfig/fonts.conf`（源与目标两侧）再 `chezmoi apply`，
或只把 `hintstyle` 改成 `hintfull` / 整段 match 注释掉。回滚同样要重启应用。

第二轮那套单独回滚：删掉 `dot_config/fontconfig/chrome-fonts.conf`、
`dot_local/bin/executable_google-chrome-stable`、
`dot_local/share/applications/google-chrome.desktop.tmpl` 三个源文件（以及目标侧），
再 `chezmoi apply`。Chrome 的 `sans-serif` 要自己改回 `Noto Serif CJK SC`
（那是应用数据，chezmoi 管不着）。同样**必须完整退出 Chrome 再启动**，关窗口不算。

## 那轮实验留下的坑

- **`<test>` 里不要用 `<or>`**。把一串 family 名塞进一个 `<test><or>` 里，`fc-match`
  完全正常，但 Chrome 启动时**段错误**（core dumped，连调试端口都来不及监听）。
  改成「一个 family 一个 `<match>`」或 `<alias>` 就没问题。定位方式：逐块二分，
  删到只剩一个 mono 块仍然崩；配 `--headless=new` 看它连 `Connection refused` 就知道
  是启动期崩溃，不是渲染期。
- **fontconfig 缓存版本警告**：headless Chrome 启动时报
  `some cache files were generated by a newer version (0x2012003) of Fontconfig …
  current version: 0x2012001`。实测无影响，只说明 `~/.cache/fontconfig` 里混进了别的
  环境写的缓存。
- **`FONTCONFIG_FILE` 必须绝对路径**。Chrome 启动过程中会 chdir，相对路径会让 fontconfig 报
  `Cannot load default config file` 然后**静默**退回系统配置——第一批 6 组实验因此全废
  （所有变体输出字节相同，连把 FiraMono 整个换成 Sarasa 的探针都没变化）。
- **Chromium 沙箱不影响 `FONTCONFIG_FILE` 传递**：加不加 `--no-sandbox`，字体替换探针都生效。
- Chrome 153 已经**没有** `--font-render-hinting` 这个 flag（`strings` 里只剩 `hinting-engine`），
  hinting 只能走 fontconfig。
- 本机 Chrome **本来就是灰度抗锯齿**（全图 chroma 恒为 0），所以“终端比浏览器清楚”
  与子像素渲染无关。
- `~/.config/fontconfig/fonts.conf` 是 **XDG include** 加载的，链条是
  `/etc/fonts/fonts.conf` → `conf.d/50-user.conf` → `fontconfig/fonts.conf`，
  文件里不要再去 include 系统主配置（会绕回来）。这一层只认 `fonts.conf` 和 `conf.d/`
  两个名字，所以旁边的 `chrome-fonts.conf` 不会被自动加载——「只影响 Chrome」就靠这一点。
- **`~/.config/fontconfig/conf.d/` 会被自动加载**：给特定应用准备的配置不要放进那个目录。
- **未验证**：笔记本内屏 eDP-1 是 `scale 1.6`，那轮实验该输出不在会话里（只有一个 DP-3），
  分数缩放下 Chrome 与 Ghostty 的栅格化差异仍是未知项，也是最可能造成“发虚”的一项。
