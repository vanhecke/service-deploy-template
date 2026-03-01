#!/usr/bin/env bash
# PROJECTNAME — Push deployment to a remote host via rsync + SSH.
#
# Usage: bin/push.sh [options] user@host
#
# Syncs the project to the remote host and runs deploy.sh there.
#
# Options:
#   -h, --help       Show this help message
#   -v, --verbose    Enable debug logging
#   -n, --dry-run    Show what would be done
#   -k, --key FILE   SSH key to use
#   -p, --port PORT  SSH port (default: 22)

set -euo pipefail
set -o errtrace
IFS=$'\n\t'
trap 'printf "Error in %s on line %d (exit %d)\n" "${FUNCNAME[0]:-main}" "$LINENO" "$?" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly SCRIPT_DIR PROJECT_ROOT

# Source core libraries
source "${PROJECT_ROOT}/lib/core/logging.sh"
source "${PROJECT_ROOT}/lib/core/options.sh"

# Define CLI options
options::define "flag|h|help|Show this help message"
options::define "flag|n|dry-run|Show what would be done"
options::define "flag|v|verbose|Enable debug logging"
options::define "option|k|key|SSH key file"
options::define "option|p|port|SSH port|22"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] user@host

Push deployment to a remote host via rsync + SSH.

Syncs the project to the remote host, runs deploy.sh there, and cleans up.

$(options::usage)

Examples:
    $(basename "$0") deploy@myserver.com
    $(basename "$0") -n deploy@myserver.com          # Dry run
    $(basename "$0") -k ~/.ssh/id_ed25519 root@host  # Custom SSH key
    $(basename "$0") -p 2222 deploy@host             # Custom SSH port
EOF
}

# @description Extract APP_NAME from etc/.env or etc/.env.example.
push::get_app_name() {
    local env_file
    if [[ -f "${PROJECT_ROOT}/etc/.env" ]]; then
        env_file="${PROJECT_ROOT}/etc/.env"
    elif [[ -f "${PROJECT_ROOT}/etc/.env.example" ]]; then
        env_file="${PROJECT_ROOT}/etc/.env.example"
    else
        logging::error "No etc/.env or etc/.env.example found"
        return 1
    fi

    local app_name
    # shellcheck disable=SC2034
    app_name="$(grep -E '^APP_NAME=' "$env_file" | head -1 | cut -d= -f2-)"
    if [[ -z "$app_name" ]]; then
        logging::error "APP_NAME not found in ${env_file}"
        return 1
    fi
    printf '%s' "$app_name"
}

# @description Build SSH options array from parsed CLI flags.
push::ssh_opts() {
    local -a opts=(-o "StrictHostKeyChecking=accept-new" -o "ConnectTimeout=10")
    if [[ -n "${KEY:-}" ]]; then
        opts+=(-i "$KEY")
    fi
    if [[ "${PORT:-22}" != "22" ]]; then
        opts+=(-p "$PORT")
    fi
    printf '%s\n' "${opts[@]}"
}

# @description Build rsync options array.
push::rsync_opts() {
    local -a ssh_opts
    mapfile -t ssh_opts < <(push::ssh_opts)

    local ssh_cmd="ssh"
    if [[ ${#ssh_opts[@]} -gt 0 ]]; then
        ssh_cmd="ssh ${ssh_opts[*]}"
    fi

    local -a opts=(
        -az --delete
        -e "$ssh_cmd"
        --exclude='.git'
        --exclude='.github'
        --exclude='tests'
        --exclude='.env'
        --exclude='docs'
        --exclude='.worktrees'
        --exclude='.claude'
        --exclude='research.md'
        --exclude='node_modules'
    )

    if [[ "${VERBOSE}" == "true" ]]; then
        opts+=(-v)
    fi
    if [[ "${DRY_RUN}" == "true" ]]; then
        opts+=(-n)
    fi

    printf '%s\n' "${opts[@]}"
}

main() {
    options::parse "$@"

    # Apply parsed options
    [[ "${VERBOSE}" == "true" ]] && export LOG_LEVEL="DEBUG"

    # Validate user@host argument
    if [[ ${#ARGS[@]} -eq 0 ]]; then
        logging::error "Missing required argument: user@host"
        usage >&2
        exit 1
    fi
    local target="${ARGS[0]}"

    # Basic validation of user@host format
    if [[ "$target" != *@* ]]; then
        logging::error "Invalid target '${target}' — expected user@host format"
        exit 1
    fi

    # Validate SSH key file if specified
    if [[ -n "${KEY:-}" ]] && [[ ! -f "$KEY" ]]; then
        logging::error "SSH key file not found: ${KEY}"
        exit 1
    fi

    # Get APP_NAME for the remote temp directory
    local app_name
    app_name="$(push::get_app_name)"
    local remote_dir="/tmp/${app_name}-deploy"

    logging::info "Deploying to ${target}:${remote_dir}"
    logging::debug "SSH port: ${PORT}"
    [[ -n "${KEY:-}" ]] && logging::debug "SSH key: ${KEY}"

    # Build rsync options
    local -a rsync_opts
    mapfile -t rsync_opts < <(push::rsync_opts)

    # Step 1: rsync the project to the remote host
    logging::info "Syncing project files to ${target}"
    if [[ "${DRY_RUN}" == "true" ]]; then
        logging::info "[DRY RUN] Would rsync to ${target}:${remote_dir}/"
        logging::debug "rsync ${rsync_opts[*]} ${PROJECT_ROOT}/ ${target}:${remote_dir}/"
    fi
    # rsync --dry-run (-n) is already added in rsync_opts when DRY_RUN is true
    rsync "${rsync_opts[@]}" "${PROJECT_ROOT}/" "${target}:${remote_dir}/"

    if [[ "${DRY_RUN}" == "true" ]]; then
        logging::info "[DRY RUN] Would run deploy.sh on ${target}"
        logging::info "[DRY RUN] Would clean up ${remote_dir} on ${target}"
        return 0
    fi

    # Build SSH options for direct ssh calls
    local -a ssh_opts
    mapfile -t ssh_opts < <(push::ssh_opts)

    # Step 2: SSH to the host and run deploy.sh
    logging::info "Running deploy.sh on ${target}"
    # shellcheck disable=SC2029
    ssh "${ssh_opts[@]}" "$target" "cd ${remote_dir} && sudo ./bin/deploy.sh"

    # Step 3: Clean up the temp directory on success
    logging::info "Cleaning up ${remote_dir} on ${target}"
    # shellcheck disable=SC2029
    ssh "${ssh_opts[@]}" "$target" "rm -rf ${remote_dir}"

    logging::info "Deployment to ${target} complete"
}

if ! (return 0 2>/dev/null); then
    main "$@"
fi
