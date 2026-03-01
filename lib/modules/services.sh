#!/usr/bin/env bash
# @description systemd service management helpers.

[[ -n "${_SERVICES_SH_LOADED:-}" ]] && return 0
readonly _SERVICES_SH_LOADED=1

# @description Enable and start a systemd service idempotently.
services::enable_and_start() {
    local service="$1"
    if ! systemctl is-enabled "$service" &>/dev/null; then
        systemctl enable "$service"
    fi
    if ! systemctl is-active "$service" &>/dev/null; then
        systemctl start "$service"
    fi
}

# @description Restart a service.
services::restart() {
    systemctl restart "$1"
}

# @description Reload a service configuration.
services::reload() {
    systemctl reload "$1"
}

# @description Check if a service is active.
services::is_active() {
    systemctl is-active "$1" &>/dev/null
}

# @description Reload the systemd daemon after unit file changes.
services::daemon_reload() {
    systemctl daemon-reload
}
