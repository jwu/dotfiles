# Zed 配置同步

Zed 的设置由 chezmoi 部署。仓库里有两份内容相同的 `settings.json`：

| 平台 | 源 | 目标 |
| --- | --- | --- |
| Linux / macOS | `dot_config/zed/settings.json` | `~/.config/zed/settings.json` |
| Windows | `AppData/Roaming/Zed/settings.json` | `%APPDATA%\Zed\settings.json` |

源文件**刻意不加 `private_` 前缀**，目标权限因此是 0644 而不是 0600：文件里没有密钥，
Zed 的凭据在 `~/.local/share/zed/credentials`。带上前缀时源文件名会变成
`private_settings.json`，不再匹配 Zed 默认的 JSONC 规则
`**/{zed,Zed}/{settings,keymap,tasks,debug}.json`，于是它被当作严格 JSON，在编辑器里打开源
文件会满屏报 `Comments are not permitted in JSON`（目标名仍是 `settings.json`，所以实际生效
的那份一直没受影响，只有编辑仓库源文件时才看得见）。

有两份是因为 Zed 在 Windows 上读 `%APPDATA%` 而不是 `~/.config`，`.chezmoiignore` 按 OS
只放行对应的一份。

改完源之后应用一次：

```bash
chezmoi apply ~/.config/zed/settings.json
```

Zed 重启后加载新配置。配置写坏时删掉 `settings.json` 可以让 Zed 回到默认设置——源里那份
还在仓库，`chezmoi apply` 就能拿回来。

`run_once_after_60-zed-cli.sh.tmpl` 另管一件事：Arch 的 `zed` 包只提供 `zeditor`，它会在
`~/.local/bin/zed` 建一个指向 `zeditor` 的符号链接，让 `$EDITOR` 与 `zed <path>` 可用。
