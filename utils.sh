#!/usr/bin/env bash

UTILS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

utils::use_color() {
    [[ -z "${NO_COLOR+x}" && -z "${DOTFILES_NO_COLOR:-}" ]] &&
        { [[ -n "${DOTFILES_COLOR:-}" ]] || { [[ -t 1 ]] && [[ "${TERM:-}" != dumb ]]; }; }
}

utils::message() {
    local prefix="$1" color="$2" bold="$3" message="$4"

    if utils::use_color; then
        printf '\033[%sm%s\033[0m ' "$color" "$prefix"
        if [[ "$bold" == true ]]; then
            printf '\033[1m%s\033[0m\n' "$message"
        else
            printf '%s\n' "$message"
        fi
    else
        printf '%s %s\n' "$prefix" "$message"
    fi
}

utils::step() {
    utils::message '==>' 34 true "$*"
}

utils::detail() {
    printf '%s\n' "$*"
}

utils::warn() {
    utils::message 'Warning:' 33 false "$*" >&2
}

utils::error() {
    utils::message 'Error:' 31 false "$*" >&2
}

utils::die() {
    utils::error "$*"
    exit 1
}

utils::summary() {
    local message="$1" outcome="${2:-Configured}" badge

    case "$outcome" in
        Installed) badge='📦' ;;
        Configured) badge='🔧' ;;
        Restored) badge='🔄' ;;
        Unchanged) badge='✅' ;;
        Skipped) badge='⚠️' ;;
        *) utils::die "Unknown summary outcome: $outcome" ;;
    esac
    utils::step 'Summary'
    if [[ -n "${DOTFILES_NO_EMOJI+x}" ]]; then
        utils::detail "$message"
    else
        badge="${DOTFILES_SUMMARY_BADGE-$badge}"
        printf '%s  %s\n' "$badge" "$message"
    fi
}

utils::refuse_root_user_install() {
    local install_mode="${1:-user}"

    if [[ "$install_mode" == "--system" ]]; then
        install_mode="system"
    fi

    if [[ "$install_mode" != "system" ]] && [[ "$EUID" -eq 0 ]]; then
        utils::die 'Refusing to run user install as root. Re-run without sudo, or use --system.'
    fi
}

utils::resolve_target_user() {
    if [[ "$EUID" -eq 0 ]]; then
        TARGET_USER="${SUDO_USER:-}"
        if [[ -z "$TARGET_USER" ]]; then
            return 1
        fi
        TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
        if [[ -z "$TARGET_HOME" ]]; then
            TARGET_HOME="/home/$TARGET_USER"
        fi
        AS_ROOT=true
    else
        TARGET_USER="$USER"
        TARGET_HOME="$HOME"
        AS_ROOT=false
    fi
}

utils::run_as_target() {
    local command="$1"
    if [[ "${AS_ROOT:-false}" == true ]]; then
        sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" bash -lc "$command"
    else
        HOME="$TARGET_HOME" bash -lc "$command"
    fi
}

utils::exec_as_target() {
    if [[ "${AS_ROOT:-false}" == true ]]; then
        sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" "$@"
    else
        HOME="$TARGET_HOME" "$@"
    fi
}
