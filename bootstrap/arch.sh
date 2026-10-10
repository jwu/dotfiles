#!/bin/bash
# One entry point for a bare Arch Linux machine, and the only script here that
# needs root and an interactive terminal: install chezmoi, provision packages,
# clone the repo, point chezmoi at it, apply.
#
# All sudo work lives here so `chezmoi apply` stays root-free and works without a
# TTY. See docs/chezmoi-notes.md and docs/design.md, the bootstrap section.
#
# Usage:
#   sh -c "$(curl -fsLS https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/arch.sh)"
set -uo pipefail

REPO_SSH="${REPO_SSH:-git@github.com:jwu/dotfiles.git}"
REPO_HTTPS="${REPO_HTTPS:-https://github.com/jwu/dotfiles.git}"
SRC_DIR="${SRC_DIR:-$HOME/bin/dotfiles}"
CONFIG_DIR="$HOME/.config/chezmoi"

# The toolchain (go/gcc/make/pkgconf/gtk3) is listed here rather than installed
# by the build scripts: those run without root, and installing belongs in one
# place.
PACKAGES=(
  "zsh"
  "starship"
  "zoxide"
  "neovim"
  "tree-sitter-cli"
  "fzf"
  "eza"
  "fd"
  "ripgrep"
  "bat"
  "git-delta"
  "jq"
  "just"
  "cocogitto"
  "unzip"
  # pi-webfetch's YouTube/Bilibili route; scrapling itself is per-user, see
  # run_onchange_before_13-scrapling.sh.tmpl and docs/pi-webfetch.md.
  "yt-dlp"
  "terminus-font"
  "otf-firamono-nerd"
  "niri"
  "hyprland"
  "nautilus"
  "ghostty"
  "alacritty"
  "waybar"
  "swaylock"
  "swayidle"
  "hyprlock"
  "fcitx5"
  "fcitx5-gtk"
  "fcitx5-qt"
  "fcitx5-rime"
  "fcitx5-configtool"
  "cliphist"
  "fuzzel"
  "wtype"
  "wl-clipboard"
  # Screenshot/annotation flow (Mod+Shift+A / Print); see docs/niri.md.
  # portal-wlr is what implements the portal Screenshot interface on niri for
  # flameshot; the grim + slurp it pulls in are its own capture tools, not
  # something flameshot calls. wayland-utils serves the niri-flameshot-gui
  # helper, which needs wl_output order only when there is more than one output.
  "xdg-desktop-portal"
  "xdg-desktop-portal-gtk"
  "xdg-desktop-portal-wlr"
  "flameshot"
  "satty"
  "wayland-utils"
  "noto-fonts-cjk"
  "noto-fonts-emoji"
  "noto-fonts"
  "adwaita-fonts"
  "ttf-sarasa-gothic"
  "go"
  "gcc"
  "make"
  "pkgconf"
  "gtk3"
  "git"
  # Rust is installed per-user by run_onchange_before_12-dev-runtimes.sh.tmpl;
  # see docs/dev-env.md.
)

XWS_PKG="xwayland-satellite"
XWS_AUR_PKG="xwayland-satellite-git"

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

# ==========================================
# Root-only provisioning
# ==========================================

# A pacman transaction is atomic: one file that cannot be retrieved rolls the
# whole upgrade back and installs nothing, so every later step that needs these
# packages fails too. The usual cause is the DB of the mirror listed first in
# /etc/pacman.d/mirrorlist being a few hours behind: a package was rebuilt, that
# mirror still lists the old version, and the old file is already gone from every
# mirror. Fix the mirrorlist first, then -Syy -- -Syy alone re-reads the same
# stale mirror.
install_packages() {
  echo "    Installing/updating: ${PACKAGES[*]}"
  if sudo pacman -Syu --needed --noconfirm "${PACKAGES[@]}"; then
    return 0
  fi
  echo "    pacman failed: a failed transaction installs no package at all." >&2
  echo "    A 404 on 'failed retrieving file' means the first mirror is behind." >&2
  echo "    Fix /etc/pacman.d/mirrorlist, run 'sudo pacman -Syy', then re-run." >&2
  return 1
}

