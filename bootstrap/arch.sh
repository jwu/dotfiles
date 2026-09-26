#!/bin/bash
# One entry point for a bare Arch Linux machine: install chezmoi, clone this
# repo into ~/bin/dotfiles, point chezmoi at it and apply.
#
# Everything else -- packages, both waybar builds, the Rime dictionaries and the
# pi-config checkout -- is handled by this repo's run_* scripts, which chezmoi
# executes during apply. This script exists only because installing chezmoi
# cannot be done by chezmoi itself.
#
# Usage:
#   sh -c "$(curl -fsLS https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/arch.sh)"
#
# It replaces install-arch, which used to clone three repositories (configs,
# desktop-settings, pi-config) and run each one's installer. Those two retired
# repos are gone; pi-config is now cloned by run_once_after_50-pi-config.sh.
set -uo pipefail

REPO_SSH="${REPO_SSH:-git@github.com:jwu/dotfiles.git}"
REPO_HTTPS="${REPO_HTTPS:-https://github.com/jwu/dotfiles.git}"
SRC_DIR="${SRC_DIR:-$HOME/bin/dotfiles}"
CONFIG_DIR="$HOME/.config/chezmoi"

step() {
  local name="$1"
  shift
  local rc=0
  echo ""
  echo ">>> $name"
  "$@" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "    ok"
  else
    echo "    FAILED (exit $rc)" >&2
    return "$rc"
  fi
}

require() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" &> /dev/null; then
      echo "Error: $tool is required but not installed." >&2
      exit 1
    fi
  done
}

install_chezmoi() {
  if command -v chezmoi &> /dev/null; then
    echo "    chezmoi: $(chezmoi --version | head -1)"
    return 0
  fi
  # Arch ships chezmoi in extra, so it stays in step with system updates.
  sudo pacman -S --needed --noconfirm chezmoi
}

ensure_repo() {
  if [ -d "$SRC_DIR/.git" ]; then
    echo "    updating $SRC_DIR"
    git -C "$SRC_DIR" pull --ff-only || echo "    pull skipped (local changes or no network)"
    return 0
  fi
  mkdir -p "$(dirname "$SRC_DIR")"
  echo "    cloning into $SRC_DIR"
  # BatchMode keeps a first-time SSH connection from stopping on a host-key or
  # passphrase prompt: it fails immediately and the HTTPS fallback takes over
  # (the repo is public, so no token is needed).
  if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
    git clone "$REPO_SSH" "$SRC_DIR" 2> /dev/null; then
    return 0
  fi
  echo "    SSH clone failed, retrying over HTTPS"
  git clone "$REPO_HTTPS" "$SRC_DIR"
}

write_chezmoi_config() {
  # sourceDir is what lets `chezmoi diff` and the run_* scripts find the source,
  # which deliberately lives outside chezmoi's default location
  # (~/.local/share/chezmoi) so it sits next to the other ~/bin checkouts.
  mkdir -p "$CONFIG_DIR"
  if [ -f "$CONFIG_DIR/chezmoi.toml" ]; then
    echo "    keeping existing $CONFIG_DIR/chezmoi.toml"
    grep -q '^sourceDir' "$CONFIG_DIR/chezmoi.toml" \
      || echo "    warning: it has no sourceDir; chezmoi may not find $SRC_DIR" >&2
    return 0
  fi
  cat > "$CONFIG_DIR/chezmoi.toml" << EOF
sourceDir = "$SRC_DIR"
EOF
  echo "    wrote $CONFIG_DIR/chezmoi.toml (sourceDir = $SRC_DIR)"
}

apply() {
  chezmoi init --apply
}

echo ">>> dotfiles bootstrap (Arch)"
echo "    repo:      $REPO_SSH"
echo "    sourceDir: $SRC_DIR"

if ! command -v pacman &> /dev/null; then
  echo "Error: pacman is not available; this bootstrap targets Arch Linux." >&2
  exit 1
fi

require git curl sudo

step "install chezmoi" install_chezmoi || exit 1
step "clone/update dotfiles" ensure_repo || exit 1
step "configure chezmoi sourceDir" write_chezmoi_config || exit 1
step "chezmoi init --apply" apply || exit 1

echo ""
echo ">>> Done. During apply the run_* scripts installed packages, built the"
echo "    waybar modules, fetched the Rime dictionaries and cloned pi-config."
echo "    Re-run 'chezmoi apply' if any of those reported a failure above."
echo "    Log out and back in for the zsh default shell and fcitx5 to take effect."
