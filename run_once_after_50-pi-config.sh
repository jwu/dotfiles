#!/bin/bash
# pi CLI plus the pi-config checkout.
#
# pi-config stays a separate repository because its settings.json points at
# ~/bin/pi-config/extensions by absolute path, so the clone target is fixed.
# See README.md, "pi-config 的编排".
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

deploy_pi_settings() {
  # install.sh only deploys settings.json now: the static resources come from
  # chezmoi, so the two no longer overlap.
  bash "$PI_DIR/install.sh" || return 1
}

echo ">>> pi CLI + pi-config"

ensure_pi || echo "    pi CLI install failed; pi-config clone still attempted." >&2
ensure_pi_config || exit 1
deploy_pi_settings || exit 1

echo ""
echo ">>> pi-config is at $PI_DIR."
echo "    npm packages are installed by pi itself on first start, from the"
echo "    'packages' list in settings.json. Run /reload in pi to pick up changes."
