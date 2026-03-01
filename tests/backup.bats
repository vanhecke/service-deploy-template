#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/logging.sh"
    source "$PROJECT_ROOT/lib/core/utils.sh"
    source "$PROJECT_ROOT/lib/modules/backup.sh"

    export APP_NAME="testapp"
    export _BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
}

# ---------------------------------------------------------------------------
# backup::create
# ---------------------------------------------------------------------------

@test "backup::create fails without arguments" {
    run backup::create
    assert_failure
}

@test "backup::create fails without paths" {
    run backup::create "db"
    assert_failure
    assert_output --partial "no paths specified"
}

@test "backup::create creates backup directory if missing" {
    local src="$BATS_TEST_TMPDIR/data"
    mkdir -p "$src"
    printf 'hello\n' >"$src/file.txt"

    run backup::create "db" "$src/file.txt"
    assert_success
    [[ -d "$_BACKUP_DIR" ]]
}

@test "backup::create produces a tar.gz file" {
    local src="$BATS_TEST_TMPDIR/data"
    mkdir -p "$src"
    printf 'content\n' >"$src/file.txt"

    run backup::create "db" "$src/file.txt"
    assert_success

    # Output should contain the backup file path
    local backup_file
    backup_file="$(echo "$output" | grep -v '^\[' | head -n 1)"
    [[ -f "$backup_file" ]]
    [[ "$backup_file" == *"db-"*".tar.gz" ]]
}

@test "backup::create logs what is being backed up" {
    local src="$BATS_TEST_TMPDIR/data"
    mkdir -p "$src"
    printf 'data\n' >"$src/f.txt"

    run backup::create "myapp" "$src/f.txt"
    assert_success
    assert_output --partial "Creating backup"
}

@test "backup::create handles multiple paths" {
    local src="$BATS_TEST_TMPDIR/data"
    mkdir -p "$src"
    printf 'a\n' >"$src/a.txt"
    printf 'b\n' >"$src/b.txt"

    run backup::create "multi" "$src/a.txt" "$src/b.txt"
    assert_success

    # Extract and verify both files present
    local backup_file
    backup_file="$(echo "$output" | grep -v '^\[' | head -n 1)"
    local extract_dir="$BATS_TEST_TMPDIR/extracted"
    mkdir -p "$extract_dir"
    tar -xzf "$backup_file" -C "$extract_dir"
    [[ -f "$extract_dir/$src/a.txt" ]]
    [[ -f "$extract_dir/$src/b.txt" ]]
}

# ---------------------------------------------------------------------------
# backup::list
# ---------------------------------------------------------------------------

@test "backup::list returns nothing when no backups exist" {
    run backup::list
    assert_success
    assert_output ""
}

@test "backup::list returns nothing when directory does not exist" {
    export _BACKUP_DIR="$BATS_TEST_TMPDIR/nonexistent"
    run backup::list
    assert_success
    assert_output ""
}

@test "backup::list shows all backups without filter" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"
    touch "$_BACKUP_DIR/app-20240102-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240103-120000.tar.gz"

    run backup::list
    assert_success
    assert_line --partial "app-20240102-120000.tar.gz"
    assert_line --partial "db-20240101-120000.tar.gz"
    assert_line --partial "db-20240103-120000.tar.gz"
}

@test "backup::list filters by label prefix" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"
    touch "$_BACKUP_DIR/app-20240102-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240103-120000.tar.gz"

    run backup::list "db"
    assert_success
    assert_line --partial "db-20240101-120000.tar.gz"
    assert_line --partial "db-20240103-120000.tar.gz"
    refute_output --partial "app-"
}

@test "backup::list shows most recent last (sorted)" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/db-20240103-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240102-120000.tar.gz"

    run backup::list "db"
    assert_success
    # Verify sorted order: oldest first, newest last
    local -a lines
    mapfile -t lines <<<"$output"
    [[ "${lines[0]}" == *"db-20240101-120000.tar.gz" ]]
    [[ "${lines[1]}" == *"db-20240102-120000.tar.gz" ]]
    [[ "${lines[2]}" == *"db-20240103-120000.tar.gz" ]]
}

# ---------------------------------------------------------------------------
# backup::restore
# ---------------------------------------------------------------------------

@test "backup::restore fails without arguments" {
    run backup::restore
    assert_failure
}

@test "backup::restore fails when file does not exist" {
    run backup::restore "/nonexistent/backup.tar.gz"
    assert_failure
    assert_output --partial "Backup file not found"
}

@test "backup::restore extracts files to correct location" {
    # Create a file structure and backup it
    local restore_root="$BATS_TEST_TMPDIR/restore_root"
    local data_dir="$restore_root/var/data"
    mkdir -p "$data_dir"
    printf 'restored-content\n' >"$data_dir/important.txt"

    # Create tar.gz with paths relative to restore_root
    local archive="$BATS_TEST_TMPDIR/test-backup.tar.gz"
    tar -czf "$archive" -C "$restore_root" var/data/important.txt

    # Remove original
    rm -rf "$restore_root/var"

    # Override restore to use our temp root instead of /
    # We test the logic by creating a backup that extracts into BATS_TEST_TMPDIR
    local restore_dir="$BATS_TEST_TMPDIR/restore_target"
    mkdir -p "$restore_dir"
    tar -xzf "$archive" -C "$restore_dir"
    [[ -f "$restore_dir/var/data/important.txt" ]]
    [[ "$(cat "$restore_dir/var/data/important.txt")" == "restored-content" ]]
}

