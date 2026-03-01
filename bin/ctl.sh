#!/usr/bin/env bash
# @description On-machine CLI for managing the deployed service.
#
# Usage: <APP_NAME>ctl <command>
#
# Installed by deploy.sh. Sources libraries from the deploy directory.

set -euo pipefail
set -o errtrace
IFS=$'\n\t'
trap 'printf "Error in %s on line %d (exit %d)\n" "${FUNCNAME[0]:-main}" "$LINENO" "$?" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="$(basename "$APP_HOME")"
readonly SCRIPT_DIR APP_HOME APP_NAME

# Source core libraries from deployed copy
# shellcheck source=../lib/core/logging.sh
source "${APP_HOME}/deploy/lib/core/logging.sh"
# shellcheck source=../lib/core/config.sh
source "${APP_HOME}/deploy/lib/core/config.sh"
# shellcheck source=../lib/core/checks.sh
source "${APP_HOME}/deploy/lib/core/checks.sh"
# shellcheck source=../lib/core/utils.sh
source "${APP_HOME}/deploy/lib/core/utils.sh"

# Source module libraries
# shellcheck source=../lib/modules/services.sh
source "${APP_HOME}/deploy/lib/modules/services.sh"
# shellcheck source=../lib/modules/systemd.sh
source "${APP_HOME}/deploy/lib/modules/systemd.sh"
# shellcheck source=../lib/modules/backup.sh
source "${APP_HOME}/deploy/lib/modules/backup.sh"
# shellcheck source=../lib/modules/version.sh
source "${APP_HOME}/deploy/lib/modules/version.sh"

# Source application hooks
# shellcheck source=../app/hooks.sh
source "${APP_HOME}/deploy/app/hooks.sh"

# Load config if present
if [[ -d "${APP_HOME}/.config/${APP_NAME}" ]]; then
    config::load "${APP_HOME}/.config/${APP_NAME}"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# @description Build the list of services to manage. Uses APP_SERVICES if set,
# otherwise falls back to APP_NAME.
ctl::_services() {
    local svc_list="${APP_SERVICES:-${APP_NAME}}"
    local -a svcs
    IFS=' ' read -ra svcs <<<"$svc_list"
    printf '%s\n' "${svcs[@]}"
}

# @description Build the list of ports to check. Supports space-separated APP_PORT.
ctl::_ports() {
    local port_list="${APP_PORT:-}"
    [[ -z "$port_list" ]] && return 0
    local -a ports
    IFS=' ' read -ra ports <<<"$port_list"
    printf '%s\n' "${ports[@]}"
}

# @description Escape a string for safe inclusion in JSON values.
# Handles backslash, double-quote, and control characters.
ctl::_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

