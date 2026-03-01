#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/checks.sh"
}

@test "checks::detect_os identifies Ubuntu" {
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    cat >"$OS_RELEASE_FILE" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
EOF
    run checks::detect_os
    assert_success
    assert_output --partial "ubuntu"
    assert_output --partial "24.04"
}

@test "checks::detect_os identifies Debian" {
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    cat >"$OS_RELEASE_FILE" <<'EOF'
ID=debian
VERSION_ID="12"
VERSION_CODENAME=bookworm
EOF
    run checks::detect_os
    assert_success
    assert_output --partial "debian"
}

@test "checks::detect_os rejects unsupported OS" {
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    printf 'ID=fedora\nVERSION_ID="39"\n' >"$OS_RELEASE_FILE"
    run checks::detect_os
    assert_failure
    assert_output --partial "Unsupported"
}

@test "checks::detect_os fails when file missing" {
    export OS_RELEASE_FILE="/nonexistent/os-release"
    run checks::detect_os
    assert_failure
    assert_output --partial "not found"
}

@test "checks::detect_arch returns a value" {
    run checks::detect_arch
    assert_success
    assert_output --regexp '^(amd64|arm64|armhf|.+)$'
}

@test "checks::require_commands succeeds for available commands" {
    run checks::require_commands bash cat
    assert_success
}

@test "checks::require_commands fails for missing commands" {
    run checks::require_commands nonexistent_command_xyz
    assert_failure
    assert_output --partial "Missing"
    assert_output --partial "nonexistent_command_xyz"
}

@test "checks::require_bash_version passes for current bash" {
    run checks::require_bash_version 4
    assert_success
}

@test "checks::require_bash_version fails for impossibly high version" {
    run checks::require_bash_version 999
    assert_failure
}
