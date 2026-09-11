#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if (( BASH_VERSINFO[0] < 4 )); then
    common::error 'install_fonts.sh requires Bash 4 or newer.'
    exit 1
fi

SCOPE="user"
SCOPE_WAS_SET=false
EMOJI_CONFIG=true
FORCE=false
TEMP_ROOT=""
TEMP_DIR=""
INSTALL_ROOT=""
FONTCONFIG_ROOT=""
STRIPPED_CONFIG_CONTENT=""
STRIPPED_CONFIG_COUNT=0
SYSTEM_CLEAN_CONFIG_CONTENT=""
APPLE_CONFIG_NAME="99-dotfiles-apple-color-emoji.conf"
APPLE_CONFIG_MARKER="Managed by install_fonts.sh; local changes will be replaced."

declare -a FONT_IDS=()
declare -a SELECTED_FONTS=()
declare -a ACTIVE_FONTS=()
declare -a MIGRATION_FONTS=()
declare -a SKIPPED_FONTS=()
declare -a COLLECTED_FILES=()
declare -a INSTALLED_DIRS=()
declare -a LEGACY_BASENAMES=()

declare -A FONT_LABEL=()
declare -A FONT_REPOSITORY=()
declare -A FONT_ASSET=()
declare -A FONT_PAYLOAD=()
declare -A FONT_GLOB=()
declare -A FONT_FAMILY=()
declare -A FONT_DESTINATION=()
declare -A FONT_HOOK=()
declare -A FONT_STAGE_DIR=()
declare -A FONT_LEGACY_USER=()
declare -A FONT_LEGACY_SYSTEM=()
declare -A DETECTED_LEGACY_FONTS=()
declare -A DETECTED_LEGACY_CONFIG=()
declare -A DETECTED_REPLACEABLE_CONFIG=()
declare -A DETECTED_LEGACY_BACKUP=()
declare -A DETECTED_LEGACY_PACKAGE=()
declare -A DETECTED_CONFIG_CONFLICT=()
declare -A CONFIG_BACKUP_TARGET=()
declare -A SELECTED_FONT_SET=()

