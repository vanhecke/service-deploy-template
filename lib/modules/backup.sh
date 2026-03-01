#!/usr/bin/env bash
# @description Backup management: create, list, restore, rotate timestamped tar.gz archives.

[[ -n "${_BACKUP_SH_LOADED:-}" ]] && return 0
readonly _BACKUP_SH_LOADED=1

# shellcheck source=../core/logging.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/logging.sh"
# shellcheck source=../core/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/utils.sh"

# @description Return the backup directory path for the current application.
backup::_dir() {
    local dir="${_BACKUP_DIR:-/var/backup/${APP_NAME:?APP_NAME must be set}}"
    printf '%s\n' "$dir"
}

# @description Create a timestamped tar.gz backup of the given paths.
# @arg $1 string Label for the backup
# @arg $@ string Paths to back up
backup::create() {
    local label="${1:?Missing backup label}"
    shift
    if [[ $# -eq 0 ]]; then
        logging::error "backup::create: no paths specified"
        return 1
    fi

    local backup_dir
    backup_dir="$(backup::_dir)"
    utils::ensure_dir "$backup_dir"

    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    local backup_file="${backup_dir}/${label}-${timestamp}.tar.gz"

    logging::info "Creating backup ${backup_file} of: $*"
    tar -czf "$backup_file" "$@" 2>/dev/null
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        logging::error "Failed to create backup ${backup_file}"
        return 1
    fi

    printf '%s\n' "$backup_file"
}

# @description List available backups, optionally filtered by label prefix.
# @arg $1 string Optional label prefix to filter by
backup::list() {
    local label="${1:-}"
    local backup_dir
    backup_dir="$(backup::_dir)"

    [[ -d "$backup_dir" ]] || return 0

    local pattern
    if [[ -n "$label" ]]; then
        pattern="${label}-*.tar.gz"
    else
        pattern="*.tar.gz"
    fi

    # List matching files sorted by name (oldest first since timestamps sort naturally)
    local files
    files="$(find "$backup_dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | sort)"
    if [[ -n "$files" ]]; then
        printf '%s\n' "$files"
    fi
}

# @description Restore a backup tar.gz to / (restoring files to original absolute paths).
# @arg $1 string Path to the backup file
backup::restore() {
    local backup_file="${1:?Missing backup file path}"

    if [[ ! -f "$backup_file" ]]; then
        logging::error "Backup file not found: ${backup_file}"
        return 1
    fi

    logging::info "Restoring backup ${backup_file}"
    tar -xzf "$backup_file" -C /
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        logging::error "Failed to restore backup ${backup_file}"
        return 1
    fi
}

# @description Keep only the N most recent backups matching a label prefix, delete older ones.
# @arg $1 string Label prefix to match
# @arg $2 int Number of backups to keep
backup::rotate() {
    local label="${1:?Missing backup label}"
    local keep_count="${2:?Missing keep count}"
    local backup_dir
    backup_dir="$(backup::_dir)"

    [[ -d "$backup_dir" ]] || return 0

    local -a all_backups
    mapfile -t all_backups < <(find "$backup_dir" -maxdepth 1 -name "${label}-*.tar.gz" -type f 2>/dev/null | sort)

    local total=${#all_backups[@]}
    if ((total <= keep_count)); then
        return 0
    fi

    local delete_count=$((total - keep_count))
    local i
    for ((i = 0; i < delete_count; i++)); do
        logging::info "Deleting old backup: ${all_backups[$i]}"
        rm -f "${all_backups[$i]}"
    done
}

# @description Print path to the most recent backup matching a label prefix.
# @arg $1 string Label prefix to match
backup::latest() {
    local label="${1:?Missing backup label}"
    local backup_dir
    backup_dir="$(backup::_dir)"

    [[ -d "$backup_dir" ]] || return 1

    local latest
    latest="$(find "$backup_dir" -maxdepth 1 -name "${label}-*.tar.gz" -type f 2>/dev/null | sort | tail -n 1)"

    if [[ -z "$latest" ]]; then
        return 1
    fi

    printf '%s\n' "$latest"
}
