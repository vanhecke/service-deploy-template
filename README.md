# PROJECTNAME

[![CI](https://github.com/REPO_OWNER/PROJECTNAME/actions/workflows/ci.yml/badge.svg)](https://github.com/REPO_OWNER/PROJECTNAME/actions/workflows/ci.yml)

REPO_DESCRIPTION

A bash framework for deploying applications to Debian/Ubuntu servers. Handles user creation, SSH key setup, firewall configuration, systemd services, backups, and system hardening out of the box. Customize by implementing hooks in `app/hooks.sh`.

## Features

- Idempotent deployment — safe to run repeatedly
- Layered configuration via `.env` files with environment variable override
- Structured 5-level logging with color support and cron-safe mode
- Dry-run mode (`-n`) to preview changes without applying them
- Management CLI (`<appname>ctl`) for health checks, upgrades, backups, and logs
- Remote deployment via rsync + SSH (`bin/push.sh`)
- One-liner bootstrap for fresh servers (`bin/bootstrap.sh`)
- GitHub template with auto-initialization workflow
- Comprehensive test suite (bats-core) and CI (ShellCheck, shfmt)

## Prerequisites

- **Target server:** Debian 11+ / Ubuntu 22.04+, Bash 4+
- **Development machine:** [ShellCheck](https://www.shellcheck.net/), [shfmt](https://github.com/mvdan/sh), [bats-core](https://github.com/bats-core/bats-core)

## Quick Start

```bash
# Clone and configure
git clone https://github.com/REPO_OWNER/PROJECTNAME.git
cd PROJECTNAME
cp etc/.env.example etc/.env
# Edit etc/.env with your values

# Deploy locally (on target server)
sudo ./bin/deploy.sh

# Deploy to remote host
bin/push.sh deploy@your-server.com
# or: make deploy HOST=deploy@your-server.com

# Dry run (preview changes)
sudo ./bin/deploy.sh -n

# Verbose output
sudo ./bin/deploy.sh -v
```

## Project Structure

```
bin/
├── deploy.sh               Entry-point deployment script (runs as root on target)
├── push.sh                 Remote deployment via rsync + SSH
├── bootstrap.sh            One-liner bootstrap (curl | bash)
└── ctl.sh                  On-machine management CLI
lib/
├── core/                   Foundation libraries (always loaded)
│   ├── logging.sh          5-level structured logging with colors
│   ├── config.sh           Layered .env loading and validation
│   ├── checks.sh           OS/arch detection, root/command checks
│   ├── utils.sh            Temp files, backups, locks, templates, file ops
│   └── options.sh          Declarative CLI option parsing
└── modules/                Feature modules
    ├── packages.sh         apt-get wrappers (idempotent, cache-aware)
    ├── firewall.sh         UFW firewall management
    ├── services.sh         systemd service helpers
    ├── network.sh          IP validation, port checking
    ├── users.sh            User creation, sudoers management
    ├── ssh.sh              SSH key management, GitHub key import
    ├── system.sh           Swap, hostname, journald, unattended-upgrades
    ├── install.sh          Download, checksum, extract, GitHub releases
    ├── backup.sh           Timestamped backup, restore, rotation
    ├── version.sh          Version state file management
    └── systemd.sh          Unit file management, templates, bulk ops
app/
└── hooks.sh                Application hooks (customize these)
etc/
├── .env.example            Configuration template
└── templates/              Config file templates (envsubst)
tests/                      bats-core test suite
Makefile                    Task runner (lint, format, test, deploy)
```

## Configuration

Copy `etc/.env.example` to `etc/.env` and adjust values. Environment variables override `.env` values.

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | PROJECTNAME | Application identifier (used for paths, services, CLI) |
| `APP_USER` | `deploy` | Dedicated system user created for the application |
| `APP_PORT` | `8080` | Application port (checked in health command) |
| `APP_ENV` | `production` | Environment name |
| `APP_SERVICES` | _(APP_NAME)_ | Space-separated systemd unit names to manage |
| `SSH_GITHUB_USER` | `vanhecke` | GitHub username whose public keys are imported |
| `LOG_LEVEL` | `INFO` | Log verbosity: DEBUG, INFO, WARN, ERROR, FATAL |
| `LOG_FILE` | _(unset)_ | Log to file when set |
| `FIREWALL_ENABLED` | `true` | Enable UFW firewall configuration |
| `ALLOWED_PORTS` | `22 80 443` | Ports to allow through firewall |
| `SWAP_SIZE` | _(unset)_ | Create swap file (e.g., `2G`, `512M`) |
| `APP_HOSTNAME` | _(unset)_ | Set server hostname |
| `APP_DATA_DIR` | `/var/lib/PROJECTNAME` | Application data directory |
| `BACKUP_KEEP` | `5` | Number of backups to retain on rotation |
| `EXTRA_PACKAGES` | _(empty)_ | Space-separated additional apt packages to install |

## Deployment Methods

### Local Deployment

Run directly on the target server:

```bash
sudo ./bin/deploy.sh          # Standard deployment
sudo ./bin/deploy.sh -v       # Verbose (DEBUG logging)
sudo ./bin/deploy.sh -n       # Dry run
sudo ./bin/deploy.sh -C       # Cron mode (silent unless error)
```

### Remote Deployment

Push from your development machine:

```bash
bin/push.sh deploy@your-server.com
bin/push.sh -k ~/.ssh/mykey deploy@your-server.com
bin/push.sh -p 2222 deploy@your-server.com
bin/push.sh -n deploy@your-server.com     # Dry run

# Or via Makefile:
make deploy HOST=deploy@your-server.com
```

`push.sh` syncs the project via rsync (excluding `.git`, `tests`, `.env`, etc.), runs `deploy.sh` on the remote, and cleans up.

### Bootstrap (Fresh Server)

For initial setup on a bare server:

```bash
curl -fsSL https://raw.githubusercontent.com/REPO_OWNER/PROJECTNAME/main/bin/bootstrap.sh | bash
```

This clones the repo to `/opt/PROJECTNAME`, creates `.env` from the template, and runs deployment.

## What Deploy Does

`deploy.sh` executes these steps idempotently:

1. Install base packages (curl, openssh-server, rsync, plus `EXTRA_PACKAGES`)
2. Create dedicated app user with home directory
3. Lock password login (SSH keys only)
4. Import SSH public keys from GitHub
5. Install scoped sudoers rules (limited to apt-get and systemctl for the app)
6. Copy framework to app user's home
7. Install management CLI (`<appname>ctl`) to `/usr/local/bin/`
8. Configure UFW firewall (if enabled)
9. System hardening: swap, hostname, journald limits, unattended-upgrades
10. Create FHS directories (`/opt`, `/etc`, `/var/lib`, `/var/backup`)
11. Run application hooks: `app_install`, `app_configure`, `app_post_install`
12. Enable and start systemd services

## Management CLI

After deployment, `<appname>ctl` is available on the server:

```bash
appctl health              # Service, port, disk, memory, app health checks
appctl health --json       # JSON output for monitoring
appctl status              # systemd service status
appctl start               # Start all services
appctl stop                # Stop all services
appctl restart             # Restart all services
appctl upgrade             # Backup → update → apt upgrade → restart
appctl backup              # Run application backup hook
appctl restore [FILE]      # Restore from backup (latest if unspecified)
appctl version             # Show installed and application version
appctl logs [N]            # Last N log lines (default: 50)
appctl uninstall           # Remove application (with confirmation)
```

## Customizing for Your Application

Edit `app/hooks.sh` to implement your application logic. All framework libraries and `.env` variables are available inside hooks.

```bash
app_install() {
    # Download and install your application
    install::github_download_release "owner/repo" "*linux_amd64.tar.gz" "/tmp/app.tar.gz"
    install::extract "/tmp/app.tar.gz" "/opt/${APP_NAME}"
    version::set "$(install::github_latest_release "owner/repo")"
}

app_configure() {
    # Generate config files from templates
    utils::render_template "${PROJECT_ROOT}/etc/templates/app.conf" "/etc/${APP_NAME}/app.conf"
}

app_post_install() {
    # Run after services are enabled (e.g., seed database)
    :
}

app_update() {
    # Update to latest version (called by: appctl upgrade)
    install::github_download_release "owner/repo" "*linux_amd64.tar.gz" "/tmp/app.tar.gz"
    install::extract "/tmp/app.tar.gz" "/opt/${APP_NAME}"
    version::set "$(install::github_latest_release "owner/repo")"
}

app_health() {
    # Return non-zero if unhealthy (called by: appctl health)
    network::is_port_open localhost "${APP_PORT}"
}

app_version() {
    # Print application version string
    /opt/${APP_NAME}/bin/app --version 2>/dev/null || echo "unknown"
}

app_backup() {
    # Back up application data (called by: appctl backup)
    backup::create "app" "/var/lib/${APP_NAME}" "/etc/${APP_NAME}"
    backup::rotate "app" "${BACKUP_KEEP:-5}"
}

app_restore() {
    # Restore from backup file (called by: appctl restore)
    backup::restore "${1:-$(backup::latest "app")}"
}

app_uninstall() {
    # Clean up application files
    rm -rf "/opt/${APP_NAME}"
}
```

### Creating Systemd Services

Use `systemd::simple_unit` to generate unit files:

```bash
app_install() {
    # ... install binary ...

    local unit
    unit=$(systemd::simple_unit \
        --description "My Application" \
        --exec-start "/opt/${APP_NAME}/bin/app serve" \
        --user "${APP_USER}" \
        --group "${APP_USER}" \
        --working-dir "/var/lib/${APP_NAME}")
    systemd::install_unit "${APP_NAME}" "$unit"
}
```

### Config File Templates

Place templates in `etc/templates/` using shell variable syntax. They are rendered with `envsubst`:

```ini
# etc/templates/app.conf
[server]
port = ${APP_PORT}
data_dir = ${APP_DATA_DIR}
environment = ${APP_ENV}
```

Render in a hook:

```bash
utils::render_template "${PROJECT_ROOT}/etc/templates/app.conf" "/etc/${APP_NAME}/app.conf"
```

## Library Reference

The framework provides these helper libraries — all available inside hooks and entry-point scripts:

| Library | Key Functions |
|---------|---------------|
| **logging** | `debug`, `info`, `warn`, `error`, `fatal`, `cron_init/cleanup` |
| **config** | `load`, `require_vars`, `is_true`, `is_valid_port` |
| **checks** | `detect_os`, `detect_arch`, `require_root`, `require_commands`, `confirm` |
| **utils** | `tempfile`, `backup_file`, `acquire_lock`, `render_template`, `ensure_line/dir/symlink`, `execute` |
| **options** | `define`, `parse`, `usage` |
| **packages** | `install`, `remove`, `is_installed`, `update_cache` |
| **firewall** | `enable`, `allow_port/ports`, `deny_port` |
| **services** | `enable_and_start`, `restart`, `reload`, `is_active`, `daemon_reload` |
| **network** | `is_valid_ipv4`, `is_port_open`, `wait_for_port`, `get_local_ip` |
| **users** | `ensure_user`, `lock_password`, `ensure_sudoers` |
| **ssh** | `ensure_authorized_keys`, `import_github_keys` |
| **system** | `ensure_swap`, `set_hostname`, `configure_journald`, `enable_unattended_upgrades`, `ensure_fhs_dirs` |
| **install** | `download`, `verify_checksum`, `extract`, `github_latest_release`, `github_download_release`, `git_clone_or_pull` |
| **backup** | `create`, `list`, `restore`, `rotate`, `latest` |
| **version** | `get`, `set`, `check` |
| **systemd** | `install_unit`, `install_unit_from_template`, `remove_unit`, `enable/restart/status_all`, `is_all_active`, `simple_unit` |

See [CLAUDE.md](CLAUDE.md) for complete function signatures.

## Using as a GitHub Template

This repository is designed as a GitHub template. When you create a new repository from it:

1. The **template-bootstrap** workflow automatically runs
2. It replaces `PROJECTNAME`, `REPO_OWNER`, and `REPO_DESCRIPTION` placeholders throughout the codebase
3. A pull request is created with the customized files
4. After merging, the bootstrap workflow self-deletes

## Development

```bash
make help          # Show available targets
make lint          # ShellCheck on all scripts
make format        # Format with shfmt (4-space indent)
make format-check  # Check formatting without modifying
make test          # Run bats-core test suite
make check         # All checks (lint + format-check + test) — CI target
```

### Writing Tests

Tests use [bats-core](https://github.com/bats-core/bats-core) with bats-assert and bats-support:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/modules/mymodule.sh"
}

@test "mymodule::function does the right thing" {
    run mymodule::function "arg"
    assert_success
    assert_output --partial "expected"
}
```

Test files go in `tests/<modulename>.bats`.

## License

[MIT](LICENSE)
