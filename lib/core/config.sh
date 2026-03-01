#!/usr/bin/env bash
# @description Safe .env configuration loading with layered strategy and validation.
# Loading priority: defaults -> .env.defaults -> .env -> environment variables (highest).

[[ -n "${_CONFIG_SH_LOADED:-}" ]] && return 0
readonly _CONFIG_SH_LOADED=1

# @description Load a .env file safely using line-by-line parsing.
# Skips comments, blank lines, and lines without '='.
# Does NOT override existing environment variables.
config::load_env_file() {
    local env_file="${1:-.env}"
    [[ -f "$env_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        local key="${line%%=*}"
        local value="${line#*=}"
        # Skip lines without =
        [[ "$key" == "$line" ]] && continue
        # Trim leading/trailing whitespace from key
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        # Strip surrounding quotes from value
        value="${value#\"}" ; value="${value%\"}"
        value="${value#\'}" ; value="${value%\'}"
        # Only set if not already in environment
        if [[ -z "${!key:-}" ]]; then
            printf -v "$key" '%s' "$value"
            export "$key"
        fi
    done < "$env_file"
}

# @description Load configuration with layered strategy.
config::load() {
    local config_dir="${1:-${PROJECT_ROOT:-.}/etc}"
    config::load_env_file "${config_dir}/.env.defaults"
    config::load_env_file "${config_dir}/.env"
}

# @description Validate that all required variables are set.
config::require_vars() {
    local missing=()
    for var in "$@"; do
        [[ -z "${!var:-}" ]] && missing+=("$var")
    done
    if (( ${#missing[@]} > 0 )); then
        printf 'Missing required variables: %s\n' "${missing[*]}" >&2
        return 1
    fi
}

# @description Check if a value is truthy (true, 1, yes, on).
config::is_true() {
    local val="${1,,}" # lowercase
    [[ "$val" =~ ^(true|1|yes|on)$ ]]
}

# @description Validate a port number (1-65535).
config::is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}
