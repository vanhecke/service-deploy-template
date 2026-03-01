# CLAUDE.md — Agent Instructions for service-deploy-template

## What This Is

A GitHub template repository providing a production-grade bash framework for deploying applications to Debian/Ubuntu servers. The framework handles user creation, SSH setup, firewall, systemd services, backups, and system hardening — you customize it by implementing hooks in `app/hooks.sh`.

**Target OS:** Debian 11+ / Ubuntu 22.04+
**Required:** Bash 4+

## Directory Structure

```
bin/
  deploy.sh          Main deployment script (runs on target as root)
  push.sh            Remote deployment via rsync + SSH
  bootstrap.sh       One-liner remote bootstrap (curl | bash)
  ctl.sh             On-machine management CLI (installed as <appname>ctl)
lib/core/            Foundation libraries (always sourced)
  logging.sh         5-level structured logging
  config.sh          Layered .env loading with validation
  checks.sh          OS/arch detection, root/command checks
  utils.sh           Temp files, backups, locks, templates, file ops
  options.sh         Declarative CLI option parsing
lib/modules/         Feature modules (sourced as needed)
  packages.sh        apt-get wrappers (idempotent, cache-aware)
  firewall.sh        UFW management
  services.sh        systemd service helpers
  network.sh         IP validation, port checking
  users.sh           User creation, sudoers management
  ssh.sh             SSH key management, GitHub key import
  system.sh          Swap, hostname, journald, unattended-upgrades, FHS dirs
  install.sh         Download, checksum, extract, GitHub releases
  backup.sh          Timestamped tar.gz backup/restore/rotation
  version.sh         Version state file management
  systemd.sh         Unit file install/remove, template rendering, bulk ops
app/
  hooks.sh           Application customization hooks (stub implementations)
etc/
  .env.example       Configuration template (all available variables)
  templates/         Config file templates processed with envsubst
tests/               bats-core test suite
Makefile             lint, format, test, deploy targets
```

## Shell Conventions

### File Header

Every script starts with:

```bash
#!/usr/bin/env bash
# @description Brief description of what this file does
```

### Strict Mode (entry-point scripts only: bin/*.sh)

```bash
set -euo pipefail
set -o errtrace
IFS=$'\n\t'
trap 'printf "Error in %s on line %d (exit %d)\n" "${FUNCNAME[0]:-main}" "$LINENO" "$?" >&2' ERR
trap cleanup EXIT
```

Library files (`lib/**/*.sh`) do NOT set strict mode — they inherit it from the caller.

### Guard Pattern (all library files)

Every file in `lib/` prevents double-sourcing:

```bash
[[ -n "${_MODULENAME_SH_LOADED:-}" ]] && return 0
readonly _MODULENAME_SH_LOADED=1
```

### Function Naming

- Public functions: `namespace::function_name` (e.g., `backup::create`, `logging::info`)
- Private functions: `_namespace::function_name` (e.g., `_options::varname`)
- Namespaces match the filename (e.g., `firewall.sh` → `firewall::*`)

### Formatting

- **Indent:** 4 spaces (enforced by shfmt)
- **Case statements:** indented with `-ci` flag
- **Formatter:** `shfmt -i 4 -ci`
- **Linter:** `shellcheck -x` (the `-x` follows source directives)

## How to Write a New Module

Create `lib/modules/mymodule.sh`:

```bash
#!/usr/bin/env bash
# @description Brief description

[[ -n "${_MYMODULE_SH_LOADED:-}" ]] && return 0
readonly _MYMODULE_SH_LOADED=1

# Source dependencies (use PROJECT_ROOT or relative paths)
source "${BASH_SOURCE[0]%/*}/../core/logging.sh"
source "${BASH_SOURCE[0]%/*}/../core/utils.sh"

mymodule::do_thing() {
    local arg="$1"
    logging::info "Doing thing: ${arg}"
    utils::execute "Description of action" some_command "$arg"
}
```

Then source it in `bin/deploy.sh` alongside the other modules.

