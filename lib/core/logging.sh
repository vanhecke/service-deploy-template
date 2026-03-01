#!/usr/bin/env bash
# @description Structured logging with 5 levels, NO_COLOR support, timestamps.
# @see https://no-color.org/

# Guard against double-sourcing
[[ -n "${_LOGGING_SH_LOADED:-}" ]] && return 0
readonly _LOGGING_SH_LOADED=1

# Log level constants (lower = more verbose)
declare -gA _LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [FATAL]=4)

# @description Initialize ANSI color variables based on NO_COLOR, FORCE_COLOR, and terminal detection.
# shellcheck disable=SC2034
logging::setup_colors() {
    if [[ -n "${NO_COLOR:-}" ]]; then
        RED='' GREEN='' YELLOW='' CYAN='' BOLD_RED='' NC='' BOLD=''
    elif [[ -n "${FORCE_COLOR:-}" ]] || [[ -t 2 ]]; then
        RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
        CYAN='\033[0;36m' BOLD_RED='\033[1;31m' NC='\033[0m' BOLD='\033[1m'
    else
        RED='' GREEN='' YELLOW='' CYAN='' BOLD_RED='' NC='' BOLD=''
    fi
}

# @description Log a message at the specified level with ISO 8601 timestamp.
logging::log() {
    local level="${1:?Missing log level}"
    shift
    local message="$*"

    local current_level="${LOG_LEVEL:-INFO}"
    local level_num="${_LOG_LEVELS[$level]:-1}"
    local current_num="${_LOG_LEVELS[$current_level]:-1}"

    # Filter by log level
    ((level_num < current_num)) && return 0

    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    local color=""
    case "$level" in
        DEBUG) color="${CYAN:-}" ;;
        INFO) color="${GREEN:-}" ;;
        WARN) color="${YELLOW:-}" ;;
        ERROR) color="${RED:-}" ;;
        FATAL) color="${BOLD_RED:-}" ;;
    esac

    local formatted
    formatted="${color}[${timestamp}] [${level}]${NC:-} ${message}"

    # WARN/ERROR/FATAL go to stderr; DEBUG/INFO go to stdout
    if ((level_num >= 2)); then
        printf '%b\n' "$formatted" >&2
    else
        printf '%b\n' "$formatted"
    fi
}

# @description Convenience wrappers for each log level.
logging::debug() { logging::log DEBUG "$@"; }
logging::info() { logging::log INFO "$@"; }
logging::warn() { logging::log WARN "$@"; }
logging::error() { logging::log ERROR "$@"; }
logging::fatal() {
    logging::log FATAL "$@"
    exit 1
}

# Initialize colors on source
logging::setup_colors
