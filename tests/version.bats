#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/modules/version.sh"
    export APP_NAME="testapp"
    export _VERSION_FILE="$BATS_TEST_TMPDIR/version"
}

# --- version::state_file ---

@test "version::state_file returns _VERSION_FILE when set" {
    export _VERSION_FILE="/tmp/custom-version"
    run version::state_file
    assert_success
    assert_output "/tmp/custom-version"
}

@test "version::state_file returns default path based on APP_NAME" {
    unset _VERSION_FILE
    run version::state_file
    assert_success
    assert_output "/var/lib/testapp/version"
}

@test "version::state_file fails when APP_NAME is unset" {
    unset APP_NAME
    run version::state_file
    assert_failure
}

# --- version::get ---

@test "version::get returns unknown when state file does not exist" {
    rm -f "$_VERSION_FILE"
    run version::get
    assert_success
    assert_output "unknown"
}

@test "version::get reads version from state file" {
    printf '%s\n' "1.2.3" >"$_VERSION_FILE"
    run version::get
    assert_success
    assert_output "1.2.3"
}

@test "version::get reads only the first line" {
    printf '%s\n' "1.0.0" "extra-line" >"$_VERSION_FILE"
    run version::get
    assert_success
    assert_output "1.0.0"
}

@test "version::get returns unknown for empty state file" {
    : >"$_VERSION_FILE"
    run version::get
    assert_success
    assert_output "unknown"
}

# --- version::set ---

@test "version::set fails without argument" {
    run version::set
    assert_failure
}

@test "version::set writes version to state file" {
    run version::set "2.0.0"
    assert_success
    assert_output --partial "Version set to 2.0.0"

    run cat "$_VERSION_FILE"
    assert_output "2.0.0"
}

@test "version::set creates parent directory if needed" {
    export _VERSION_FILE="$BATS_TEST_TMPDIR/subdir/nested/version"
    run version::set "3.1.0"
    assert_success
    [[ -d "$BATS_TEST_TMPDIR/subdir/nested" ]]
    run cat "$_VERSION_FILE"
    assert_output "3.1.0"
}

@test "version::set overwrites existing version" {
    printf '%s\n' "1.0.0" >"$_VERSION_FILE"
    run version::set "2.0.0"
    assert_success

    run cat "$_VERSION_FILE"
    assert_output "2.0.0"
}

# --- version::check ---

@test "version::check displays unknown when no version set" {
    rm -f "$_VERSION_FILE"
    run version::check
    assert_success
    assert_output --partial "Installed version: unknown"
}

@test "version::check displays current version" {
    printf '%s\n' "4.5.6" >"$_VERSION_FILE"
    run version::check
    assert_success
    assert_output --partial "Installed version: 4.5.6"
}

@test "version::check calls app_version hook when available" {
    printf '%s\n' "1.0.0" >"$_VERSION_FILE"
    app_version() { printf '%s\n' "1.0.0-app"; }
    export -f app_version

    run version::check
    assert_success
    assert_output --partial "Installed version: 1.0.0"
    assert_output --partial "Application version: 1.0.0-app"
}

@test "version::check does not show app version without hook" {
    printf '%s\n' "1.0.0" >"$_VERSION_FILE"
    run version::check
    assert_success
    assert_output --partial "Installed version: 1.0.0"
    refute_output --partial "Application version"
}
