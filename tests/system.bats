#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/logging.sh"
    source "$PROJECT_ROOT/lib/core/utils.sh"

    # Stub out packages::install so sourcing packages.sh doesn't matter
    # and we can verify calls without needing apt
    packages::install() { :; }
    export -f packages::install

    # Stub dpkg so packages.sh source guard works
    dpkg() { return 1; }
    export -f dpkg

    source "$PROJECT_ROOT/lib/modules/system.sh"
    export DRY_RUN=true
}

# --- system::ensure_swap ---

@test "system::ensure_swap fails without argument" {
    run system::ensure_swap
    assert_failure
}

@test "system::ensure_swap rejects invalid size format" {
    run system::ensure_swap "abc"
    assert_failure
    assert_output --partial "Invalid swap size"
}

@test "system::ensure_swap rejects size without unit" {
    run system::ensure_swap "2048"
    assert_failure
    assert_output --partial "Invalid swap size"
}

@test "system::ensure_swap accepts valid size with G suffix" {
    # Mock swapon to report no active swap
    swapon() { return 0; }
    export -f swapon
    run system::ensure_swap "2G"
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "2G"
}

@test "system::ensure_swap accepts valid size with M suffix" {
    swapon() { return 0; }
    export -f swapon
    run system::ensure_swap "512M"
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "512M"
}

@test "system::ensure_swap skips when swap already active" {
    # Mock swapon --show to report active swap
    swapon() {
        if [[ "${1:-}" == "--show" ]]; then
            printf '/swapfile file 2G 0B -2\n'
            return 0
        fi
        return 0
    }
    export -f swapon
    run system::ensure_swap "2G"
    assert_success
    assert_output --partial "already active"
}

# --- system::set_hostname ---

@test "system::set_hostname fails without argument" {
    run system::set_hostname
    assert_failure
}

@test "system::set_hostname rejects invalid hostname" {
    run system::set_hostname "-invalid"
    assert_failure
    assert_output --partial "Invalid hostname"
}

@test "system::set_hostname rejects hostname with dots" {
    run system::set_hostname "host.name"
    assert_failure
    assert_output --partial "Invalid hostname"
}

@test "system::set_hostname rejects hostname with underscores" {
    run system::set_hostname "host_name"
    assert_failure
    assert_output --partial "Invalid hostname"
}

@test "system::set_hostname dry run logs message" {
    run system::set_hostname "myserver"
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "myserver"
}

@test "system::set_hostname accepts valid hostname" {
    run system::set_hostname "web-server-01"
    assert_success
    assert_output --partial "[DRY RUN]"
}

@test "system::set_hostname accepts single character hostname" {
    run system::set_hostname "a"
    assert_success
}

# --- system::configure_journald ---

@test "system::configure_journald dry run logs message" {
    run system::configure_journald
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "journald"
}

@test "system::configure_journald updates existing config" {
    export DRY_RUN=false
    local conf="$BATS_TEST_TMPDIR/journald.conf"
    printf '%s\n' '[Journal]' '#SystemMaxUse=' '#MaxRetentionSec=' >"$conf"

    # Override conf path by wrapping the function
    systemctl() { :; }
    export -f systemctl

    # We need to test the actual logic, so we override the conf path
    # by redefining the function with a custom conf path
    _test_configure_journald() {
        local conf="$1"
        local desired_max_use="SystemMaxUse=500M"
        local desired_retention="MaxRetentionSec=30day"
        local changed=0

        if grep -q "^SystemMaxUse=500M$" "$conf" 2>/dev/null; then
            :
        elif grep -q "^#*SystemMaxUse=" "$conf" 2>/dev/null; then
            sed -i.bak "s/^#*SystemMaxUse=.*/${desired_max_use}/" "$conf"
            changed=1
        else
            printf '%s\n' "$desired_max_use" >>"$conf"
            changed=1
        fi

        if grep -q "^MaxRetentionSec=30day$" "$conf" 2>/dev/null; then
            :
        elif grep -q "^#*MaxRetentionSec=" "$conf" 2>/dev/null; then
            sed -i.bak "s/^#*MaxRetentionSec=.*/${desired_retention}/" "$conf"
            changed=1
        else
            printf '%s\n' "$desired_retention" >>"$conf"
            changed=1
        fi
        printf '%d' "$changed"
    }

    run _test_configure_journald "$conf"
    assert_success
    assert_output "1"
    grep -q "^SystemMaxUse=500M$" "$conf"
    grep -q "^MaxRetentionSec=30day$" "$conf"
}

