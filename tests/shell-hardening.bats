#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

# --- ERR trap tests ---

@test "deploy.sh has set -o errtrace" {
    run grep -q 'set -o errtrace\|set -E' "$PROJECT_ROOT/bin/deploy.sh"
    assert_success
}

@test "deploy.sh has ERR trap" {
    run grep -q "trap .* ERR" "$PROJECT_ROOT/bin/deploy.sh"
    assert_success
}

@test "ctl.sh has set -o errtrace" {
    run grep -q 'set -o errtrace\|set -E' "$PROJECT_ROOT/bin/ctl.sh"
    assert_success
}

@test "ctl.sh has ERR trap" {
    run grep -q "trap .* ERR" "$PROJECT_ROOT/bin/ctl.sh"
    assert_success
}

@test "ERR trap reports line number on failure" {
    local script="$BATS_TEST_TMPDIR/err-test.sh"
    cat >"$script" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'printf "Error on line %d (exit %d)\n" "$LINENO" "$?" >&2' ERR
true
false
SCRIPT
    chmod +x "$script"
    run "$script"
    assert_failure
    assert_output --partial "Error on line 6"
}

# --- IFS restriction tests ---

@test "deploy.sh restricts IFS" {
    run grep -qF $'IFS=$\'\\n\\t\'' "$PROJECT_ROOT/bin/deploy.sh"
    assert_success
}

@test "ctl.sh restricts IFS" {
    run grep -qF $'IFS=$\'\\n\\t\'' "$PROJECT_ROOT/bin/ctl.sh"
    assert_success
}

# --- readonly metadata tests ---

@test "deploy.sh makes SCRIPT_DIR readonly" {
    run grep -q 'readonly.*SCRIPT_DIR' "$PROJECT_ROOT/bin/deploy.sh"
    assert_success
}

@test "deploy.sh makes PROJECT_ROOT readonly" {
    run grep -q 'readonly.*PROJECT_ROOT' "$PROJECT_ROOT/bin/deploy.sh"
    assert_success
}

@test "ctl.sh makes SCRIPT_DIR readonly" {
    run grep -q 'readonly.*SCRIPT_DIR' "$PROJECT_ROOT/bin/ctl.sh"
    assert_success
}

@test "ctl.sh makes APP_HOME readonly" {
    run grep -q 'readonly.*APP_HOME' "$PROJECT_ROOT/bin/ctl.sh"
    assert_success
}

# --- source-guard tests ---

@test "deploy.sh has source guard" {
    run grep -q 'return 0' "$PROJECT_ROOT/bin/deploy.sh"
    assert_success
}

@test "deploy.sh does not execute main when sourced" {
    local wrapper="$BATS_TEST_TMPDIR/source-test.sh"
    cat >"$wrapper" <<SCRIPT
#!/usr/bin/env bash
set +euo pipefail
source "$PROJECT_ROOT/bin/deploy.sh" 2>/dev/null
echo "sourced ok"
SCRIPT
    chmod +x "$wrapper"
    run "$wrapper"
    assert_success
    assert_output "sourced ok"
}

@test "ctl.sh has source guard" {
    run grep -q 'return 0' "$PROJECT_ROOT/bin/ctl.sh"
    assert_success
}
