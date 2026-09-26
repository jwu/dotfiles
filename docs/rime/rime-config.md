# Rime 输入法配置

## 配置文件说明

### Linux / Fcitx5

Fcitx5 的 Rime 用户目录为 `~/.local/share/fcitx5/rime/`。本仓库只保存跨平台用户补丁：

- `default.custom.yaml`
- `rime_ice.custom.yaml`

Fcitx5 的候选窗配置不读取 `squirrel.custom.yaml` 或 `weasel.custom.yaml`。Linux 专用的候选窗配置位于 `../fcitx5/`，包括 Classic UI 主题、字体和输入法 profile。安装 Rime 和 Fcitx5 后运行：

```bash
cd ../fcitx5
./install-linux.sh
```

脚本会在首次运行（`~/.local/share/fcitx5/rime/rime_ice.schema.yaml` 不存在）时自动下载并解压雾凇拼音词库（约 16 MB，走南大镜像，失败回退 GitHub），之后不再覆盖；`build/`、用户词频数据库和其他生成文件始终不动。下载失败时脚本只警告、不中断，按下面的「安装步骤」手动补即可。

`default.custom.yaml` 只放按键补丁：雾凇的默认配置来自上面解压到用户目录的 `default.yaml`
（`schema_list` 第一项是 `rime_ice`）。macOS / Windows 用 plum 安装时同样会把 `default.yaml`
放进用户目录，因此同一份补丁可以跨平台共用。用户目录没有 `default.yaml` 时，`schema_list`
会退回 rime-prelude 的默认值（朙月拼音，输出繁体）。


## 安装步骤

### 1. 安装 Rime 输入法

- **Linux (Arch)**: `sudo pacman -S fcitx5 fcitx5-rime`；`librime` 需带 lua 插件（`/usr/lib/rime-plugins/librime-lua.so`）
- **Windows**: 下载 [Weasel](https://github.com/rime/weasel/releases) 并安装
- **macOS**: 下载 [Squirrel](https://github.com/rime/squirrel/releases) 并安装

### 2. 安装雾凇拼音

**Linux**：通常不用手动安装，`fcitx5/install-linux.sh` 首次运行会下载 `full.zip` 解压到
`~/.local/share/fcitx5/rime/`。下载失败时可手动补：

```bash
curl -fL -o /tmp/full.zip https://github.com/iDvel/rime-ice/releases/latest/download/full.zip
bsdtar -xf /tmp/full.zip -C ~/.local/share/fcitx5/rime
```

（Arch 上也可以改用 AUR 包 `rime-ice-git`，但它把方案装到共享目录 `/usr/share/rime-data/`，
用户目录没有 `default.yaml` 时还需要在 `default.custom.yaml` 里补
`__include: rime_ice_suggestion:/`。）

**Windows / macOS**：用 plum 安装到用户目录。

```bash
git clone --depth=1 https://github.com/rime/plum
cd plum
bash rime-install iDvel/rime-ice:others/recipes/full
```

### 3. 复制配置文件

#### Linux

在 `../fcitx5/` 下运行 `./install-linux.sh`（见上文“配置文件说明”）。脚本会同步 `profile`、
`classicui.conf`、`themes/jwu/theme.conf` 和 `rime/*.custom.yaml`，覆盖前备份为
`.bak.$TIMESTAMP`，然后调用 `rime_deployer --build` 重建并 `fcitx5-remote -r` 重载。

#### Windows

Rime 配置目录：`%APPDATA%\Rime\`

1. 复制 `weasel.custom.yaml`
2. 复制 `default.custom.yaml`
3. 复制 `rime_ice.custom.yaml`
4. 重新部署 Rime（右键托盘图标 → 重新部署）

#### macOS

Rime 配置目录：`~/Library/Rime/`

1. 复制 `squirrel.custom.yaml`
2. 复制 `default.custom.yaml`
3. 复制 `rime_ice.custom.yaml`
4. 重新部署 Rime（菜单栏输入法图标 → 重新部署）

## 更新词库

`fcitx5/install-linux.sh` 只在首次安装时下载词库，之后不会更新。要跟进上游雾凇拼音的
词库，运行：

```bash
cd ../fcitx5
./update-rime-dict.sh
```

脚本会下载最新的 `full.zip` 并覆盖解压到用户目录，先把用户目录里的 `*.custom.yaml`
备份为 `.bak.$TIMESTAMP`，再调用 `install-linux.sh` 重新应用本仓库补丁并按需重建部署。
脚本最后会重启 fcitx5，确保 Rime 引擎重新加载新词库（只跑 `fcitx5-remote -r` 不保证生效）。

### 下载源与校验

- 默认**优先 GitHub 官方 release**，失败才回退南大镜像
- 无论哪个源，都用 GitHub release 的官方 `digest`（sha256）校验下载内容，镜像滞后会直接
  被拒绝并自动回退官方源
- ⚠️ 南大镜像是缓存，**可能滞后数周**：实测镜像停在 2026-06-30，而上游已到 2026-09-25。
  不要依赖 `--mirror`，它只适用于 GitHub 完全不可达时
- 无法访问 `api.github.com` 时跳过校验（此时官方源仍可信，镜像源则可能装到旧版）

⚠️ `full.zip` 自带 `default.custom.yaml` / `rime_ice.custom.yaml`，会覆盖本仓库的补丁，
这正是必须由 `install-linux.sh` 重新复制补丁的原因，因此不要手动解压后就结束。

其他说明：

- 只想更新词库与补丁、不重建：`./update-rime-dict.sh --no-deploy`
- 优先镜像（GitHub 不可达时）：`./update-rime-dict.sh --mirror`
- `tencent.dict.yaml` 是大词库，重建 `prism.bin` 可能需要几分钟
- `build/`、`*.userdb/`（用户词频）和 `sync/` 不受影响；上游 release 是滚动的
  `nightly` tag，没有可比对的版本号，直接拉最新即可

## 配置内容说明

### 外观配置（squirrel.custom.yaml / weasel.custom.yaml）

- macOS/Windows 客户端使用各自的候选窗配置
- 候选词水平排列
- 单行显示候选
- Linux Fcitx5 使用 `../fcitx5/themes/jwu/theme.conf` 实现对应样式

### 按键配置（default.custom.yaml）

- `__patch` 里的 `key_binder/bindings/+`：在雾凇默认绑定之后追加 `=` / `-` 翻页（菜单态与翻页态都生效）。`/+` 只有在 `__patch` 指令内才是「合并」操作符；直接写成同级的 `key_binder/bindings/+` 只是普通键名，会把雾凇与 rime-prelude 的默认绑定整段替换掉
- `ascii_composer/switch_key/Caps_Lock: noop`：Caps Lock 不切换中英文（仍可打大写）
- `switcher/hotkeys`：方案选单只保留 `Control+Shift+grave`