## How to Write Hooks

Edit `app/hooks.sh` — replace the stub implementations. All core and module libraries are already sourced, and all `.env` variables are available.

| Hook | Called By | Purpose |
|------|-----------|---------|
| `app_install` | deploy.sh | Download, extract, build your application |
| `app_configure` | deploy.sh | Generate config files from templates |
| `app_post_install` | deploy.sh | Run after systemd services are enabled |
| `app_update` | ctl.sh upgrade | Update application to latest version |
| `app_health` | ctl.sh health | Custom health checks (return non-zero = unhealthy) |
| `app_version` | ctl.sh version | Print current application version string |
| `app_backup` | ctl.sh backup | Back up application-specific data |
| `app_restore` | ctl.sh restore | Restore from backup (receives file path as $1) |
| `app_uninstall` | ctl.sh uninstall | Clean up application files |

Example hook:

```bash
app_install() {
    install::github_download_release "owner/repo" "*linux_amd64.tar.gz" "/tmp/app.tar.gz"
    install::extract "/tmp/app.tar.gz" "/opt/${APP_NAME}"
    version::set "$(install::github_latest_release "owner/repo")"
}

app_configure() {
    utils::render_template "${PROJECT_ROOT}/etc/templates/app.conf" "/etc/${APP_NAME}/app.conf"
}

app_health() {
    network::is_port_open localhost "${APP_PORT}"
}
```

## Available Helpers Reference

### Core: logging.sh

| Function | Purpose |
|----------|---------|
| `logging::debug "msg"` | Debug output (filtered by LOG_LEVEL) |
| `logging::info "msg"` | Info output to stdout |
| `logging::warn "msg"` | Warning to stderr |
| `logging::error "msg"` | Error to stderr |
| `logging::fatal "msg"` | Error to stderr + exit 1 |
| `logging::cron_init` | Buffer output, only dump on error |
| `logging::cron_cleanup` | Flush cron buffer |

### Core: config.sh

| Function | Purpose |
|----------|---------|
| `config::load [dir]` | Load .env.defaults + .env from dir (default: etc/) |
| `config::load_env_file file` | Load a single .env file |
| `config::require_vars VAR1 VAR2 ...` | Fatal if any var unset |
| `config::is_true value` | Check if true/1/yes/on |
| `config::is_valid_port port` | Validate 1-65535 |

### Core: checks.sh

| Function | Purpose |
|----------|---------|
| `checks::detect_os` | Set OS_ID, OS_VERSION_ID, OS_CODENAME |
| `checks::detect_arch` | Set OS_ARCH (amd64/arm64/armhf) |
| `checks::require_commands cmd ...` | Fatal if commands missing |
| `checks::require_root` | Fatal if not root |
| `checks::require_bash_version [N]` | Fatal if Bash < N (default: 4) |
| `checks::is_interactive` | True if stdin is a terminal |
| `checks::confirm "prompt"` | Y/N prompt (skipped if FORCE=true) |
| `checks::run_as_root cmd ...` | Execute with sudo if needed |

### Core: utils.sh

| Function | Purpose |
|----------|---------|
| `utils::tempfile varname [ext]` | Create auto-cleaned temp file |
| `utils::cleanup_tempfiles` | Remove all registered temps |
| `utils::backup_file file` | Create .backup.TIMESTAMP copy |
| `utils::acquire_lock lockfile` | Exclusive flock on FD 200 |
| `utils::render_template tmpl output` | envsubst substitution |
| `utils::ensure_line file line [marker]` | Idempotent line append |
| `utils::ensure_dir dir [owner] [mode]` | mkdir with ownership/perms |
| `utils::execute desc cmd ...` | DRY_RUN-aware execution with logging |
| `utils::home_dir username` | Portable home directory lookup |
| `utils::ensure_symlink target link` | Idempotent symlink |

### Core: options.sh

