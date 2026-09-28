#!/bin/bash
set -euo pipefail

# ==========================================
# Configuration and Paths
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RIME_DIR="$HOME/.local/share/fcitx5/rime"

# full.zip carries its own copies of these two patches, so the extraction below
# always overwrites them. See docs/rime/rime-config.md.
PATCH_SRC="$ROOT_DIR/dot_local/share/fcitx5/rime"
PATCHES=(default.custom.yaml rime_ice.custom.yaml)

# Rime Ice is not vendored here; pull the rolling "latest" release.
#
# GitHub is tried first. The NJU mirror is only a fallback: it is a cache that
# can lag weeks behind (observed 2026-06-30 while upstream was already
# 2026-09-25), so every download is verified against the official release
# digest and a stale mirror is rejected. See rime/rime-config.md.
RIME_ICE_GITHUB="https://github.com/iDvel/rime-ice/releases/latest/download/full.zip"
RIME_ICE_MIRROR="https://mirror.nju.edu.cn/github-release/iDvel/rime-ice/LatestRelease/full.zip"
RIME_ICE_API="https://api.github.com/repos/iDvel/rime-ice/releases/latest"

# ==========================================
# Helpers
# ==========================================

usage() {
  cat <<'EOF'
Usage: update-rime-dict.sh [options]

Refresh the Rime Ice (雾凇拼音) dictionaries in ~/.local/share/fcitx5/rime
from the latest upstream release, re-apply this repo's patches and rebuild.

  --mirror      优先南大镜像（可能滞后，仍会用官方 sha256 校验并自动回退）
  --no-deploy   只更新词库 + 重新应用补丁，不重建/重载
  -h, --help    显示本帮助

默认：GitHub 官方源优先，失败回退南大镜像；下载后用官方 release sha256 校验。
EOF
}

download() {
  local url="$1" out="$2"
  echo ">>> Downloading $url"
  curl -fL --retry 2 --connect-timeout 10 -o "$out" "$url"
}

# Echo the official sha256 (hex) of full.zip, or nothing if unreachable. gh
# carries a 5000/h token, anonymous curl only 60/h. See docs/rime/rime-config.md.
official_digest() {
  if command -v gh &> /dev/null; then
    local via_gh
    via_gh="$(timeout 20 gh api "${RIME_ICE_API#https://api.github.com/}" \
      --jq '.assets[] | select(.name == "full.zip") | .digest' 2> /dev/null)" || true
    if [ -n "$via_gh" ]; then
      printf '%s\n' "${via_gh#sha256:}"
      return 0
    fi
  fi
  command -v python3 &> /dev/null || return 1
  local json
  json="$(curl -fsSL --max-time 15 "$RIME_ICE_API" 2>/dev/null)" || return 1
  printf '%s' "$json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for asset in data.get("assets", []):
    if asset.get("name") == "full.zip":
        print(asset.get("digest", "").replace("sha256:", ""))
        break
' 2> /dev/null
}

verify_sha256() {
  local file="$1" expected="$2" actual
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  if [ "$actual" != "$expected" ]; then
    echo "    checksum mismatch (expected $expected, got $actual)" >&2
    return 1
  fi
  echo ">>> sha256 verified: $actual"
  return 0
}

# Download and, when a digest is known, verify. Non-zero means "reject source".
try_source() {
  local url="$1" out="$2"
  download "$url" "$out" || return 1
  if [ -n "$EXPECTED" ]; then
    verify_sha256 "$out" "$EXPECTED" || return 1
  fi
  return 0
}

apply_patches() {
  local name
  for name in "${PATCHES[@]}"; do
    cp "$PATCH_SRC/$name" "$RIME_DIR/$name"
  done
  echo ">>> Patches re-applied: ${PATCHES[*]}"
}

# Rime keeps the compiled dictionaries in memory, so reloading fcitx5's config is
# not always enough to pick up a newly built one. Prefer a full restart, and fall
# back to fcitx5-remote -r when the DBus call is unavailable.
reload_fcitx5() {
  if command -v gdbus &> /dev/null; then
    if gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
      --method org.fcitx.Fcitx.Controller1.Restart &> /dev/null; then
      echo ">>> Restarted fcitx5 to load the new Rime build."
      return 0
    fi
  fi
  if command -v fcitx5-remote &> /dev/null; then
    if fcitx5-remote -r 2> /dev/null; then
      echo ">>> Reloaded fcitx5 config (restart fcitx5 if Rime still shows old words)."
      return 0
    fi
  fi
  echo ">>> Warning: could not restart fcitx5; restart it manually." >&2
  return 0
}

