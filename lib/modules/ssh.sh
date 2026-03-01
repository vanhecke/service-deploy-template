#!/usr/bin/env bash
# @description SSH authorized_keys management and GitHub public key import.

[[ -n "${_SSH_SH_LOADED:-}" ]] && return 0
readonly _SSH_SH_LOADED=1

# @description Ensure ~/.ssh directory and authorized_keys exist with correct permissions.
ssh::ensure_authorized_keys() {
    local username="${1:?Missing username}"
    local home_dir
    home_dir="$(eval echo "~${username}")"
    local ssh_dir="${home_dir}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would ensure ${auth_keys}"
        return 0
    fi
    utils::ensure_dir "$ssh_dir" "${username}:${username}" "700"
    [[ -f "$auth_keys" ]] || touch "$auth_keys"
    chown "${username}:${username}" "$auth_keys"
    chmod 600 "$auth_keys"
    logging::debug "Ensured ${auth_keys} with correct permissions"
}

# @description Import public keys from GitHub for a user. Idempotent — skips keys already present.
ssh::import_github_keys() {
    local github_user="${1:?Missing GitHub username}"
    local username="${2:?Missing system username}"
    local home_dir
    home_dir="$(eval echo "~${username}")"
    local auth_keys="${home_dir}/.ssh/authorized_keys"
    local url="https://github.com/${github_user}.keys"

    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would import keys from ${url} for ${username}"
        return 0
    fi

    local keys
    keys="$(curl -fsSL --connect-timeout 10 "$url" 2>/dev/null)" || {
        logging::error "Failed to fetch keys from ${url}"
        return 1
    }

    # Validate response contains at least one SSH key
    if ! printf '%s\n' "$keys" | grep -q '^ssh-'; then
        logging::error "No valid SSH keys found at ${url}"
        return 1
    fi

    local added=0
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        [[ "$key" != ssh-* ]] && continue
        if ! grep -qF "$key" "$auth_keys" 2>/dev/null; then
            printf '%s\n' "$key" >>"$auth_keys"
            ((added++))
        fi
    done <<<"$keys"

    if ((added > 0)); then
        logging::info "Added ${added} key(s) from GitHub user ${github_user} to ${username}"
    else
        logging::debug "All keys from GitHub user ${github_user} already present for ${username}"
    fi
}
