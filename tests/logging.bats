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
