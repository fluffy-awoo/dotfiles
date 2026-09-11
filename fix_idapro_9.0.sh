#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

DEPS=(
    libxcb-cursor0
    qtwayland5
)

if ! utils::resolve_target_user; then
    if [[ "$EUID" -eq 0 ]]; then
        utils::warn "Running as root without sudo user context."
        TARGET_HOME="$HOME"
        TARGET_USER="root"
        AS_ROOT=true
    fi
fi

utils::step "Installing dependencies..."
if [[ "$AS_ROOT" == true ]]; then
    apt update
    apt install -y "${DEPS[@]}"
else
    sudo apt update
    sudo apt install -y "${DEPS[@]}"
fi
utils::detail "Installed dependencies: ${DEPS[*]}"

if [[ "${1:-}" != "--path" ]]; then
    utils::detail 'PATH update was not requested.'
    utils::summary 'IDA Pro dependencies installed' Installed
    exit 0
fi

LINE='export PATH="$PATH:$HOME/idapro-9.0"'
RC_FILES=("$TARGET_HOME/.zshrc" "$TARGET_HOME/.bashrc" "$TARGET_HOME/.profile")
added=0

for rc in "${RC_FILES[@]}"; do
    if [[ -f "$rc" ]]; then
        utils::step "Checking $rc..."
        if ! grep -Fq "$LINE" "$rc"; then
            if [[ "$AS_ROOT" == true ]] && [[ -n "${SUDO_USER:-}" ]]; then
                sudo -u "$TARGET_USER" bash -lc "printf '\n# Added by %s on %s\n%s\n' \"$(basename "$0")\" \"$(date --iso-8601=seconds)\" '$LINE' >> '$rc'"
            else
                printf '\n# Added by %s on %s\n%s\n' "$(basename "$0")" "$(date --iso-8601=seconds)" "$LINE" >> "$rc"
            fi
            utils::detail "Appended PATH to $rc"
            added=1
        else
            utils::detail "PATH already present in $rc"
        fi
    else
        utils::detail "$rc does not exist — skipping."
    fi
done

if [[ $added -eq 0 ]]; then
    utils::summary 'IDA Pro dependencies installed; no shell startup files changed' Installed
else
    utils::step 'Caveats'
    utils::detail 'Restart your shell to apply the PATH changes.'
    utils::summary 'IDA Pro dependencies and shell PATH configured' Configured
fi
