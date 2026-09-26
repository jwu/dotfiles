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

- [ ] **源侧改造已完成，但 `chezmoi apply` 还没执行**（`sourceDir` 已写好，`chezmoi diff` 已对过）。
      执行前先看一眼 `chezmoi diff --include=files`，然后 `apply -v` 跑两次，第二次必须 0 行。
      当前 status：`chezmoi status` 中文件改动 30 余条、脚本 0 条（6 个 `run_*.sh` 在 Windows 上
      渲染为空）。风险低：对账下来 10 个 Windows 目标全部是源更新，没有 home 更新的情况。
- [ ] apply 之后确认 alacritty / wezterm 真的用 `cmd /k %USERPROFILE%\bin\dotfiles\win\init.bat`
      启动（clink、aliases、starship 都能用），并把 `~/bin/configs`、`~/bin/dev-settings` 删掉。
- [ ] `~/.gitconfig` 收成纯个人层（`[user]` + `[core] sshCommand`），delta 等公共设置已由
      `~/.config/git/config` 提供。
- [ ] Zed 的 Windows settings 目前是直接收进来的独立文件，还没和 Unix 侧 `dot_config/zed/`
      统一（只差字体与几处默认值）。要么合并成模板，要么接受两份。
- [ ] 本次没纳入：`~/.config/lsd/config.yaml`、`~/.config/git/ignore`、`~/.config/opencode/`、
      `nvim/lazy-lock.json`、`~/bin/imtip-config/`、`~/bin/dev-settings/`（dev-settings 两个平台都没迁）。

### 下一台机器

- [ ] `bootstrap/macos.sh` 只做过 `bash -n` 与逐条人工核对，**从未在真正的裸机上跑过**（本机
      Homebrew 与所有包都已就位）。
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