fonts::register() {
    local id="$1"
    local label="$2"
    local repository="$3"
    local asset="$4"
    local payload="$5"
    local file_glob="$6"
    local family="$7"
    local destination="$8"
    local hook="$9"
    local legacy_user="${10}"
    local legacy_system="${11}"
    local repository_owner repository_name existing_id

    if [[ ! "$id" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || [[ "$id" == "all" ]]; then
        common::die "Invalid or reserved font ID in catalog: ${id:-empty}"
    fi
    if [[ -z "$label" ]] || [[ -z "$family" ]]; then
        common::die "Catalog entry '$id' is missing its label or family."
    fi
    if [[ ! "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        common::die "Catalog repository for '$id' must be an owner/name pair."
    fi
    repository_owner="${repository%%/*}"
    repository_name="${repository#*/}"
    if [[ "$repository_owner" == "." ]] || [[ "$repository_owner" == ".." ]] ||
        [[ "$repository_name" == "." ]] || [[ "$repository_name" == ".." ]]; then
        common::die "Catalog repository for '$id' contains a reserved path component."
    fi
    if [[ ! "$asset" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
        common::die "Catalog asset for '$id' must be a safe filename."
    fi
    case "$payload" in
        tar.xz|file) ;;
        *) common::die "Unsupported catalog payload for '$id': $payload" ;;
    esac
    if [[ -z "$file_glob" ]] || [[ "$file_glob" == */* ]]; then
        common::die "Catalog font glob for '$id' must not contain a path."
    fi
    if [[ ! "$destination" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
        common::die "Catalog destination for '$id' must be a safe directory name."
    fi
    case "$hook" in
        none|apple-emoji) ;;
        *) common::die "Unsupported catalog hook for '$id': $hook" ;;
    esac
    if [[ -n "$legacy_user" ]] &&
        { [[ "$legacy_user" == /* ]] || [[ "$legacy_user" == *".."* ]]; }; then
        common::die "Catalog user legacy path for '$id' must be a safe relative path."
    fi
    if [[ -n "$legacy_system" ]] &&
        { [[ "$legacy_system" != /usr/share/fonts/* ]] || [[ "$legacy_system" == *".."* ]]; }; then
        common::die "Catalog system legacy path for '$id' must stay under /usr/share/fonts."
    fi

    for existing_id in "${FONT_IDS[@]}"; do
        if [[ "$existing_id" == "$id" ]]; then
            common::die "Duplicate font ID in catalog: $id"
        fi
        if [[ "${FONT_DESTINATION[$existing_id]}" == "$destination" ]]; then
            common::die "Duplicate font destination in catalog: $destination"
        fi
    done

    FONT_IDS+=("$id")
    FONT_LABEL["$id"]="$label"
    FONT_REPOSITORY["$id"]="$repository"
    FONT_ASSET["$id"]="$asset"
    FONT_PAYLOAD["$id"]="$payload"
    FONT_GLOB["$id"]="$file_glob"
    FONT_FAMILY["$id"]="$family"
    FONT_DESTINATION["$id"]="$destination"
    FONT_HOOK["$id"]="$hook"
    FONT_LEGACY_USER["$id"]="$legacy_user"
    FONT_LEGACY_SYSTEM["$id"]="$legacy_system"
}

fonts::register_catalog() {
    fonts::register \
        "jetbrains-mono" \
        "JetBrainsMono Nerd Font" \
        "ryanoasis/nerd-fonts" \
        "JetBrainsMono.tar.xz" \
        "tar.xz" \
        "JetBrainsMonoNerdFont-*.ttf" \
        "JetBrainsMono Nerd Font" \
        "JetBrainsMonoNerd" \
        "none" \
        ".fonts/JetBrainsMonoNerd" \
        "/usr/share/fonts/JetBrainsMonoNerd"

    fonts::register \
        "sf-mono" \
        "SF Mono Nerd Font" \
        "fluffy-flufff/SF-Mono-Nerd-Font" \
        "SFMonoNerdFont.tar.xz" \
        "tar.xz" \
        "SFMonoNerdFont-*.otf" \
        "SF Mono Nerd Font" \
        "SFMonoNerdFont" \
        "none" \
        ".fonts/SFMonoNerd" \
        "/usr/share/fonts/SFMonoNerd"

    fonts::register \
        "sf-mono-terminal" \
        "SF Mono Terminal Nerd Font" \
        "fluffy-flufff/SF-Mono-Nerd-Font" \
        "SFMonoTerminalNerdFont.tar.xz" \
        "tar.xz" \
        "SFMonoTerminalNerdFont-*.ttf" \
        "SF Mono Terminal Nerd Font" \
        "SFMonoTerminalNerdFont" \
        "none" \
        "" \
        ""

    fonts::register \
        "apple-emoji" \
        "Apple Color Emoji" \
        "samuelngs/apple-emoji-ttf" \
        "AppleColorEmoji-Linux.ttf" \
        "file" \
        "AppleColorEmoji-Linux.ttf" \
        "Apple Color Emoji" \
        "AppleColorEmoji" \
        "apple-emoji" \
        ".local/share/fonts/AppleColorEmoji.ttf" \
        "/usr/share/fonts/AppleColorEmoji"
}

fonts::list() {
    local id

    common::step 'Available fonts (latest stable release)'
    for id in "${FONT_IDS[@]}"; do
        printf '  %-18s %-30s %s\n' \
            "$id" \
            "${FONT_LABEL[$id]}" \
            "${FONT_REPOSITORY[$id]}"
    done
}

usage() {
    common::step 'Usage: install_fonts.sh [OPTIONS] FONT...'
    printf '\n'
    fonts::list
    cat <<'EOF'

Special selector:
  all              Install every registered font
  sf-mono          Install both SF Mono Nerd Font families

Options:
  --user           Install for the current user (default)
  --system         Install system-wide using sudo when needed
  --set-default    Prefer Apple Color Emoji through fontconfig (default)
  --no-set-default Install Apple Color Emoji without fontconfig changes
  --force          Remove recognized legacy artifacts, then reinstall
  --list           List registered fonts without making changes
  -h, --help       Show this help without making changes

Examples:
  ./install_fonts.sh jetbrains-mono
  ./install_fonts.sh sf-mono apple-emoji
  ./install_fonts.sh apple-emoji --no-set-default
  ./install_fonts.sh all --force
  ./install_fonts.sh all --system
EOF
}

fonts::usage_error() {
    common::error "$*"
    printf '\n' >&2
    usage >&2
    exit 2
}

fonts::set_scope() {
    local requested_scope="$1"

    if [[ "$SCOPE_WAS_SET" == true ]] && [[ "$SCOPE" != "$requested_scope" ]]; then
        fonts::usage_error "Choose either --user or --system, not both."
    fi

    SCOPE="$requested_scope"
    SCOPE_WAS_SET=true
}

fonts::select() {
    local requested_id="$1"
    local registered_id=""

    if [[ -z "$requested_id" ]]; then
        fonts::usage_error "Font names cannot be empty."
    fi
    for registered_id in "${FONT_IDS[@]}"; do
        [[ "$registered_id" == "$requested_id" ]] && break
        registered_id=""
    done
    if [[ -z "$registered_id" ]]; then
        fonts::usage_error "Unknown font: $requested_id"
    fi

    if [[ -z "${SELECTED_FONT_SET[$registered_id]+selected}" ]]; then
        SELECTED_FONT_SET["$registered_id"]=true
        SELECTED_FONTS+=("$registered_id")
    fi
}

fonts::select_argument() {
    local requested_id="$1"
    local id

    case "$requested_id" in
        all)
            for id in "${FONT_IDS[@]}"; do
                fonts::select "$id"
            done
        ;;
        sf-mono)
            fonts::select "sf-mono"
            fonts::select "sf-mono-terminal"
        ;;
        *)
            fonts::select "$requested_id"
        ;;
    esac
}

fonts::parse_args() {
    local argument

    while [[ $# -gt 0 ]]; do
        argument="$1"
        case "$argument" in
            --user)
                fonts::set_scope "user"
            ;;
            --system)
                fonts::set_scope "system"
            ;;
            --set-default|--emoji-config)
                EMOJI_CONFIG=true
            ;;
            --no-set-default|--no-emoji-config)
                EMOJI_CONFIG=false
            ;;
            --force)
                FORCE=true
            ;;
            --list)
                fonts::list
                exit 0
            ;;
            -h|--help)
                usage
                exit 0
            ;;
            all)
                fonts::select_argument "$argument"
            ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    fonts::select_argument "$1"
                    shift
                done
                break
            ;;
            -*)
                fonts::usage_error "Unknown option: $argument"
            ;;
            *)
                fonts::select_argument "$argument"
            ;;
        esac
        shift
    done

    if [[ "${#SELECTED_FONTS[@]}" -eq 0 ]]; then
        fonts::usage_error "Choose at least one font."
    fi
}

fonts::cleanup() {
    if [[ -z "$TEMP_DIR" ]] || [[ ! -d "$TEMP_DIR" ]]; then
        return
    fi

    case "$TEMP_DIR" in
        "$TEMP_ROOT"/dotfiles-fonts.*)
            rm -rf -- "$TEMP_DIR"
        ;;
        *)
            common::warn "Refusing to remove unexpected temporary directory: $TEMP_DIR"
        ;;
    esac
}

fonts::handle_interrupt() {
    exit 130
}

fonts::handle_terminate() {
    exit 143
}

fonts::require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 ||
        common::die "Missing required command: $command_name"
}

fonts::check_requirements() {
    local command_name id needs_tar_xz=false needs_cat=false
    local needs_rmdir=false needs_ln=false needs_mv=false

    for command_name in curl fc-cache fc-scan find install mkdir mktemp rm uname; do
        fonts::require_command "$command_name"
    done
    for id in "${ACTIVE_FONTS[@]}"; do
        [[ "${FONT_PAYLOAD[$id]}" == "tar.xz" ]] && needs_tar_xz=true
        if [[ "${FONT_HOOK[$id]}" == "apple-emoji" ]]; then
            needs_cat=true
        fi
    done
    for id in "${MIGRATION_FONTS[@]}"; do
        [[ -n "${DETECTED_LEGACY_FONTS[$id]:-}" ]] && needs_rmdir=true
        if [[ -n "${DETECTED_LEGACY_BACKUP[$id]:-}" ]]; then
            needs_ln=true
            needs_mv=true
        fi
        [[ -n "${DETECTED_REPLACEABLE_CONFIG[$id]:-}" ]] && needs_mv=true
        if [[ -n "${DETECTED_LEGACY_PACKAGE[$id]:-}" ]]; then
            fonts::require_command dpkg
        fi
    done
    if [[ "$needs_tar_xz" == true ]]; then
        fonts::require_command tar
        fonts::require_command xz
    fi
    if [[ "$needs_cat" == true ]]; then
        fonts::require_command cat
    fi
    if [[ "$needs_rmdir" == true ]]; then
        fonts::require_command rmdir
    fi
    if [[ "$needs_ln" == true ]]; then
        fonts::require_command ln
    fi
    if [[ "$needs_mv" == true ]]; then
        fonts::require_command mv
    fi
    if [[ "$SCOPE" == "system" ]] && [[ "$EUID" -ne 0 ]]; then
        fonts::require_command sudo
    fi
}

fonts::hook_is_enabled() {
    local id="$1"

    case "${FONT_HOOK[$id]}" in
        none) return 1 ;;
        apple-emoji) [[ "$EMOJI_CONFIG" == true ]] ;;
        *) common::die "Unsupported post-install hook for $id: ${FONT_HOOK[$id]}" ;;
    esac
}

fonts::selection_has_fontconfig_hook() {
    local id

    for id in "${SELECTED_FONTS[@]}"; do
        fonts::hook_is_enabled "$id" && return 0
    done
    return 1
}

fonts::run_for_scope() {
    if [[ "$SCOPE" == "system" ]] && [[ "$EUID" -ne 0 ]]; then
        sudo -- "$@"
    else
        "$@"
    fi
}

fonts::resolve_paths() {
    local data_home config_home

    if [[ "$SCOPE" == "system" ]]; then
        INSTALL_ROOT="/usr/local/share/fonts"
        FONTCONFIG_ROOT="/etc/fonts/conf.d"
        common::step "System-wide install selected. Privileged writes will use sudo when needed."
        return
    fi

    if [[ "$EUID" -eq 0 ]]; then
        common::die "Refusing a user install as root. Use --system for a system install."
    fi

    data_home="${XDG_DATA_HOME:-}"
    if [[ -n "$data_home" ]] && [[ "$data_home" != /* ]]; then
        common::warn "Ignoring relative XDG_DATA_HOME: $data_home"
        data_home=""
    fi
    if [[ -z "$data_home" ]]; then
        if [[ -z "${HOME:-}" ]] || [[ "$HOME" != /* ]]; then
            common::die "HOME must be absolute when XDG_DATA_HOME is not set."
        fi
        data_home="$HOME/.local/share"
    fi

    if fonts::selection_has_fontconfig_hook; then
        config_home="${XDG_CONFIG_HOME:-}"
        if [[ -n "$config_home" ]] && [[ "$config_home" != /* ]]; then
            common::warn "Ignoring relative XDG_CONFIG_HOME: $config_home"
            config_home=""
        fi
        if [[ -z "$config_home" ]]; then
            if [[ -z "${HOME:-}" ]] || [[ "$HOME" != /* ]]; then
                common::die "HOME must be absolute when XDG_CONFIG_HOME is not set."
            fi
            config_home="$HOME/.config"
        fi
        FONTCONFIG_ROOT="$config_home/fontconfig/conf.d"
    fi

    INSTALL_ROOT="$data_home/fonts"
    common::step "User install selected."
}

fonts::legacy_apple_config_contents() {
    cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>serif</family>
    <prefer><family>Apple Color Emoji</family></prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Apple Color Emoji</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>Apple Color Emoji</family></prefer>
  </alias>
  <match target="pattern">
    <test qual="any" name="family"><string>Noto Color Emoji</string></test>
    <edit name="family" mode="assign" binding="same">
      <string>Apple Color Emoji</string>
    </edit>
  </match>
</fontconfig>
EOF
}

fonts::is_exact_legacy_apple_config() {
    local config_file="$1"
    local actual expected

    [[ -f "$config_file" ]] && [[ ! -L "$config_file" ]] && [[ -r "$config_file" ]] ||
        return 1
    actual=""
    expected=""
    if IFS= read -r -d '' actual < "$config_file"; then
        return 1
    fi
    IFS= read -r -d '' expected < <(fonts::legacy_apple_config_contents) || :
    [[ "$actual" == "$expected" ]]
}

fonts::file_mentions_apple_emoji() {
    local config_file="$1"
    local line

    [[ -f "$config_file" ]] && [[ ! -L "$config_file" ]] && [[ -r "$config_file" ]] ||
        return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *'Apple Color Emoji'* ]] && return 0
    done < "$config_file"
    return 1
}

fonts::append_legacy_font_path() {
    local id="$1"
    local path="$2"
    local existing_path

    while IFS= read -r existing_path; do
        [[ "$existing_path" == "$path" ]] && return 0
    done <<< "${DETECTED_LEGACY_FONTS[$id]:-}"
    if [[ -n "${DETECTED_LEGACY_FONTS[$id]:-}" ]]; then
        DETECTED_LEGACY_FONTS["$id"]+=$'\n'
    fi
    DETECTED_LEGACY_FONTS["$id"]+="$path"
}

fonts::record_legacy_font_path() {
    local id="$1"
    local path="$2"

    if [[ -e "$path" ]] || [[ -L "$path" ]]; then
        fonts::append_legacy_font_path "$id" "$path"
    fi
}

fonts::strip_old_apple_insertion() {
    local config_file="$1"
    local line next_line trimmed next_trimmed output=""
    local index
    local -a lines=()

    STRIPPED_CONFIG_CONTENT=""
    STRIPPED_CONFIG_COUNT=0
    [[ -r "$config_file" ]] || return 1
    if ! mapfile -t lines < "$config_file"; then
        return 1
    fi
    for ((index = 0; index < ${#lines[@]}; index += 1)); do
        line="${lines[$index]}"
        trimmed="$line"
        trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

        if [[ "$trimmed" == '<family>Apple Color Emoji</family>' ]] &&
            ((index + 1 < ${#lines[@]})); then
            next_line="${lines[$((index + 1))]}"
            next_trimmed="$next_line"
            next_trimmed="${next_trimmed#"${next_trimmed%%[![:space:]]*}"}"
            next_trimmed="${next_trimmed%"${next_trimmed##*[![:space:]]}"}"
            if [[ "$next_trimmed" == '<family>Noto Color Emoji</family>'* ]]; then
                ((STRIPPED_CONFIG_COUNT += 1))
                continue
            fi
        fi
        output+="$line"$'\n'
    done
    STRIPPED_CONFIG_CONTENT="${output%$'\n'}"
}

fonts::system_legacy_backup_is_proven() {
    local active_config="/etc/fonts/conf.d/60-generic.conf"
    local backup_config="/etc/fonts/conf.d/60-generic.conf.bak"
    local active_content backup_content active_clean backup_clean
    local active_count backup_count

    SYSTEM_CLEAN_CONFIG_CONTENT=""
    [[ -f "$backup_config" ]] && [[ ! -L "$backup_config" ]] &&
        [[ -r "$backup_config" ]] && [[ -f "$active_config" ]] &&
        [[ -r "$active_config" ]] || return 1

    if ! active_content="$(<"$active_config")"; then
        return 1
    fi
    if ! backup_content="$(<"$backup_config")"; then
        return 1
    fi
    fonts::strip_old_apple_insertion "$active_config" || return 1
    active_clean="$STRIPPED_CONFIG_CONTENT"
    active_count="$STRIPPED_CONFIG_COUNT"
    fonts::strip_old_apple_insertion "$backup_config" || return 1
    backup_clean="$STRIPPED_CONFIG_CONTENT"
    backup_count="$STRIPPED_CONFIG_COUNT"

    if [[ "$active_content" == "$backup_content" ]] &&
        [[ "$active_count" -eq 0 ]] && [[ "$backup_count" -eq 0 ]]; then
        SYSTEM_CLEAN_CONFIG_CONTENT="$active_content"
        return 0
    fi
    if [[ "$active_count" -eq 1 ]] && [[ "$backup_count" -eq 0 ]] &&
        [[ "$active_clean" == "$backup_content" ]]; then
        SYSTEM_CLEAN_CONFIG_CONTENT="$active_clean"
        return 0
    fi
    if [[ "$active_content" == "$backup_content" ]] &&
        [[ "$active_count" -eq 1 ]] && [[ "$backup_count" -eq 1 ]] &&
        [[ "$active_clean" == "$backup_clean" ]]; then
        SYSTEM_CLEAN_CONFIG_CONTENT="$active_clean"
        return 0
    fi
    return 1
}

fonts::detect_legacy() {
    local id="$1"
    local legacy_path legacy_config package_status
    local found=false

    if [[ "$SCOPE" == "system" ]]; then
        legacy_path="${FONT_LEGACY_SYSTEM[$id]}"
    elif [[ -n "${FONT_LEGACY_USER[$id]}" ]] &&
        [[ -n "${HOME:-}" ]] && [[ "$HOME" == /* ]]; then
        legacy_path="$HOME/${FONT_LEGACY_USER[$id]}"
    else
        legacy_path=""
    fi
    [[ -n "$legacy_path" ]] && fonts::record_legacy_font_path "$id" "$legacy_path"

    if [[ "$id" == "sf-mono" ]]; then
        if [[ "$SCOPE" == "system" ]]; then
            fonts::record_legacy_font_path \
                "$id" "/usr/local/share/fonts/SFMonoNerdFontMono"
        else
            fonts::record_legacy_font_path \
                "$id" "$INSTALL_ROOT/SFMonoNerdFontMono"
        fi
    fi

    if [[ "$SCOPE" == "system" ]] && [[ "$id" == "jetbrains-mono" ]]; then
        fonts::record_legacy_font_path \
            "$id" "/usr/share/fonts/truetype/JetBrainsMonoNerd"
    fi
    if [[ "$SCOPE" == "system" ]] && [[ "${FONT_HOOK[$id]}" == "apple-emoji" ]]; then
        fonts::record_legacy_font_path \
            "$id" "/usr/share/fonts/truetype/apple-color-emoji"
    fi

    if [[ "${FONT_HOOK[$id]}" == "apple-emoji" ]]; then
        if fonts::hook_is_enabled "$id" &&
            [[ -n "${HOME:-}" ]] && [[ "$HOME" == /* ]]; then
            legacy_config="$HOME/.config/fontconfig/fonts.conf"
            if fonts::is_exact_legacy_apple_config "$legacy_config"; then
                DETECTED_LEGACY_CONFIG["$id"]="$legacy_config"
            elif [[ -L "$legacy_config" ]] ||
                fonts::file_mentions_apple_emoji "$legacy_config"; then
                DETECTED_REPLACEABLE_CONFIG["$id"]="$legacy_config"
            fi
        fi

        if fonts::hook_is_enabled "$id" && [[ "$SCOPE" == "system" ]] &&
            { [[ -e "/etc/fonts/conf.d/60-generic.conf.bak" ]] ||
              [[ -L "/etc/fonts/conf.d/60-generic.conf.bak" ]]; }; then
            if fonts::system_legacy_backup_is_proven; then
                DETECTED_LEGACY_BACKUP["$id"]="/etc/fonts/conf.d/60-generic.conf.bak"
            else
                DETECTED_CONFIG_CONFLICT["$id"]="/etc/fonts/conf.d/60-generic.conf.bak"
            fi
        fi

        if [[ "$SCOPE" == "system" ]] && command -v dpkg-query >/dev/null 2>&1; then
            if package_status="$(
                dpkg-query -W -f='${db:Status-Status}' \
                    fonts-apple-color-emoji 2>/dev/null
            )" && [[ "$package_status" == "installed" ]]; then
                DETECTED_LEGACY_PACKAGE["$id"]="fonts-apple-color-emoji"
            fi
        fi
    fi

    [[ -n "${DETECTED_LEGACY_FONTS[$id]:-}" ]] && found=true
    [[ -n "${DETECTED_LEGACY_CONFIG[$id]:-}" ]] && found=true
    [[ -n "${DETECTED_REPLACEABLE_CONFIG[$id]:-}" ]] && found=true
    [[ -n "${DETECTED_LEGACY_BACKUP[$id]:-}" ]] && found=true
    [[ -n "${DETECTED_LEGACY_PACKAGE[$id]:-}" ]] && found=true
    [[ -n "${DETECTED_CONFIG_CONFLICT[$id]:-}" ]] && found=true
    [[ "$found" == true ]]
}

fonts::report_legacy() {
    local id="$1"
    local path

    common::warn "Legacy ${FONT_LABEL[$id]} state detected:"
    while IFS= read -r path; do
        [[ -n "$path" ]] && printf '    %s\n' "$path" >&2
    done <<< "${DETECTED_LEGACY_FONTS[$id]:-}"
    [[ -n "${DETECTED_LEGACY_CONFIG[$id]:-}" ]] &&
        printf '    %s\n' "${DETECTED_LEGACY_CONFIG[$id]}" >&2
    [[ -n "${DETECTED_REPLACEABLE_CONFIG[$id]:-}" ]] &&
        printf '    config requiring --force: %s\n' \
            "${DETECTED_REPLACEABLE_CONFIG[$id]}" >&2
    [[ -n "${DETECTED_LEGACY_BACKUP[$id]:-}" ]] &&
        printf '    %s\n' "${DETECTED_LEGACY_BACKUP[$id]}" >&2
    [[ -n "${DETECTED_LEGACY_PACKAGE[$id]:-}" ]] &&
        printf '    package: %s\n' "${DETECTED_LEGACY_PACKAGE[$id]}" >&2
    [[ -n "${DETECTED_CONFIG_CONFLICT[$id]:-}" ]] &&
        printf '    unmanaged config: %s\n' "${DETECTED_CONFIG_CONFLICT[$id]}" >&2
    return 0
}

fonts::evaluate_legacy() {
    local id

    ACTIVE_FONTS=()
    MIGRATION_FONTS=()
    SKIPPED_FONTS=()
    for id in "${SELECTED_FONTS[@]}"; do
        if ! fonts::detect_legacy "$id"; then
            ACTIVE_FONTS+=("$id")
            continue
        fi

        fonts::report_legacy "$id"
        if [[ -n "${DETECTED_CONFIG_CONFLICT[$id]:-}" ]]; then
            common::warn "Skipping ${FONT_LABEL[$id]}; the config is not safe to change automatically."
            SKIPPED_FONTS+=("$id")
        elif [[ "$FORCE" == true ]]; then
            common::step "--force will migrate ${FONT_LABEL[$id]} after its download validates."
            ACTIVE_FONTS+=("$id")
            MIGRATION_FONTS+=("$id")
        else
            common::warn "Skipping ${FONT_LABEL[$id]}; rerun with --force to migrate it."
            SKIPPED_FONTS+=("$id")
        fi
    done
    return 0
}

fonts::create_temp_dir() {
    TEMP_ROOT="${TMPDIR:-/tmp}"
    if [[ "$TEMP_ROOT" != /* ]] || [[ ! -d "$TEMP_ROOT" ]]; then
        common::warn "Ignoring unusable TMPDIR: $TEMP_ROOT"
        TEMP_ROOT="/tmp"
    fi
    TEMP_ROOT="${TEMP_ROOT%/}"
    [[ -n "$TEMP_ROOT" ]] || TEMP_ROOT="/tmp"

    if ! TEMP_DIR="$(mktemp -d "$TEMP_ROOT/dotfiles-fonts.XXXXXXXX")"; then
        common::die "Could not create a temporary directory under $TEMP_ROOT."
    fi
    trap fonts::cleanup EXIT
    trap fonts::handle_interrupt INT
    trap fonts::handle_terminate TERM
}

fonts::download_file() {
    local url="$1"
    local destination="$2"

    if ! curl --fail --location --silent --show-error --retry 3 \
        --proto '=https' --proto-redir '=https' \
        "$url" --output "$destination"; then
        common::die "Download failed: ${url##*/}"
    fi
}

fonts::extract_archive() {
    local id="$1"
    local archive="$2"
    local destination="$3"

    if ! tar --list --xz --file="$archive" >/dev/null; then
        common::die "Could not read the ${FONT_LABEL[$id]} archive."
    fi
    if ! tar --extract --xz --file="$archive" --directory="$destination" \
        --no-same-owner --no-same-permissions; then
        common::die "Could not extract the ${FONT_LABEL[$id]} archive."
    fi
}

fonts::collect_files() {
    local id="$1"
    local stage_dir="${FONT_STAGE_DIR[$id]}"
    local font_file

    COLLECTED_FILES=()
    while IFS= read -r -d '' font_file; do
        COLLECTED_FILES+=("$font_file")
    done < <(
        find "$stage_dir" -type f -name "${FONT_GLOB[$id]}" -print0
    )
}

fonts::verify_font_file() {
    local id="$1"
    local font_file="$2"
    local expected_family="${FONT_FAMILY[$id]}"
    local reported_families reported_family
    local family_matches=false
    local -a family_names=()

    if [[ ! -s "$font_file" ]]; then
        common::die "Downloaded font is empty: ${font_file##*/}"
    fi
    if ! reported_families="$(fc-scan --format='%{family}\n' "$font_file")"; then
        common::die "Could not read font metadata from ${font_file##*/}."
    fi
    reported_families="${reported_families//$'\n'/,}"
    IFS=',' read -r -a family_names <<< "$reported_families"
    for reported_family in "${family_names[@]}"; do
        if [[ "$reported_family" == "$expected_family" ]]; then
            family_matches=true
            break
        fi
    done
    if [[ "$family_matches" != true ]]; then
        common::die \
            "Unexpected family in ${font_file##*/}: ${reported_families:-unknown}"
    fi
}

fonts::prepare() {
    local id="$1"
    local stage_dir="$TEMP_DIR/stage-$id"
    local payload_file="$TEMP_DIR/${id}-${FONT_ASSET[$id]}"
    local download_url="https://github.com/${FONT_REPOSITORY[$id]}/releases/latest/download/${FONT_ASSET[$id]}"
    local font_file basename existing_basename
    local -a basenames=()

    mkdir -p -- "$stage_dir"
    common::step "Downloading the latest ${FONT_LABEL[$id]} release asset..."

    case "${FONT_PAYLOAD[$id]}" in
        tar.xz)
            fonts::download_file \
                "$download_url" \
                "$payload_file"
            fonts::extract_archive "$id" "$payload_file" "$stage_dir"
        ;;
        file)
            payload_file="$stage_dir/${FONT_ASSET[$id]}"
            fonts::download_file \
                "$download_url" \
                "$payload_file"
        ;;
        *)
            common::die "Unsupported payload for $id: ${FONT_PAYLOAD[$id]}"
        ;;
    esac

    FONT_STAGE_DIR["$id"]="$stage_dir"
    fonts::collect_files "$id"
    if [[ "${#COLLECTED_FILES[@]}" -eq 0 ]]; then
        common::die "No matching font files were found for ${FONT_LABEL[$id]}."
    fi

    for font_file in "${COLLECTED_FILES[@]}"; do
        basename="${font_file##*/}"
        for existing_basename in "${basenames[@]}"; do
            if [[ "$existing_basename" == "$basename" ]]; then
                common::die "Duplicate font filename in ${FONT_LABEL[$id]}: $basename"
            fi
        done
        basenames+=("$basename")
        fonts::verify_font_file "$id" "$font_file"
    done
    common::detail \
        "Validated ${#COLLECTED_FILES[@]} ${FONT_LABEL[$id]} font file(s)"
}

fonts::set_legacy_basenames() {
    local id="$1"

    LEGACY_BASENAMES=()
    case "$id" in
        jetbrains-mono)
            LEGACY_BASENAMES=(
                JetBrainsMonoNerdFont-Thin.ttf
                JetBrainsMonoNerdFont-ExtraLight.ttf
                JetBrainsMonoNerdFont-Light.ttf
                JetBrainsMonoNerdFont-Regular.ttf
                JetBrainsMonoNerdFont-Medium.ttf
                JetBrainsMonoNerdFont-SemiBold.ttf
                JetBrainsMonoNerdFont-Bold.ttf
                JetBrainsMonoNerdFont-ExtraBold.ttf
                JetBrainsMonoNerdFont-ThinItalic.ttf
                JetBrainsMonoNerdFont-ExtraLightItalic.ttf
                JetBrainsMonoNerdFont-LightItalic.ttf
                JetBrainsMonoNerdFont-Italic.ttf
                JetBrainsMonoNerdFont-MediumItalic.ttf
                JetBrainsMonoNerdFont-SemiBoldItalic.ttf
                JetBrainsMonoNerdFont-BoldItalic.ttf
                JetBrainsMonoNerdFont-ExtraBoldItalic.ttf
            )
        ;;
        sf-mono)
            LEGACY_BASENAMES=(
                SFMonoNerdFontMono-Bold.otf
                SFMonoNerdFontMono-BoldItalic.otf
                SFMonoNerdFontMono-Heavy.otf
                SFMonoNerdFontMono-HeavyItalic.otf
                SFMonoNerdFontMono-Italic.otf
                SFMonoNerdFontMono-Light.otf
                SFMonoNerdFontMono-LightItalic.otf
                SFMonoNerdFontMono-Medium.otf
                SFMonoNerdFontMono-MediumItalic.otf
                SFMonoNerdFontMono-Regular.otf
                SFMonoNerdFontMono-SemiBold.otf
                SFMonoNerdFontMono-SemiBoldItalic.otf
                "SFMono Bold Italic Nerd Font Complete.otf"
                "SFMono Bold Nerd Font Complete.otf"
                "SFMono Heavy Italic Nerd Font Complete.otf"
                "SFMono Heavy Nerd Font Complete.otf"
                "SFMono Light Italic Nerd Font Complete.otf"
                "SFMono Light Nerd Font Complete.otf"
                "SFMono Medium Italic Nerd Font Complete.otf"
                "SFMono Medium Nerd Font Complete.otf"
                "SFMono Regular Italic Nerd Font Complete.otf"
                "SFMono Regular Nerd Font Complete.otf"
                "SFMono Semibold Italic Nerd Font Complete.otf"
                "SFMono Semibold Nerd Font Complete.otf"
            )
        ;;
        sf-mono-terminal)
            LEGACY_BASENAMES=()
        ;;
        apple-emoji)
            LEGACY_BASENAMES=(AppleColorEmoji.ttf)
        ;;
        *)
            common::die "No legacy filename manifest for $id."
        ;;
    esac
}

