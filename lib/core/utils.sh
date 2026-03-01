#!/usr/bin/env bash
# @description Common utilities: backup, lock file, template rendering, idempotent file ops.

[[ -n "${_UTILS_SH_LOADED:-}" ]] && return 0
readonly _UTILS_SH_LOADED=1

_TEMP_FILES=()

# @description Create a temporary file and register it for automatic cleanup.
# @arg $1 string Variable name to receive the file path
# @arg $2 string Optional file extension (default: tmp)
utils::tempfile() {
    local -n _tf_ref="$1"
    local ext="${2:-tmp}"
    local base
    base=$(mktemp "/tmp/${APP_NAME:-script}.XXXXXX")
    mv "$base" "${base}.${ext}"
    _tf_ref="${base}.${ext}"
    _TEMP_FILES+=("$_tf_ref")
}

# @description Remove all temporary files created by utils::tempfile.
utils::cleanup_tempfiles() {
    local f
    for f in "${_TEMP_FILES[@]}"; do
        [[ -f "$f" ]] && rm -f "$f"
    done
    _TEMP_FILES=()
}

# @description Create a timestamped backup of a file.
utils::backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local backup
    backup="${file}.backup.$(date '+%Y%m%d%H%M%S')"
    cp -a "$file" "$backup"
    printf '%s\n' "$backup"
}

# @description Acquire an exclusive lock file using flock.
utils::acquire_lock() {
    local lock_file="$1"
    export LOCK_FILE="$lock_file"
    exec 200>"$lock_file"
    if ! flock -n 200; then
        printf 'Cannot acquire lock: %s\n' "$lock_file" >&2
        return 1
    fi
}

# @description Render a template file by substituting environment variables via envsubst.
utils::render_template() {
    local template="$1"
    local output="$2"
    if [[ ! -f "$template" ]]; then
        printf 'Template not found: %s\n' "$template" >&2
        return 1
    fi
    envsubst <"$template" >"$output"
}

# @description Idempotently ensure a line exists in a file.
utils::ensure_line() {
    local file="$1"
    local line="$2"
    local marker="${3:-$line}"
    [[ -f "$file" ]] || touch "$file"
    grep -qF "$marker" "$file" 2>/dev/null || printf '%s\n' "$line" >>"$file"
}

# @description Create a directory idempotently with optional ownership.
utils::ensure_dir() {
    local dir="$1"
    local owner="${2:-}"
    local mode="${3:-}"
    mkdir -p "$dir"
    [[ -n "$owner" ]] && chown "$owner" "$dir" || true
    [[ -n "$mode" ]] && chmod "$mode" "$dir" || true
}

# @description Create a symlink idempotently.
utils::ensure_symlink() {
    local target="$1"
    local link_name="$2"
    ln -sfn "$target" "$link_name"
}
