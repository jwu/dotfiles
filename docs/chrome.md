# Chrome：视频、硬解与 Vulkan

这台机器（Intel Iris Plus Graphics 650 / Kaby Lake GT3e、i915、niri）上，Chrome 的
`--enable-features=Vulkan` 会同时造成两件事：

1. 所有网页视频**白屏**；
2. VA-API 硬件解码**完全不初始化**（i915 的 VCS 引擎保持 0ms）。

两件事都只在 Skia 后端被切到 `GaneshVulkan` 时出现。所以 `chrome-flags.conf` 的
口径是**不启用 Vulkan**，只开硬解：

```
--enable-features=AcceleratedVideoDecodeLinuxGL
```

代价是 WebGPU 没有硬件 adapter（`requestAdapter()` 返回 null；加
`--enable-unsafe-webgpu` 会退到 SwiftShader 软渲染）。这是刻意的取舍：
`~/dev/vgpu-render/` 需要硬件 WebGPU 时用 `chrome-webgpu`，见下。

这套配置只对纯 Intel 显卡的机器有意义，所以源是 `chrome-flags.conf.tmpl`：
渲染时用 `lspci -d ::0300` 判断，只有「有 Intel 显卡且没有 NVIDIA/AMD 显卡」才加那行
feature。带独显的机器（比如那台 4070Ti）拿到的仍是两行代理；`chrome-webgpu` 启动器与
它的 desktop 条目由 `.chezmoiignore` 里的同一条件排除。判据逻辑实测过三种输入：
纯 NVIDIA / 纯 Intel / Intel+NVIDIA 混合，后两种里只有第二种会渲染出那段。

## 实测矩阵

真实会话里启动独立 profile 的 Chrome，用 CDP `Page.captureScreenshot` 截图、
FFmpeg `signalstats` 取平均亮度判显示是否正常（正常播放的暗色画面 YAVG≈29，
白屏≈211.7，黑屏≈0.7），用 `/proc/<gpu-pid>/fdinfo/*` 里 i915 的
`drm-engine-video` 增量判硬解，用同一页面的 `navigator.gpu.requestAdapter()` 判 WebGPU：

| 配置 | 视频显示 | 硬解 | WebGPU |
| --- | --- | --- | --- |
| 无 Vulkan、无硬解 feature | 正常 | ❌ | null adapter |
| 无 Vulkan + `AcceleratedVideoDecodeLinuxGL` | 正常 | ✅ 499ms/5s | null adapter |
| `Vulkan`（任意组合） | 白屏 | ❌ 0ms | Intel 硬件 adapter |
| `Vulkan --ozone-platform=x11` | 正常 | ❌ | Intel 硬件 adapter，渲染正常 |
| `Vulkan --disable-gpu-compositing` | 正常 | ❌ | adapter 有，canvas 不显示 |
| 无 Vulkan + `--enable-unsafe-webgpu` | 正常 | — | SwiftShader |

`video` 元素本身始终正常：`readyState=4`、`videoWidth/Height` 正确、`currentTime`
前进。坏的是视频帧作为 GPU 纹理的路径——Vulkan 下 `canvas.drawImage(video)` 读出来
接近全黑（平均 0），GL 下读得到（平均 36.8）。

`chrome://gpu` 能直接看到后端：带 Vulkan feature 时 `Skia Backend: GaneshVulkan`，
否则 `GaneshGL`。

## 硬解的量化

1080p60 H.264 播放 6 秒的 CPU 占用：

| | renderer | gpu-process | i915 VCS |
| --- | --- | --- | --- |
| 软解（Vulkan 下） | 34% | 11% | 0ms/5s |
| 硬解（`AcceleratedVideoDecodeLinuxGL`） | 6% | 17% | 499ms/5s |

`--enable-features` 是**后者覆盖前者**：同一行里写
`--enable-features=Vulkan,AcceleratedVideoDecodeLinuxGL` 并不会两个都生效，
而是两个都按合并列表处理，但 Vulkan 一旦在内，硬解仍然不初始化。

驱动侧本身是好的：`intel-media-driver` 装好后

```
ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -i in.mp4 -f null -
```

能走通 `iHD_drv_video.so`（1209 帧零错误），Chrome 的 GPU 进程也会加载
`iHD_drv_video.so` + `libva-drm.so` 并打开 `/dev/dri/renderD128`。

## 需要 WebGPU 时

用 `~/.local/bin/chrome-webgpu`（源在 `dot_local/bin/executable_chrome-webgpu`）。
它带 `--ozone-platform=x11 --enable-features=Vulkan` 和独立 profile
（`~/.local/share/chrome-webgpu`），能与日常 Chrome 同时运行。命令行里的
`--enable-features` 排在 wrapper 读的 `chrome-flags.conf` 之后，会覆盖那行的
`AcceleratedVideoDecodeLinuxGL`，所以这个实例不会去试硬解。

已验证：`requestAdapter()` 拿到 Intel gen-9 硬件 adapter，WebGPU 画布内容可见，
同一实例播放本地视频正常（截图 YAVG≈30）。

启动器也注册到了 fuzzel：`dot_local/share/applications/google-chrome-webgpu.desktop.tmpl`
提供 `Google Chrome (WebGPU)` 条目，与 `Google Chrome` 并列。它故意不带 `MimeType`，
不会去抢 http/https 的默认处理器。

这一整套（`chrome-flags.conf` 的硬解行、启动器、desktop 条目）都只部署在纯 Intel
显卡的机器上，带独显的机器不需要：那边 Vulkan WebGPU 本来就能直接跑。

## 被否的方向

- **去掉 Vulkan、保留软件 WebGPU**（`--enable-unsafe-webgpu`）：视频正常，但 adapter
  是 SwiftShader，做不了真实的 GPU 工作负载。
- **`--disable-gpu-compositing`**：视频正常、Dawn 仍有硬件 adapter，但 WebGPU canvas
  内容不显示，等于不可用。
- **XWayland + Vulkan**：视频与硬件 WebGPU 都能用，但失去硬解，且不再是原生 Wayland。
- **等上游修**：Chrome 154 里没有把 Skia-GL 与 Dawn-Vulkan 分开的开关；
  `--use-gl` / `--use-angle` 一改，Vulkan 也被一起绕开，WebGPU 回到 null adapter。

## 诊断方法

- **wrapper 会偷偷加参数**：Arch 的 `/usr/bin/google-chrome-stable` 读
  `~/.config/chrome-flags.conf`。所谓「无 flag」的对照实例其实也带着这份文件，要测
  干净基线得用 `XDG_CONFIG_HOME=<空目录>` 或直接调 `/opt/google/chrome/chrome`。
- **判白屏别只看 `readyState`**：解码正常但合成失败是最迷惑的一种；截图取亮度
  比看播放状态可靠。
- **`/tmp` 是 tmpfs**：测试 profile 各占 100MB+，写满后 Chrome 会写出损坏的 cache，
  表现为视频黑屏、日志里全是 `disk I/O error`。排查前先 `df -h /tmp`。
- **硬解判据用 fdinfo**：`drm-engine-video` 的时间增量比 CPU 占用直接。

## 顺带记一笔

10-17 的 Crash Reports 里，87 个 GPU 进程崩溃 dump 全部来自带
`--enable-features=Vulkan` 的实例，堆栈里能看到 ANGLE 跑在
`Vulkan 1.4.354 (Intel Iris Plus Graphics 650)` 上。这个 feature 在这代硬件上
本身就不稳，视频白屏只是它更常见的表现。