fonts::validate_legacy_font_path() {
    local id="$1"
    local path="$2"
    local basename target

    if [[ ! -e "$path" ]] && [[ ! -L "$path" ]]; then
        common::die "Legacy font state changed before migration: $path"
    fi
    if [[ -L "$path" ]]; then
        return 0
    fi
    if [[ "$path" == */AppleColorEmoji.ttf ]]; then
        [[ -f "$path" ]] ||
            common::die "Refusing to remove unexpected legacy path type: $path"
        return 0
    fi
    [[ -d "$path" ]] ||
        common::die "Refusing to remove unexpected legacy path type: $path"

    fonts::set_legacy_basenames "$id"
    for basename in "${LEGACY_BASENAMES[@]}"; do
        target="$path/$basename"
        if [[ -L "$target" ]] || [[ -f "$target" ]] || [[ ! -e "$target" ]]; then
            continue
        fi
        common::die "Refusing to remove unexpected legacy font type: $target"
    done
    if ! fonts::run_for_scope find \
        "$path" -mindepth 1 -maxdepth 1 -print -quit >/dev/null; then
        common::die "Could not inspect legacy font directory: $path"
    fi
}

fonts::validate_replaceable_apple_config() {
    local id="$1"
    local config_file="${DETECTED_REPLACEABLE_CONFIG[$id]}"
    local backup_file="${config_file}.before-install_fonts.bak"

    if [[ -L "$config_file" ]]; then
        :
    elif [[ -f "$config_file" ]] &&
        fonts::file_mentions_apple_emoji "$config_file"; then
        :
    else
        common::die "The Apple Emoji config changed before migration: $config_file"
    fi
    if [[ -e "$backup_file" ]] || [[ -L "$backup_file" ]]; then
        common::die "Refusing to replace an existing config backup: $backup_file"
    fi
    CONFIG_BACKUP_TARGET["$id"]="$backup_file"
}

