#!/usr/bin/env bash
# @description On-machine CLI for managing the deployed service.
#
# Usage: <APP_NAME>ctl <command>
#
# Installed by deploy.sh. Sources libraries from the deploy directory.

set -euo pipefail
set -o errtrace
IFS=$'\n\t'
trap 'printf "Error on line %d (exit %d)\n" "$LINENO" "$?" >&2' ERR

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

# Load config if present
if [[ -d "${APP_HOME}/.config/${APP_NAME}" ]]; then
    config::load "${APP_HOME}/.config/${APP_NAME}"
fi

ctl::health() {
    local ok=true

    # Check systemd service
    if systemctl is-active "${APP_NAME}" &>/dev/null; then
        logging::info "Service ${APP_NAME}: active"
    else
        logging::warn "Service ${APP_NAME}: inactive or not found"
        ok=false
    fi

    # Check app port if configured
    if [[ -n "${APP_PORT:-}" ]]; then
        if ss -tlnp | grep -q ":${APP_PORT} " 2>/dev/null; then
            logging::info "Port ${APP_PORT}: listening"
        else
            logging::warn "Port ${APP_PORT}: not listening"
            ok=false
        fi
    fi

    # Disk space (warn if >90%)
    local disk_pct
    disk_pct="$(df / --output=pcent | tail -1 | tr -d ' %')"
    if ((disk_pct > 90)); then
        logging::warn "Disk usage: ${disk_pct}%"
        ok=false
    else
        logging::info "Disk usage: ${disk_pct}%"
    fi

    # Memory (warn if <10% free)
    local mem_avail mem_total mem_pct
    mem_avail="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
    mem_total="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    if [[ -n "$mem_avail" ]] && [[ -n "$mem_total" ]] && ((mem_total > 0)); then
        mem_pct=$(((mem_total - mem_avail) * 100 / mem_total))
        if ((mem_pct > 90)); then
            logging::warn "Memory usage: ${mem_pct}%"
            ok=false
        else
            logging::info "Memory usage: ${mem_pct}%"
        fi
    fi

    [[ "$ok" == true ]]
}

ctl::update() {
    logging::info "Running system update"
    checks::run_as_root apt-get update -qq
    checks::run_as_root apt-get upgrade -y -qq
    logging::info "Update complete"
}

ctl::status() {
    systemctl status "${APP_NAME}" --no-pager 2>/dev/null || logging::info "No service unit found for ${APP_NAME}"
}

ctl::restart() {
    checks::run_as_root systemctl restart "${APP_NAME}"
    logging::info "Restarted ${APP_NAME}"
}

ctl::logs() {
    local lines="${2:-50}"
    journalctl -u "${APP_NAME}" --no-pager -n "$lines"
}

ctl::usage() {
    cat <<EOF
Usage: ${APP_NAME}ctl <command>

Commands:
    health      Run health checks (service, port, disk, memory)
    update      Update system packages (apt upgrade)
    status      Show service status
    restart     Restart the service
    logs [N]    Show last N log lines (default: 50)
    help        Show this help

EOF
}

if ! (return 0 2>/dev/null); then
    case "${1:-help}" in
        health) ctl::health ;;
        update) ctl::update ;;
        status) ctl::status ;;
        restart) ctl::restart ;;
        logs) ctl::logs "$@" ;;
        help | --help | -h) ctl::usage ;;
        *)
            logging::error "Unknown command: $1"
            ctl::usage
            exit 1
            ;;
    esac
fi
