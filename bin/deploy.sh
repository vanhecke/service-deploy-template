#!/usr/bin/env bash
# PROJECTNAME — REPO_DESCRIPTION
#
# Usage: sudo ./bin/deploy.sh [options]
#
# Idempotent deployment script. Run on the destination box as root.
# Sets up a dedicated app user, imports SSH keys, installs the management CLI.
#
# Options:
#   -h, --help       Show this help message
#   -v, --verbose    Enable debug logging
#   -n, --dry-run    Show what would be done without making changes
#   -c, --config     Path to config directory (default: etc/)

set -euo pipefail
set -o errtrace
IFS=$'\n\t'
trap 'printf "Error on line %d (exit %d)\n" "$LINENO" "$?" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly SCRIPT_DIR PROJECT_ROOT

# Source core libraries
source "${PROJECT_ROOT}/lib/core/logging.sh"
source "${PROJECT_ROOT}/lib/core/config.sh"
source "${PROJECT_ROOT}/lib/core/checks.sh"
source "${PROJECT_ROOT}/lib/core/utils.sh"
source "${PROJECT_ROOT}/lib/core/options.sh"

# Source module libraries
source "${PROJECT_ROOT}/lib/modules/packages.sh"
source "${PROJECT_ROOT}/lib/modules/firewall.sh"
source "${PROJECT_ROOT}/lib/modules/services.sh"
source "${PROJECT_ROOT}/lib/modules/network.sh"
source "${PROJECT_ROOT}/lib/modules/users.sh"
source "${PROJECT_ROOT}/lib/modules/ssh.sh"

# Define CLI options (single source of truth)
options::define "flag|h|help|Show this help message"
options::define "flag|v|verbose|Enable debug logging"
options::define "flag|n|dry-run|Show what would be done without making changes"
options::define "option|c|config|Configuration directory|${PROJECT_ROOT}/etc"
options::define "flag|C|cron|Run silently unless an error occurs"

cleanup() {
    local exit_code=$?
    logging::cron_cleanup
    utils::cleanup_tempfiles
    [[ -n "${SCRATCH_DIR:-}" ]] && rm -rf "$SCRATCH_DIR"
    [[ -n "${LOCK_FILE:-}" ]] && rm -f "$LOCK_FILE"
    exit "$exit_code"
}
trap cleanup EXIT

usage() {
    cat <<EOF
Usage: sudo $(basename "$0") [options]

PROJECTNAME deploy script — run on the destination box.
REPO_DESCRIPTION

Sets up:
  - Dedicated app user with SSH access
  - GitHub public key import
  - Scoped sudoers rules
  - On-machine management CLI (<APP_NAME>ctl)
  - Firewall rules (optional)

$(options::usage)

Environment Variables:
    APP_NAME         Application name
    APP_USER         Dedicated user to create
    APP_PORT         Application port (default: 8080)
    SSH_GITHUB_USER  GitHub username for SSH key import (default: vanhecke)
    LOG_LEVEL        Log level: DEBUG|INFO|WARN|ERROR|FATAL (default: INFO)

Examples:
    sudo $(basename "$0")                  # Deploy with default config
    sudo $(basename "$0") -v               # Deploy with debug logging
    sudo $(basename "$0") -n               # Dry run — show what would happen
    sudo $(basename "$0") -c /etc/myapp    # Custom config directory
EOF
}

# @description Copy the deploy project into the app user's home directory.
deploy::install_project() {
    local app_user="$1"
    local home_dir
    home_dir="$(eval echo "~${app_user}")"
    local deploy_dir="${home_dir}/deploy"

    if [[ "${DRY_RUN}" == true ]]; then
        logging::info "[DRY RUN] Would copy project to ${deploy_dir}"
        return 0
    fi
    utils::ensure_dir "$deploy_dir" "${app_user}:${app_user}"
    rsync -a --delete --exclude='.git' --exclude='.env' "${PROJECT_ROOT}/" "${deploy_dir}/"
    chown -R "${app_user}:${app_user}" "$deploy_dir"
    logging::info "Installed deploy project to ${deploy_dir}"
}

