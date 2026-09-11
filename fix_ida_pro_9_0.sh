#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

DEPS=(
    libxcb-cursor0
    qtwayland5
)

if ! common::resolve_target_user; then
    if [[ "$EUID" -eq 0 ]]; then
        common::warn "Running as root without sudo user context."
        TARGET_HOME="$HOME"
        TARGET_USER="root"
        AS_ROOT=true
    fi
fi

common::step 'Installing IDA Pro 9.0 dependencies'
if [[ "$AS_ROOT" == true ]]; then
    apt update
    apt install -y "${DEPS[@]}"
else
    sudo apt update
    sudo apt install -y "${DEPS[@]}"
fi
common::detail "Installed dependencies: ${DEPS[*]}"

if [[ "${1:-}" != "--path" ]]; then
    common::detail 'PATH update was not requested.'
    common::summary 'IDA Pro dependencies installed'
    exit 0
fi

LINE='export PATH="$PATH:$HOME/idapro-9.0"'
RC_FILES=("$TARGET_HOME/.zshrc" "$TARGET_HOME/.bashrc" "$TARGET_HOME/.profile")
added=0

for rc in "${RC_FILES[@]}"; do
    if [[ -f "$rc" ]]; then
        common::step "Checking $rc..."
        if ! grep -Fq "$LINE" "$rc"; then
            if [[ "$AS_ROOT" == true ]] && [[ -n "${SUDO_USER:-}" ]]; then
                sudo -u "$TARGET_USER" bash -lc "printf '\n# Added by %s on %s\n%s\n' \"$(basename "$0")\" \"$(date --iso-8601=seconds)\" '$LINE' >> '$rc'"
            else
                printf '\n# Added by %s on %s\n%s\n' "$(basename "$0")" "$(date --iso-8601=seconds)" "$LINE" >> "$rc"
            fi
            common::detail "Appended PATH to $rc"
            added=1
        else
            common::detail "PATH already present in $rc"
        fi
    else
        common::detail "$rc does not exist — skipping."
    fi
done

if [[ $added -eq 0 ]]; then
    common::summary 'IDA Pro dependencies installed; no shell startup files changed'
else
    common::step 'Caveats'
    common::detail 'Restart your shell to apply the PATH changes.'
    common::summary 'IDA Pro dependencies and shell PATH configured'
fi
