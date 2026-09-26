# TODO

仓库有意留下的开放事项。**迁移本身已经完成**——这不是一份未完成的施工清单，而是
「知道有问题、暂时不做」的记录。

## 需要动手

### 这台 macOS

- [ ] 决定 `.config/glow/one-dark.json` 与 `.config/zellij/config.kdl` 是否要留在这台机器上。
      它们是跨平台配置，2026-09-26 接入时一并部署了过来；不用这两个工具就把它们加进
      `.chezmoiignore` 的 darwin 分支。
- [ ] 清理旧备份：`~/.config/ghostty/config.bak.*`、`~/.config/zed/settings.json.bak.*`、
      `~/.pi/agent/*.bak*`、`~/.config/alacritty/alacritty.toml.bak`。
- [ ] 清理 `~/bin/configs`、`~/bin/desktop-settings`、`~/bin/dev-settings`。注意 `~/.gitconfig`
      里还有指向 `~/bin/configs/`、`~/bin/desktop-settings/` 的 `includeIf`，删目录时要一并处理。

### 文档

- [ ] `docs/inputsource-pro/inputsource-pro-config.md` 与 `docs/totalcmd/totalcmd-config.md` 引用的
      `./images/*.png|jpeg` 从未随文档一起迁入，链接是死的（全仓 markdown 链接检查会报 6 处）。
      要么补图，要么删掉引用。

### 这台 Windows

- [x] 接入完成（2026-09-26）：`chezmoi apply -v` 退出码 0、第二次 0 行，`diff --include=files` 与
      `status` 均为 0。本地提交未 push。
- [x] `bootstrap/windows.bat` 已重写并在本机跑通：scoop 装工具与 per-user 字体、
      `clink autorun install`、三个用户环境变量；无提权。`win/` 整个目录已删除。
- [x] 新终端里确认通过：starship 提示符（蓝目录 + 灰 `❯`、前面无空行）、`chcp` 65001、别名都正常。
      **注意取舍：Clink 现在由终端执行 `%LOCALAPPDATA%\clink\session.cmd` 加载（`clink autorun`
      已卸载）**，所以只有 Alacritty / WezTerm 里有 Clink；Win+R 或 VS Code 的普通 cmd 没有。
      原因（`os.setenv` 不改 cmd 环境块）记在 [`docs/windows-shell.md`](docs/windows-shell.md)。
- [x] `~/bin/configs` 已删（2026-09-27）：旧 clink 会话早已退出，`clink_history_21792~`
      也不在了，剩下 `win/clink_profile/{clink_history,clink.log,clink_errorlevel_*.txt}`
      一并删除。`~/bin/dev-settings` 此前已删。
- [x] `~/.gitconfig` 已收成纯个人层（`[user]` + `[core] sshCommand`）；delta 等由
      `~/.config/git/config` 提供。已验证 `git config` 取值正常。
- [x] Zed 的 Windows settings 已与 Unix 侧对齐，只保留 `ui_font_family: Inter`（Unix 是
      FiraMono Nerd Font）；共享 fallback 列表加了 `Microsoft YaHei`。
- [x] 上次「没纳入」的配置已决定不纳入、直接删除（2026-09-27）：
      `~/.config/lsd/config.yaml`、`~/.config/git/ignore`、`~/.config/opencode/`、
      `%LOCALAPPDATA%\nvim\lazy-lock.json`、`~/bin/imtip-config/`、`%APPDATA%\Zed\AGENTS.md`
      全部删除。`~/bin/dev-settings` 此前已删。
- [x] `~/.config/{gitui,lsd,eza}` 上一版遗留已删（2026-09-27）：gitui 是 Windows 上被
      ignore 排除的冗余副本（真实配置在 %APPDATA%\gitui），eza 是空目录，lsd 的 config.yaml
      与「没纳入」项一并删除。

### 下一台机器

- [ ] `bootstrap/macos.sh` 只做过 `bash -n` 与逐条人工核对，**从未在真正的裸机上跑过**（本机
      Homebrew 与所有包都已就位）。
- [ ] `bootstrap/windows.bat` 在本机完整跑通（所有步骤 ok），但本机不是裸机——scoop、git、
      Nerd Font 都已就位。**没在真正的裸机上跑过**；字体那一步只在本机已装过的情况下验证过。
      Clink 的 `session.lua`（chcp 与别名）也只在真实交互终端里才看得到效果，需要开一次终端确认。
- [ ] Windows 侧记得：任何新的 `run_*` 脚本都必须带 `.tmpl` + `{{ if ne .chezmoi.os "windows" -}}`
      外壳，否则 `chezmoi apply` 会因 exec(3) 失败而中止。流程见
      [`docs/onboarding-a-machine.md`](docs/onboarding-a-machine.md)。

## 待决定

1. **`settings.json` 的排除边界**：`pi-config/settings.json` 含 pi 的 npm 插件列表
   （`@eko24ive/pi-ask` 等），这对跨机器一致有值，但它同时含本机 provider / 模型状态。
   要不要把「插件列表」单独抽成模板纳入？
2. **家目录里从未被管过的配置**：`~/.config/{chrome,chromium}-flags.conf`、`mimeapps.list`。
   已决定不纳入（范围严格等于两个退役仓库已有的东西），可随时 `chezmoi add` 补。
   `nvim/lazy-lock.json` 已随 Windows 收尾一并删除（lazy.nvim 会在下次更新时重新生成）。
3. ~~Windows 上 `~/bin` 的遗留~~ 已清理（2026-09-27）：删掉与 scoop 重复的便携版
   （alacritty / starship / fzf / zoxide / eza / fd / delta / bat / rg / coreutils 的 exe，
   以及 clink、clink-completions、NerdFont 目录和 zoxide 的 completions/man/文档）。
   非 scoop 工具（zig、nvim、nvm、godot、mpv、Everything、ImTip、yazi、yt-dlp 等）保留。
4. **旧的 `mac/config.sh` 是否整体退役**：配置迁走后它已经没有内容，`bootstrap/macos.sh` 是
   按它演化重写的，剩下的只是删掉旧文件。
5. **GitHub 上仍有不可达的旧对象**：`git filter-repo` 加 force push 只移动了 `main`，旧 commit
   在被 GC 之前仍可按 SHA 读取（[`docs/design.md`](docs/design.md) 有实测命令）。已决定不再
   处理——要立即失效只有联系 GitHub Support 或删除重建仓库。

## 已经不是问题

- **git 代理**：Linux 那台直连 GitHub 报 SSL 失败，代理 `127.0.0.1:7890` 现在只存在于它的
  `~/.gitconfig` 里，不再跟着公共层污染其它机器。
- **`gh` 抢写 `git config`**：credential 段落在公共层，且被模板化成 `.chezmoi.homeDir`，
  渲染结果与 `gh` 自己写入的一致。