# yay: the AUR helper used for xwayland-satellite-git. yay-bin ships a prebuilt
# x86_64 binary, so bootstrapping the helper needs no Go/Rust toolchain and no
# long compile. This has to run before install_xwayland_satellite(), which skips
# itself when no helper is on PATH.
ensure_yay() {
  if command -v yay &> /dev/null; then
    echo "    yay: $(command -v yay)"
    return 0
  fi
  # makepkg refuses to build as root, and every privileged action already goes
  # through sudo.
  if [ "$(id -u)" -eq 0 ]; then
    echo "    yay is missing and makepkg cannot run as root; run this as a normal user" >&2
    return 1
  fi
  echo "    yay: installing base-devel"
  sudo pacman -S --needed --noconfirm base-devel || return 1
  local tmp
  tmp="$(mktemp -d)" || return 1
  echo "    yay: building yay-bin from the AUR"
  if ! git clone --quiet https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"; then
    rm -rf "$tmp"
    return 1
  fi
  if ! (cd "$tmp/yay-bin" && makepkg -si --noconfirm); then
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
  command -v yay &> /dev/null
}

# extra's xwayland-satellite 0.8.2-1 hands the X input focus to
# override-redirect popups on their first configure, so an X11 dropdown is
# dismissed the moment it appears: Steam's top bar only flashes. Upstream fixed
# the focus rules in #494 but cut no release, and the AUR -git package tracks
# master. See docs/xwayland-satellite.md.
install_xwayland_satellite() {
  echo "    Target: $XWS_AUR_PKG"
  if pacman -Q "$XWS_AUR_PKG" &> /dev/null; then
    echo "    Already installed: $(pacman -Q "$XWS_AUR_PKG")"
    return 0
  fi
  if ! command -v yay &> /dev/null; then
    echo "    yay is required to install $XWS_AUR_PKG; skipping (X11 menus under Steam keep closing instantly)." >&2
    return 1
  fi
  # The -git package provides/conflicts $XWS_PKG, so drop the repo package first
  # rather than let pacman hit its conflict prompt under --noconfirm.
  if pacman -Q "$XWS_PKG" &> /dev/null; then
    sudo pacman -R --noconfirm "$XWS_PKG" || return 1
  fi
  yay -S --needed --noconfirm "$XWS_AUR_PKG" || return 1
}

# chsh rejects an empty -s argument with "shell must be a full path name", which
# says nothing about the real cause: zsh was never installed because the pacman
# step above failed. It also asks for the user's own password via PAM, which is
# another reason this cannot live in a run_ script.
set_default_shell() {
  local zsh
  if ! zsh="$(command -v zsh)"; then
    echo "    zsh is not installed (see the pacman step above); skipping." >&2
    return 1
  fi
  if [ "${SHELL:-}" = "$zsh" ]; then
    echo "    zsh is already the default shell."
    return 0
  fi
  echo "    Changing default shell to zsh ($zsh)..."
  chsh -s "$zsh" || return 1
}

# TTY font. Used to be the first block of linux/config.sh.
set_tty_font() {
  local config="/etc/vconsole.conf"
  local font="ter-v16n"
  if [ -f "$config" ] && grep -q "^FONT=" "$config"; then
    sudo sed -i "s/^FONT=.*/FONT=$font/" "$config"
  else
    echo "FONT=$font" | sudo tee -a "$config" > /dev/null
  fi
}

# SATA/HDD temperatures exist only while drivetemp is loaded, and the module is
# not autoloaded: a machine without NVMe would just show --°C in waybar.
load_drivetemp() {
  sudo modprobe drivetemp 2> /dev/null || true
  echo drivetemp | sudo tee /etc/modules-load.d/drivetemp.conf > /dev/null
}

