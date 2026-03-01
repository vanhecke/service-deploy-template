#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/config.sh"
}

@test "config::load_env_file loads key=value pairs" {
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf 'MY_VAR=hello\n' > "$env_file"
    unset MY_VAR
    config::load_env_file "$env_file"
    [[ "$MY_VAR" == "hello" ]]
}

@test "config::load_env_file skips comments" {
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf '# this is a comment\nVALID_VAR=yes\n' > "$env_file"
    unset VALID_VAR
    config::load_env_file "$env_file"
    [[ "$VALID_VAR" == "yes" ]]
}

@test "config::load_env_file skips blank lines" {
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf '\n\nSOME_VAR=value\n\n' > "$env_file"
    unset SOME_VAR
    config::load_env_file "$env_file"
    [[ "$SOME_VAR" == "value" ]]
}

@test "config::load_env_file strips quotes" {
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf 'QUOTED="hello world"\n' > "$env_file"
    unset QUOTED
    config::load_env_file "$env_file"
    [[ "$QUOTED" == "hello world" ]]
}

@test "config::load_env_file does not override existing env vars" {
    export EXISTING_VAR="original"
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf 'EXISTING_VAR=overwritten\n' > "$env_file"
    config::load_env_file "$env_file"
    [[ "$EXISTING_VAR" == "original" ]]
}

@test "config::load_env_file returns 0 for missing file" {
    run config::load_env_file "/nonexistent/path/.env"
    assert_success
}

@test "config::require_vars succeeds when all vars set" {
    export REQ_A="a" REQ_B="b"
    run config::require_vars REQ_A REQ_B
    assert_success
}

@test "config::require_vars fails and lists missing vars" {
    unset MISSING_X MISSING_Y 2>/dev/null || true
    run config::require_vars MISSING_X MISSING_Y
    assert_failure
    assert_output --partial "MISSING_X"
    assert_output --partial "MISSING_Y"
}

@test "config::is_true accepts truthy values" {
    config::is_true "true"
    config::is_true "1"
    config::is_true "yes"
    config::is_true "on"
    config::is_true "TRUE"
}

@test "config::is_true rejects falsy values" {
    ! config::is_true "false"
    ! config::is_true "0"
    ! config::is_true "no"
    ! config::is_true ""
}

@test "config::is_valid_port accepts valid ports" {
    config::is_valid_port 80
    config::is_valid_port 443
    config::is_valid_port 65535
    config::is_valid_port 1
}

@test "config::is_valid_port rejects invalid ports" {
    ! config::is_valid_port 0
    ! config::is_valid_port 65536
    ! config::is_valid_port "abc"
    ! config::is_valid_port ""
}
