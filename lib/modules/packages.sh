#!/usr/bin/env bash
# @description apt-get wrappers with idempotent installs and cache-aware updates.

[[ -n "${_PACKAGES_SH_LOADED:-}" ]] && return 0
readonly _PACKAGES_SH_LOADED=1

readonly _APT_CACHE_MAX_AGE=3600 # 1 hour in seconds

# @description Update apt cache if older than _APT_CACHE_MAX_AGE.
packages::update_cache() {
    local stamp="/var/lib/apt/periodic/update-success-stamp"
    local now
    now="$(date +%s)"
    if [[ -f "$stamp" ]]; then
        local last
        last="$(stat -c %Y "$stamp" 2>/dev/null || stat -f %m "$stamp" 2>/dev/null)"
        if (( now - last < _APT_CACHE_MAX_AGE )); then
            return 0
        fi
    fi
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
}

# @description Install packages idempotently.
packages::install() {
    local to_install=()
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        fi
    done
    if (( ${#to_install[@]} > 0 )); then
        packages::update_cache
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${to_install[@]}"
    fi
}

# @description Check if a package is installed.
packages::is_installed() {
    dpkg -s "$1" &>/dev/null
}

# @description Remove packages.
packages::remove() {
    local to_remove=()
    for pkg in "$@"; do
        if dpkg -s "$pkg" &>/dev/null; then
            to_remove+=("$pkg")
        fi
    done
    if (( ${#to_remove[@]} > 0 )); then
        DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "${to_remove[@]}"
    fi
}