# sudo caches credentials per TTY, so unattended tooling (an agent editing
# /etc-level state) cannot use sudo at all without this. Widening the cache to
# the whole machine is the point, and the cost, of the file. See docs/design.md,
# the provision section.
install_sudo_window() {
  local file="/etc/sudoers.d/00-global-timestamp"
  local wanted='Defaults timestamp_type=global
Defaults timestamp_timeout=15'
  if [ -f "$file" ] && [ "$(sudo cat "$file")" = "$wanted" ]; then
    echo "    already in place"
    return 0
  fi
  printf '%s\n' "$wanted" | sudo tee "$file" > /dev/null
  # `sudo tee` leaves 0644; files under sudoers.d must be exactly 0440 or visudo
  # refuses them (the runtime sudo plugin is more forgiving than visudo).
  sudo chown root:root "$file"
  sudo chmod 0440 "$file"
  sudo visudo -c > /dev/null
}

# 2016-2017 T1 MacBook Pros (no T2 chip) carry two Alpine Ridge Thunderbolt 3
# controllers whose PME loop heats the chassis until the Thunderbolt resume path
# hangs for good. This installer stops the hang (wakeup sources off plus
# pcie_port_pm=off); it does not stop the ~45s wakeup itself, which raises no ACPI
# event at all. DMI-gated and idempotent; writes /etc, udev rules and the GRUB
# cmdline. See docs/suspend.md.
install_apple_suspend_fix() {
  sudo "$SRC_DIR/scripts/apple-macbook-suspend-fix.sh"
}

# mihomo ships as an AUR package, but two things around it are local policy: the
# loopback-only controller and the overlay that re-pins what the subscription may
# not change. The web panel is not ours to deploy -- mihomo downloads it itself
# into the external-ui directory. See docs/design.md, the mihomo section.
install_mihomo() {
  # Neither name is in the official repos, so `pacman -S` cannot resolve them:
  # both mihomo and clash-geoip are AUR-only. mihomo-bin provides `mihomo`.
  if ! command -v yay &> /dev/null; then
    echo "    yay is required for mihomo-bin / clash-geoip; skipping" >&2
    return 1
  fi
  yay -S --needed --noconfirm mihomo-bin clash-geoip || return 1
  # clash-geoip tracks upstream geodata; mihomo-bin ships none of its own.
  sudo ln -sf /etc/clash/Country.mmdb /etc/mihomo/Country.mmdb
}

install_mihomo_overlay() {
  sudo install -m 0755 "$SRC_DIR/scripts/mihomo-overlay.sh" /usr/local/bin/mihomo-overlay
  sudo install -d /etc/systemd/system/mihomo.service.d
  # The subscription ships external-controller 0.0.0.0 and knows nothing about
  # mixed-port: the flag pins the controller, the overlay pins mixed-port.
  printf '%s\n' \
    '[Service]' \
    'ExecStart=' \
    'ExecStart=/usr/bin/mihomo -d /etc/mihomo -ext-ctl 127.0.0.1:9090 -ext-ui ui/xd' \
    'ExecStartPre=+/usr/local/bin/mihomo-overlay' \
    | sudo tee /etc/systemd/system/mihomo.service.d/override.conf > /dev/null
}

enable_mihomo() {
  sudo systemctl daemon-reload
  sudo systemctl enable --now mihomo
}

# voxtype: hold-to-talk dictation driven by the keyboard's evdev events. The AUR
# package ships every binary variant and points /usr/bin/voxtype at the
# Whisper-only one; SenseVoice and Paraformer need the ONNX build. See
# docs/voxtype.md.
install_voxtype() {
  if ! command -v yay &> /dev/null; then
    echo "    yay is required for voxtype-bin; skipping (dictation stays unavailable)." >&2
    return 1
  fi
  yay -S --needed --noconfirm voxtype-bin || return 1
  # Writes /usr/bin/voxtype, hence root. It is idempotent.
  sudo voxtype setup onnx --enable || return 1
}

# The evdev listener opens /dev/input/event* directly. uaccess is the narrow
# grant: it follows the logged-in session instead of permanent group membership.
# Names are hardware-specific, so this file lists this machine's keyboards and
# needs a new line for a different one.
install_voxtype_udev() {
  sudo install -m 0644 "$SRC_DIR/scripts/70-voxtype-uaccess.rules" \
    /etc/udev/rules.d/70-voxtype-uaccess.rules || return 1
  sudo udevadm control --reload-rules
  sudo udevadm trigger --action=add --subsystem-match=input
  sudo udevadm settle
}