| Function | Purpose |
|----------|---------|
| `options::define "type\|short\|long\|desc[\|default]"` | Register CLI option |
| `options::parse "$@"` | Parse args, set variables, collect positionals in ARGS |
| `options::usage` | Print formatted help section |

### Module: packages.sh

| Function | Purpose |
|----------|---------|
| `packages::update_cache` | apt update if cache > 1 hour old |
| `packages::install pkg ...` | Install only missing packages |
| `packages::is_installed pkg` | Check if installed |
| `packages::remove pkg ...` | Remove if installed |

### Module: firewall.sh

| Function | Purpose |
|----------|---------|
| `firewall::enable` | Enable UFW (default deny in, allow out) |
| `firewall::allow_port port [proto]` | Idempotent allow rule |
| `firewall::allow_ports port ...` | Allow multiple ports |
| `firewall::deny_port port [proto]` | Deny rule |

### Module: services.sh

| Function | Purpose |
|----------|---------|
| `services::enable_and_start svc` | Enable + start (idempotent) |
| `services::restart svc` | Restart service |
| `services::reload svc` | Reload config |
| `services::is_active svc` | Check if active |
| `services::daemon_reload` | Reload systemd daemon |

### Module: network.sh

| Function | Purpose |
|----------|---------|
| `network::is_valid_ipv4 ip` | Validate IPv4 format |
| `network::is_port_open host port [timeout]` | Check TCP port (default 3s) |
| `network::wait_for_port host port [max]` | Poll until open (default 30s) |
| `network::get_local_ip` | Get primary local IP |

### Module: users.sh

| Function | Purpose |
|----------|---------|
| `users::ensure_user username` | Create system user (idempotent) |
| `users::lock_password username` | Lock password login |
| `users::ensure_sudoers user app` | Install scoped sudoers rules (validated with visudo) |

### Module: ssh.sh

| Function | Purpose |
|----------|---------|
| `ssh::ensure_authorized_keys user` | Create .ssh dir + authorized_keys with correct perms |
| `ssh::import_github_keys gh_user sys_user` | Fetch + append GitHub public keys (idempotent) |

### Module: system.sh

| Function | Purpose |
|----------|---------|
| `system::ensure_swap size` | Create swap file (e.g., "2G") if none active |
| `system::set_hostname name` | Set hostname (RFC 1123 validated) |
| `system::configure_journald` | Set 500M max, 30-day retention |
| `system::enable_unattended_upgrades` | Install + configure security auto-updates |
| `system::ensure_fhs_dirs app [owner]` | Create /opt, /etc, /var/lib, /var/backup dirs |

### Module: install.sh

| Function | Purpose |
|----------|---------|
| `install::download url dest` | Download with 3 retries |
| `install::verify_checksum file sha256` | SHA-256 verification |
| `install::extract archive dest` | Auto-detect .tar.gz/.tar.xz/.zip |
| `install::github_latest_release owner/repo` | Get latest release tag |
| `install::github_download_release owner/repo pattern dest` | Download matching release asset |
| `install::git_clone_or_pull url dest [branch]` | Idempotent git clone/pull |

### Module: backup.sh

| Function | Purpose |
|----------|---------|
| `backup::create label path ...` | Create timestamped tar.gz |
| `backup::list [label]` | List backups (oldest first) |
| `backup::restore file` | Extract tar.gz to / |
| `backup::rotate label keep` | Delete old, keep N newest |
| `backup::latest label` | Path to most recent backup |

### Module: version.sh

| Function | Purpose |
|----------|---------|
| `version::get` | Read version from state file |
| `version::set ver` | Write version to state file |
| `version::check` | Display version + call app_version hook |

### Module: systemd.sh

| Function | Purpose |
|----------|---------|
| `systemd::install_unit name content` | Write .service file (idempotent, reloads daemon) |
| `systemd::install_unit_from_template tmpl name` | Render template + install |
| `systemd::remove_unit name` | Stop, disable, remove |
| `systemd::enable_all svc ...` | Enable + start multiple services |
| `systemd::restart_all svc ...` | Restart multiple services |
| `systemd::status_all svc ...` | Show status of multiple services |
| `systemd::is_all_active svc ...` | True only if all active |
| `systemd::simple_unit --opt val ...` | Generate unit content from named params |