# @description Install the management CLI and create a symlink in /usr/local/bin.
deploy::install_ctl() {
    local app_user="$1"
    local app_name="$2"
    local home_dir
    home_dir="$(eval echo "~${app_user}")"
    local bin_dir="${home_dir}/bin"
    local ctl_name="${app_name}ctl"
    local ctl_path="${bin_dir}/${ctl_name}"

    if [[ "${DRY_RUN}" == true ]]; then
        logging::info "[DRY RUN] Would install ${ctl_name} to ${ctl_path}"
        return 0
    fi
    utils::ensure_dir "$bin_dir" "${app_user}:${app_user}"
    cp "${PROJECT_ROOT}/bin/ctl.sh" "$ctl_path"
    chmod 755 "$ctl_path"
    chown "${app_user}:${app_user}" "$ctl_path"
    utils::ensure_symlink "$ctl_path" "/usr/local/bin/${ctl_name}"
    logging::info "Installed ${ctl_name} → /usr/local/bin/${ctl_name}"
}

main() {
    options::parse "$@"

    # Apply parsed options
    [[ "${VERBOSE}" == true ]] && export LOG_LEVEL="DEBUG"
    [[ "${CRON}" == true ]] && logging::cron_init
    local config_dir="${CONFIG}"

    logging::info "Starting PROJECTNAME deployment"

    # Load configuration
    config::load "$config_dir"
    config::require_vars APP_NAME APP_USER

    # shellcheck disable=SC2153 # Set by config::load
    local app_name="${APP_NAME}"
    # shellcheck disable=SC2153 # Set by config::load
    local app_user="${APP_USER}"
    local github_user="${SSH_GITHUB_USER:-vanhecke}"

    # Preflight checks
    checks::require_bash_version 4
    checks::detect_os
    checks::detect_arch
    logging::info "Detected OS: ${OS_ID} ${OS_VERSION_ID} (${OS_ARCH})"

    if [[ "$DRY_RUN" == true ]]; then
        logging::info "[DRY RUN] Showing what would be done"
    fi

    # 1. Require root
    checks::require_root

    # 2. Install base packages
    local -a extra_pkgs=()
    if [[ -n "${EXTRA_PACKAGES:-}" ]]; then
        IFS=' ' read -ra extra_pkgs <<<"${EXTRA_PACKAGES}"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        logging::info "[DRY RUN] Would install packages: curl openssh-server rsync ${extra_pkgs[*]:-}"
    else
        packages::install curl openssh-server rsync "${extra_pkgs[@]}"
    fi

    # 3. Create dedicated user
    users::ensure_user "$app_user"

    # 4. Lock password login
    users::lock_password "$app_user"

    # 5. Set up SSH directory
    ssh::ensure_authorized_keys "$app_user"

    # 6. Import GitHub SSH keys
    ssh::import_github_keys "$github_user" "$app_user"

    # 7. Install scoped sudoers rules
    users::ensure_sudoers "$app_user" "$app_name"

    # 8. Copy deploy project to user home
    deploy::install_project "$app_user"

    # 9. Install management CLI
    deploy::install_ctl "$app_user" "$app_name"

    # 10. Firewall (if enabled)
    if [[ "${FIREWALL_ENABLED:-false}" == true ]]; then
        local -a allowed_ports=()
        IFS=' ' read -ra allowed_ports <<<"${ALLOWED_PORTS:-22}"
        if [[ "$DRY_RUN" == true ]]; then
            logging::info "[DRY RUN] Would enable firewall and allow ports: ${allowed_ports[*]}"
        else
            firewall::enable
            firewall::allow_ports "${allowed_ports[@]}"
        fi
    fi

    logging::info "PROJECTNAME deployment complete"
    if [[ "$DRY_RUN" != true ]]; then
        logging::info "Management CLI available: ${app_name}ctl help"
    fi
}

if ! (return 0 2>/dev/null); then
    main "$@"
fi
