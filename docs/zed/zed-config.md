# Zed 配置同步

Zed 的设置由 chezmoi 部署。仓库里有两份内容相同的 `private_settings.json`
（`private_` 前缀只表示目标权限 0600，不是文件名的一部分）：

| 平台 | 源 | 目标 |
| --- | --- | --- |
| Linux / macOS | `dot_config/zed/private_settings.json` | `~/.config/zed/settings.json` |
| Windows | `AppData/Roaming/Zed/private_settings.json` | `%APPDATA%\Zed\settings.json` |

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
