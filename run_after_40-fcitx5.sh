#!/bin/bash
# Fcitx5 / Rime runtime steps that chezmoi cannot express as files:
#   1. fetch the Rime Ice dictionaries on the first run (~16 MB, a third-party
#      release that moves independently of this repo, so it is not vendored)
#   2. rebuild Rime's compiled data
#   3. restart fcitx5 so it picks up the new build
#
# The profile, classicui.conf, the candidate-window theme and the *.custom.yaml
# patches are deployed by chezmoi and are deliberately NOT copied here.
# run_after_ guarantees this runs once those files are on disk, because
# rime_deployer builds on top of them.
#
# Never clear the user directory: *.userdb holds the learned frequency data,
# which is exactly what an update must preserve. See docs/rime/rime-config.md.
set -uo pipefail

FCITX_CONFIG_DIR="$HOME/.config/fcitx5"
FCITX_DATA_DIR="$HOME/.local/share/fcitx5"
RIME_DIR="$FCITX_DATA_DIR/rime"

if ! command -v fcitx5 &> /dev/null; then
  echo "fcitx5 is not installed; skipping the Rime steps." >&2
  exit 0
fi

# Rime keeps the compiled dictionaries in memory, so reloading fcitx5's config is
# not always enough to pick up a new build. Prefer a full restart, and fall back
# to fcitx5-remote -r when the DBus call is unavailable.
reload_fcitx5() {
  if command -v gdbus &> /dev/null; then
    if gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
      --method org.fcitx.Fcitx.Controller1.Restart &> /dev/null; then
      echo "    Restarted fcitx5 to load the new Rime build."
      return 0
    fi
  fi
  if command -v fcitx5-remote &> /dev/null; then
    if fcitx5-remote -r 2> /dev/null; then
      echo "    Reloaded fcitx5 config (restart fcitx5 if Rime still shows old words)."
      return 0
    fi
  fi
  echo "    Warning: could not restart fcitx5; restart it manually." >&2
  return 0
}

RIME_ICE_MIRROR="https://mirror.nju.edu.cn/github-release/iDvel/rime-ice/LatestRelease/full.zip"
RIME_ICE_UPSTREAM="https://github.com/iDvel/rime-ice/releases/latest/download/full.zip"

install_rime_ice() {
  if [ -f "$RIME_DIR/rime_ice.schema.yaml" ]; then
    echo "    Rime Ice dictionaries already present."
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)" || return 1
  echo "    Downloading Rime Ice dictionaries (~16 MB)..."
  if ! curl -fL --retry 2 -o "$tmp/full.zip" "$RIME_ICE_MIRROR"; then
    if ! curl -fL --retry 2 -o "$tmp/full.zip" "$RIME_ICE_UPSTREAM"; then
      rm -rf "$tmp"
      return 1
    fi
  fi
  if command -v bsdtar &> /dev/null; then
    bsdtar -xf "$tmp/full.zip" -C "$RIME_DIR" || { rm -rf "$tmp"; return 1; }
  elif command -v unzip &> /dev/null; then
    unzip -q -o "$tmp/full.zip" -d "$RIME_DIR" || { rm -rf "$tmp"; return 1; }
  else
    echo "    Neither bsdtar nor unzip is available; install unzip to unpack the archive." >&2
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
  echo "    Rime Ice dictionaries installed."
}

mkdir -p "$FCITX_CONFIG_DIR/conf" "$FCITX_DATA_DIR/themes/jwu" "$RIME_DIR"

# Dictionaries first: the patches deployed by chezmoi are applied on top of them,
# so a future release that happens to ship a .custom.yaml cannot overwrite them.
if ! install_rime_ice; then
  echo "    Warning: Rime Ice dictionaries were not installed; see docs/rime/rime-config.md." >&2
fi

if command -v rime_deployer &> /dev/null && [ -f /usr/share/rime-data/default.yaml ]; then
  rime_deployer --build "$RIME_DIR" /usr/share/rime-data "$RIME_DIR/build"
fi

reload_fcitx5

echo "Fcitx5 Rime steps done (build/ and the user frequency data were left alone)."
