---
description: 把家目录里改过的配置回收到 dotfiles 源
argument-hint: "[路径...]"
---

把家目录侧的配置改动回收到本仓库（chezmoi 源）。这是 `/apply` 的反方向：
apply 是源 → 家目录，collect 是家目录 → 源。回收的是**配置**，不是某台机器的现状快照。

## 参数

${@:-（未指定，走下面的扫描流程）}

## 0. 判据：`chezmoi status` 的第一列

第一列表示**家目录相对 chezmoi 上次写入的差异**，也就是家目录侧的漂移：

| 第一列 | 第二列 | 含义 | 归谁管 |
| --- | --- | --- | --- |
| `M` | `M` | 家目录被改过 | **本命令** |
| 空 | `M` | 源被改过，家目录还没跟上 | `/apply` |
| 空 | `R` | `run_*` 脚本待跑 | `/apply` |
| 空 | 空 | 一致 | 无 |

先跑 `chezmoi status`，只挑**第一列非空**的条目。第一列为空的一律留给 `/apply`，
不要在这里碰——那方向的改动属于源，回收会把它们抹掉。

## 1. 能自动回收的：`chezmoi re-add`

对第一列为 `M` 的普通文件：

```bash
chezmoi re-add --dry-run -v      # 只打印 diff，不写源；把输出给我看
chezmoi re-add                   # 确认后真正写回源
```

`re-add` 自己会跳过模板，`create_` 文件连 `status` 都不显示，构建产物（`~/.local/bin`
下那类）不是受管目标，所以都不需要额外排除。

不带 `--dry-run` 的 `re-add` 会**直接改源**，所以永远先 dry-run 给我看。

## 2. 需要语义合并的：模板

模板的漂移不会出现在 `re-add` 的输出里，必须手工搬。对每个第一列为 `M` 的 `.tmpl` 目标：

```bash
chezmoi execute-template < 源模板 > /tmp/rendered
diff -u /tmp/rendered ~/对应目标
```

看懂家目录改了什么，把改动**翻译**回模板的对应位置——包括它该受哪个
`{{ if .chezmoi.os }}` 约束。**绝不**把渲染结果整份写进模板：那会抹掉所有 `{{ }}`，
把模板降级成某台机器的快照。

改完重新渲染比对，确认渲染结果与家目录现状一致，再把合并方案告诉我。

## 3. 家目录里源没管过的新文件

先找候选，但**不要擅自 add**。递归全扫会撞上几千个运行时数据（chromium 的 profile 一
个就够呛），所以只看两级：

```bash
chezmoi managed --include=files --path-style absolute | sort > /tmp/managed.txt

# 1) ~/.config 下源里完全没有的一级目录：新装软件的迹象
comm -23 <(fd -t d --max-depth 1 . ~/.config | sort) \
         <(fd -t d --max-depth 1 . dot_config \
           | sed "s|^dot_config|$HOME/.config|" | sort)

# 2) 浅层、近期改动、且尚未纳入的文件
fd -t f --max-depth 2 --changed-within 14d . \
   ~/.config ~/.local/bin ~/.local/share/applications 2>/dev/null \
   | sort > /tmp/candidates.txt
comm -23 /tmp/candidates.txt /tmp/managed.txt
```

噪音是预期的，而且不该每次重新判断：先读 [`docs/chezmoi-notes.md`](../../docs/chezmoi-notes.md)
的「家目录里不纳入源的清单」，命中的一律跳过（运行时状态、缓存、构建产物、工具自动
重写、凭据、机器身份）。把剩下真正像配置的候选列给我，**逐条问我**要不要纳入——
包括参数里直接传进来的路径。遇到清单里没有的新路径，按同样的判据判断并向清单补一条。

我确认某个路径后：

```bash
chezmoi add --secrets=error <路径>
```

`--secrets=error` 让疑似密钥直接失败，而不是写进仓库。纳入前先定源侧命名：
`dot_` / `private_` / `executable_` / `.tmpl`。凭据、`~/.pi/agent/auth.json`、`~/.gitconfig`
（个人层，每台机器手工维护）一律不纳入。

## 4. 验证与汇报

```bash
chezmoi status                   # 第一列应清空
chezmoi diff --include=files     # 应只剩还没合并完的模板改动
```

`diff` 不为空就回到第 2 步——说明还有模板改动没搬完。

汇报：哪些文件被回收、模板合并改了什么、哪些候选被拒绝及原因、哪些家目录删除待处理。

## 注意事项

- 第一列为 `D`（家目录侧把某个受管文件删了）时不要自作主张：问我是从源里一并删掉
  （`chezmoi forget` + 删源文件），还是重新 `apply` 恢复。删除文件必须先经我同意。
- 不要为了让 `status` 干净而把家目录的临时改动收进源。先判断那个改动是不是想留的：
  调试输出、写死的本机路径、一次性试错都不该进仓库。
- 靠 `re-add` 就能完成时，不要为了「顺手」去改模板。
- 找文件用 `fd`，找文本用 `rg`，不要 `find` / `grep -r`。
