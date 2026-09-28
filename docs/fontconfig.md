# 字体渲染与中文回退（fontconfig）

Chrome 里的文字观感能不能对齐 Ghostty——这件事做过一轮完整实测，结论与踩到的坑记在
这里。当时的实验台（隔离 Chrome + CDP 截图 + 像素分析）在 `/tmp/chrome-font-lab`，
是临时目录，重启即失；下面这些数据是那次实验里唯一需要留下来的部分。

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
本机发行版默认是 `hinting=True(slight)` + `autohint=False`——**差别只在 `autohint`**。

所以「把 Ghostty 的方案搬到 Chrome」在参数层就落成了两条：`autohint=true`（真正对齐），
以及是否把 `hintstyle` 往 `hintfull` 推（观感更硬更清楚，但**不是** Ghostty 的取值）。

## 落到源里的配置

`dot_config/fontconfig/fonts.conf`（目标 `~/.config/fontconfig/fonts.conf`）：

1. `hinting=true` / `hintstyle=hintfull` / `autohint=true`——全局生效。
   `hintfull` 是主动选择的「更清楚」方向，代价是偏离 Ghostty 的 `hintslight`；
   想严格对齐 Ghostty 就把 `hintfull` 换成 `hintslight`（实测两者分别 4.77% / 1.89% 像素差异）。
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

## 被拒绝的方案

- **`--disable-font-subpixel-positioning`**：确实有效（1.40%），但整行字距会被按整数像素
  重排，中文混排行内的疏密肉眼可见地不匀。最终没要。
- **复刻 `font-codepoint-map`**：做不到。真实网页的中文走字形回退，而这条路径既不吃
  `lang` 规则，也只认 family 名；也就是说没法像 Ghostty 那样「按码点区段钉某个 face」。
  能做的只有「网页显式请求某个 family 时把它顶到另一个 family」。
- **复刻 `font-thicken`**：做不到。fontconfig 的 `embolden` 实测改动量为 0。
- **`hintfull` vs `hintslight`**：两者都测过。选了 `hintfull`（更清楚），
  没选「严格等于 Ghostty」的 `hintslight`。
- **改日韩字体**：不动。`Noto Sans CJK JP/KR/TC/HK` 保留原样，否则日韩字形会被简体写法顶掉。

## 怎么验证

```bash
# 参数层：hintstyle 3 就是 hintfull，autohint 应为 True
fc-match -v "Noto Sans CJK SC" | rg -n 'hintstyle|autohint|family'
# 回退层：应返回 Sarasa 而不是 Noto
fc-match "Noto Sans CJK SC"
```

**必须重启应用**：fontconfig 的参数在进程启动时读取，已运行的 Chrome 不会变
（Chrome 要整个退出，不是关窗口）。

端到端肉眼验证：重启 Chrome，看中文网页（笔画应比之前更硬、更贴网格，中文换成了 Sarasa）。

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
或只把 `hintstyle` 改回 `hintslight` / 整段 match 注释掉。回滚同样要重启应用。

## 那轮实验留下的坑

- **`FONTCONFIG_FILE` 必须绝对路径**。Chrome 启动过程中会 chdir，相对路径会让 fontconfig 报
  `Cannot load default config file` 然后**静默**退回系统配置——第一批 6 组实验因此全废
  （所有变体输出字节相同，连把 FiraMono 整个换成 Sarasa 的探针都没变化）。
- **Chromium 沙箱不影响 `FONTCONFIG_FILE` 传递**：加不加 `--no-sandbox`，字体替换探针都生效。
- Chrome 153 已经**没有** `--font-render-hinting` 这个 flag（`strings` 里只剩 `hinting-engine`），
  hinting 只能走 fontconfig。
- 本机 Chrome **本来就是灰度抗锯齿**（全图 chroma 恒为 0），所以“终端比浏览器清楚”
  与子像素渲染无关。
- `~/.config/fontconfig/fonts.conf` 由 `/etc/fonts/fonts.conf` 的 xdg include **自动加载**，
  文件里不要再去 include 系统主配置（会绕回来）。
- **未验证**：笔记本内屏 eDP-1 是 `scale 1.6`，那轮实验该输出不在会话里（只有一个 DP-3），
  分数缩放下 Chrome 与 Ghostty 的栅格化差异仍是未知项，也是最可能造成“发虚”的一项。