fonts::validate_migration_plan() {
    local id="$1"
    local path config_file

    config_file="${DETECTED_LEGACY_CONFIG[$id]:-}"
    if [[ -n "$config_file" ]] &&
        ! fonts::is_exact_legacy_apple_config "$config_file"; then
        common::die "The legacy Apple Emoji config changed before migration: $config_file"
    fi
    if [[ -n "${DETECTED_REPLACEABLE_CONFIG[$id]:-}" ]]; then
        fonts::validate_replaceable_apple_config "$id"
    fi
    if [[ -n "${DETECTED_LEGACY_BACKUP[$id]:-}" ]] &&
        ! fonts::system_legacy_backup_is_proven; then
        common::die "The legacy 60-generic.conf state changed before migration."
    fi
    while IFS= read -r path; do
        [[ -n "$path" ]] && fonts::validate_legacy_font_path "$id" "$path"
    done <<< "${DETECTED_LEGACY_FONTS[$id]:-}"
    return 0
}

fonts::validate_migration_plans() {
    local id

    for id in "${MIGRATION_FONTS[@]}"; do
        fonts::validate_migration_plan "$id"
    done
    return 0
}

fonts::remove_legacy_font_path() {
    local id="$1"
    local path="$2"
    local basename target remaining

    if [[ ! -e "$path" ]] && [[ ! -L "$path" ]]; then
        return 0
    fi

    common::step "Removing legacy font artifact: $path"
    if [[ -L "$path" ]]; then
        fonts::run_for_scope rm -f -- "$path"
        return 0
    fi
    if [[ "$path" == */AppleColorEmoji.ttf ]]; then
        [[ -f "$path" ]] || common::die "Refusing to remove unexpected legacy path type: $path"
        fonts::run_for_scope rm -f -- "$path"
        return 0
    fi
    [[ -d "$path" ]] || common::die "Refusing to remove unexpected legacy path type: $path"

    fonts::set_legacy_basenames "$id"
    for basename in "${LEGACY_BASENAMES[@]}"; do
        target="$path/$basename"
        if [[ -L "$target" ]] || [[ -f "$target" ]]; then
            fonts::run_for_scope rm -f -- "$target"
        elif [[ -e "$target" ]]; then
            common::die "Refusing to remove unexpected legacy font type: $target"
        fi
    done

    if ! remaining="$(
        fonts::run_for_scope find "$path" -mindepth 1 -maxdepth 1 -print -quit
    )"; then
        common::die "Could not inspect legacy font directory: $path"
    fi
    if [[ -z "$remaining" ]]; then
        fonts::run_for_scope rmdir -- "$path"
    else
        common::warn "Legacy directory contains unrecognized files and was kept: $path"
    fi
}