ctl::health() {
    local json_mode=false
    if [[ "${1:-}" == "--json" ]]; then
        json_mode=true
    fi

    local ok=true

    # -- Collect service status --
    local -a svc_names=()
    local -a svc_states=()
    local svc state
    while IFS= read -r svc; do
        svc_names+=("$svc")
        if systemctl is-active "$svc" &>/dev/null; then
            state="active"
        else
            state="inactive"
            ok=false
        fi
        svc_states+=("$state")
        if [[ "$json_mode" == false ]]; then
            if [[ "$state" == "active" ]]; then
                logging::info "Service ${svc}: active"
            else
                logging::warn "Service ${svc}: inactive or not found"
            fi
        fi
    done < <(ctl::_services)

    # -- Collect port status --
    local -a port_names=()
    local -a port_states=()
    local port pstate
    while IFS= read -r port; do
        [[ -z "$port" ]] && continue
        port_names+=("$port")
        if ss -tlnp | grep -q ":${port} " 2>/dev/null; then
            pstate="listening"
        else
            pstate="closed"
            ok=false
        fi
        port_states+=("$pstate")
        if [[ "$json_mode" == false ]]; then
            if [[ "$pstate" == "listening" ]]; then
                logging::info "Port ${port}: listening"
            else
                logging::warn "Port ${port}: not listening"
            fi
        fi
    done < <(ctl::_ports)

    # -- Disk usage --
    local disk_pct
    disk_pct="$(df / --output=pcent | tail -1 | tr -d ' %')"
    if ((disk_pct > 90)); then
        ok=false
        [[ "$json_mode" == false ]] && logging::warn "Disk usage: ${disk_pct}%"
    else
        [[ "$json_mode" == false ]] && logging::info "Disk usage: ${disk_pct}%"
    fi

    # -- Memory usage --
    local mem_pct=0
    local mem_avail mem_total
    mem_avail="$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null)" || true
    mem_total="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)" || true
    if [[ -n "${mem_avail:-}" ]] && [[ -n "${mem_total:-}" ]] && ((mem_total > 0)); then
        mem_pct=$(((mem_total - mem_avail) * 100 / mem_total))
        if ((mem_pct > 90)); then
            ok=false
            [[ "$json_mode" == false ]] && logging::warn "Memory usage: ${mem_pct}%"
        else
            [[ "$json_mode" == false ]] && logging::info "Memory usage: ${mem_pct}%"
        fi
    fi

    # -- App health hook --
    local app_health_status="ok"
    if ! app_health 2>/dev/null; then
        app_health_status="fail"
        ok=false
        [[ "$json_mode" == false ]] && logging::warn "App health check: failed"
    else
        [[ "$json_mode" == false ]] && logging::info "App health check: ok"
    fi

    # -- JSON output --
    if [[ "$json_mode" == true ]]; then
        local overall="healthy"
        [[ "$ok" == false ]] && overall="unhealthy"

        local hostname_val
        hostname_val="$(hostname)"
        local version_val
        version_val="$(version::get 2>/dev/null)" || version_val="unknown"
        local timestamp_val
        timestamp_val="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

        # Build services JSON object
        local svc_json=""
        local i
        for ((i = 0; i < ${#svc_names[@]}; i++)); do
            [[ -n "$svc_json" ]] && svc_json+=", "
            svc_json+="\"$(ctl::_json_escape "${svc_names[$i]}")\": \"$(ctl::_json_escape "${svc_states[$i]}")\""
        done

        # Build ports JSON object
        local port_json=""
        for ((i = 0; i < ${#port_names[@]}; i++)); do
            [[ -n "$port_json" ]] && port_json+=", "
            port_json+="\"$(ctl::_json_escape "${port_names[$i]}")\": \"$(ctl::_json_escape "${port_states[$i]}")\""
        done

        printf '{"status": "%s", "hostname": "%s", "app": "%s", "version": "%s", "services": {%s}, "ports": {%s}, "disk_pct": %d, "mem_pct": %d, "app_health": "%s", "timestamp": "%s"}\n' \
            "$overall" \
            "$(ctl::_json_escape "$hostname_val")" \
            "$(ctl::_json_escape "$APP_NAME")" \
            "$(ctl::_json_escape "$version_val")" \
            "$svc_json" \
            "$port_json" \
            "$disk_pct" \
            "$mem_pct" \
            "$app_health_status" \
            "$timestamp_val"
        [[ "$ok" == true ]]
        return
    fi

    [[ "$ok" == true ]]
}

ctl::status() {
    local -a svcs
    mapfile -t svcs < <(ctl::_services)
    systemd::status_all "${svcs[@]}"
}

ctl::restart() {
    local -a svcs
    mapfile -t svcs < <(ctl::_services)
    local svc
    for svc in "${svcs[@]}"; do
        checks::run_as_root systemctl restart "$svc"
        logging::info "Restarted ${svc}"
    done
}

ctl::start() {
    local -a svcs
    mapfile -t svcs < <(ctl::_services)
    local svc
    for svc in "${svcs[@]}"; do
        checks::run_as_root systemctl start "$svc"
        logging::info "Started ${svc}"
    done
}

ctl::stop() {
    local -a svcs
    mapfile -t svcs < <(ctl::_services)
    local svc
    for svc in "${svcs[@]}"; do
        checks::run_as_root systemctl stop "$svc"
        logging::info "Stopped ${svc}"
    done
}

ctl::upgrade() {
    logging::info "Starting upgrade"

    # Back up first
    logging::info "Running pre-upgrade backup"
    app_backup

    # Run application update hook
    logging::info "Running app_update hook"
    app_update

    # System package upgrade
    logging::info "Running system package upgrade"
    checks::run_as_root apt-get update -qq
    checks::run_as_root apt-get upgrade -y -qq

    # Restart services
    logging::info "Restarting services"
    ctl::restart

    logging::info "Upgrade complete"
}

ctl::backup() {
    app_backup
}

ctl::restore() {
    local file="${1:-}"
    if [[ -n "$file" ]]; then
        app_restore "$file"
    else
        app_restore
    fi
}

ctl::version() {
    version::check
}

ctl::uninstall() {
    if ! checks::confirm "Uninstall ${APP_NAME}? This cannot be undone."; then
        logging::info "Uninstall cancelled"
        return 0
    fi

    logging::info "Running app_uninstall hook"
    app_uninstall

    # Remove systemd units
    local -a svcs
    mapfile -t svcs < <(ctl::_services)
    local svc
    for svc in "${svcs[@]}"; do
        checks::run_as_root systemd::remove_unit "$svc"
    done

    logging::info "Uninstall of ${APP_NAME} complete"
}

ctl::logs() {
    local lines="${1:-50}"
    local -a svcs
    mapfile -t svcs < <(ctl::_services)
    local svc
    for svc in "${svcs[@]}"; do
        journalctl -u "$svc" --no-pager -n "$lines"
    done
}

ctl::usage() {
    cat <<EOF
Usage: ${APP_NAME}ctl <command>

Commands:
    health [--json]  Run health checks (service, port, disk, memory, app)
    status           Show service status
    start            Start all services
    stop             Stop all services
    restart          Restart all services
    upgrade          Backup, update app, apt upgrade, restart
    backup           Run application backup hook
    restore [FILE]   Restore from backup (latest if FILE omitted)
    version          Show installed and application version
    uninstall        Remove application and systemd units
    logs [N]         Show last N log lines (default: 50)
    help             Show this help

EOF
}

if ! (return 0 2>/dev/null); then
    case "${1:-help}" in
        health) ctl::health "${2:-}" ;;
        status) ctl::status ;;
        start) ctl::start ;;
        stop) ctl::stop ;;
        restart) ctl::restart ;;
        upgrade) ctl::upgrade ;;
        backup) ctl::backup ;;
        restore)
            shift
            ctl::restore "${1:-}"
            ;;
        version) ctl::version ;;
        uninstall) ctl::uninstall ;;
        logs)
            shift
            ctl::logs "${1:-}"
            ;;
        help | --help | -h) ctl::usage ;;
        *)
            logging::error "Unknown command: $1"
            ctl::usage
            exit 1
            ;;
    esac
fi
