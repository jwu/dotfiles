# lightpanda

lightpanda 是一个用 Zig 写的原生 headless 浏览器：无 Chromium、无 Node、无 Python 依赖，
提供 `fetch`（一次性抓取）、`serve`（CDP WebSocket 服务）、`mcp`（MCP server）与 `agent`
（自带 LLM 的浏览循环）。本机把它接进了 pi 的内置 MCP，用来替代「为了读一个页面而拉起
658 MB Chromium」的那条路。

本文只记**本机实测出来的边界**：能做什么、哪一条不能指望它、以及接入 pi 的方式。

## 落点

| 项 | 值 |
| --- | --- |
| 包 | AUR `lightpanda-nightly-bin`（`pacman -Q` 显示 `1.1.0+nightly.10724+6891af6b3-1`） |
| 二进制 | `/usr/bin/lightpanda` |
| 来源 | 手工 `yay` 装，**不在** `bootstrap/` 的 `PACKAGES` 里 |

它没有进装机清单：nightly 是滚动构建（版本号里的 commit 每次升级都变），而
`bootstrap/` 里的包都要求两个平台都有官方源。要纳管就得先进 `bootstrap/arch.sh` 的 AUR
段，并接受版本号无法固定。

## 实测（2026-10-18）

### `fetch --dump`

单页抓取的墙钟时间，同一台机器、直连（未走 mihomo 代理）：

```text
lightpanda fetch --dump markdown https://example.com      0.97s / 1.02s / 0.97s（三次）
lightpanda fetch --dump markdown https://news.ycombinator.com   1.3s
lightpanda fetch --dump markdown https://github.com/…           2.9s
scrapling shell -c "Fetcher.get('https://example.com')"         1.24s
```

单次差距不大——`scrapling` 的时间大头是解释器与 import，不是浏览器。真正的区别是依赖
体积与并发：lightpanda 是约 20 MB 的静态二进制，可以同时起十几个；`scrapling` 每个进程
都要拖 Python 栈。

`--dump` 支持 `html`、`markdown`、`pdf`、`png`、`semantic_tree`、`semantic_tree_text`、
`structured_data`。`--dump-max-bytes` **只对 html 与 markdown 有效**，传别的会直接
`fatal: --dump-max-bytes needs text`。

两处值得单独记：

- `structured_data` 干净得可以直接进 prompt：`jsonLd` / `openGraph` / `twitterCard` /
  `meta` / `link` 分好组，没有噪声。
- `semantic_tree_text` 是给模型看的紧凑视图，一行一个节点带 role 与 accessible name
  （`22 'Sorry, we're not able to serve your requests this quickly.'`）。

### markdown 不提取正文

这是它**不能**替代 webfetch 那条路的原因。`gh repo` 页面 dump 出来的开头是导航菜单：

```text
## Navigation Menu
[Homepage](https://github.com/)
[Sign in](https://github.com/login?return_to=…)
- Platform
  - AI CODE CREATION
    - [GitHub CopilotWrite faster with AI](…)
```

`lightpanda` 只做 DOM → Markdown，不做 Readability 式正文抽取。webfetch 走的是
Scrapling 取 HTML 再经 Defuddle 清洗（见 `docs/pi-webfetch.md`），正文优先。所以两者
不冲突：要**正文**用 webfetch，要**整页 DOM / 语义树 / 交互**用 lightpanda。

### CDP

`lightpanda serve --port 9333` 之后 `/json/version` 返回 `"Protocol-Version": "1.3"`，
`Target.createTarget` → `Target.attachToTarget` → `Page.navigate` → `Runtime.evaluate`
整条链在 Node 24 的原生 `WebSocket` 上跑通，不需要 puppeteer。

JS 是真的在跑：`data:text/html` 里用 `setTimeout(…, 300)` 改 DOM，evaluate 读到
`JS ran Lightpanda/1.0`。纯 CSR 站点也能渲染：

```text
excalidraw.com   load 1.2s，336 个节点，title 'Excalidraw Whiteboard'
linear.app       load 4.0s，4766 个节点，title/正文都出来了
```

端口要绕开 9222：本机的 Chrome 常驻监听它（`chrome-devtools-mcp` 也接在那里），
lightpanda 撞上会 `fatal: address already in use`。

### MCP

`lightpanda mcp`（stdio）暴露 32 个工具，覆盖面比预期宽：

- 读：`goto`、`markdown`、`html`、`tree`、`structuredData`、`links`、`extract`、`nodeDetails`
- 动：`click`、`fill`、`hover`、`press`、`scroll`、`selectOption`、`setChecked`、`detectForms`
- 等：`waitForSelector`、`waitForScript`、`waitForState`
- 环境：`getCookies`、`search`（brave 等搜索引擎）、`screenshot`（文字布局渲染，不是像素级）
- 会话：`session_new` / `session_list` / `session_close`，多页面互相隔离
- 逃生口：`evaluate`、`save`（把当前会话存成可重放脚本）

## 接入 pi

`~/.pi/agent/mcp.json` 是 `create_` 目标（源 `create_mcp.json`）：**只在目标不存在时渲染
一次**，之后由 `/mcp` 与 `pi mcp add` 回写。因此两边要分别改：

```json
"lightpanda": {
  "command": "lightpanda",
  "args": ["mcp"],
  "exposure": "codemode",
  "description": "Headless browser without Chrome: …"
}
```

