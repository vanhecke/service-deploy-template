#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/logging.sh"
    source "$PROJECT_ROOT/lib/core/utils.sh"
    source "$PROJECT_ROOT/lib/modules/install.sh"
}

# ---------------------------------------------------------------------------
# install::download
# ---------------------------------------------------------------------------

@test "install::download fails without arguments" {
    run install::download
    assert_failure
}

@test "install::download fails with only URL" {
    run install::download "http://example.com/file"
    assert_failure
}

@test "install::download dry run does not call curl" {
    export DRY_RUN=true
    curl() {
        echo "curl should not be called"
        return 1
    }
    export -f curl
    run install::download "http://example.com/file" "$BATS_TEST_TMPDIR/out"
    assert_success
    assert_output --partial "[DRY RUN]"
}

@test "install::download calls curl with correct flags" {
    local call_log="$BATS_TEST_TMPDIR/curl_calls.txt"
    curl() {
        printf '%s\n' "$*" >"$BATS_TEST_TMPDIR/curl_calls.txt"
        return 0
    }
    export -f curl
    run install::download "http://example.com/file.tgz" "$BATS_TEST_TMPDIR/out"
    assert_success
    run cat "$call_log"
    assert_output --partial "-fSL"
    assert_output --partial "--retry 3"
    assert_output --partial "http://example.com/file.tgz"
}

@test "install::download returns failure when curl fails" {
    curl() { return 1; }
    export -f curl
    run install::download "http://bad-url/file" "$BATS_TEST_TMPDIR/out"
    assert_failure
    assert_output --partial "Failed to download"
}

@test "install::download creates destination directory" {
    curl() {
        touch "$BATS_TEST_TMPDIR/nested/dir/file"
        return 0
    }
    export -f curl
    run install::download "http://example.com/f" "$BATS_TEST_TMPDIR/nested/dir/file"
    assert_success
    [[ -d "$BATS_TEST_TMPDIR/nested/dir" ]]
}

# ---------------------------------------------------------------------------
# install::verify_checksum
# ---------------------------------------------------------------------------

@test "install::verify_checksum fails without arguments" {
    run install::verify_checksum
    assert_failure
}

@test "install::verify_checksum fails when file does not exist" {
    run install::verify_checksum "/nonexistent/file" "abc123"
    assert_failure
    assert_output --partial "File not found"
}

@test "install::verify_checksum succeeds with correct checksum" {
    local testfile="$BATS_TEST_TMPDIR/testfile"
    printf 'hello\n' >"$testfile"
    local expected
    if command -v sha256sum &>/dev/null; then
        expected="$(sha256sum "$testfile" | awk '{print $1}')"
    else
        expected="$(shasum -a 256 "$testfile" | awk '{print $1}')"
    fi
    run install::verify_checksum "$testfile" "$expected"
    assert_success
    assert_output --partial "Checksum verified"
}

@test "install::verify_checksum fails with wrong checksum" {
    local testfile="$BATS_TEST_TMPDIR/testfile"
    printf 'hello\n' >"$testfile"
    run install::verify_checksum "$testfile" "0000000000000000000000000000000000000000000000000000000000000000"
    assert_failure
    assert_output --partial "Checksum mismatch"
}

# ---------------------------------------------------------------------------
# install::extract
# ---------------------------------------------------------------------------

@test "install::extract fails without arguments" {
    run install::extract
    assert_failure
}

@test "install::extract fails when archive does not exist" {
    run install::extract "/nonexistent/archive.tar.gz" "$BATS_TEST_TMPDIR/out"
    assert_failure
    assert_output --partial "Archive not found"
}

@test "install::extract fails for unsupported format" {
    local fakefile="$BATS_TEST_TMPDIR/archive.rar"
    touch "$fakefile"
    run install::extract "$fakefile" "$BATS_TEST_TMPDIR/out"
    assert_failure
    assert_output --partial "Unsupported archive format"
}

@test "install::extract handles .tar.gz archive" {
    # Create a real small tar.gz
    local src="$BATS_TEST_TMPDIR/src"
    mkdir -p "$src"
    printf 'content\n' >"$src/file.txt"
    local archive="$BATS_TEST_TMPDIR/test.tar.gz"
    tar -czf "$archive" -C "$BATS_TEST_TMPDIR" src/file.txt

    local dest="$BATS_TEST_TMPDIR/extracted"
    run install::extract "$archive" "$dest"
    assert_success
    [[ -f "$dest/src/file.txt" ]]
    [[ "$(cat "$dest/src/file.txt")" == "content" ]]
}

