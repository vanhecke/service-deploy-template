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

@test "checks::is_interactive is defined" {
    run bash -c "source '$PROJECT_ROOT/lib/core/checks.sh'; declare -f checks::is_interactive"
    assert_success
}

@test "checks::is_interactive returns false when piped" {
    run bash -c "source '$PROJECT_ROOT/lib/core/checks.sh'; checks::is_interactive" <<<""
    assert_failure
}

@test "checks::run_as_root is defined" {
    run bash -c "source '$PROJECT_ROOT/lib/core/checks.sh'; declare -f checks::run_as_root"
    assert_success
}

@test "checks::run_as_root executes the given command" {
    # We're not root in tests, so run_as_root will try sudo.
    # Test with a mock sudo that just executes the command.
    local mock_dir="$BATS_TEST_TMPDIR/mock-bin"
    mkdir -p "$mock_dir"
    local bash_path
    bash_path="$(command -v bash)"
    cat >"$mock_dir/sudo" <<MOCK
#!${bash_path}
# Strip sudo flags (-H --)
while [[ "\${1:-}" == -* ]]; do shift; done
exec "\$@"
MOCK
    chmod +x "$mock_dir/sudo"

    run bash -c "
        export PATH='$mock_dir':\$PATH
        source '$PROJECT_ROOT/lib/core/checks.sh'
        checks::run_as_root echo 'hello elevated'
    "
    assert_success
    assert_output --partial "hello elevated"
}

@test "checks::run_as_root fails without arguments" {
    run checks::run_as_root
    assert_failure
}

@test "checks::confirm is defined" {
    run bash -c "source '$PROJECT_ROOT/lib/core/checks.sh'; declare -f checks::confirm"
    assert_success
}

@test "checks::confirm returns 0 when FORCE is true" {
    FORCE=true run checks::confirm "Proceed?"
    assert_success
}

@test "checks::confirm returns 0 on yes input" {
    run bash -c "
        source '$PROJECT_ROOT/lib/core/checks.sh'
        echo 'y' | checks::confirm 'Proceed?'
    "
    assert_success
}

@test "checks::confirm returns 1 on no input" {
    run bash -c "
        source '$PROJECT_ROOT/lib/core/checks.sh'
        echo 'n' | checks::confirm 'Proceed?'
    "
    assert_failure
}
