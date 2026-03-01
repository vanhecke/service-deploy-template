#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/utils.sh"
}

@test "utils::backup_file creates backup with timestamp" {
    local original="$BATS_TEST_TMPDIR/myfile.conf"
    printf 'content' >"$original"
    run utils::backup_file "$original"
    assert_success
    assert_output --regexp '\.backup\.[0-9]{14}$'
    [[ -f "$(echo "$output")" ]]
}

@test "utils::backup_file returns 0 for missing file" {
    run utils::backup_file "/nonexistent/file"
    assert_success
}

@test "utils::ensure_line adds missing line" {
    local file="$BATS_TEST_TMPDIR/lines.txt"
    printf 'existing line\n' >"$file"
    utils::ensure_line "$file" "new line"
    grep -qF "new line" "$file"
}

@test "utils::ensure_line is idempotent" {
    local file="$BATS_TEST_TMPDIR/lines.txt"
    printf 'existing line\n' >"$file"
    utils::ensure_line "$file" "new line"
    utils::ensure_line "$file" "new line"
    local count
    count=$(grep -cF "new line" "$file")
    [[ "$count" -eq 1 ]]
}

@test "utils::ensure_line creates file if missing" {
    local file="$BATS_TEST_TMPDIR/new_file.txt"
    utils::ensure_line "$file" "first line"
    [[ -f "$file" ]]
    grep -qF "first line" "$file"
}

@test "utils::ensure_dir creates directory" {
    local dir="$BATS_TEST_TMPDIR/newdir/subdir"
    utils::ensure_dir "$dir"
    [[ -d "$dir" ]]
}

@test "utils::ensure_symlink creates symlink" {
    local target="$BATS_TEST_TMPDIR/target_file"
    local link="$BATS_TEST_TMPDIR/my_link"
    printf 'data' >"$target"
    utils::ensure_symlink "$target" "$link"
    [[ -L "$link" ]]
    [[ "$(readlink "$link")" == "$target" ]]
}

@test "utils::ensure_symlink is idempotent" {
    local target="$BATS_TEST_TMPDIR/target_file"
    local link="$BATS_TEST_TMPDIR/my_link"
    printf 'data' >"$target"
    utils::ensure_symlink "$target" "$link"
    utils::ensure_symlink "$target" "$link"
    [[ -L "$link" ]]
}

@test "utils::render_template substitutes env vars" {
    local template="$BATS_TEST_TMPDIR/template.conf"
    local output="$BATS_TEST_TMPDIR/output.conf"
    export MY_SETTING="hello"
    printf 'value=${MY_SETTING}\n' >"$template"
    utils::render_template "$template" "$output"
    grep -qF "value=hello" "$output"
}

@test "utils::render_template fails for missing template" {
    run utils::render_template "/nonexistent/template" "/tmp/out"
    assert_failure
    assert_output --partial "not found"
}

@test "utils::tempfile creates a file" {
    local myfile
    utils::tempfile myfile "csv"
    [[ -f "$myfile" ]]
    rm -f "$myfile"
}

@test "utils::tempfile uses extension" {
    local myfile
    utils::tempfile myfile "json"
    [[ "$myfile" == *.json ]]
    rm -f "$myfile"
}

# --- utils::execute tests ---

@test "utils::execute is defined" {
    run bash -c "source '$PROJECT_ROOT/lib/core/logging.sh'; source '$PROJECT_ROOT/lib/core/utils.sh'; declare -f utils::execute"
    assert_success
}

@test "utils::execute runs a command" {
    source "$PROJECT_ROOT/lib/core/logging.sh"
    run utils::execute "Creating test file" touch "$BATS_TEST_TMPDIR/exec-test"
    assert_success
    [[ -f "$BATS_TEST_TMPDIR/exec-test" ]]
}

@test "utils::execute logs the command in dry-run mode" {
    source "$PROJECT_ROOT/lib/core/logging.sh"
    DRY_RUN=true run utils::execute "Creating test file" touch "$BATS_TEST_TMPDIR/dry-test"
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "Creating test file"
    [[ ! -f "$BATS_TEST_TMPDIR/dry-test" ]]
}

@test "utils::execute propagates command failure" {
    source "$PROJECT_ROOT/lib/core/logging.sh"
    run utils::execute "Failing command" false
    assert_failure
}

@test "utils::cleanup_tempfiles removes created files" {
    local myfile
    utils::tempfile myfile "tmp"
    [[ -f "$myfile" ]]
    utils::cleanup_tempfiles
    [[ ! -f "$myfile" ]]
}
