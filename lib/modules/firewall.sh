#!/usr/bin/env bash
# @description UFW firewall rule management with idempotent operations.

[[ -n "${_FIREWALL_SH_LOADED:-}" ]] && return 0
readonly _FIREWALL_SH_LOADED=1

# @description Enable UFW with default deny incoming.
firewall::enable() {
    if ! ufw status | grep -qF "active"; then
        ufw default deny incoming
        ufw default allow outgoing
        ufw --force enable
    fi
}

# @description Allow a port through UFW idempotently.
firewall::allow_port() {
    local port="$1"
    local proto="${2:-tcp}"
    local rule="${port}/${proto}"
    if ! ufw status | grep -qF "$rule"; then
        ufw allow "$rule"
    fi
}

# @description Allow multiple ports.
firewall::allow_ports() {
    for port in "$@"; do
        firewall::allow_port "$port"
    done
}

# @description Deny a port through UFW.
firewall::deny_port() {
    local port="$1"
    local proto="${2:-tcp}"
    ufw deny "${port}/${proto}"
}
