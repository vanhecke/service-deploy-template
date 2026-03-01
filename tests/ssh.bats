#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/logging.sh"
    source "$PROJECT_ROOT/lib/core/utils.sh"
    source "$PROJECT_ROOT/lib/modules/ssh.sh"
    export DRY_RUN=true
}

@test "ssh::ensure_authorized_keys dry run logs message" {
    run ssh::ensure_authorized_keys "testuser"
    assert_success
    assert_output --partial "[DRY RUN]"
}

@test "ssh::import_github_keys dry run logs message" {
    run ssh::import_github_keys "vanhecke" "testuser"
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "vanhecke"
}

@test "ssh::ensure_authorized_keys fails without username" {
    run ssh::ensure_authorized_keys
    assert_failure
}

@test "ssh::import_github_keys fails without arguments" {
    run ssh::import_github_keys
    assert_failure
}
