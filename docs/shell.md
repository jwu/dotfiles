# zsh

`dot_zshrc.tmpl` 用 `{{ if eq .chezmoi.os }}` 分平台。两处值得记下的坑：

## nvm 有两种装法，只认一种会让它静默消失

macOS 分支必须同时认：

- Homebrew 的 formula 装在 `$(brew --prefix nvm)`；
- `git clone` 装的在 `$NVM_DIR`。

原本只探 brew 那一路。问题在于 **`brew --prefix nvm` 对一个没有安装的 formula 也会
打印一个路径并以 0 退出**——所以它不会报错，只会让 nvm 加载不到。只能靠 `-s` 探
文件本身，不能看命令是否成功。

## Apple Silicon 的 MPS 变量

```sh
export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
```

PyTorch 的 MPS 后端没有覆盖全部算子，缺算子时默认直接报错而不是回落到 CPU。高水位
设为 0 是避免它在显存紧张时把张量提前换出。

这两个变量只在 darwin 设：对 Linux 没有意义，而源曾经是从 Linux 生成的，所以它们
一度被漏掉，`apply` 会把它们从这台机器上删掉。

## 模板空白的坑

`{{ if }}` / `{{ end }}` 独占一行时，自身贡献一个换行（充当空行）；而 `-}}` 会吃掉
**所有**连续空白，不是一个换行。用错就会丢空行，所以改动这段后要渲染比对：

```bash
chezmoi execute-template < dot_zshrc.tmpl | diff - ~/.zshrc
```

## 其它

- `PI_NERD_FONTS` / `COLORTERM` 只在 Linux 设。
- macOS 的 `/Applications/*` alias 只在 darwin 设。
