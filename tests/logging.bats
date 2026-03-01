#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/logging.sh"
}

@test "logging::info outputs message to stdout" {
    run logging::info "hello world"
    assert_success
    assert_output --partial "[INFO]"
    assert_output --partial "hello world"
}

@test "logging::error outputs message to stderr" {
    run bash -c 'source "$PROJECT_ROOT/lib/core/logging.sh" && NO_COLOR=1 logging::error "bad thing" 2>&1'
    assert_success
    assert_output --partial "[ERROR]"
    assert_output --partial "bad thing"
}

@test "logging::debug is filtered at default INFO level" {
    run logging::debug "hidden message"
    assert_success
    refute_output --partial "hidden message"
}

@test "logging::debug shows when LOG_LEVEL=DEBUG" {
    LOG_LEVEL=DEBUG run logging::debug "visible message"
    assert_success
    assert_output --partial "visible message"
}

@test "logging::warn outputs to stderr" {
    run bash -c 'source "$PROJECT_ROOT/lib/core/logging.sh" && NO_COLOR=1 logging::warn "careful" 2>&1'
    assert_success
    assert_output --partial "[WARN]"
}

@test "NO_COLOR disables color codes" {
    NO_COLOR=1 logging::setup_colors
    [[ -z "$RED" ]]
    [[ -z "$GREEN" ]]
    [[ -z "$NC" ]]
}

@test "logging::log includes ISO 8601 timestamp" {
    run logging::info "timestamp test"
    assert_success
    assert_output --regexp '\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]'
}

@test "logging::busy runs command and returns its exit code" {
    run logging::busy "working" true
    assert_success
}

@test "logging::busy propagates command failure" {
    run logging::busy "failing" false
    assert_failure
}

# --- cron mode tests ---

@test "logging::cron_init is defined" {
    run bash -c "source '$PROJECT_ROOT/lib/core/logging.sh'; declare -f logging::cron_init"
    assert_success
}

@test "logging::cron_init suppresses output" {
    local script="$BATS_TEST_TMPDIR/cron-test.sh"
    cat >"$script" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source "${1}/lib/core/logging.sh"
logging::cron_init
echo "this should be captured"
logging::info "also captured"
SCRIPT
    chmod +x "$script"
    run "$script" "$PROJECT_ROOT"
    assert_success
    refute_output --partial "this should be captured"
    refute_output --partial "also captured"
}

@test "logging::cron_cleanup dumps output on error" {
    local script="$BATS_TEST_TMPDIR/cron-err-test.sh"
    cat >"$script" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source "${1}/lib/core/logging.sh"
trap 'logging::cron_cleanup' EXIT
logging::cron_init
echo "diagnostic info"
false
SCRIPT
    chmod +x "$script"
    run "$script" "$PROJECT_ROOT"
    assert_failure
    assert_output --partial "diagnostic info"
}

# --- log-to-file tests ---

@test "logging::log writes to LOG_FILE when set" {
    local logfile="$BATS_TEST_TMPDIR/test.log"
    LOG_FILE="$logfile" run logging::info "file logging test"
    assert_success
    run cat "$logfile"
    assert_output --partial "[INFO]"
    assert_output --partial "file logging test"
}

@test "logging::log strips ANSI codes when writing to LOG_FILE" {
    local logfile="$BATS_TEST_TMPDIR/test.log"
    FORCE_COLOR=1 LOG_FILE="$logfile" run bash -c "
        source '$PROJECT_ROOT/lib/core/logging.sh'
        logging::info 'color test'
    "
    assert_success
    # Log file should not contain escape sequences
    run grep -P '\033' "$logfile"
    assert_failure
}

@test "logging::log appends to existing LOG_FILE" {
    local logfile="$BATS_TEST_TMPDIR/test.log"
    printf 'existing line\n' >"$logfile"
    LOG_FILE="$logfile" run logging::info "appended"
    assert_success
    run cat "$logfile"
    assert_output --partial "existing line"
    assert_output --partial "appended"
}

@test "logging::cron_cleanup is silent on success" {
    local script="$BATS_TEST_TMPDIR/cron-ok-test.sh"
    cat >"$script" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source "${1}/lib/core/logging.sh"
trap 'logging::cron_cleanup' EXIT
logging::cron_init
echo "should stay hidden"
SCRIPT
    chmod +x "$script"
    run "$script" "$PROJECT_ROOT"
    assert_success
    refute_output --partial "should stay hidden"
}