@test "install::extract handles .tgz archive" {
    local src="$BATS_TEST_TMPDIR/src"
    mkdir -p "$src"
    printf 'tgz-content\n' >"$src/data.txt"
    local archive="$BATS_TEST_TMPDIR/test.tgz"
    tar -czf "$archive" -C "$BATS_TEST_TMPDIR" src/data.txt

    local dest="$BATS_TEST_TMPDIR/extracted_tgz"
    run install::extract "$archive" "$dest"
    assert_success
    [[ -f "$dest/src/data.txt" ]]
}

@test "install::extract handles .zip archive" {
    local src="$BATS_TEST_TMPDIR/zipsrc"
    mkdir -p "$src"
    printf 'zip-content\n' >"$src/zipped.txt"
    local archive="$BATS_TEST_TMPDIR/test.zip"
    (cd "$BATS_TEST_TMPDIR" && zip -q -r "$archive" zipsrc/zipped.txt)

    local dest="$BATS_TEST_TMPDIR/extracted_zip"
    run install::extract "$archive" "$dest"
    assert_success
    [[ -f "$dest/zipsrc/zipped.txt" ]]
}

@test "install::extract handles .tar.xz archive" {
    # xz may not be available everywhere; skip if not
    if ! command -v xz &>/dev/null; then
        skip "xz not available"
    fi
    local src="$BATS_TEST_TMPDIR/xzsrc"
    mkdir -p "$src"
    printf 'xz-content\n' >"$src/xzfile.txt"
    local archive="$BATS_TEST_TMPDIR/test.tar.xz"
    tar -cJf "$archive" -C "$BATS_TEST_TMPDIR" xzsrc/xzfile.txt

    local dest="$BATS_TEST_TMPDIR/extracted_xz"
    run install::extract "$archive" "$dest"
    assert_success
    [[ -f "$dest/xzsrc/xzfile.txt" ]]
}

@test "install::extract creates destination directory" {
    local src="$BATS_TEST_TMPDIR/newsrc"
    mkdir -p "$src"
    printf 'data\n' >"$src/f.txt"
    local archive="$BATS_TEST_TMPDIR/mk.tar.gz"
    tar -czf "$archive" -C "$BATS_TEST_TMPDIR" newsrc/f.txt

    local dest="$BATS_TEST_TMPDIR/deep/nested/dir"
    run install::extract "$archive" "$dest"
    assert_success
    [[ -d "$dest" ]]
}

# ---------------------------------------------------------------------------
# install::github_latest_release
# ---------------------------------------------------------------------------

@test "install::github_latest_release fails without argument" {
    run install::github_latest_release
    assert_failure
}

@test "install::github_latest_release parses tag from JSON" {
    curl() {
        cat <<'RESPONSE'
{
  "tag_name": "v1.2.3",
  "name": "Release 1.2.3"
}
RESPONSE
    }
    export -f curl
    run install::github_latest_release "owner/repo"
    assert_success
    assert_output "v1.2.3"
}

@test "install::github_latest_release fails on API error" {
    curl() {
        echo "Not Found"
        return 1
    }
    export -f curl
    run install::github_latest_release "owner/nonexistent"
    assert_failure
    assert_output --partial "Failed to query GitHub API"
}

@test "install::github_latest_release fails when no tag in response" {
    curl() { echo '{"message": "Not Found"}'; }
    export -f curl
    run install::github_latest_release "owner/repo"
    assert_failure
    assert_output --partial "Could not parse release tag"
}

# ---------------------------------------------------------------------------
# install::github_download_release
# ---------------------------------------------------------------------------

@test "install::github_download_release fails without arguments" {
    run install::github_download_release
    assert_failure
}

