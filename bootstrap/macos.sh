#!/bin/bash
# One entry point for a bare macOS machine: install chezmoi, provision packages
# with Homebrew, clone the repo, point chezmoi at it, apply. The counterpart of
# bootstrap/arch.sh, with the same split -- every action needing root or a
# terminal lives here so `chezmoi apply` stays root-free and works without a TTY.
# See docs/chezmoi-notes.md.
#
# Homebrew is the one chicken-and-egg step this script cannot solve; install it
# first (https://brew.sh).
#
# Usage (bash, not sh: macOS /bin/sh is bash in POSIX mode, without arrays):
#   bash -c "$(curl -fsLS https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/macos.sh)"
set -uo pipefail

REPO_SSH="${REPO_SSH:-git@github.com:jwu/dotfiles.git}"
REPO_HTTPS="${REPO_HTTPS:-https://github.com/jwu/dotfiles.git}"
SRC_DIR="${SRC_DIR:-$HOME/bin/dotfiles}"
CONFIG_DIR="$HOME/.config/chezmoi"

# Formula list evolved from the retired jwu/configs mac/install.sh. None of the
# Linux side's packages (hyprland, niri, waybar, fcitx5, gtk3, ...) appear here:
# they have no macOS build and the matching configs are excluded by
# .chezmoiignore on darwin.
PACKAGES=(
  "chezmoi"
  "coreutils"
  "git"
  "ripgrep"
  "starship"
  "zoxide"
  "neovim"
  "fzf"
  "eza"
  "fd"
  "bat"
  "git-delta"
  "jq"
  "just"
  "cocogitto"
  "yazi"
  "gitui"
  "glow"
  "zsh"
)

# GUI applications and fonts ship as casks, not formulae.
# input-source-pro must stay here rather than being left to the docs: the
# run_once_ that imports its exported settings is consumed if it fires before
# the app exists.
CASKS=(
  "neovide"
  "input-source-pro"
  "font-fira-mono-nerd-font"
)

FAILED_STEPS=()

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
    FAILED_STEPS+=("$name")
    echo "    FAILED (exit $rc); continuing" >&2
  fi
  return 0
}

# Hard dependency: without chezmoi nothing after this can run.
step_required() {
  local name="$1"
  shift
  echo ""
  echo ">>> $name"
  if ! "$@"; then
    echo "    FAILED; cannot continue" >&2
    exit 1
  fi
  echo "    ok"
}

summary() {
  echo ""
  echo "=========================================="
  if [ "${#FAILED_STEPS[@]}" -eq 0 ]; then
    echo ">>> All steps completed."
    return 0
  fi
  echo ">>> Finished with ${#FAILED_STEPS[@]} failed step(s):"
  local s
  for s in "${FAILED_STEPS[@]}"; do
    echo "      - $s"
  done
  echo ""
  echo "    Fix these and re-run; every step is idempotent."
  return 1
}

require() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" > /dev/null 2>&1; then
      echo "Error: $tool is required but not installed." >&2
      exit 1
    fi
  done
}

# ==========================================
# Steps
# ==========================================

# Homebrew is the package manager and the source of the zsh below; it cannot
# install itself. The two prefixes cover Apple Silicon and Intel.
ensure_brew() {
  if command -v brew > /dev/null 2>&1; then
    echo "    brew: $(command -v brew)"
    return 0
  fi
  local prefix
  for prefix in /opt/homebrew /usr/local; do
    if [ -x "$prefix/bin/brew" ]; then
      echo "    brew found at $prefix/bin/brew; add it to PATH and re-run" >&2
      return 1
    fi
  done
  echo "    brew is not installed; install it from https://brew.sh and re-run." >&2
  return 1
}

install_chezmoi() {
  if command -v chezmoi > /dev/null 2>&1; then
    echo "    chezmoi: $(chezmoi --version | head -1)"
    return 0
  fi
  brew install chezmoi
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

install_formulae() {
  echo "    Installing/updating: ${PACKAGES[*]}"
  # No --needed equivalent: brew install is a no-op for an up-to-date formula.
  brew install "${PACKAGES[@]}"
}

install_casks() {
  echo "    Installing casks: ${CASKS[*]}"
  brew install --cask "${CASKS[@]}"
}

# chsh goes through PAM and prompts for the user's own password, so it can only
# run in a terminal -- the same reason it lives in bootstrap and not in a run_
# script. It also only accepts shells listed in /etc/shells, and Homebrew's zsh
# is not added there automatically.
set_default_shell() {
  local zsh
  zsh="$(brew --prefix)/bin/zsh"
  if [ ! -x "$zsh" ]; then
    echo "    $zsh is missing (see the Homebrew step above); skipping." >&2
    return 1
  fi
  if [ "${SHELL:-}" = "$zsh" ]; then
    echo "    $zsh is already the default shell."
    return 0
  fi
  if ! grep -qx "$zsh" /etc/shells; then
    echo "    Adding $zsh to /etc/shells (needs sudo)..."
    echo "$zsh" | sudo tee -a /etc/shells > /dev/null || return 1
  fi
  echo "    Changing default shell to $zsh..."
  chsh -s "$zsh"
}

# ==========================================
# Run
# ==========================================

echo ">>> dotfiles bootstrap (macOS)"
echo "    repo:      $REPO_SSH"
echo "    sourceDir: $SRC_DIR"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Error: this bootstrap targets macOS; use bootstrap/arch.sh on Linux." >&2
  exit 1
fi

require git curl

step_required "Homebrew" ensure_brew
step_required "install chezmoi" install_chezmoi
step_required "clone/update dotfiles" ensure_repo
step_required "configure chezmoi sourceDir" write_chezmoi_config

step "Homebrew formulae" install_formulae
step "Homebrew casks (Neovide, Input Source Pro, FiraMono Nerd Font)" install_casks
step "default shell (zsh)" set_default_shell

step_required "chezmoi init --apply" chezmoi init --apply

summary
echo ""
echo ">>> Restart your terminal for the new login shell and the zsh config."
echo "    From now on 'chezmoi apply' needs no root and works without a terminal."
