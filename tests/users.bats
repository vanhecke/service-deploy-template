#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/logging.sh"
    source "$PROJECT_ROOT/lib/core/utils.sh"
    source "$PROJECT_ROOT/lib/modules/users.sh"
    export DRY_RUN=true
}

@test "users::ensure_user dry run logs create message" {
    # Mock id to simulate non-existent user
    id() { return 1; }
    export -f id
    run users::ensure_user "testuser"
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "testuser"
}

@test "users::ensure_user dry run skips existing user" {
    # Mock id to simulate existing user
    id() { return 0; }
    export -f id
    run users::ensure_user "testuser"
    assert_success
    refute_output --partial "[DRY RUN]"
}

@test "users::lock_password dry run logs message" {
    run users::lock_password "testuser"
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "testuser"
}

@test "users::ensure_sudoers dry run logs message" {
    run users::ensure_sudoers "testuser" "myapp"
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "sudoers"
}

@test "users::ensure_user fails without username" {
    run users::ensure_user
    assert_failure
}

@test "users::lock_password fails without username" {
    run users::lock_password
    assert_failure
}

@test "users::ensure_sudoers fails without arguments" {
    run users::ensure_sudoers
    assert_failure
}
