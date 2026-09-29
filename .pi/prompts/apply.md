---
description: 比对 dotfiles 源与 home 目录，应用并验证
argument-hint: "[焦点]"
---

把本仓库（chezmoi 源）与 home 目录比对，然后应用、验证。
本命令只作用于本仓库。

## 本次焦点

${@:-（未指定，比对本仓库当前的全部差异）}

## 0. 前置检查

### 0.1 先把本地源同步到 origin

比对必须基于最新的源：本仓库同时驱动多台机器，落在过期基线上的结论会和别处不一致。
先同步：

```bash
git fetch --prune origin
git status -sb | head -1     # ## main...origin/main [ahead N, behind M]
```

按差距处理：

- 未分叉且落后：`git pull --ff-only`
- 分叉（本地有未推送提交、远程也前进）：`git pull --rebase`
- 已是最新：跳过

任何一步失败——无网络、未提交改动挡住 rebase、rebase 冲突——都**立即中止 `/apply`**，
不要 apply。把 `git status` 和冲突文件报告给我，说明仓库正卡在 rebase 中间态
（`git rebase --continue` 继续 / `git rebase --abort` 放弃），等我把 git 冲突解决干净再重跑。

### 0.2 其余检查

- `git status --short` 看源里已有哪些未提交改动，避免和本次比对的差异混淆
- 如果 home 目录与源的差异远超预期（像是这台机器尚未比对过），停下报告，不要 apply

## 1. 比对

- 跑 `chezmoi diff --include=files`，看清配置层会改什么
- 把摘要展示给我：哪些目标 A/M/D、关键 hunk 的含义
- **等我说确认之后再 apply**。如果 diff 为空，说明源已生效，直接跳到第 3 步

## 2. 应用

- 跑 `chezmoi apply -v`
- 如果 `run_*` 脚本失败：chezmoi 是 fail-fast，失败的脚本会被记进 `scriptState`
  且不会自动重试，所以必须修好脚本本身（不是绕过它），再清记账后重跑：

  ```bash
  chezmoi state delete-bucket --bucket=scriptState
  ```

- 平台不适用的 `run_*` 脚本必须 `exit 0`，不能让它在别的 OS 上失败
- 严禁为了让 diff 干净而放宽源内容去迁就当前 home 目录——源是真源

## 3. 验证

```bash
chezmoi apply -v                 # 必须零输出
chezmoi diff --include=files     # 必须为空
```

两步任一不满足，回到第 1 步继续查。

## 4. 汇报

- 列出本次比对的差异：哪些目标 A/M/D、各自的关键 hunk 含义
- 给出两步验证的结果
- 需要提交时提醒我显式跑 `/commit`，**不要自行 commit 或 push**

## 注意事项

- 改 `bootstrap/` 或 `.chezmoiignore` 的排除规则、删除文件、大规模移动或重命名源文件，
  必须先征求我的同意
- 不要把个人身份写进仓库：邮箱、姓名、工作目录
- 不要翻译用户可见字符串：`dot_config/waybar/**` 的 `format` / `tooltip-format`、
  `gpu-watch.c` 的 `emit_off()` 消息、`update-rime-dict.sh` 的 `--help`、
  图标里的「中」字、Rime 的选项名
- 找文件用 `fd`，找文本用 `rg`，不要 `find` / `grep -r`
- chezmoi 的怪癖先查 `docs/chezmoi-notes.md`
