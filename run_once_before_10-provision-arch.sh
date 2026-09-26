#!/bin/bash
# One-shot provisioning for a bare Arch machine: pacman packages, the AUR
# xwayland-satellite-git, the default shell, Oh My Zsh, the TTY font, the
# drivetemp module and a stale-script cleanup.
#
# Triggered by chezmoi's run_once_ prefix: it runs once and is skipped while its
# content is unchanged. Every step is best-effort -- on a bare machine the
# network is the least predictable part, and a failed pacman transaction must not
# leave the config files undeployed. Failures are collected and reported at the
# end, and the exit code stays non-zero so a later apply retries the script.
#
# Reasoning and gotchas live in docs/; this file keeps only what a reader of the
# code needs. See docs/xwayland-satellite.md and docs/waybar.md.
set -uo pipefail

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
  echo "    Re-run 'chezmoi apply' after fixing them: run_once_ retries a script"
  echo "    that failed, and the other steps below are idempotent."
  return 1
}

if ! command -v pacman &> /dev/null; then
  echo "Error: pacman is not available; this script targets Arch Linux." >&2
  exit 1
fi

# The toolchain (go/gcc/make/pkgconf/gtk3) is listed here rather than installed
# by the build scripts, because run_once_before_ runs before anything is built
# and sudo-installing belongs in one place.
PACKAGES=(
  "zsh"
  "starship"
  "zoxide"
  "neovim"
  "tree-sitter-cli"
  "fzf"
  "eza"
  "fd"
  "bat"
  "git-delta"
  "unzip"
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
  "noto-fonts-cjk"
  "noto-fonts-emoji"
  "adwaita-fonts"
  "ttf-sarasa-gothic"
  "go"
  "gcc"
  "make"
  "pkgconf"
  "gtk3"
  "git"
)

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

XWS_PKG="xwayland-satellite"
XWS_AUR_PKG="xwayland-satellite-git"

# yay: the AUR helper used for xwayland-satellite-git. yay-bin ships a prebuilt
# x86_64 binary, so bootstrapping the helper needs no Go/Rust toolchain and no
# long compile. This has to run before install_xwayland_satellite(), which skips
# itself when no helper is on PATH.
ensure_yay() {
  if command -v yay &> /dev/null; then
    echo "    yay: $(command -v yay)"
    return 0
  fi
  # makepkg refuses to build as root, and every privileged action in this script
  # already goes through sudo.
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
# step above failed.
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

install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "    Oh My Zsh is already installed."
    return 0
  fi
  echo "    Installing Oh My Zsh..."
  # Fetch first: `sh -c "$(curl ...)"` would swallow a failed download and run an
  # empty script, silently leaving Oh My Zsh uninstalled.
  local installer
  installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || return 1
  sh -c "$installer" "" --unattended || return 1
}

install_zsh_autosuggestions() {
  local dest="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
  if [ -d "$dest" ]; then
    echo "    already exists, pulling latest..."
    git -C "$dest" pull || echo "    pull skipped (local changes or no network)"
    return 0
  fi
  git clone https://github.com/zsh-users/zsh-autosuggestions "$dest" || return 1
}

# TTY font. Used to be the first block of linux/config.sh; it belongs with
# provisioning because it writes /etc and therefore needs sudo.
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

# config.sh used to drop the stale hardcoded-NVMe script so nobody edits the
# wrong one. One-shot, so it lives here.
cleanup_stale() {
  rm -f "$HOME/.config/waybar/scripts/nvme-temp.sh"
}

step "pacman packages" install_packages
step "yay (AUR helper for xwayland-satellite-git)" ensure_yay
step "xwayland-satellite-git (AUR)" install_xwayland_satellite
step "default shell (zsh)" set_default_shell
step "Oh My Zsh" install_oh_my_zsh
step "zsh-autosuggestions" install_zsh_autosuggestions
step "TTY font (vconsole)" set_tty_font
step "drivetemp module" load_drivetemp
step "stale script cleanup" cleanup_stale

summary
