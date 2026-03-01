#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/logging.sh"
    source "$PROJECT_ROOT/lib/core/utils.sh"

    # Stub systemctl so services.sh functions work without real systemd
    systemctl() { return 0; }
    export -f systemctl

    source "$PROJECT_ROOT/lib/modules/services.sh"
    source "$PROJECT_ROOT/lib/modules/systemd.sh"

    export _SYSTEMD_DIR="$BATS_TEST_TMPDIR/systemd"
    mkdir -p "$_SYSTEMD_DIR"
}

# ---------------------------------------------------------------------------
# systemd::install_unit
# ---------------------------------------------------------------------------

@test "systemd::install_unit fails without arguments" {
    run systemd::install_unit
    assert_failure
}

@test "systemd::install_unit creates unit file" {
    run systemd::install_unit "myapp" "[Unit]
Description=My App"
    assert_success
    assert_output --partial "Installing unit myapp.service"
    [[ -f "$_SYSTEMD_DIR/myapp.service" ]]
    run cat "$_SYSTEMD_DIR/myapp.service"
    assert_output --partial "[Unit]"
    assert_output --partial "Description=My App"
}

@test "systemd::install_unit calls daemon-reload" {
    local reload_called="$BATS_TEST_TMPDIR/reload_called"
    systemctl() {
        if [[ "$1" == "daemon-reload" ]]; then
            touch "$BATS_TEST_TMPDIR/reload_called"
        fi
        return 0
    }
    export -f systemctl

    run systemd::install_unit "myapp" "[Unit]"
    assert_success
    [[ -f "$reload_called" ]]
}

@test "systemd::install_unit is idempotent — skips write on same content" {
    local content="[Unit]
Description=Test"
    # First install
    run systemd::install_unit "myapp" "$content"
    assert_success
    assert_output --partial "Installing"

    # Second install — should skip
    run systemd::install_unit "myapp" "$content"
    assert_success
    assert_output --partial "already up to date"
    refute_output --partial "Installing"
    refute_output --partial "Updating"
}

@test "systemd::install_unit updates when content changes" {
    run systemd::install_unit "myapp" "[Unit]
Description=V1"
    assert_success
    assert_output --partial "Installing"

    run systemd::install_unit "myapp" "[Unit]
Description=V2"
    assert_success
    assert_output --partial "Updating"
    run cat "$_SYSTEMD_DIR/myapp.service"
    assert_output --partial "Description=V2"
}

# ---------------------------------------------------------------------------
# systemd::install_unit_from_template
# ---------------------------------------------------------------------------

@test "systemd::install_unit_from_template fails without arguments" {
    run systemd::install_unit_from_template
    assert_failure
}

@test "systemd::install_unit_from_template renders and installs" {
    local tpl="$BATS_TEST_TMPDIR/myapp.service.tpl"
    export APP_DESC="My App"
    printf '[Unit]\nDescription=${APP_DESC}\n' >"$tpl"

    run systemd::install_unit_from_template "$tpl" "myapp"
    assert_success
    [[ -f "$_SYSTEMD_DIR/myapp.service" ]]
    run cat "$_SYSTEMD_DIR/myapp.service"
    assert_output --partial "Description=My App"
}

@test "systemd::install_unit_from_template fails with missing template" {
    run systemd::install_unit_from_template "/nonexistent/tpl" "myapp"
    assert_failure
    assert_output --partial "Template not found"
}

# ---------------------------------------------------------------------------
# systemd::remove_unit
# ---------------------------------------------------------------------------

@test "systemd::remove_unit fails without argument" {
    run systemd::remove_unit
    assert_failure
}

@test "systemd::remove_unit removes existing unit file" {
    printf '[Unit]\n' >"$_SYSTEMD_DIR/myapp.service"
    run systemd::remove_unit "myapp"
    assert_success
    assert_output --partial "Stopping and disabling"
    assert_output --partial "Removing"
    [[ ! -f "$_SYSTEMD_DIR/myapp.service" ]]
}

@test "systemd::remove_unit is safe when unit does not exist" {
    run systemd::remove_unit "nonexistent"
    assert_success
    assert_output --partial "does not exist"
}

@test "systemd::remove_unit calls systemctl stop and disable" {
    printf '[Unit]\n' >"$_SYSTEMD_DIR/myapp.service"
    local log="$BATS_TEST_TMPDIR/systemctl_log"
    systemctl() {
        printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/systemctl_log"
        return 0
    }
    export -f systemctl

    run systemd::remove_unit "myapp"
    assert_success
    run cat "$log"
    assert_output --partial "stop myapp.service"
    assert_output --partial "disable myapp.service"
    assert_output --partial "daemon-reload"
}

# ---------------------------------------------------------------------------
# systemd::enable_all
# ---------------------------------------------------------------------------

@test "systemd::enable_all enables and starts multiple services" {
    local log="$BATS_TEST_TMPDIR/systemctl_log"
    systemctl() {
        printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/systemctl_log"
        return 0
    }
    export -f systemctl

    # services::enable_and_start checks is-enabled and is-active first,
    # both returning non-zero from our stub triggers enable + start
    run systemd::enable_all "app1" "app2" "app3"
    assert_success
    run cat "$log"
    assert_output --partial "app1"
    assert_output --partial "app2"
    assert_output --partial "app3"
}

