#!/usr/bin/env bash
# @description Dedicated user creation, password locking, and scoped sudoers management.

[[ -n "${_USERS_SH_LOADED:-}" ]] && return 0
readonly _USERS_SH_LOADED=1

# @description Create a system user with home directory if it does not exist.
users::ensure_user() {
    local username="${1:?Missing username}"
    if id "$username" &>/dev/null; then
        logging::debug "User ${username} already exists"
        return 0
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would create user ${username}"
        return 0
    fi
    useradd --create-home --shell /bin/bash "$username"
    logging::info "Created user ${username}"
}

# @description Lock password login for a user (idempotent).
users::lock_password() {
    local username="${1:?Missing username}"
    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would lock password for ${username}"
        return 0
    fi
    passwd -l "$username" &>/dev/null
    logging::debug "Password locked for ${username}"
}

# @description Install scoped sudoers rules for the app user, validated with visudo.
users::ensure_sudoers() {
    local username="${1:?Missing username}"
    local app_name="${2:?Missing app_name}"

    # Validate inputs to prevent path traversal and sudoers injection
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        logging::error "Invalid username for sudoers: ${username}"
        return 1
    fi
    if [[ ! "$app_name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        logging::error "Invalid app_name for sudoers: ${app_name}"
        return 1
    fi

    local sudoers_file="/etc/sudoers.d/${app_name}"
    local sudoers_content
    sudoers_content="$(
        cat <<EOF
# Managed by ${app_name} deploy script — do not edit manually
${username} ALL=(ALL) NOPASSWD: /usr/bin/apt-get update
${username} ALL=(ALL) NOPASSWD: /usr/bin/apt-get upgrade -y -qq
${username} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart ${app_name}
${username} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start ${app_name}
${username} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop ${app_name}
EOF
    )"

    if [[ -f "$sudoers_file" ]] && [[ "$(cat "$sudoers_file")" == "$sudoers_content" ]]; then
        logging::debug "Sudoers rules for ${app_name} already up to date"
        return 0
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would install sudoers rules to ${sudoers_file}"
        return 0
    fi

    # Write to temp file, validate, then move into place
    local tmpfile
    tmpfile="$(mktemp /etc/sudoers.d/.tmp.XXXXXX)"
    printf '%s\n' "$sudoers_content" >"$tmpfile"
    chmod 0440 "$tmpfile"
    if ! visudo -cf "$tmpfile" &>/dev/null; then
        rm -f "$tmpfile"
        logging::error "Invalid sudoers syntax — discarded"
        return 1
    fi
    mv "$tmpfile" "$sudoers_file"
    logging::info "Installed sudoers rules to ${sudoers_file}"
}