fonts::restore_legacy_system_config() {
    local id="$1"
    local active_config="/etc/fonts/conf.d/60-generic.conf"
    local backup_config="${DETECTED_LEGACY_BACKUP[$id]}"
    local canonical_config="/usr/share/fontconfig/conf.avail/60-generic.conf"
    local active_content clean_file temporary_link

    if ! fonts::system_legacy_backup_is_proven; then
        common::die "The legacy 60-generic.conf state changed during migration."
    fi
    if ! active_content="$(<"$active_config")"; then
        common::die "Could not read the active 60-generic.conf during migration."
    fi
    if [[ -f "$canonical_config" ]] && [[ ! -L "$canonical_config" ]] &&
        [[ -r "$canonical_config" ]]; then
        if [[ ! -L "$active_config" ]] ||
            [[ ! "$active_config" -ef "$canonical_config" ]]; then
            common::step "Restoring the distribution fontconfig symlink..."
            temporary_link="/etc/fonts/conf.d/.60-generic.conf.install_fonts.${TEMP_DIR##*/}"
            if [[ -e "$temporary_link" ]] || [[ -L "$temporary_link" ]]; then
                common::die "Refusing to replace an unexpected temporary link: $temporary_link"
            fi
            fonts::run_for_scope ln -s -- "$canonical_config" "$temporary_link"
            if ! fonts::run_for_scope mv -Tf -- "$temporary_link" "$active_config"; then
                fonts::run_for_scope rm -f -- "$temporary_link" || true
                common::die "Could not atomically restore the distribution fontconfig symlink."
            fi
        fi
    elif [[ "$active_content" != "$SYSTEM_CLEAN_CONFIG_CONTENT" ]]; then
        clean_file="$TEMP_DIR/60-generic.clean.conf"
        printf '%s\n' "$SYSTEM_CLEAN_CONFIG_CONTENT" > "$clean_file"
        common::step "Restoring 60-generic.conf from the proven legacy backup..."
        fonts::run_for_scope install -m 0644 -- "$clean_file" "$active_config"
    fi
    common::step "Removing the proven legacy fontconfig backup: $backup_config"
    fonts::run_for_scope rm -f -- "$backup_config"
}