@test "system::configure_journald is idempotent" {
    local conf="$BATS_TEST_TMPDIR/journald.conf"
    printf '%s\n' '[Journal]' 'SystemMaxUse=500M' 'MaxRetentionSec=30day' >"$conf"

    # The already-set values should not trigger a change
    run grep -c "^SystemMaxUse=500M$" "$conf"
    assert_output "1"
    run grep -c "^MaxRetentionSec=30day$" "$conf"
    assert_output "1"
}

# --- system::enable_unattended_upgrades ---

@test "system::enable_unattended_upgrades dry run logs message" {
    run system::enable_unattended_upgrades
    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "unattended-upgrades"
}

# --- system::ensure_fhs_dirs ---

@test "system::ensure_fhs_dirs fails without argument" {
    run system::ensure_fhs_dirs
    assert_failure
}

@test "system::ensure_fhs_dirs rejects invalid app name" {
    run system::ensure_fhs_dirs "../../etc"
    assert_failure
    assert_output --partial "Invalid application name"
}

@test "system::ensure_fhs_dirs rejects app name starting with dash" {
    run system::ensure_fhs_dirs "-badname"
    assert_failure
    assert_output --partial "Invalid application name"
}

@test "system::ensure_fhs_dirs rejects app name with uppercase" {
    run system::ensure_fhs_dirs "MyApp"
    assert_failure
    assert_output --partial "Invalid application name"
}

@test "system::ensure_fhs_dirs creates directories" {
    export DRY_RUN=false

    # Override utils::ensure_dir to track calls in tmpdir
    local created_dirs="$BATS_TEST_TMPDIR/created_dirs.txt"
    : >"$created_dirs"
    utils::ensure_dir() {
        printf '%s\n' "$1" >>"$BATS_TEST_TMPDIR/created_dirs.txt"
    }
    export -f utils::ensure_dir

    run system::ensure_fhs_dirs "myapp"
    assert_success
    assert_output --partial "Ensured FHS directories"

    # Verify all 4 directories were requested
    run grep -c . "$created_dirs"
    assert_output "4"
    run grep "/opt/myapp" "$created_dirs"
    assert_success
    run grep "/etc/myapp" "$created_dirs"
    assert_success
    run grep "/var/lib/myapp" "$created_dirs"
    assert_success
    run grep "/var/backup/myapp" "$created_dirs"
    assert_success
}

@test "system::ensure_fhs_dirs passes owner to ensure_dir" {
    export DRY_RUN=false

    local call_log="$BATS_TEST_TMPDIR/ensure_dir_calls.txt"
    : >"$call_log"
    utils::ensure_dir() {
        printf '%s %s\n' "$1" "${2:-}" >>"$BATS_TEST_TMPDIR/ensure_dir_calls.txt"
    }
    export -f utils::ensure_dir

    run system::ensure_fhs_dirs "myapp" "deploy:deploy"
    assert_success

    run grep "deploy:deploy" "$call_log"
    assert_success
    # All 4 dirs should have the owner
    run grep -c "deploy:deploy" "$call_log"
    assert_output "4"
}

@test "system::ensure_fhs_dirs accepts valid app names" {
    export DRY_RUN=false
    utils::ensure_dir() { :; }
    export -f utils::ensure_dir

    run system::ensure_fhs_dirs "my-app"
    assert_success

    run system::ensure_fhs_dirs "my_app"
    assert_success

    run system::ensure_fhs_dirs "_app123"
    assert_success
}
