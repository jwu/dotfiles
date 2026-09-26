#!/bin/bash
# Arch's zed package only provides `zeditor`. Also provide the upstream name,
# which is what `zed <path>` and $EDITOR expect ($EDITOR needs `zed --wait`).
# A symlink is enough: the package keeps owning /usr/bin/zeditor, so this
# survives package updates. Skips itself when zed is not installed.
set -uo pipefail

if ! command -v zeditor &> /dev/null; then
  echo "zeditor not found; skipping (install the zed package first)."
  exit 0
fi

mkdir -p "$HOME/.local/bin"
ln -sf /usr/bin/zeditor "$HOME/.local/bin/zed"
echo "Installed $HOME/.local/bin/zed -> /usr/bin/zeditor"
