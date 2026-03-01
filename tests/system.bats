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

@test "system::ensure_swap creates swap and updates fstab" {
    export DRY_RUN=false
    export _FSTAB_FILE="$BATS_TEST_TMPDIR/fstab"
    printf '%s\n' "# /etc/fstab" >"$_FSTAB_FILE"

    # Mock swapon to report no active swap, then succeed
    swapon() {
        if [[ "${1:-}" == "--show" ]]; then
            return 0
        fi
        return 0
    }
    export -f swapon

    # Mock fallocate, mkswap, chmod
    fallocate() { touch "$3"; }
    export -f fallocate
    mkswap() { :; }
    export -f mkswap
    chmod() { :; }
    export -f chmod

    run system::ensure_swap "2G"
    assert_success
    assert_output --partial "Swap enabled: 2G"

    # Verify fstab was updated
    run grep "/swapfile none swap sw 0 0" "$_FSTAB_FILE"
    assert_success
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

@test "system::set_hostname updates /etc/hosts with new entry" {
    export DRY_RUN=false
    export _HOSTS_FILE="$BATS_TEST_TMPDIR/hosts"
    printf '%s\n' "127.0.0.1 localhost" >"$_HOSTS_FILE"

    hostnamectl() { :; }
    export -f hostnamectl

    run system::set_hostname "myserver"
    assert_success
    assert_output --partial "Hostname set to myserver"

    # Should have appended a 127.0.1.1 line
    run grep "^127.0.1.1 myserver$" "$_HOSTS_FILE"
    assert_success
}

@test "system::set_hostname replaces existing 127.0.1.1 entry" {
    export DRY_RUN=false
    export _HOSTS_FILE="$BATS_TEST_TMPDIR/hosts"
    printf '%s\n' "127.0.0.1 localhost" "127.0.1.1 oldhost" >"$_HOSTS_FILE"

    hostnamectl() { :; }
    export -f hostnamectl

    # Mock sed -i for macOS (BSD sed lacks \b and requires backup arg for -i)
    sed() {
        local args=()
        for arg in "$@"; do
            if [[ "$arg" == "-i" ]]; then
                args+=("-i" "")
            elif [[ "$arg" == *'\b'* ]]; then
                # Replace \b with [[:space:]] boundary for BSD sed
                args+=("${arg//\\b/[[:space:]]}")
            else
                args+=("$arg")
            fi
        done
        /usr/bin/sed "${args[@]}"
    }
    export -f sed

    run system::set_hostname "newhost"
    assert_success

    # Should have replaced the old entry
    run grep "^127.0.1.1 newhost$" "$_HOSTS_FILE"
    assert_success
    # Old entry should be gone
    run grep "oldhost" "$_HOSTS_FILE"
    assert_failure
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
    export _JOURNALD_CONF="$BATS_TEST_TMPDIR/journald.conf"
    printf '%s\n' '[Journal]' '#SystemMaxUse=' '#MaxRetentionSec=' >"$_JOURNALD_CONF"

    systemctl() { :; }
    export -f systemctl

    # Make sed -i portable for macOS
    sed() {
        local args=()
        for arg in "$@"; do
            if [[ "$arg" == "-i" ]]; then
                args+=("-i" "")
            else
                args+=("$arg")
            fi
        done
        /usr/bin/sed "${args[@]}"
    }
    export -f sed

    run system::configure_journald
    assert_success
    assert_output --partial "Configured journald"

    grep -q "^SystemMaxUse=500M$" "$_JOURNALD_CONF"
    grep -q "^MaxRetentionSec=30day$" "$_JOURNALD_CONF"
}

@test "system::configure_journald is idempotent" {
    export DRY_RUN=false
    export LOG_LEVEL=DEBUG
    export _JOURNALD_CONF="$BATS_TEST_TMPDIR/journald.conf"
    printf '%s\n' '[Journal]' 'SystemMaxUse=500M' 'MaxRetentionSec=30day' >"$_JOURNALD_CONF"

    systemctl() { :; }
    export -f systemctl

    run system::configure_journald
    assert_success
    # Should not have restarted or reported changes
    assert_output --partial "already configured"

    # Values should still be correct
    run grep -c "^SystemMaxUse=500M$" "$_JOURNALD_CONF"
    assert_output "1"
    run grep -c "^MaxRetentionSec=30day$" "$_JOURNALD_CONF"
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
