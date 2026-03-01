#!/usr/bin/env bash
# @description Systemd unit file management: install, remove, and bulk service operations.

[[ -n "${_SYSTEMD_SH_LOADED:-}" ]] && return 0
readonly _SYSTEMD_SH_LOADED=1

# shellcheck source=../core/logging.sh
source "${BASH_SOURCE[0]%/*}/../core/logging.sh"
# shellcheck source=../core/utils.sh
source "${BASH_SOURCE[0]%/*}/../core/utils.sh"
# shellcheck source=services.sh
source "${BASH_SOURCE[0]%/*}/services.sh"

# @description Write a systemd unit file and reload the daemon. Idempotent: only
#   writes if content differs from the existing file. The .service suffix is added
#   automatically -- do not include it in NAME.
# @arg $1 string Unit name (without .service suffix)
# @arg $2 string Unit file content
systemd::install_unit() {
    local name="${1:?Missing unit name}"
    local content="${2:?Missing unit content}"
    local unit_dir="${_SYSTEMD_DIR:-/etc/systemd/system}"
    local unit_file="${unit_dir}/${name}.service"

    utils::ensure_dir "$unit_dir"

    if [[ -f "$unit_file" ]]; then
        if printf '%s\n' "$content" | cmp -s "$unit_file" -; then
            logging::info "Unit ${name}.service is already up to date"
            return 0
        fi
        logging::info "Updating unit ${name}.service"
    else
        logging::info "Installing unit ${name}.service"
    fi

    printf '%s\n' "$content" >"$unit_file"
    services::daemon_reload
}

# @description Render a template file using envsubst and install it as a systemd unit.
# @arg $1 string Path to the template file
# @arg $2 string Unit name (without .service suffix)
systemd::install_unit_from_template() {
    local template="${1:?Missing template file}"
    local name="${2:?Missing unit name}"
    local rendered
    utils::tempfile rendered
    utils::render_template "$template" "$rendered"
    local content
    content="$(cat "$rendered")"
    systemd::install_unit "$name" "$content"
}

# @description Stop, disable, and remove a systemd unit file. Safe if the unit
#   does not exist. Runs daemon-reload after removal.
# @arg $1 string Unit name (without .service suffix)
systemd::remove_unit() {
    local name="${1:?Missing unit name}"
    local unit_dir="${_SYSTEMD_DIR:-/etc/systemd/system}"
    local unit_file="${unit_dir}/${name}.service"

    if [[ ! -f "$unit_file" ]]; then
        logging::info "Unit ${name}.service does not exist, nothing to remove"
        return 0
    fi

    logging::info "Stopping and disabling ${name}.service"
    systemctl stop "${name}.service" 2>/dev/null || true
    systemctl disable "${name}.service" 2>/dev/null || true

    logging::info "Removing ${unit_file}"
    rm -f "$unit_file"
    services::daemon_reload
}

# @description Enable and start multiple services.
# @arg $@ string Service names
systemd::enable_all() {
    local svc
    for svc in "$@"; do
        services::enable_and_start "$svc"
    done
}

# @description Restart multiple services.
# @arg $@ string Service names
systemd::restart_all() {
    local svc
    for svc in "$@"; do
        services::restart "$svc"
    done
}

# @description Show status of multiple services (no pager).
# @arg $@ string Service names
systemd::status_all() {
    local svc
    for svc in "$@"; do
        systemctl status "$svc" --no-pager || true
    done
}

# @description Return true only if ALL given services are active.
# @arg $@ string Service names
systemd::is_all_active() {
    local svc
    for svc in "$@"; do
        if ! services::is_active "$svc"; then
            return 1
        fi
    done
    return 0
}

# @description Generate a systemd unit file from named parameters. Prints the
#   unit file content to stdout.
# @option --description string Service description
# @option --exec-start string ExecStart command (required)
# @option --user string User to run as
# @option --group string Group to run as
# @option --working-dir string Working directory
# @option --restart string Restart policy (default: always)
# @option --restart-sec string Restart delay in seconds (default: 5)
# @option --after string After dependency (default: network.target)
# @option --wanted-by string WantedBy target (default: multi-user.target)
systemd::simple_unit() {
    local description=""
    local exec_start=""
    local user=""
    local group=""
    local working_dir=""
    local restart="always"
    local restart_sec="5"
    local after="network.target"
    local wanted_by="multi-user.target"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description="$2"
                shift 2
                ;;
            --exec-start)
                exec_start="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --group)
                group="$2"
                shift 2
                ;;
            --working-dir)
                working_dir="$2"
                shift 2
                ;;
            --restart)
                restart="$2"
                shift 2
                ;;
            --restart-sec)
                restart_sec="$2"
                shift 2
                ;;
            --after)
                after="$2"
                shift 2
                ;;
            --wanted-by)
                wanted_by="$2"
                shift 2
                ;;
            *)
                logging::error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$exec_start" ]]; then
        logging::error "systemd::simple_unit requires --exec-start"
        return 1
    fi

    local unit=""
    unit+="[Unit]"$'\n'
    if [[ -n "$description" ]]; then
        unit+="Description=${description}"$'\n'
    fi
    unit+="After=${after}"$'\n'
    unit+=""$'\n'
    unit+="[Service]"$'\n'
    unit+="ExecStart=${exec_start}"$'\n'
    unit+="Restart=${restart}"$'\n'
    unit+="RestartSec=${restart_sec}"$'\n'
    if [[ -n "$user" ]]; then
        unit+="User=${user}"$'\n'
    fi
    if [[ -n "$group" ]]; then
        unit+="Group=${group}"$'\n'
    fi
    if [[ -n "$working_dir" ]]; then
        unit+="WorkingDirectory=${working_dir}"$'\n'
    fi
    unit+=""$'\n'
    unit+="[Install]"$'\n'
    unit+="WantedBy=${wanted_by}"

    printf '%s\n' "$unit"
}