fonts::migrate_legacy() {
    local id="$1"
    local path config_file config_backup package

    package="${DETECTED_LEGACY_PACKAGE[$id]:-}"
    if [[ -n "$package" ]]; then
        common::step "Removing legacy package: $package"
        fonts::run_for_scope dpkg --remove "$package"
    fi

    config_file="${DETECTED_LEGACY_CONFIG[$id]:-}"
    if [[ -n "$config_file" ]]; then
        if ! fonts::is_exact_legacy_apple_config "$config_file"; then
            common::die "The legacy Apple Emoji config changed during migration: $config_file"
        fi
        common::step "Removing legacy Apple Emoji config: $config_file"
        fonts::run_for_scope rm -f -- "$config_file"
    fi

    config_file="${DETECTED_REPLACEABLE_CONFIG[$id]:-}"
    if [[ -n "$config_file" ]]; then
        fonts::validate_replaceable_apple_config "$id"
        config_backup="${CONFIG_BACKUP_TARGET[$id]}"
        common::step "Preserving the previous Apple Emoji config at $config_backup..."
        fonts::run_for_scope mv -- "$config_file" "$config_backup"
    fi

    if [[ -n "${DETECTED_LEGACY_BACKUP[$id]:-}" ]]; then
        fonts::restore_legacy_system_config "$id"
    fi

    while IFS= read -r path; do
        [[ -n "$path" ]] && fonts::remove_legacy_font_path "$id" "$path"
    done <<< "${DETECTED_LEGACY_FONTS[$id]:-}"
    return 0
}

