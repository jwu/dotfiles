# AeroSpace 配置说明

本目录包含我的 AeroSpace 配置文件：`./.aerospace.toml`。

## 安装

AeroSpace 不在 Homebrew 主 cask 源中，需要先添加作者 tap：

```bash
brew tap nikitabobko/tap
brew install --cask nikitabobko/tap/aerospace
```

新版 Homebrew 会拒绝加载未信任的第三方 cask，需先执行 `brew trust --cask nikitabobko/tap/aerospace`（旧版可跳过）。

首次启动 AeroSpace 后，需要在「系统设置 → 隐私与安全性 → 辅助功能」中授权，`aerospace` CLI 才能连上服务。此后可用 `aerospace reload-config` 重载配置，`mac/install.sh` 在检测到该命令时也会自动调用。

## 配置文件位置

将配置复制到：

```bash
cp .aerospace.toml ~/.aerospace.toml
```

macOS 上也可以直接运行 `mac/install.sh`，它会完成这步复制（覆盖前备份）并重载配置。

修改配置后，可以重载 AeroSpace 配置使其生效。

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