# The AU05 (Vibe Key) needs the grant above for voxtype's evdev listener, plus
# hidraw for the keepalive that stops its firmware rebooting every ~4 s. See
# docs/ulanzi-au05.md.
install_ulanzi_au05_udev() {
  sudo install -m 0644 "$SRC_DIR/scripts/71-ulanzi-au05.rules" \
    /etc/udev/rules.d/71-ulanzi-au05.rules || return 1
  sudo udevadm control --reload-rules
  sudo udevadm trigger --action=add --subsystem-match=input --subsystem-match=hidraw
  sudo udevadm settle
}

# paraformer-zh is what the deployed config selects. The other engines' models
# (Cohere 1.5 GB, SenseVoice 239 MB) download on demand instead.
install_voxtype_models() {
  if ! command -v voxtype &> /dev/null; then
    echo "    voxtype is not installed; skipping the model download" >&2
    return 1
  fi
  voxtype setup --download --model paraformer-zh || return 1
}

# User-level service, so no root: it writes ~/.config/systemd/user/ and enables
# it through the caller's own user manager. Runs after `chezmoi init --apply` so
# the daemon starts on the config this repo deploys.
install_voxtype_service() {
  if ! command -v voxtype &> /dev/null; then
    echo "    voxtype is not installed; skipping the user service" >&2
    return 1
  fi
  voxtype setup systemd
}

# wordseg-rs re-spaces the concatenated English that Paraformer emits; voxtype
# calls it through [output.post_process]. It is its own project, published to
# crates.io, so this repo only pins the dependency rather than carrying the
# source. The AUR route would be more Arch-native, but its registration is
# closed (2026-09), and `cargo install` works on every platform this repo
# targets.
install_wordseg() {
  if ! command -v cargo &> /dev/null; then
    if ! command -v rustup &> /dev/null; then
      echo "    neither cargo nor rustup is available; skipping wordseg-rs (voxtype keeps working, but English stays unspaced)." >&2
      return 1
    fi
    # rustup ships without a toolchain: cargo does not exist until one is picked.
    rustup default stable || return 1
  fi
  cargo install --locked --root "$HOME/.local" wordseg-rs
}

# ==========================================
# Run
# ==========================================

echo ">>> dotfiles bootstrap (Arch)"
echo "    repo:      $REPO_SSH"
echo "    sourceDir: $SRC_DIR"

if ! command -v pacman &> /dev/null; then
  echo "Error: pacman is not available; this bootstrap targets Arch Linux." >&2
  exit 1
fi

require git curl sudo

step_required "install chezmoi" install_chezmoi
step_required "clone/update dotfiles" ensure_repo
step_required "configure chezmoi sourceDir" write_chezmoi_config

step "pacman packages" install_packages
step "yay (AUR helper for xwayland-satellite-git)" ensure_yay
step "xwayland-satellite-git (AUR)" install_xwayland_satellite
step "default shell (zsh)" set_default_shell
step "TTY font (vconsole)" set_tty_font
step "drivetemp module" load_drivetemp
step "passwordless sudo window for unattended tooling" install_sudo_window
step "Alpine Ridge fix + lid lock (T1 MacBook Pro)" install_apple_suspend_fix
step "mihomo (kernel + geodata)" install_mihomo
step "mihomo service overrides" install_mihomo_overlay
step "enable mihomo" enable_mihomo
step "voxtype (AUR) + ONNX backend" install_voxtype
step "voxtype udev rule for keyboard access" install_voxtype_udev
step "uaccess for the Ulanzi AU05 (Vibe Key)" install_ulanzi_au05_udev
step "voxtype model (paraformer-zh)" install_voxtype_models

step_required "chezmoi init --apply" chezmoi init --apply
# wordseg-rs has to exist before the daemon starts, otherwise the first
# transcription runs without the re-spacing filter.
step "wordseg-rs (English re-spacing filter)" install_wordseg
step "voxtype user service" install_voxtype_service

summary
echo ""
echo ">>> Log out and back in for the zsh default shell and fcitx5 to take effect."
echo "    From now on 'chezmoi apply' needs no root and works without a terminal."
