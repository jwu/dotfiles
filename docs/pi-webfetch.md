# pi-webfetch 的外部依赖

`@johnnywu/pi-webfetch` 把 URL 分成三条路由，每条都靠一个**外部 CLI**：GitHub 走 `gh`，
YouTube / Bilibili 走 `yt-dlp`，其余网页走 `scrapling`（再经 Defuddle 转 Markdown；音频、
视频之外的图片走内建下载，不依赖 CLI）。上游把这些工具的抓取流程写在包内的
`docs/{gh,yt-dlp,scrapling}.md`，本文只记**本仓库怎么装它们**和踩到的坑。

## 症状

2026-10-02 之前这台机器只有 `gh`：`scrapling` 与 `yt-dlp` 都不在 PATH。webfetch 的表现
是「GitHub 能用，其他一律失败」——非 GitHub URL 报 `spawn scrapling ENOENT`，并附一句
`Make sure Scrapling is available via scrapling shell -L warning -c "print('ok')"`。
`docs/reference-terminal.md` 早把 `yt-dlp` 列进期望清单，但没有任何装机步骤真的装它。

## 落点

| 工具 | 位置 | 来源 |
| --- | --- | --- |
| `gh` | 手工（`~/.local/bin/gh`） | 未纳管；GitHub 路由一直可用，暂不动 |
| `yt-dlp` | `bootstrap/arch.sh` / `bootstrap/macos.sh` 的 `PACKAGES` | 系统包层：`extra` / Homebrew |
| `scrapling` | `run_onchange_before_13-scrapling.sh.tmpl` | `uv tool install "scrapling[shell]"` + `playwright install chromium` |

`yt-dlp` 是系统包：两个平台的官方源都有，装在那里就能被 `pacman -Syu` / `brew upgrade`
带着更新，也不需要在仓库里再写一份升级逻辑。

`scrapling` 相反，是 per-user 的 Python 工具：走 `uv tool`，落在
`~/.local/share/uv/tools/scrapling`，shim 在 `~/.local/bin`。编号 13 是紧挨
`before_12-dev-runtimes.sh.tmpl`——后者负责装 `uv`，前者依赖它。两个脚本都在任何文件落盘
之前执行，都不需要 root，所以不进 `bootstrap/`。

## 上游 `scrapling install` 在 Arch 上必然失败

`scrapling install` 的顺序是：

```text
playwright install chromium      ← 这一步是有效的
playwright install-deps chromium ← apt-get，Arch 上没有 apt-get
tld 数据更新
写 .scrapling_dependencies_installed 标记
```

第二步在非 Debian 系统上直接抛异常（Playwright 不认识 Arch，会 fallback 到
`ubuntu24.04-x64` 的依赖清单，然后执行 `apt-get`），`CalledProcessError` 让整个命令以 1
退出，**marker 与 tld 更新都没跑到**。看起来像「Scrapling 装不上」，实际上浏览器已经下好，
缺的只是 apt。

脚本因此不复用上游命令，而是：

1. `"$py" -m playwright install chromium`——只做有效的那一半；`~/.cache/ms-playwright`
   里的 Chromium（含 `headless_shell` 与 ffmpeg，实测约 658 MB）对 `--force` 重装免疫；
2. 手写上游本会写的 marker 文件，让**手动**跑 `scrapling install` 时它是 no-op，而不是
   必然失败的 apt-get。

Arch 上 Playwright 每次下载都打印 `BEWARE: your OS is not officially supported by
Playwright; downloading fallback build for ubuntu24.04-x64.`。这只是提示：Ubuntu 与 Arch
的 glibc 兼容，实测三种 fetcher 都正常（见「验证」）。

## `[shell]`，不是 `[fetchers]`

webfetch 调用的是 `scrapling shell -L warning -c "..."`，而 `scrapling shell` 在跑那段
Python 之前会 `from IPython.terminal.embed import InteractiveShellEmbed`。只装
`scrapling[fetchers]` 时，连最简单的 `Fetcher.get()` 都过不去：

```text
ModuleNotFoundError: No module named 'IPython'
```

`scrapling[shell]` 的定义就是 `fetchers` + `IPython` + `markdownify`（见包内 `METADATA`
的 `Provides-Extra: shell`），所以脚本直接用它。

`StealthyFetcher` 不需要 camoufox：`scrapling/engines/_browsers/_stealth.py` 用的是
**patchright**（Playwright 的反检测分支），与 `DynamicFetcher` 共用上面的 Chromium。

## yt-dlp

pacman 的 `yt-dlp` 是 `2026.08.19-1`，实测 `webfetch` 的 JSON 路由（`-J` 元数据 + VTT
字幕 + 清理）在无 cookies 时就能成功。

webfetch 还实现了一条 cookies 递进重试：命令失败且 stderr 命中
`Sign in to confirm you're not a bot` 时，带 `--cookies-from-browser chrome` 重试。本机的
Chrome 在 `~/.local/bin/google-chrome-stable`，实测这条路径也能跑通（没有触发 keyring
解锁），所以 Arch 的 `python-secretstorage` 没有装——真遇上读不出 cookies 再补。

yt-dlp 的 YouTube 解析还需要 **JS runtime**，默认只启用 `deno`（优先级 deno > node >
quickjs > bun）。本机 `/usr/bin/deno` 来自 pacman 的 `deno` 包，**不在仓库的 `PACKAGES`
里**（`docs/dev-env.md` 的「未纳入」也记着它）。仓库装的 nvm Node 是备选运行时，但
yt-dlp 只认显式传参 `--js-runtimes node`，而 webfetch 不传。

## 未纳入

- **Windows**：`run_*.sh` 在 Windows 上被渲染成空字符串（见 `docs/design.md` 的 (c) 条），
  所以 `scrapling` 在 Windows 上不会被安装，webfetch 的通用网页路由在那台机器上仍不可用。
  `yt-dlp` 要纳管则进 `bootstrap/windows.bat` 的 scoop 清单。
- **`gh`**：一直是手工装、手工升级的；它不属于这条问题的范围。
- **网络前提**：本机的对外访问靠 mihomo 的 `proxy on`（`dot_zshrc.tmpl` 里那三个
  `*_proxy` 变量）。抓取类命令行会把代理环境继承下去，从没有代理的 shell 里跑 webfetch
  会连不上，与本文的安装无关。

## 验证

安装后实测（2026-10-02）：

```text
Fetcher.get('https://example.com')          → 200, 713 bytes
DynamicFetcher.fetch(...)                   → 200, 12747 bytes
StealthyFetcher.fetch(...)                  → 200, 12747 bytes
webfetch https://example.com                → fetcher 策略 + Defuddle，209 字符 Markdown
yt-dlp -J (watch?v=dQw4w9WgXcQ)             → youtube_video，人工字幕正文完整
yt-dlp --cookies-from-browser chrome -J ... → rc=0
```

一个回归点：如果哪天 `scrapling shell -c "print('ok')"` 报 `ModuleNotFoundError`，
先看 `[shell]` extra 是不是被换成 `[fetchers]` 了。
