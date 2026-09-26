# TODO

仓库有意留下的开放事项。**迁移本身已经完成**——这不是一份未完成的施工清单，而是
「知道有问题、暂时不做」的记录。

## 需要动手

### Linux 机器（Arch）

- [ ] **先手工建 `~/.gitconfig`，再 `chezmoi apply`。** 源里的 `.config/git/config` 只剩公共层，
      `[user]` 与 `[http] proxy` 移进了个人层；个人层不在仓库里，apply 补不回来，中间态会丢掉
      身份与代理。个人层的分层见 [`docs/design.md`](docs/design.md) 的「公共层与个人层」。
- [ ] 若已经拉过历史重写之前的那批提交：`git fetch && git reset --hard origin/main`（或重新
      clone），因为 `43655d4` 之后的 hash 全变了。

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
- [ ] `~/bin/configs` 还剩两个被旧 clink 会话占用的文件
      （`win/clink_profile/clink_history`、`clink_history_21792~`）。关掉那个终端后
      `rm -rf ~/bin/configs` 即可。`~/bin/dev-settings` 已删。
- [x] `~/.gitconfig` 已收成纯个人层（`[user]` + `[core] sshCommand`）；delta 等由
      `~/.config/git/config` 提供。已验证 `git config` 取值正常。
- [x] Zed 的 Windows settings 已与 Unix 侧对齐，只保留 `ui_font_family: Inter`（Unix 是
      FiraMono Nerd Font）；共享 fallback 列表加了 `Microsoft YaHei`。
- [ ] 本次没纳入：`~/.config/lsd/config.yaml`、`~/.config/git/ignore`、`~/.config/opencode/`、
      `nvim/lazy-lock.json`、`~/bin/imtip-config/`、`%APPDATA%\Zed\AGENTS.md`、
      `~/bin/dev-settings` 装机脚本（两个平台都没迁）。
- [ ] `~/.config/{gitui,lsd,eza}` 是上一版遗留、已不受管理，仍留在本机。

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
2. **家目录里从未被管过的配置**：`~/.config/{chrome,chromium}-flags.conf`、`mimeapps.list`、
   `nvim/lazy-lock.json`。已决定不纳入（范围严格等于两个退役仓库已有的东西），可随时
   `chezmoi add` 补。其中 `lazy-lock.json` 是 35 个插件的版本锁，纳入后新机器可复现相同的
   插件版本，单独考虑的价值最高。
3. **Windows 上 `~/bin` 的遗留**：旧的便携版 exe（alacritty / starship / fzf / …）、
   `~/bin/clink`、`~/bin/NerdFont`。scoop shims 在用户 PATH 里排在 `~\bin` 前面，所以不会遮蔽，
   但也没必要留着。清不清由用户决定。
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
