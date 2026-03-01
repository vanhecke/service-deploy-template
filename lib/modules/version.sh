#!/usr/bin/env bash
# @description Version state management: read, write, and display installed version.

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../core/logging.sh
# shellcheck source=../core/utils.sh

[[ -n "${_VERSION_SH_LOADED:-}" ]] && return 0
readonly _VERSION_SH_LOADED=1

_VERSION_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_VERSION_SH_DIR}/../core/logging.sh"
source "${_VERSION_SH_DIR}/../core/utils.sh"

# @description Print the path to the version state file.
# Default: /var/lib/${APP_NAME}/version. Overridable via _VERSION_FILE env var.
version::state_file() {
    local app="${APP_NAME:?APP_NAME is required}"
    printf '%s\n' "${_VERSION_FILE:-/var/lib/${app}/version}"
}

# @description Read and print the current installed version from the state file.
# Prints "unknown" if the file does not exist.
version::get() {
    local state_file
    state_file="$(version::state_file)"

    if [[ -f "$state_file" ]]; then
        local ver
        read -r ver <"$state_file"
        printf '%s\n' "${ver:-unknown}"
    else
        printf '%s\n' "unknown"
    fi
}

# @description Write a version string to the state file. Creates parent directory if needed.
# @arg $1 string Version string to write
version::set() {
    local ver="${1:?Missing version argument}"
    local state_file
    state_file="$(version::state_file)"

    local parent
    parent="$(dirname "$state_file")"
    utils::ensure_dir "$parent"

    printf '%s\n' "$ver" >"$state_file"
    logging::info "Version set to ${ver}"
}

# @description Display the current version. If an app_version function exists (hook),
# call it and display that too. Intended for the ctl CLI.
version::check() {
    local current
    current="$(version::get)"
    logging::info "Installed version: ${current}"

    if declare -F app_version &>/dev/null; then
        local app_ver
        app_ver="$(app_version)"
        logging::info "Application version: ${app_ver}"
    fi
}
