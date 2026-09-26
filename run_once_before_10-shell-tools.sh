#!/bin/bash
# Root-free shell tooling: Oh My Zsh, the autosuggestions plugin, and a one-shot
# cleanup of a stale waybar script.
#
# Everything needing sudo lives in bootstrap/arch.sh. See docs/chezmoi-notes.md.
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
  echo "    Re-run 'chezmoi apply' after fixing them; run_once_ retries a script"
  echo "    that failed."
  return 1
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

# config.sh used to drop the stale hardcoded-NVMe script so nobody edits the
# wrong one. One-shot, so it lives here.
cleanup_stale() {
  rm -f "$HOME/.config/waybar/scripts/nvme-temp.sh"
}

echo ">>> shell tooling (root-free)"

step "Oh My Zsh" install_oh_my_zsh
step "zsh-autosuggestions" install_zsh_autosuggestions
step "stale script cleanup" cleanup_stale

summary
