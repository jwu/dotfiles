#!/bin/bash
# One entry point for a Debian machine, and the only script here that needs root
# and an interactive terminal: install chezmoi, provision packages, clone the
# repo, point chezmoi at it, apply.
#
# Debian is used as a headless server here, so this installs no GUI packages and
# the repo's desktop targets are excluded by [data] headless = true in
# chezmoi.toml. Set HEADLESS=0 to provision a Debian desktop instead (the
# desktop packages still have to be installed by hand: they are not in PACKAGES).
#
# All sudo work lives here so `chezmoi apply` stays root-free and works without a
# TTY. See docs/ecs.md and docs/design.md, the bootstrap section.
#
# Usage:
#   HEADLESS=1 bash bootstrap/debian.sh
#
# A machine whose GitHub release downloads are blocked (the ECS this targets) can
# hand over a prebuilt binary instead of using get.chezmoi.io:
#   CHEZMOI_BIN=/tmp/chezmoi HEADLESS=1 bash bootstrap/debian.sh
set -uo pipefail

REPO_SSH="${REPO_SSH:-git@github.com:jwu/dotfiles.git}"
REPO_HTTPS="${REPO_HTTPS:-https://github.com/jwu/dotfiles.git}"
SRC_DIR="${SRC_DIR:-$HOME/bin/dotfiles}"
CONFIG_DIR="$HOME/.config/chezmoi"
HEADLESS="${HEADLESS:-0}"

# Debian's names differ from Arch's for two of these (fd-find ships `fdfind`,
# bat ships `batcat`); the zshrc calls the upstream names, so link_debian_names
# bridges the gap. Everything here is a terminal program: a headless box reads
# no GUI configuration, which is what the headless switch in chezmoi.toml means.
PACKAGES=(
  "zsh"
  "starship"
  "zoxide"
  "neovim"
  "fzf"
  "eza"
  "fd-find"
  "bat"
  "ripgrep"
  "git-delta"
  "jq"
  "unzip"
  "tmux"
  # pi-webfetch's YouTube/Bilibili route; scrapling itself is per-user, see
  # run_onchange_before_13-scrapling.sh.tmpl and docs/pi-webfetch.md.
  "yt-dlp"
  # gcc keeps the run_* scripts that compile helpers from aborting an apply;
  # make is here for language toolchains installed later.
  "build-essential"
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
    if ! command -v "$tool" &> /dev/null; then
      echo "Error: $tool is required but not installed." >&2
      exit 1
    fi
  done
}

# ==========================================
# chezmoi itself
# ==========================================

install_chezmoi() {
  if command -v chezmoi &> /dev/null; then
    echo "    chezmoi: $(chezmoi --version | head -1)"
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  # Debian carries no chezmoi package, so the binary comes from either the
  # caller's copy or upstream's installer. The installer fetches the GitHub
  # release, which is blocked on the ECS this repo targets; CHEZMOI_BIN is the
  # escape hatch there (the dev machine downloads the linux_amd64 tarball and
  # scp's it over). See docs/ecs.md.
  if [ -n "${CHEZMOI_BIN:-}" ]; then
    install -m 0755 "$CHEZMOI_BIN" "$HOME/.local/bin/chezmoi"
  else
    BINDIR="$HOME/.local/bin" sh -c "$(curl -fsLS https://get.chezmoi.io)"
  fi
  command -v chezmoi &> /dev/null && chezmoi --version | head -1
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
  if [ "$HEADLESS" = "1" ]; then
    # Read by .chezmoiignore and the GUI-only run_* scripts; a missing key means
    # a desktop, so only headless machines get the section.
    cat >> "$CONFIG_DIR/chezmoi.toml" << EOF

[data]
headless = true
EOF
  fi
  echo "    wrote $CONFIG_DIR/chezmoi.toml (sourceDir = $SRC_DIR, headless = $HEADLESS)"
}

# ==========================================
# Root-only provisioning
# ==========================================

install_packages() {
  echo "    Installing/updating: ${PACKAGES[*]}"
  sudo apt-get update || return 1
  # DEBIAN_FRONTEND keeps a package that grew a debconf question on an upgrade
  # from stopping an unattended run on a TTY prompt.
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PACKAGES[@]}"
}

# Debian renames two binaries the zshrc calls by their upstream names. ~/bin is
# first on PATH in dot_zshrc.tmpl, so the links win over the packaged names.
link_debian_names() {
  mkdir -p "$HOME/bin"
  local pair src dst
  for pair in "fd:fdfind" "bat:batcat"; do
    dst="${pair%%:*}"
    src="${pair##*:}"
    if ! command -v "$src" &> /dev/null; then
      echo "    $src is not installed; skipping the $dst link" >&2
      continue
    fi
    ln -sf "$(command -v "$src")" "$HOME/bin/$dst"
    echo "    $HOME/bin/$dst -> $(command -v "$src")"
  done
}

# chsh rejects an empty -s argument with "shell must be a full path name", which
# says nothing about the real cause: zsh was never installed because the apt step
# above failed. It also asks for the user's own password via PAM, which is
# another reason this cannot live in a run_ script.
set_default_shell() {
  local zsh
  if ! zsh="$(command -v zsh)"; then
    echo "    zsh is not installed (see the apt step above); skipping." >&2
    return 1
  fi
  if [ "${SHELL:-}" = "$zsh" ]; then
    echo "    zsh is already the default shell."
    return 0
  fi
  echo "    Changing default shell to zsh ($zsh)..."
  chsh -s "$zsh" || return 1
}

# ==========================================
# Run
# ==========================================

echo ">>> dotfiles bootstrap (Debian, headless=$HEADLESS)"
echo "    repo:      $REPO_SSH"
echo "    sourceDir: $SRC_DIR"

if ! command -v apt-get &> /dev/null; then
  echo "Error: apt-get is not available; this bootstrap targets Debian/Ubuntu." >&2
  exit 1
fi

require git curl sudo

step_required "install chezmoi" install_chezmoi
step_required "clone/update dotfiles" ensure_repo
step_required "configure chezmoi sourceDir" write_chezmoi_config

step "apt packages" install_packages
step "Debian binary names (fd, bat)" link_debian_names
step "default shell (zsh)" set_default_shell

step_required "chezmoi init --apply" chezmoi init --apply

summary
echo ""
echo ">>> Log out and back in for the zsh default shell to take effect."
echo "    From now on 'chezmoi apply' needs no root and works without a terminal."
