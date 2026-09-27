# AeroSpace 配置说明

配置源是仓库根目录的 `dot_aerospace.toml`，由 chezmoi 部署到 `~/.aerospace.toml`。

## 安装

AeroSpace 不在 Homebrew 主 cask 源中，需要先添加作者 tap：

```bash
brew tap nikitabobko/tap
brew install --cask nikitabobko/tap/aerospace
```

新版 Homebrew 会拒绝加载未信任的第三方 cask，需先执行 `brew trust --cask nikitabobko/tap/aerospace`（旧版可跳过）。

首次启动 AeroSpace 后，需要在「系统设置 → 隐私与安全性 → 辅助功能」中授权，`aerospace` CLI 才能连上服务。此后可用 `aerospace reload-config` 重载配置；`chezmoi apply` 改动配置时会由 `run_onchange_after_70-aerospace.sh.tmpl` 自动调用它。

## 配置文件位置

由 chezmoi 部署：

```bash
chezmoi apply ~/.aerospace.toml
```

改完源文件后 `chezmoi apply` 会自动重载（`run_onchange_after_70-aerospace.sh.tmpl` 盯
`dot_aerospace.toml` 的哈希）。

配置里 `auto-reload-config` 是有意关掉的：AeroSpace 自带的「保存即重载」是一个常驻的文件
监视，而这份配置一年只改几次。手动重载仍可用 `aerospace reload-config`，或在 service 模式
（`Alt + Shift + ;`）按 `Esc`。

## 配置特点

这份配置整体比较简单，主要包括：

- 使用 `Alt + H/J/K/L` 在窗口之间切换焦点
- 使用 `Alt + Shift + H/J/K/L` 移动窗口
- 使用 `Alt + -` / `Alt + =` 调整窗口大小
- 使用 `Alt + /` 和 `Alt + ,` 切换布局
- 使用 `Alt + 数字 / 字母` 切换工作区
- 使用 `Alt + Shift + ;` 进入 service 模式，执行重载配置、重置布局、移动窗口到工作区等操作

## 工作区分配

当前配置里：

- `1` 到 `5` 分配到内建屏幕（`built-in`）
- `6` 到 `0` 分配到副屏（`secondary`）

并预先保留了多个持久工作区，方便长期使用固定分组。

## 窗口行为

当前配置默认会让新窗口先以浮动方式打开：

```toml
[[on-window-detected]]
check-further-callbacks = true
run = 'layout floating'
```

如果有需要，可以再针对特定应用单独改回 tiling。

## 参考

- AeroSpace: https://github.com/nikitabobko/AeroSpace