@test "install::github_download_release finds matching asset" {
    curl() {
        if [[ "$*" == *"api.github.com"* ]]; then
            cat <<'RESPONSE'
{
  "tag_name": "v2.0.0",
  "assets": [
    {
      "name": "tool-linux-amd64.tar.gz",
      "browser_download_url": "https://github.com/owner/repo/releases/download/v2.0.0/tool-linux-amd64.tar.gz"
    },
    {
      "name": "tool-darwin-arm64.tar.gz",
      "browser_download_url": "https://github.com/owner/repo/releases/download/v2.0.0/tool-darwin-arm64.tar.gz"
    }
  ]
}
RESPONSE
        else
            # Actual download call - just succeed
            return 0
        fi
    }
    export -f curl
    run install::github_download_release "owner/repo" "tool-linux-*.tar.gz" "$BATS_TEST_TMPDIR/out.tar.gz"
    assert_success
    assert_output --partial "Downloaded"
}

@test "install::github_download_release fails when no asset matches" {
    curl() {
        cat <<'RESPONSE'
{
  "tag_name": "v1.0.0",
  "assets": [
    {
      "name": "other-file.deb",
      "browser_download_url": "https://github.com/owner/repo/releases/download/v1.0.0/other-file.deb"
    }
  ]
}
RESPONSE
    }
    export -f curl
    run install::github_download_release "owner/repo" "*.tar.gz" "$BATS_TEST_TMPDIR/out"
    assert_failure
    assert_output --partial "No asset matching"
}

@test "install::github_download_release fails on API error" {
    curl() {
        echo "API error"
        return 1
    }
    export -f curl
    run install::github_download_release "owner/repo" "*.tar.gz" "$BATS_TEST_TMPDIR/out"
    assert_failure
    assert_output --partial "Failed to query GitHub API"
}

# ---------------------------------------------------------------------------
# install::git_clone_or_pull
# ---------------------------------------------------------------------------

@test "install::git_clone_or_pull fails without arguments" {
    run install::git_clone_or_pull
    assert_failure
}

@test "install::git_clone_or_pull dry run does not call git" {
    export DRY_RUN=true
    git() {
        echo "git should not be called"
        return 1
    }
    export -f git
    run install::git_clone_or_pull "https://github.com/owner/repo.git" "$BATS_TEST_TMPDIR/repo"
    assert_success
    assert_output --partial "[DRY RUN]"
}

@test "install::git_clone_or_pull clones when dest does not exist" {
    local call_log="$BATS_TEST_TMPDIR/git_calls.txt"
    git() {
        printf '%s\n' "$*" >"$BATS_TEST_TMPDIR/git_calls.txt"
        return 0
    }
    export -f git
    run install::git_clone_or_pull "https://github.com/owner/repo.git" "$BATS_TEST_TMPDIR/newrepo"
    assert_success
    assert_output --partial "Cloning"
    run cat "$call_log"
    assert_output --partial "clone"
    assert_output --partial "https://github.com/owner/repo.git"
}

@test "install::git_clone_or_pull clones with branch when specified" {
    local call_log="$BATS_TEST_TMPDIR/git_calls.txt"
    git() {
        printf '%s\n' "$*" >"$BATS_TEST_TMPDIR/git_calls.txt"
        return 0
    }
    export -f git
    run install::git_clone_or_pull "https://github.com/owner/repo.git" "$BATS_TEST_TMPDIR/newrepo" "develop"
    assert_success
    run cat "$call_log"
    assert_output --partial "-b develop"
}

@test "install::git_clone_or_pull pulls when .git exists" {
    local dest="$BATS_TEST_TMPDIR/existing"
    mkdir -p "$dest/.git"
    local call_log="$BATS_TEST_TMPDIR/git_calls.txt"
    git() {
        printf '%s\n' "$*" >"$BATS_TEST_TMPDIR/git_calls.txt"
        return 0
    }
    export -f git
    run install::git_clone_or_pull "https://github.com/owner/repo.git" "$dest"
    assert_success
    assert_output --partial "Updating existing"
    run cat "$call_log"
    assert_output --partial "pull"
}

@test "install::git_clone_or_pull returns failure when git clone fails" {
    git() { return 1; }
    export -f git
    run install::git_clone_or_pull "https://github.com/owner/repo.git" "$BATS_TEST_TMPDIR/newrepo"
    assert_failure
    assert_output --partial "git clone failed"
}

@test "install::git_clone_or_pull returns failure when git pull fails" {
    local dest="$BATS_TEST_TMPDIR/existing"
    mkdir -p "$dest/.git"
    git() { return 1; }
    export -f git
    run install::git_clone_or_pull "https://github.com/owner/repo.git" "$dest"
    assert_failure
    assert_output --partial "git pull failed"
}
