#!/bin/bash
# Arch's zed package names the upstream "zed" CLI "zeditor", so the command line
# only has `zeditor`. Provide the upstream name too -- it is what `zed <path>`
# and $EDITOR expect, and $EDITOR needs `zed --wait`. A symlink is enough: the
# package keeps owning /usr/bin/zeditor, so this survives package updates.
#
# Degrades to a skip note: zed is optional.
set -uo pipefail

if ! command -v zeditor &> /dev/null; then
  echo "zeditor not found; skipping (install the zed package first)."
  exit 0
fi

mkdir -p "$HOME/.local/bin"
ln -sf /usr/bin/zeditor "$HOME/.local/bin/zed"
echo "Installed $HOME/.local/bin/zed -> /usr/bin/zeditor"
