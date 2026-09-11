#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

utils::step "Preparing pyenv installer..."

if ! utils::resolve_target_user; then
    utils::error "Refusing to run as root without an invoking user. Run as your user or with sudo from your account."
    exit 1
fi

utils::detail "Target user: ${TARGET_USER}"
utils::detail "Target home: ${TARGET_HOME}"

DEPS=(make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev \
libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev libzstd-dev)

utils::step "Checking for missing apt packages..."
TO_INSTALL=()
for pkg in "${DEPS[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        TO_INSTALL+=("$pkg")
    fi
done

if [ "${#TO_INSTALL[@]}" -gt 0 ]; then
    utils::step "Installing packages: ${TO_INSTALL[*]}"
    if [[ "$AS_ROOT" == true ]]; then
        apt update
        apt install -y "${TO_INSTALL[@]}"
    else
        sudo apt update
        sudo apt install -y "${TO_INSTALL[@]}"
    fi
    utils::detail "Packages installed"
else
    utils::detail "All build dependencies already present"
fi

PYENV_DIR="$TARGET_HOME/.pyenv"
PYENV_BIN="$PYENV_DIR/bin/pyenv"

if [[ -e "$PYENV_DIR" ]]; then
    FOREIGN_OWNER="$(find "$PYENV_DIR" ! -user "$TARGET_USER" -print -quit 2>/dev/null || true)"
    if [[ -n "$FOREIGN_OWNER" ]]; then
        TARGET_GROUP="$(id -gn "$TARGET_USER")"
        utils::error "${PYENV_DIR} contains files not owned by ${TARGET_USER}."
        utils::detail "Review them, then repair ownership once with:" >&2
        utils::detail "sudo chown -R '${TARGET_USER}:${TARGET_GROUP}' -- '${PYENV_DIR}'" >&2
        exit 1
    fi
fi

if [[ -x "$PYENV_BIN" ]]; then
    utils::step "Updating the existing pyenv installation for ${TARGET_USER}"
    if [[ -x "$PYENV_DIR/plugins/pyenv-update/bin/pyenv-update" ]]; then
        utils::run_as_target '"$HOME/.pyenv/bin/pyenv" update'
    else
        utils::run_as_target 'git -C "$HOME/.pyenv" pull --ff-only'
    fi
    utils::detail "pyenv update finished"
elif [[ -e "$PYENV_DIR" ]]; then
    utils::error "${PYENV_DIR} exists but does not contain an executable pyenv."
    utils::detail "Move it aside after reviewing its installed Python versions, then rerun this script." >&2
    exit 1
else
    utils::step "Installing pyenv via https://pyenv.run for ${TARGET_USER}"
    utils::run_as_target 'curl -fsSL https://pyenv.run | bash'
    utils::detail "pyenv installer finished"
fi

if [[ ! -x "$PYENV_BIN" ]]; then
    utils::error "pyenv installation verification failed: ${PYENV_BIN} is not executable."
    exit 1
fi

PYENV_VERSION="$(utils::run_as_target '"$HOME/.pyenv/bin/pyenv" --version')"
utils::detail "Verified ${PYENV_VERSION}"

ensure_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        utils::exec_as_target touch -- "$file"
    fi
}

configure_shell_file() {
    local file="$1"
    local shell_name="$2"
    local enable_virtualenv="${3:-false}"
    local line tmp_file last_index
    local -a preserved_lines=()

    ensure_file_exists "$file"
    tmp_file="$(utils::exec_as_target mktemp)"

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            'export PYENV_ROOT="$HOME/.pyenv"' | \
            'export PATH="$PYENV_ROOT/bin:$PATH"' | \
            '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' | \
            'eval "$(pyenv init --path)"' | \
            'eval "$(pyenv init -)"' | \
            'eval "$(pyenv init - bash)"' | \
            'eval "$(pyenv init - zsh)"' | \
            'eval "$(pyenv virtualenv-init -)"')
                continue
            ;;
        esac
        preserved_lines+=("$line")
    done < "$file"

    while (( ${#preserved_lines[@]} > 0 )); do
        last_index=$(( ${#preserved_lines[@]} - 1 ))
        [[ -z "${preserved_lines[$last_index]}" ]] || break
        unset "preserved_lines[$last_index]"
    done

    if (( ${#preserved_lines[@]} > 0 )); then
        printf '%s\n' "${preserved_lines[@]}" >> "$tmp_file"
        printf '\n' >> "$tmp_file"
    fi
    printf '%s\n' \
        'export PYENV_ROOT="$HOME/.pyenv"' \
        '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' \
        "eval \"\$(pyenv init - $shell_name)\"" >> "$tmp_file"
    if [[ "$enable_virtualenv" == true ]]; then
        printf '%s\n' 'eval "$(pyenv virtualenv-init -)"' >> "$tmp_file"
    fi

    if ! utils::exec_as_target cp -- "$tmp_file" "$file"; then
        utils::exec_as_target rm -f -- "$tmp_file"
        return 1
    fi
    utils::exec_as_target rm -f -- "$tmp_file"
    utils::detail "Updated $(basename "$file") for ${shell_name}"
}

TARGET_SHELL="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
SHELL_NAME="${TARGET_SHELL##*/}"
ENABLE_VIRTUALENV=false
if [[ -x "$PYENV_DIR/plugins/pyenv-virtualenv/bin/pyenv-virtualenv" ]]; then
    ENABLE_VIRTUALENV=true
fi

case "$SHELL_NAME" in
    bash)
        BASH_PROFILE="$TARGET_HOME/.profile"
        for candidate in .bash_profile .bash_login .profile; do
            if [[ -f "$TARGET_HOME/$candidate" ]]; then
                BASH_PROFILE="$TARGET_HOME/$candidate"
                break
            fi
        done
        configure_shell_file "$TARGET_HOME/.bashrc" bash "$ENABLE_VIRTUALENV"
        configure_shell_file "$BASH_PROFILE" bash false
    ;;
    zsh)
        configure_shell_file "$TARGET_HOME/.zshrc" zsh "$ENABLE_VIRTUALENV"
        configure_shell_file "$TARGET_HOME/.zprofile" zsh false
    ;;
    *)
        utils::warn "Unsupported login shell '${SHELL_NAME:-unknown}'; shell startup files were not changed."
        utils::detail "Configure it with: ${PYENV_BIN} init --install" >&2
    ;;
esac

utils::step 'Caveats'
utils::detail "Restart with: exec \"\$SHELL\""
utils::summary "pyenv setup complete for ${TARGET_USER}" Configured
