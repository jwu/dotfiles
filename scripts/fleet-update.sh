export PATH="$HOME/.pi/agent/bin:$HOME/.local/bin:$HOME/bin:$HOME/.cargo/bin:$HOME/.bun/bin:/opt/homebrew/bin:$PATH"
if ! command -v pi >/dev/null 2>&1; then
    for node_bin in "$HOME"/.nvm/versions/node/*/bin; do
        if [ -x "$node_bin/pi" ]; then PATH="$node_bin:$PATH"; fi
    done
fi
export http_proxy="$proxy" https_proxy="$proxy" all_proxy="$proxy"
export HTTP_PROXY="$proxy" HTTPS_PROXY="$proxy" ALL_PROXY="$proxy"
export no_proxy=localhost,127.0.0.1,::1 NO_PROXY=localhost,127.0.0.1,::1 NODE_USE_ENV_PROXY=1
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.proxy GIT_CONFIG_VALUE_0="$proxy"

if ! curl -fsSL --max-time 15 -o /dev/null https://registry.npmjs.org/; then
    echo 'Could not reach npm through the SSH proxy' >&2
    exit 1
fi

update_dotfiles() {
    source_dir=$(chezmoi source-path) || return
    origin=$(git -C "$source_dir" remote get-url origin) || return
    case "$origin" in
        https://github.com/jwu/dotfiles|https://github.com/jwu/dotfiles.git|git@github.com:jwu/dotfiles|git@github.com:jwu/dotfiles.git|ssh://git@github.com/jwu/dotfiles.git) ;;
        *) echo 'chezmoi source does not track jwu/dotfiles' >&2; return 1 ;;
    esac
    [ "$(git -C "$source_dir" branch --show-current)" = main ] || { echo 'chezmoi source is not on main' >&2; return 1; }
    git -C "$source_dir" fetch https://github.com/jwu/dotfiles.git refs/heads/main:refs/remotes/origin/main || return
    git -C "$source_dir" merge --ff-only refs/remotes/origin/main || return
    chezmoi diff --include=files >/dev/null || return
    chezmoi status --include=files || return
    chezmoi apply --keep-going --error-on-conflict --no-tty
    status=$?
    chezmoi status --include=files
    return "$status"
}

update_pi() {
    (cd "$HOME" && pi update --all --no-approve) || return
    pi --version
}

update_magpie() {
    "$magpie" update --proxy "$proxy" || return
    "$magpie" --version
}

update_herdr() (
    set -e
    manifest=$(curl -fsSL --retry 2 --max-time 20 https://releases.herdr.dev/core/latest.json)
    version=$(printf '%s' "$manifest" | tr -d '[:space:]' | sed -n 's/.*"version":"\([0-9][0-9.]*\)".*/\1/p')
    [ -n "$version" ]
    installed=$(herdr-core --version)
    if [ "$installed" = "hc $version" ]; then
        printf '%s is current\n' "$installed"
        exit 0
    fi
    installer=$(mktemp)
    trap 'rm -f "$installer"' EXIT
    curl -fsSL --retry 2 --max-time 30 https://releases.herdr.dev/core/install.sh -o "$installer"
    HC_VERSION="$version" HC_INSTALL_DIR="$(dirname "$(command -v herdr-core)")" sh "$installer"
    [ "$(herdr-core --version)" = "hc $version" ]
)

run_step() {
    step=$1
    tool=$2
    if [ -z "$tool" ]; then
        result=ABSENT
    elif [ "$mode" = check ]; then
        printf '%s: %s\n' "$step" "$tool"
        result=READY
    else
        printf 'Updating %s\n' "$step"
        "update_$step"
        status=$?
        if [ "$status" -eq 0 ]; then result=OK; else result="FAILED ($status)"; fi
    fi
    printf 'FLEET_RESULT %s %s\n' "$step" "$result"
}

magpie=$(command -v magpie || true)
if [ -z "$magpie" ] && [ -x /Applications/Magpie.app/Contents/MacOS/magpie ]; then
    magpie=/Applications/Magpie.app/Contents/MacOS/magpie
fi
run_step dotfiles "$(command -v chezmoi)"
run_step pi "$(command -v pi)"
run_step magpie "$magpie"
run_step herdr "$(command -v herdr-core)"
