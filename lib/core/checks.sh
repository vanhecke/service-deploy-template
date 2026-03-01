#!/usr/bin/env bash
# @description OS detection, dependency checking, root verification, architecture detection.

[[ -n "${_CHECKS_SH_LOADED:-}" ]] && return 0
readonly _CHECKS_SH_LOADED=1

# @description Detect the OS by parsing /etc/os-release.
# Sets global variables: OS_ID, OS_VERSION_ID, OS_CODENAME
checks::detect_os() {
    local release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ ! -f "$release_file" ]]; then
        printf 'Cannot detect OS: %s not found\n' "$release_file" >&2
        return 1
    fi

    local id="" version_id="" codename=""
    while IFS='=' read -r key value; do
        value="${value#\"}"
        value="${value%\"}"
        case "$key" in
            ID) id="$value" ;;
            VERSION_ID) version_id="$value" ;;
            VERSION_CODENAME) codename="$value" ;;
        esac
    done <"$release_file"

    OS_ID="$id"
    OS_VERSION_ID="$version_id"
    OS_CODENAME="$codename"
    export OS_ID OS_VERSION_ID OS_CODENAME

    case "$id" in
        ubuntu | debian) ;;
        *)
            printf 'Unsupported OS: %s\n' "$id" >&2
            return 1
            ;;
    esac

    printf '%s %s (%s)\n' "$id" "$version_id" "$codename"
}

# @description Detect CPU architecture and map to Debian package naming.
checks::detect_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64) OS_ARCH="amd64" ;;
        aarch64) OS_ARCH="arm64" ;;
        armv7l) OS_ARCH="armhf" ;;
        *) OS_ARCH="$machine" ;;
    esac
    export OS_ARCH
    printf '%s\n' "$OS_ARCH"
}

# @description Check that all required commands are available in PATH.
checks::require_commands() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if ((${#missing[@]} > 0)); then
        printf 'Missing required commands: %s\n' "${missing[*]}" >&2
        return 1
    fi
}

# @description Verify the script is running as root.
checks::require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        printf 'This script must be run as root\n' >&2
        return 1
    fi
}

# @description Verify minimum Bash version.
checks::require_bash_version() {
    local min_version="${1:-4}"
    if ((BASH_VERSINFO[0] < min_version)); then
        printf 'Bash %s+ required, found %s\n' "$min_version" "$BASH_VERSION" >&2
        return 1
    fi
}

# @description Check if stdin is connected to a terminal (interactive).
checks::is_interactive() {
    [[ -t 0 ]]
}

# @description Prompt the user for y/n confirmation. Returns 0 on yes, 1 on no.
#   Skips prompt and returns 0 when FORCE=true.
checks::confirm() {
    local prompt="${1:?Missing prompt message}"
    [[ "${FORCE:-false}" == true ]] && return 0
    local answer
    printf '%s [y/N] ' "$prompt" >&2
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# @description Run a command as root, using sudo if not already root.
checks::run_as_root() {
    if [[ $# -eq 0 ]]; then
        printf 'checks::run_as_root: missing command\n' >&2
        return 1
    fi
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        "$@"
    else
        sudo -H -- "$@"
    fi
}
