#!/usr/bin/env bash
# PROJECTNAME — REPO_DESCRIPTION
#
# Usage: ./bin/deploy.sh [options]
#
# Options:
#   -h, --help       Show this help message
#   -v, --verbose    Enable debug logging
#   -n, --dry-run    Show what would be done without making changes
#   -c, --config     Path to config directory (default: etc/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core libraries
source "${PROJECT_ROOT}/lib/core/logging.sh"
source "${PROJECT_ROOT}/lib/core/config.sh"
source "${PROJECT_ROOT}/lib/core/checks.sh"
source "${PROJECT_ROOT}/lib/core/utils.sh"

# Source module libraries
source "${PROJECT_ROOT}/lib/modules/packages.sh"
source "${PROJECT_ROOT}/lib/modules/firewall.sh"
source "${PROJECT_ROOT}/lib/modules/services.sh"
source "${PROJECT_ROOT}/lib/modules/network.sh"

# Globals
DRY_RUN=false
CONFIG_DIR="${PROJECT_ROOT}/etc"

cleanup() {
    local exit_code=$?
    [[ -n "${SCRATCH_DIR:-}" ]] && rm -rf "$SCRATCH_DIR"
    [[ -n "${LOCK_FILE:-}" ]] && rm -f "$LOCK_FILE"
    exit "$exit_code"
}
trap cleanup EXIT

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

PROJECTNAME deploy script.
REPO_DESCRIPTION

Options:
    -h, --help       Show this help message
    -v, --verbose    Enable debug logging
    -n, --dry-run    Show what would be done without making changes
    -c, --config     Path to config directory (default: etc/)

Environment Variables:
    APP_NAME         Application name
    APP_PORT         Application port (default: 8080)
    LOG_LEVEL        Log level: DEBUG|INFO|WARN|ERROR|FATAL (default: INFO)
    LOG_FILE         Path to log file (optional, logs to file when set)

Examples:
    $(basename "$0")                  # Deploy with default config
    $(basename "$0") -v               # Deploy with debug logging
    $(basename "$0") -n               # Dry run
    $(basename "$0") -c /etc/myapp    # Custom config directory
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -v | --verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            -n | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -c | --config)
                CONFIG_DIR="$2"
                shift 2
                ;;
            *)
                logging::error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    logging::info "Starting PROJECTNAME deployment"

    # Load configuration
    config::load "$CONFIG_DIR"
    config::require_vars APP_NAME

    # Preflight checks
    checks::require_bash_version 4
    checks::detect_os
    checks::detect_arch
    logging::info "Detected OS: ${OS_ID} ${OS_VERSION_ID} (${OS_ARCH})"

    if [[ "$DRY_RUN" == true ]]; then
        logging::info "[DRY RUN] Would deploy ${APP_NAME}"
        exit 0
    fi

    # --- Add your deployment steps below ---
    #
    # Example:
    #   checks::require_root
    #   packages::install curl wget unzip
    #   firewall::enable
    #   firewall::allow_ports 22 80 443 "${APP_PORT:-8080}"
    #   services::enable_and_start your-service
    #
    # --- End deployment steps ---

    logging::info "PROJECTNAME deployment complete"
}

main "$@"