fonts::validate_install_target() {
    local id="$1"
    local destination="$INSTALL_ROOT/${FONT_DESTINATION[$id]}"

    if [[ -L "$destination" ]]; then
        common::die "Refusing to install through a symbolic link: $destination"
    fi
    if [[ -e "$destination" ]] && [[ ! -d "$destination" ]]; then
        common::die "Font destination exists but is not a directory: $destination"
    fi
}

fonts::validate_install_targets() {
    local id

    for id in "${ACTIVE_FONTS[@]}"; do
        fonts::validate_install_target "$id"
    done
}

fonts::install_font() {
    local id="$1"
    local destination="$INSTALL_ROOT/${FONT_DESTINATION[$id]}"
    local font_file installed_file

    fonts::collect_files "$id"
    fonts::validate_install_target "$id"

    common::step "Installing ${FONT_LABEL[$id]} to $destination..."
    fonts::run_for_scope install -d -m 0755 -- "$destination"
    fonts::run_for_scope install -m 0644 -- "${COLLECTED_FILES[@]}" "$destination/"

    for font_file in "${COLLECTED_FILES[@]}"; do
        installed_file="$destination/${font_file##*/}"
        [[ -f "$installed_file" ]] ||
            common::die "Installation verification failed: $installed_file"
    done

    INSTALLED_DIRS+=("$destination")
    common::detail \
        "Installed ${#COLLECTED_FILES[@]} ${FONT_LABEL[$id]} font file(s)"
}