# ---------------------------------------------------------------------------
# systemd::restart_all
# ---------------------------------------------------------------------------

@test "systemd::restart_all restarts multiple services" {
    local log="$BATS_TEST_TMPDIR/systemctl_log"
    systemctl() {
        printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/systemctl_log"
        return 0
    }
    export -f systemctl

    run systemd::restart_all "svc1" "svc2"
    assert_success
    run cat "$log"
    assert_output --partial "restart svc1"
    assert_output --partial "restart svc2"
}

# ---------------------------------------------------------------------------
# systemd::status_all
# ---------------------------------------------------------------------------

@test "systemd::status_all calls systemctl status for each service" {
    local log="$BATS_TEST_TMPDIR/systemctl_log"
    systemctl() {
        printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/systemctl_log"
        return 0
    }
    export -f systemctl

    run systemd::status_all "a" "b"
    assert_success
    run cat "$log"
    assert_output --partial "status a --no-pager"
    assert_output --partial "status b --no-pager"
}

# ---------------------------------------------------------------------------
# systemd::is_all_active
# ---------------------------------------------------------------------------

@test "systemd::is_all_active returns 0 when all are active" {
    systemctl() {
        # is-active always succeeds
        return 0
    }
    export -f systemctl

    run systemd::is_all_active "a" "b" "c"
    assert_success
}

@test "systemd::is_all_active returns 1 when any is inactive" {
    systemctl() {
        if [[ "$1" == "is-active" && "$2" == "b" ]]; then
            return 1
        fi
        return 0
    }
    export -f systemctl

    run systemd::is_all_active "a" "b" "c"
    assert_failure
}

@test "systemd::is_all_active returns 0 with no arguments" {
    run systemd::is_all_active
    assert_success
}

# ---------------------------------------------------------------------------
# systemd::simple_unit
# ---------------------------------------------------------------------------

@test "systemd::simple_unit fails without --exec-start" {
    run systemd::simple_unit --description "Test"
    assert_failure
    assert_output --partial "requires --exec-start"
}

@test "systemd::simple_unit fails on unknown option" {
    run systemd::simple_unit --bad-flag "x"
    assert_failure
    assert_output --partial "Unknown option"
}

@test "systemd::simple_unit generates minimal unit with defaults" {
    run systemd::simple_unit --exec-start "/usr/bin/myapp"
    assert_success
    assert_output --partial "[Unit]"
    assert_output --partial "After=network.target"
    assert_output --partial "[Service]"
    assert_output --partial "ExecStart=/usr/bin/myapp"
    assert_output --partial "Restart=always"
    assert_output --partial "RestartSec=5"
    assert_output --partial "[Install]"
    assert_output --partial "WantedBy=multi-user.target"
}

@test "systemd::simple_unit includes description when set" {
    run systemd::simple_unit --description "My App" --exec-start "/usr/bin/myapp"
    assert_success
    assert_output --partial "Description=My App"
}

@test "systemd::simple_unit includes user and group" {
    run systemd::simple_unit --exec-start "/usr/bin/myapp" --user "deploy" --group "deploy"
    assert_success
    assert_output --partial "User=deploy"
    assert_output --partial "Group=deploy"
}

@test "systemd::simple_unit includes working directory" {
    run systemd::simple_unit --exec-start "/usr/bin/myapp" --working-dir "/opt/myapp"
    assert_success
    assert_output --partial "WorkingDirectory=/opt/myapp"
}

@test "systemd::simple_unit overrides defaults" {
    run systemd::simple_unit \
        --exec-start "/usr/bin/myapp" \
        --restart "on-failure" \
        --restart-sec "10" \
        --after "network-online.target" \
        --wanted-by "graphical.target"
    assert_success
    assert_output --partial "Restart=on-failure"
    assert_output --partial "RestartSec=10"
    assert_output --partial "After=network-online.target"
    assert_output --partial "WantedBy=graphical.target"
}

@test "systemd::simple_unit omits description when not set" {
    run systemd::simple_unit --exec-start "/usr/bin/myapp"
    assert_success
    refute_output --partial "Description="
}

@test "systemd::simple_unit omits user/group/working-dir when not set" {
    run systemd::simple_unit --exec-start "/usr/bin/myapp"
    assert_success
    refute_output --partial "User="
    refute_output --partial "Group="
    refute_output --partial "WorkingDirectory="
}

@test "systemd::simple_unit integrates with install_unit" {
    local content
    content="$(systemd::simple_unit \
        --description "Integration Test" \
        --exec-start "/usr/bin/myapp" \
        --user "deploy")"

    run systemd::install_unit "myapp" "$content"
    assert_success
    [[ -f "$_SYSTEMD_DIR/myapp.service" ]]
    run cat "$_SYSTEMD_DIR/myapp.service"
    assert_output --partial "Description=Integration Test"
    assert_output --partial "ExecStart=/usr/bin/myapp"
    assert_output --partial "User=deploy"
}