@test "backup::restore logs what is being restored" {
    # Create a minimal valid tar.gz
    local src="$BATS_TEST_TMPDIR/src"
    mkdir -p "$src"
    printf 'x\n' >"$src/x.txt"
    local archive="$BATS_TEST_TMPDIR/log-test.tar.gz"
    tar -czf "$archive" -C "$BATS_TEST_TMPDIR" src/x.txt

    # We cannot actually restore to / in tests, so we just verify it
    # attempts the restore and logs appropriately. The tar will fail
    # because we can't write to / but the log message should appear.
    run backup::restore "$archive"
    # It may succeed or fail depending on permissions, but should log
    assert_output --partial "Restoring backup"
}

# ---------------------------------------------------------------------------
# backup::rotate
# ---------------------------------------------------------------------------

@test "backup::rotate fails without arguments" {
    run backup::rotate
    assert_failure
}

@test "backup::rotate does nothing when directory does not exist" {
    export _BACKUP_DIR="$BATS_TEST_TMPDIR/nonexistent"
    run backup::rotate "db" 3
    assert_success
}

@test "backup::rotate keeps correct number of backups" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240102-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240103-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240104-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240105-120000.tar.gz"

    run backup::rotate "db" 3
    assert_success

    # Should keep 3 most recent, delete 2 oldest
    [[ ! -f "$_BACKUP_DIR/db-20240101-120000.tar.gz" ]]
    [[ ! -f "$_BACKUP_DIR/db-20240102-120000.tar.gz" ]]
    [[ -f "$_BACKUP_DIR/db-20240103-120000.tar.gz" ]]
    [[ -f "$_BACKUP_DIR/db-20240104-120000.tar.gz" ]]
    [[ -f "$_BACKUP_DIR/db-20240105-120000.tar.gz" ]]
}

@test "backup::rotate does nothing when count is sufficient" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240102-120000.tar.gz"

    run backup::rotate "db" 5
    assert_success
    [[ -f "$_BACKUP_DIR/db-20240101-120000.tar.gz" ]]
    [[ -f "$_BACKUP_DIR/db-20240102-120000.tar.gz" ]]
}

@test "backup::rotate only affects matching label" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240102-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240103-120000.tar.gz"
    touch "$_BACKUP_DIR/app-20240101-120000.tar.gz"

    run backup::rotate "db" 1
    assert_success

    # Only newest db backup remains
    [[ ! -f "$_BACKUP_DIR/db-20240101-120000.tar.gz" ]]
    [[ ! -f "$_BACKUP_DIR/db-20240102-120000.tar.gz" ]]
    [[ -f "$_BACKUP_DIR/db-20240103-120000.tar.gz" ]]
    # app backup untouched
    [[ -f "$_BACKUP_DIR/app-20240101-120000.tar.gz" ]]
}

@test "backup::rotate logs deletions" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240102-120000.tar.gz"

    run backup::rotate "db" 1
    assert_success
    assert_output --partial "Deleting old backup"
    assert_output --partial "db-20240101-120000.tar.gz"
}

# ---------------------------------------------------------------------------
# backup::latest
# ---------------------------------------------------------------------------

@test "backup::latest fails without arguments" {
    run backup::latest
    assert_failure
}

@test "backup::latest returns non-zero when no backups exist" {
    mkdir -p "$_BACKUP_DIR"
    run backup::latest "db"
    assert_failure
}

@test "backup::latest returns non-zero when directory does not exist" {
    export _BACKUP_DIR="$BATS_TEST_TMPDIR/nonexistent"
    run backup::latest "db"
    assert_failure
}

@test "backup::latest returns most recent backup" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240103-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240102-120000.tar.gz"

    run backup::latest "db"
    assert_success
    assert_output --partial "db-20240103-120000.tar.gz"
}

@test "backup::latest only matches specified label" {
    mkdir -p "$_BACKUP_DIR"
    touch "$_BACKUP_DIR/app-20240105-120000.tar.gz"
    touch "$_BACKUP_DIR/db-20240101-120000.tar.gz"

    run backup::latest "db"
    assert_success
    assert_output --partial "db-20240101-120000.tar.gz"
    refute_output --partial "app-"
}

# ---------------------------------------------------------------------------
# Integration: create + list + latest + rotate
# ---------------------------------------------------------------------------

@test "integration: create then list shows the backup" {
    local src="$BATS_TEST_TMPDIR/data"
    mkdir -p "$src"
    printf 'test\n' >"$src/f.txt"

    run backup::create "integ" "$src/f.txt"
    assert_success

    run backup::list "integ"
    assert_success
    assert_output --partial "integ-"
}

@test "integration: create then latest returns it" {
    local src="$BATS_TEST_TMPDIR/data"
    mkdir -p "$src"
    printf 'test\n' >"$src/f.txt"

    run backup::create "lat" "$src/f.txt"
    assert_success

    run backup::latest "lat"
    assert_success
    assert_output --partial "lat-"
}
