#!/usr/bin/env bash
# @description System-level configuration: swap, hostname, journald, unattended upgrades, FHS dirs.

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../core/logging.sh
# shellcheck source=../core/utils.sh
# shellcheck source=./packages.sh

[[ -n "${_SYSTEM_SH_LOADED:-}" ]] && return 0
readonly _SYSTEM_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/utils.sh"
source "${SCRIPT_DIR}/packages.sh"

# @description Create a swap file if none is currently active.
# @arg $1 string Swap size (e.g., 2G, 512M)
system::ensure_swap() {
    local size="${1:?Missing swap size (e.g., 2G)}"

    # Validate size format
    if [[ ! "$size" =~ ^[0-9]+[MG]$ ]]; then
        logging::error "Invalid swap size format: ${size} (expected e.g. 2G or 512M)"
        return 1
    fi

    # Check if swap is already active
    if swapon --show --noheadings 2>/dev/null | grep -q .; then
        logging::info "Swap already active, skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would create ${size} swap file at /swapfile"
        return 0
    fi

    local swapfile="/swapfile"
    local fstab="${_FSTAB_FILE:-/etc/fstab}"

    if [[ -f "$swapfile" ]]; then
        logging::warn "Swap file exists but is not active, re-enabling"
    else
        logging::info "Creating ${size} swap file"
        fallocate -l "$size" "$swapfile"
        chmod 600 "$swapfile"
        mkswap "$swapfile" >/dev/null
    fi

    swapon "$swapfile"
    utils::ensure_line "$fstab" "/swapfile none swap sw 0 0" "/swapfile"
    logging::info "Swap enabled: ${size}"
}

# @description Set the system hostname and update /etc/hosts idempotently.
# @arg $1 string Desired hostname
system::set_hostname() {
    local name="${1:?Missing hostname}"

    # Validate hostname (RFC 1123)
    if [[ ! "$name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        logging::error "Invalid hostname: ${name}"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would set hostname to ${name}"
        return 0
    fi

    hostnamectl set-hostname "$name"

    # Update /etc/hosts: replace existing 127.0.1.1 line or add one
    local hosts_file="${_HOSTS_FILE:-/etc/hosts}"
    local hosts_line="127.0.1.1 ${name}"
    if grep -q '^127\.0\.1\.1\b' "$hosts_file" 2>/dev/null; then
        sed -i "s/^127\.0\.1\.1\b.*/${hosts_line}/" "$hosts_file"
    else
        printf '%s\n' "$hosts_line" >>"$hosts_file"
    fi

    logging::info "Hostname set to ${name}"
}

# @description Configure journald with sensible defaults (SystemMaxUse, MaxRetentionSec). Idempotent.
system::configure_journald() {
    local conf="${_JOURNALD_CONF:-/etc/systemd/journald.conf}"
    local desired_max_use="SystemMaxUse=500M"
    local desired_retention="MaxRetentionSec=30day"
    local changed=0

    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would configure journald"
        return 0
    fi

    if [[ ! -f "$conf" ]]; then
        logging::error "journald.conf not found at ${conf}"
        return 1
    fi

    # Update or add SystemMaxUse
    if grep -q "^SystemMaxUse=500M$" "$conf" 2>/dev/null; then
        : # already set
    elif grep -q "^#*SystemMaxUse=" "$conf" 2>/dev/null; then
        sed -i "s/^#*SystemMaxUse=.*/${desired_max_use}/" "$conf"
        changed=1
    else
        printf '%s\n' "$desired_max_use" >>"$conf"
        changed=1
    fi

    # Update or add MaxRetentionSec
    if grep -q "^MaxRetentionSec=30day$" "$conf" 2>/dev/null; then
        : # already set
    elif grep -q "^#*MaxRetentionSec=" "$conf" 2>/dev/null; then
        sed -i "s/^#*MaxRetentionSec=.*/${desired_retention}/" "$conf"
        changed=1
    else
        printf '%s\n' "$desired_retention" >>"$conf"
        changed=1
    fi

    if ((changed)); then
        systemctl restart systemd-journald
        logging::info "Configured journald: ${desired_max_use}, ${desired_retention}"
    else
        logging::debug "journald already configured"
    fi
}

# @description Install and configure unattended-upgrades for security patches only.
system::enable_unattended_upgrades() {
    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would enable unattended-upgrades"
        return 0
    fi

    packages::install unattended-upgrades

    local auto_conf="/etc/apt/apt.conf.d/20auto-upgrades"

    # Configure auto-upgrades
    local auto_content
    auto_content='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
    printf '%s\n' "$auto_content" >"$auto_conf"

    logging::info "Unattended-upgrades enabled for security patches"
}

# @description Create FHS-compliant directories for an application.
# @arg $1 string Application name
# @arg $2 string Optional owner (user:group)
system::ensure_fhs_dirs() {
    local app_name="${1:?Missing application name}"
    local owner="${2:-}"

    # Validate app_name to prevent path traversal
    if [[ ! "$app_name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        logging::error "Invalid application name: ${app_name}"
        return 1
    fi

    local dirs=(
        "/opt/${app_name}"
        "/etc/${app_name}"
        "/var/lib/${app_name}"
        "/var/backup/${app_name}"
    )

    local dir
    for dir in "${dirs[@]}"; do
        utils::ensure_dir "$dir" "$owner"
    done

    logging::info "Ensured FHS directories for ${app_name}"
}