`systemd::simple_unit` options: `--description`, `--exec-start` (required), `--user`, `--group`, `--working-dir`, `--restart` (default: always), `--restart-sec` (default: 5), `--after` (default: network.target), `--wanted-by` (default: multi-user.target).

## Configuration System

**Priority** (highest to lowest): environment variables > `etc/.env` > `etc/.env.defaults` > hardcoded defaults.

`config::load` only sets variables that are not already in the environment, preserving env var precedence.

Key variables: `APP_NAME`, `APP_USER`, `APP_PORT`, `APP_ENV`, `APP_SERVICES`, `APP_DATA_DIR`, `SSH_GITHUB_USER`, `LOG_LEVEL`, `LOG_FILE`, `FIREWALL_ENABLED`, `ALLOWED_PORTS`, `SWAP_SIZE`, `APP_HOSTNAME`, `BACKUP_KEEP`, `EXTRA_PACKAGES`.

## DRY_RUN Pattern

Use `utils::execute` for simple commands:

```bash
utils::execute "Installing nginx" apt-get install -y nginx
```

For complex logic, check the variable directly:

```bash
if [[ "${DRY_RUN:-false}" == true ]]; then
    logging::info "[DRY RUN] Would restart services"
    return 0
fi
```

## Idempotency Patterns

All state-changing operations must check existing state first:

- **Check before create:** `id "$user" &>/dev/null || useradd ...`
- **Use ensure_* functions:** `utils::ensure_dir`, `utils::ensure_line`, `utils::ensure_symlink`
- **Content comparison:** `cmp -s` before overwriting files (see `systemd::install_unit`)
- **Package checks:** `packages::is_installed` before `apt-get install`
- **Grep before append:** `grep -q` before adding lines to files

## Testing

Tests use **bats-core** with bats-assert and bats-support.

### Test file structure

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/modulename.sh"
}

@test "namespace::function does expected thing" {
    run namespace::function "arg"
    assert_success
    assert_output --partial "expected"
}
```

- Test files: `tests/<modulename>.bats`
- Common setup provides: `$PROJECT_ROOT`, `NO_COLOR=1`, bats-assert/bats-support
- Use `$BATS_TEST_TMPDIR` for temporary files in tests
- Run tests: `make test` or `bats --print-output-on-failure tests/`

### Testing stderr output

Wrap in `bash -c` to capture stderr alongside stdout:

```bash
@test "error goes to stderr" {
    run bash -c 'source "$PROJECT_ROOT/lib/core/logging.sh" && NO_COLOR=1 logging::error "msg" 2>&1'
    assert_output --partial "[ERROR]"
}
```

## Linting and CI

```bash
make lint          # shellcheck -x on all scripts
make format        # shfmt -w -i 4 -ci .
make format-check  # shfmt -d (check only)
make test          # bats tests
make check         # all of the above (CI target)
```

CI runs on push to main and PRs: ShellCheck → shfmt → bats (sequential).

## Deployment Lifecycle

1. **`bin/push.sh user@host`** — rsync project to remote `/tmp/<app>-deploy/`, SSH-execute deploy.sh, clean up
2. **`bin/deploy.sh`** — runs on target as root: install packages, create user, configure SSH/firewall/system, run hooks, enable services
3. **`bin/ctl.sh`** — installed as `<app>ctl`, runs as app user for health/start/stop/upgrade/backup/logs

## Security Practices

- Validate usernames and app names with regex (`^[a-z_][a-z0-9_-]*$`) to prevent injection
- Use `visudo -cf` to validate sudoers files before installation
- Never hardcode credentials; use `.env` files (git-ignored)
- Lock password login on app users; require SSH keys
- Scoped sudoers rules: only allow specific systemctl and apt-get commands
- Verify checksums on downloaded files with `install::verify_checksum`