# ==========================================
# Arguments
# ==========================================

DEPLOY=1
PREFER_MIRROR=0
for arg in "$@"; do
  case "$arg" in
    --mirror) PREFER_MIRROR=1 ;;
    --no-deploy) DEPLOY=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

# ==========================================
# Preflight
# ==========================================

if ! command -v fcitx5 &> /dev/null; then
  echo "Error: fcitx5 is not installed." >&2
  exit 1
fi

if command -v bsdtar &> /dev/null; then
  ARCHIVER=bsdtar
elif command -v unzip &> /dev/null; then
  ARCHIVER=unzip
else
  echo "Error: neither bsdtar nor unzip is available; install unzip." >&2
  exit 1
fi

# Fail before touching the user directory: a run that cannot put the patches
# back must not start at all.
for name in "${PATCHES[@]}"; do
  if [ ! -f "$PATCH_SRC/$name" ]; then
    echo "Error: $PATCH_SRC/$name is missing; run this from the dotfiles repo." >&2
    exit 1
  fi
done

mkdir -p "$RIME_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ==========================================
# Download
# ==========================================

echo ">>> Fetching official release digest..."
EXPECTED="$(official_digest || true)"
if [ -n "$EXPECTED" ]; then
  echo "    official sha256: $EXPECTED"
else
  echo "    warning: could not fetch official digest; checksum verification skipped." >&2
fi

if [ "$PREFER_MIRROR" -eq 1 ]; then
  SOURCES=("$RIME_ICE_MIRROR" "$RIME_ICE_GITHUB")
else
  SOURCES=("$RIME_ICE_GITHUB" "$RIME_ICE_MIRROR")
fi

DOWNLOADED=0
for url in "${SOURCES[@]}"; do
  if try_source "$url" "$TMP_DIR/full.zip"; then
    DOWNLOADED=1
    break
  fi
  echo ">>> Source unavailable or stale: $url" >&2
done

if [ "$DOWNLOADED" -ne 1 ]; then
  echo "Error: no usable download source." >&2
  exit 1
fi

# ==========================================
# Verify Archive
# ==========================================

if [ "$ARCHIVER" = bsdtar ]; then
  bsdtar -tf "$TMP_DIR/full.zip" > /dev/null
else
  unzip -tq "$TMP_DIR/full.zip" > /dev/null
fi
echo ">>> Archive OK."

# ==========================================
# Back Up User Patches
# ==========================================

# full.zip ships its own *.custom.yaml, so extracting overwrites the patches in
# the user directory. Back them up; install-linux.sh re-applies the repo copies
# below.
shopt -s nullglob
for f in "$RIME_DIR"/*.custom.yaml; do
  echo ">>> Backing up $f to $f.bak.$TIMESTAMP"
  cp -a "$f" "$f.bak.$TIMESTAMP"
done
shopt -u nullglob

# ==========================================
# Extract
# ==========================================

echo ">>> Extracting dictionaries into $RIME_DIR ..."
if [ "$ARCHIVER" = bsdtar ]; then
  bsdtar -xf "$TMP_DIR/full.zip" -C "$RIME_DIR"
else
  unzip -q -o "$TMP_DIR/full.zip" -d "$RIME_DIR"
fi

# ==========================================
# Re-apply Patches / Rebuild
# ==========================================

apply_patches

if [ "$DEPLOY" -eq 1 ]; then
  if command -v rime_deployer &> /dev/null && [ -f /usr/share/rime-data/default.yaml ]; then
    echo ">>> Rebuilding (tencent.dict.yaml makes this take a few minutes)..."
    rime_deployer --build "$RIME_DIR" /usr/share/rime-data "$RIME_DIR/build" \
      || echo ">>> Warning: the rebuild failed; fcitx5 retries on its next start." >&2
  else
    echo ">>> rime_deployer or /usr/share/rime-data is missing; the rebuild was skipped." >&2
    echo "    Deploy from the fcitx5 menu before relying on the new words." >&2
  fi
  reload_fcitx5
else
  echo ">>> Deploy skipped (--no-deploy)."
fi

echo ">>> Rime dictionaries updated."
