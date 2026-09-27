---
description: 把本次会话的改动落到 dotfiles 源，对账并 apply
argument-hint: "[焦点]"
---

把本次会话谈定的改动落到本仓库（chezmoi 源），然后对账、应用、验证。
本命令只作用于本仓库。

## 本次焦点

${@:-（未指定，处理本次会话中所有已谈定的改动）}

## 0. 前置检查

- `git status --short` 看源里已有哪些未提交改动，避免和本次改动混淆
- 如果家目录与源的差异远超本次改动（像是这台机器尚未对账），停下报告，不要 apply

## 1. 落源

把本次会话谈定的改动写进源文件，遵守仓库规则：

- 源文件命名：`dot_`（前置点）、`private_`（0600/0700）、`executable_`（755）、`.tmpl`（模板）
- 注释用简洁英文，只留代码说不出的东西：一个非显然的约束，或一个指向
- 繁琐信息写进 `docs/<主题>.md`，注释里指向它；不要再开一层文档目录
- 结构性改动先看 `docs/design.md` 有无对应章节需要同步
- 模板改完必须单独渲染比对，不要凭想象：

  ```bash
  chezmoi execute-template < 源模板 | diff - ~/对应目标
  ```

## 2. 对账

- 跑 `chezmoi diff --include=files`，看清配置层会改什么
- 把摘要展示给我：哪些目标 A/M/D、关键 hunk 的含义
- **等我说确认之后再 apply**。如果 diff 为空，说明源已生效，直接跳到第 4 步

## 3. 应用

- 跑 `chezmoi apply -v`
- 如果 `run_*` 脚本失败：chezmoi 是 fail-fast，失败的脚本会被记进 `scriptState`
  且不会自动重试，所以必须修好脚本本身（不是绕过它），再清记账后重跑：

  ```bash
  chezmoi state delete-bucket --bucket=scriptState
  ```

- 平台不适用的 `run_*` 脚本必须 `exit 0`，不能让它在别的 OS 上失败
- 严禁为了让 diff 干净而放宽源内容去迁就当前家目录——源是真源

## 4. 验证

```bash
chezmoi apply -v                 # 必须零输出
chezmoi diff --include=files     # 必须为空
```

两步任一不满足，回到第 1 步继续查。

## 5. 汇报

- 列出本次落源的文件，各自改了什么
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
