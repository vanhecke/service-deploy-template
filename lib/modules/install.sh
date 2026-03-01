#!/usr/bin/env bash
# @description Download, verify, extract, and git-clone helpers for software installation.

[[ -n "${_INSTALL_SH_LOADED:-}" ]] && return 0
readonly _INSTALL_SH_LOADED=1

# shellcheck source=../core/logging.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/logging.sh"
# shellcheck source=../core/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/utils.sh"

# @description Download a file via curl with retry and progress.
# @arg $1 string URL to download
# @arg $2 string Destination file path
install::download() {
    local url="${1:?Missing URL}"
    local dest="${2:?Missing destination path}"

    logging::info "Downloading ${url} -> ${dest}"

    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would download ${url} to ${dest}"
        return 0
    fi

    local dest_dir
    dest_dir="$(dirname "$dest")"
    utils::ensure_dir "$dest_dir"

    if ! curl -fSL --retry 3 --retry-delay 2 -o "$dest" "$url"; then
        logging::error "Failed to download ${url}"
        return 1
    fi

    logging::info "Downloaded ${url} successfully"
}

# @description Verify a file's SHA-256 checksum.
# @arg $1 string File to verify
# @arg $2 string Expected SHA-256 hex digest
install::verify_checksum() {
    local file="${1:?Missing file path}"
    local expected="${2:?Missing expected SHA-256 checksum}"

    if [[ ! -f "$file" ]]; then
        logging::error "File not found for checksum verification: ${file}"
        return 1
    fi

    local actual
    if command -v sha256sum &>/dev/null; then
        actual="$(sha256sum "$file" | awk '{print $1}')"
    elif command -v shasum &>/dev/null; then
        actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    else
        logging::error "No sha256sum or shasum available"
        return 1
    fi

    if [[ "$actual" != "$expected" ]]; then
        logging::error "Checksum mismatch for ${file}: expected=${expected} actual=${actual}"
        return 1
    fi

    logging::info "Checksum verified for ${file}"
    return 0
}

# @description Extract an archive, auto-detecting format by extension.
# @arg $1 string Archive file path (.tar.gz, .tar.xz, or .zip)
# @arg $2 string Destination directory
install::extract() {
    local archive="${1:?Missing archive path}"
    local dest="${2:?Missing destination directory}"

    if [[ ! -f "$archive" ]]; then
        logging::error "Archive not found: ${archive}"
        return 1
    fi

    utils::ensure_dir "$dest"

    logging::info "Extracting ${archive} -> ${dest}"

    case "$archive" in
        *.tar.gz | *.tgz)
            tar -xzf "$archive" -C "$dest"
            ;;
        *.tar.xz)
            tar -xJf "$archive" -C "$dest"
            ;;
        *.zip)
            unzip -o -q "$archive" -d "$dest"
            ;;
        *)
            logging::error "Unsupported archive format: ${archive}"
            return 1
            ;;
    esac

    logging::info "Extracted ${archive} to ${dest}"
}

# @description Query GitHub API for the latest release tag of a repository.
# @arg $1 string Repository in OWNER/REPO format
install::github_latest_release() {
    local repo="${1:?Missing OWNER/REPO}"

    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local response

    if ! response="$(curl -fsSL "$api_url" 2>&1)"; then
        logging::error "Failed to query GitHub API for ${repo}: ${response}"
        return 1
    fi

    local tag
    # Parse tag_name from JSON without jq dependency
    tag="$(printf '%s\n' "$response" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"

    if [[ -z "$tag" ]]; then
        logging::error "Could not parse release tag from GitHub API response for ${repo}"
        return 1
    fi

    printf '%s\n' "$tag"
}

# @description Download a release asset from the latest GitHub release.
# @arg $1 string Repository in OWNER/REPO format
# @arg $2 string Glob pattern to match asset filename
# @arg $3 string Destination file path
install::github_download_release() {
    local repo="${1:?Missing OWNER/REPO}"
    local pattern="${2:?Missing asset filename pattern}"
    local dest="${3:?Missing destination path}"

    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local response

    if ! response="$(curl -fsSL "$api_url" 2>&1)"; then
        logging::error "Failed to query GitHub API for ${repo}: ${response}"
        return 1
    fi

    # Extract browser_download_url lines and find matching asset
    local download_url
    download_url="$(printf '%s\n' "$response" |
        grep '"browser_download_url"' |
        sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' |
        while IFS= read -r url; do
            local filename
            filename="$(basename "$url")"
            # shellcheck disable=SC2254
            case "$filename" in
                $pattern)
                    printf '%s\n' "$url"
                    break
                    ;;
            esac
        done)"

    if [[ -z "$download_url" ]]; then
        logging::error "No asset matching '${pattern}' found in ${repo} latest release"
        return 1
    fi

    install::download "$download_url" "$dest"
}

# @description Idempotent git clone or pull.
# @arg $1 string Repository URL
# @arg $2 string Destination directory
# @arg $3 string Optional branch name
install::git_clone_or_pull() {
    local url="${1:?Missing repository URL}"
    local dest="${2:?Missing destination directory}"
    local branch="${3:-}"

    if [[ "${DRY_RUN:-false}" == true ]]; then
        logging::info "[DRY RUN] Would git clone/pull ${url} to ${dest}"
        return 0
    fi

    if [[ -d "${dest}/.git" ]]; then
        logging::info "Updating existing repository at ${dest}"
        local -a git_args=(git -C "$dest" pull)
        if ! "${git_args[@]}"; then
            logging::error "git pull failed for ${dest}"
            return 1
        fi
    else
        logging::info "Cloning ${url} into ${dest}"
        local -a clone_args=(git clone)
        if [[ -n "$branch" ]]; then
            clone_args+=(-b "$branch")
        fi
        clone_args+=("$url" "$dest")
        if ! "${clone_args[@]}"; then
            logging::error "git clone failed for ${url}"
            return 1
        fi
    fi

    logging::info "Repository ${url} ready at ${dest}"
}
