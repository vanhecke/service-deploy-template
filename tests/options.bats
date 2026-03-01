#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    # Reset state before each test — options.sh guard and definitions
    unset _OPTIONS_SH_LOADED
    _OPTIONS_DEFS=()
    source "$PROJECT_ROOT/lib/core/options.sh"
}

@test "options::define registers definitions" {
    options::define "flag|h|help|Show help"
    options::define "option|c|config|Config dir|etc"
    [[ "${#_OPTIONS_DEFS[@]}" -eq 2 ]]
}

@test "options::parse sets flag to true" {
    options::define "flag|h|help|Show help"
    options::define "flag|v|verbose|Verbose output"
    options::parse -v
    [[ "$VERBOSE" == "true" ]]
}

@test "options::parse sets flag default to false" {
    options::define "flag|v|verbose|Verbose output"
    options::parse
    [[ "$VERBOSE" == "false" ]]
}

@test "options::parse sets option value" {
    options::define "flag|h|help|Show help"
    options::define "option|c|config|Config dir|etc"
    options::parse -c /custom/path
    [[ "$CONFIG" == "/custom/path" ]]
}

@test "options::parse uses option default" {
    options::define "option|c|config|Config dir|etc"
    options::parse
    [[ "$CONFIG" == "etc" ]]
}

@test "options::parse converts dashes to underscores" {
    options::define "flag|n|dry-run|Dry run mode"
    options::parse --dry-run
    [[ "$DRY_RUN" == "true" ]]
}

@test "options::parse supports long form" {
    options::define "flag|v|verbose|Verbose"
    options::parse --verbose
    [[ "$VERBOSE" == "true" ]]
}

@test "options::parse fails on unknown option" {
    options::define "flag|h|help|Show help"
    run options::parse --bogus
    assert_failure
    assert_output --partial "unknown option"
}

@test "options::parse fails when option missing argument" {
    options::define "option|c|config|Config dir|etc"
    run options::parse -c
    assert_failure
    assert_output --partial "requires an argument"
}

@test "options::usage lists all options" {
    options::define "flag|h|help|Show help"
    options::define "flag|v|verbose|Verbose"
    options::define "option|c|config|Config dir|etc"
    run options::usage
    assert_success
    assert_output --partial "-h, --help"
    assert_output --partial "-v, --verbose"
    assert_output --partial "-c, --config"
    assert_output --partial "(default: etc)"
}

@test "options::parse handles help flag by calling usage function" {
    usage() { printf 'custom help\n'; }
    export -f usage
    options::define "flag|h|help|Show help"
    run options::parse --help
    # help exits with 0
    assert_success
    assert_output --partial "custom help"
}
