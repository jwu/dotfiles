#!/bin/bash
set -euo pipefail

# ==========================================
# Configuration and Paths
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RIME_DIR="$HOME/.local/share/fcitx5/rime"

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

# Echo the official sha256 (hex) of full.zip, or nothing if unreachable.
official_digest() {
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

if [ "$DEPLOY" -eq 1 ]; then
  "$SCRIPT_DIR/install-linux.sh"
else
  cp "$ROOT_DIR/rime/default.custom.yaml" "$RIME_DIR/default.custom.yaml"
  cp "$ROOT_DIR/rime/rime_ice.custom.yaml" "$RIME_DIR/rime_ice.custom.yaml"
  echo ">>> Patches re-applied; deploy skipped (--no-deploy)."
fi

echo ">>> Rime dictionaries updated."
