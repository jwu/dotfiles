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
- [x] 新增 `bootstrap/windows.bat`（winget→scoop 装 chezmoi → clone → `win/install.bat` →
      `chezmoi init --apply`），已冒烟测试（见「下一台机器」）。
- [ ] **在新终端里确认** clink / starship / aliases 真的起来了（当前那个终端还是 apply 之前的旧
      会话）。配置里 alacritty / wezterm 已改为 `cmd /k %USERPROFILE%\bin\dotfiles\win\init.bat`。
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
- [ ] `bootstrap/windows.bat` 同理。本机已接入，只验证过三条路径：非管理员会中止、正常流程
      exit 0、失败步骤会记账并 exit 1（后两条用桩替掉了 `install.bat` 与 apply）。**没在裸机上
      跑过**，字体安装那一步（需要管理员）也没实测。
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
3. **`win/nu/*.nu` 是否重写**：要纳入必须先确定 nushell 版本与目标位置
   （`%APPDATA%\nushell\`）。这是重写，不是搬移。
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
