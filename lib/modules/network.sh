#!/usr/bin/env bash
# @description IP validation, port checking, and DNS helpers.

[[ -n "${_NETWORK_SH_LOADED:-}" ]] && return 0
readonly _NETWORK_SH_LOADED=1

# @description Validate an IPv4 address.
network::is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.'
    read -ra octets <<<"$ip"
    for octet in "${octets[@]}"; do
        ((octet <= 255)) || return 1
    done
}

# @description Check if a TCP port is open on a host.
network::is_port_open() {
    local host="$1"
    local port="$2"
    local timeout="${3:-3}"
    # shellcheck disable=SC2016 # $1/$2 are positional args to inner bash, not this shell
    timeout "$timeout" bash -c 'echo >/dev/tcp/"$1"/"$2"' _ "$host" "$port" 2>/dev/null
}

# @description Wait for a port to become available.
network::wait_for_port() {
    local host="$1"
    local port="$2"
    local max_wait="${3:-30}"
    local elapsed=0
    while ((elapsed < max_wait)); do
        network::is_port_open "$host" "$port" 1 && return 0
        sleep 1
        ((elapsed++))
    done
    return 1
}

# @description Get the primary local IP address.
network::get_local_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}'
}
