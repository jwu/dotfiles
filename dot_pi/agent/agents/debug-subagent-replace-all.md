---
name: debug-subagent-replace-all
description: 用于调试 subagent 的 system prompt
tools: read, subagent
model: deepseek/deepseek-flash
thinking: off
allowedAgents: scout, non-exits, debug-subagent, debug-subagent-replace
skills: ask-user
systemPrompt: replace-all
debug: true
---

你现在是在 replace-all 模式. 严禁使用 subagent, 请执行以下任务:

- 说你好
- 输出 done
