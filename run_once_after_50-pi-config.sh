#!/bin/bash
# pi CLI plus the pi-config checkout.
#
# pi-config is the one repository that stays separate from dotfiles: it carries
# the TypeScript extension project and the npm plugins, and its settings.json
# points at ~/bin/pi-config/extensions -- a path that must not move. That is also
# why the clone target is fixed here.
#
# Its static resources (agents/, skills/, prompts/, themes/, keybindings.json,
# APPEND_SYSTEM.md) are owned by chezmoi now, so pi-config/install.sh is NOT run:
# as it stands it would copy the same files over the ones chezmoi just deployed
# and the two would fight. install.sh needs to be trimmed before it can be called
# here again -- see README.md, stage 5.
#
# Degrades to a warning: pi is optional on a machine that does not use it.
set -uo pipefail

PI_REPO_SSH="${PI_REPO_SSH:-git@github.com:jwu/pi-config.git}"
PI_REPO_HTTPS="${PI_REPO_HTTPS:-https://github.com/jwu/pi-config.git}"
PI_DIR="$HOME/bin/pi-config"

ensure_pi() {
  if command -v pi &> /dev/null; then
    echo "    pi: $(command -v pi)"
    return 0
  fi
  if ! command -v npm &> /dev/null; then
    echo "    pi: npm is missing; install nodejs and npm, then re-run." >&2
    return 1
  fi
  echo "    pi: installing @earendil-works/pi-coding-agent (npm -g)"
  npm install -g @earendil-works/pi-coding-agent || return 1
}

ensure_pi_config() {
  if [ -d "$PI_DIR/.git" ]; then
    echo "    pi-config: updating (git pull --ff-only)"
    git -C "$PI_DIR" pull --ff-only || echo "    pi-config: pull skipped (local changes or no network)"
    return 0
  fi
  mkdir -p "$(dirname "$PI_DIR")"
  echo "    pi-config: cloning into $PI_DIR"
  # BatchMode keeps a first-time SSH connection from stopping on a host-key or
  # passphrase prompt: it fails immediately and the HTTPS fallback takes over.
  if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
    git clone "$PI_REPO_SSH" "$PI_DIR" 2> /dev/null; then
    return 0
  fi
  echo "    pi-config: SSH clone failed, retrying over HTTPS"
  git clone "$PI_REPO_HTTPS" "$PI_DIR"
}

echo ">>> pi CLI + pi-config"

ensure_pi || echo "    pi CLI install failed; pi-config clone still attempted." >&2
ensure_pi_config || exit 1

echo ""
echo ">>> pi-config is at $PI_DIR."
echo "    Its npm packages are installed by pi itself on first start, from the"
echo "    'packages' list in settings.json. Run /reload in pi to pick up changes."