- **源**（`private_dot_pi/private_agent/create_mcp.json`）决定新机器拿到什么。
- **本机**（`~/.pi/agent/mcp.json`）必须手工同步或用 `pi mcp add`，`chezmoi apply` 不会碰它。

`pi mcp add` 也能写，但它用自己那条 `JSON.stringify` 路径重排格式（把 `"args": ["blender-mcp"]`
展开成三行）。源里统一用行内短数组，手工对齐比事后收拾更省事。

`exposure` 用 `codemode`：32 个工具全列进系统提示太占位置，而且绝大多数会话只用到
`goto` + `markdown`。工具名为 `mcp__lightpanda__<tool>`，改完要在会话里 `/reload` 才出现。

这些工具是**有状态**的：`markdown` 没有 `url` 参数，只渲染「当前页面」，所以一次读取是
两步——`goto({url})` 建立页面，再 `markdown({selector?})` 取子树。

## 与 chrome-devtools 分工

两个 server 同时启用，边界靠「需不需要真实浏览器」划。lightpanda 的三个硬限制都是实测出来的：

| 限制 | 实测 | 后果 |
| --- | --- | --- |
| `--load-resources` 在 fetch 下默认 `none` | 日志 `$msg="iframes disabled"` | iframe / image 根本不请求，YouTube、B 站 dump 出的是空壳 |
| `--user-agent` 不能含 `Mozilla` | `fatal: invalid user-agent err=Reserved hint="… can't contain Mozilla"` | 伪装不了 Chrome，反爬站给登录墙；`--http-header` 覆盖 UA 也走同一条校验 |
| 无 WebGL、无 serviceWorker | evaluate 得 `webgl: false`、`serviceWorker: false`（canvas2d、fetch、shadow DOM、IntersectionObserver 都有） | 3D、地图、图表类渲染不出来 |

打开子资源并等到 `networkidle` 能救回内容，代价同时也是实测的：

```text
--load-resources iframe --load-resources image --wait-until networkidle
example.com    1.0s → 1.0s
bilibili.com   2.5s → 3.1s（首页导航出来）
youtube.com    3.5s → 5.6s（首页导航出来）
```

`mcp` 与 `agent` 子命令的 `--load-resources` 默认是 `stylesheet`，不是 `none`——默认值按
子命令变，这是唯一容易记反的地方。

分工：

| 场景 | 选 | 为什么 |
| --- | --- | --- |
| 读一篇文章 / 文档正文 | **都不是**，用 webfetch | Scrapling + Defuddle 抽正文；这两个只会吐整页导航 |
| 登录态站点（X 时间线、内部后台、要 cookie 的页面） | chrome-devtools | 日常 Chrome 本来就在登录态；lightpanda 要手工导 `cookies.txt` |
| 调自己正在开发的页面：样式、网络、Lighthouse、性能 trace、堆快照 | chrome-devtools | lightpanda 没有这些面板能力，`screenshot` 还是文字布局渲染而非像素 |
| 像素级截图 / 视频 / 3D / 地图 | chrome-devtools | lightpanda `webgl: false` |
| 批量抓 20+ 页、要并发与隔离 | lightpanda | 约 20 MB 静态二进制，`session_new` 给每个客户端独立 cookie 与页面，且不抢正在用的浏览器窗口 |
| 只要结构：DOM 树、表单字段、可点元素、链接表 | lightpanda | `tree` / `interactiveElements` / `detectForms` / `links` 直出，比 `take_snapshot` 轻 |
| 一次性探查、不想起 GUI | lightpanda | `fetch --dump` 一行，不必先有 Chrome 在 9222 上挂着 |

一句话：chrome-devtools 是「我的浏览器，帮我看」，lightpanda 是「一群用完就扔的浏览器」。
先问两个问题——需要真实登录态或真实渲染吗？需要调试面板吗？任一为是就用 chrome-devtools。

lightpanda 唯一会把人坑住的地方是**它默认什么都不加载**：dump 出空页面时先加
`--load-resources iframe --load-resources image` 与 `--wait-until networkidle`，而不是怀疑站点。

## 未纳入

- **`agent` / `run`**：内置 LLM 浏览循环，可用 `--provider` 接各家 API，也能 `--save` 出
  可重放脚本。本机没配它的 key，没测；pi 自己就是 agent，需要时再评估。
- **`--adblock-lists` / `--block-private-networks`**：默认不拦。要读内网页面（本机 dev
  server）时这正好，所以没开。
- **Windows / macOS**：`lightpanda` 有这两个平台的构建，但仓库只在这里手工装了一份；
  另一台机器要用得自己装。

## 验证

```bash
lightpanda fetch --dump markdown --dump-max-bytes 400 https://example.com   # 有输出即通
lightpanda fetch --dump markdown --load-resources iframe --load-resources image \
  --wait-until networkidle https://www.youtube.com                            # 能读到导航即子资源路径正常
lightpanda serve --port 9333 & curl -s http://127.0.0.1:9333/json/version   # CDP 在
pi mcp list | grep -A1 lightpanda                                           # 32 tools, connected
```

`pi mcp list` 里显示 `connected` 但工具数为 0，通常是 `lightpanda` 不在 PATH——`command`
是裸名字，pi 用会话的 PATH 解析，从 GUI 启动的会话可能看不到 `~/.local/bin`。