fonts::is_managed_apple_config() {
    local config_file="$1"
    local line

    while IFS= read -r line; do
        [[ "$line" == *"$APPLE_CONFIG_MARKER"* ]] && return 0
    done < "$config_file"
    return 1
}

fonts::validate_apple_config_target() {
    local target="$FONTCONFIG_ROOT/$APPLE_CONFIG_NAME"

    if [[ -L "$target" ]]; then
        common::die "Refusing to replace a symbolic-link fontconfig fragment: $target"
    fi
    if [[ -e "$target" ]]; then
        if [[ ! -f "$target" ]]; then
            common::die "Fontconfig target exists but is not a file: $target"
        fi
        if ! fonts::is_managed_apple_config "$target"; then
            common::die "Refusing to replace an unmanaged fontconfig fragment: $target"
        fi
    fi
}

fonts::validate_hook_targets() {
    local id

    for id in "${ACTIVE_FONTS[@]}"; do
        if ! fonts::hook_is_enabled "$id"; then
            continue
        fi
        case "${FONT_HOOK[$id]}" in
            none) ;;
            apple-emoji) fonts::validate_apple_config_target ;;
            *) common::die "Unsupported post-install hook for $id: ${FONT_HOOK[$id]}" ;;
        esac
    done
}

fonts::configure_apple_emoji() {
    local source_file="$TEMP_DIR/$APPLE_CONFIG_NAME"
    local target="$FONTCONFIG_ROOT/$APPLE_CONFIG_NAME"

    fonts::validate_apple_config_target
    cat > "$source_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- $APPLE_CONFIG_MARKER -->
<fontconfig>
  <alias>
    <family>serif</family>
    <prefer><family>Apple Color Emoji</family></prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Apple Color Emoji</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>Apple Color Emoji</family></prefer>
  </alias>
  <match target="pattern">
    <test qual="any" name="family"><string>emoji</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>Apple Color Emoji</string>
    </edit>
  </match>
  <match target="pattern">
    <test qual="any" name="family"><string>Noto Color Emoji</string></test>
    <edit name="family" mode="assign" binding="same">
      <string>Apple Color Emoji</string>
    </edit>
  </match>
</fontconfig>
EOF

    common::step "Installing the Apple Color Emoji fontconfig fragment..."
    fonts::run_for_scope install -d -m 0755 -- "$FONTCONFIG_ROOT"
    fonts::run_for_scope install -m 0644 -- "$source_file" "$target"
    common::detail "Installed fontconfig fragment at $target"
}

fonts::run_hooks() {
    local id

    for id in "${ACTIVE_FONTS[@]}"; do
        if ! fonts::hook_is_enabled "$id"; then
            continue
        fi
        case "${FONT_HOOK[$id]}" in
            none) ;;
            apple-emoji) fonts::configure_apple_emoji ;;
            *) common::die "Unsupported post-install hook for $id: ${FONT_HOOK[$id]}" ;;
        esac
    done
}

main() {
    local id

    fonts::register_catalog
    fonts::parse_args "$@"

    if [[ "$(uname -s)" != "Linux" ]]; then
        common::die "This installer currently supports Linux only."
    fi

    fonts::resolve_paths
    fonts::evaluate_legacy
    if [[ "${#ACTIVE_FONTS[@]}" -eq 0 ]]; then
        common::summary 'Every selected font was skipped; no changes were made.'
        return 0
    fi

    fonts::check_requirements
    fonts::create_temp_dir

    for id in "${ACTIVE_FONTS[@]}"; do
        fonts::prepare "$id"
    done
    fonts::validate_install_targets
    fonts::validate_hook_targets
    fonts::validate_migration_plans

    for id in "${ACTIVE_FONTS[@]}"; do
        fonts::install_font "$id"
    done
    fonts::run_hooks

    for id in "${MIGRATION_FONTS[@]}"; do
        fonts::migrate_legacy "$id"
    done

    common::step "Refreshing the font cache..."
    if [[ "${#MIGRATION_FONTS[@]}" -gt 0 ]]; then
        if ! fonts::run_for_scope fc-cache -f >/dev/null; then
            common::die "Font cache refresh failed."
        fi
    elif ! fonts::run_for_scope fc-cache -f "${INSTALLED_DIRS[@]}" >/dev/null; then
        common::die "Font cache refresh failed."
    fi
    common::detail "Font cache refreshed"

    for id in "${ACTIVE_FONTS[@]}"; do
        common::detail "${FONT_LABEL[$id]} family: ${FONT_FAMILY[$id]}"
    done
    [[ "${#SKIPPED_FONTS[@]}" -eq 0 ]] ||
        common::warn "${#SKIPPED_FONTS[@]} selected font(s) were skipped."
    common::summary "Installed ${#ACTIVE_FONTS[@]} font family selection(s); ${#SKIPPED_FONTS[@]} skipped"
}

main "$@"
