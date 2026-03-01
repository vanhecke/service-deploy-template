# PROJECTNAME

[![CI](https://github.com/REPO_OWNER/PROJECTNAME/actions/workflows/ci.yml/badge.svg)](https://github.com/REPO_OWNER/PROJECTNAME/actions/workflows/ci.yml)

REPO_DESCRIPTION

## Prerequisites

- Bash 4+
- Target: Debian 11+/Ubuntu 22.04+
- Development: [ShellCheck](https://www.shellcheck.net/), [shfmt](https://github.com/mvdan/sh), [bats-core](https://github.com/bats-core/bats-core)

## Quick Start

```bash
# Clone and configure
git clone https://github.com/REPO_OWNER/PROJECTNAME.git
cd PROJECTNAME
cp etc/.env.example etc/.env
# Edit etc/.env with your values

# Deploy
sudo ./bin/deploy.sh

# Deploy with debug logging
sudo ./bin/deploy.sh -v

# Dry run (no changes)
./bin/deploy.sh -n
```

## Project Structure

```
├── bin/deploy.sh           # Entry-point deploy script
├── lib/core/               # Core libraries
│   ├── logging.sh          # 5-level structured logging
│   ├── config.sh           # Safe .env loading and validation
│   ├── checks.sh           # OS detection, dependency checks
│   └── utils.sh            # Backup, lock, template, file ops
├── lib/modules/            # Deployment modules
│   ├── packages.sh         # apt-get wrappers
│   ├── firewall.sh         # UFW management
│   ├── services.sh         # systemd helpers
│   └── network.sh          # IP/port utilities
├── etc/                    # Configuration
│   ├── .env.example        # Environment variable template
│   └── templates/          # Config file templates (envsubst)
├── tests/                  # bats-core tests
└── Makefile                # Task runner
```

## Configuration

Copy `etc/.env.example` to `etc/.env` and adjust values. Environment variables override `.env` file values.

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | PROJECTNAME | Application name |
| `APP_PORT` | `8080` | Application port |
| `LOG_LEVEL` | `INFO` | Log verbosity (DEBUG/INFO/WARN/ERROR/FATAL) |
| `LOG_FILE` | _(unset)_ | Log to file when set |
| `FIREWALL_ENABLED` | `true` | Enable UFW configuration |
| `ALLOWED_PORTS` | `22 80 443` | Ports to allow through firewall |

## Development

```bash
make help          # Show available targets
make lint          # Run ShellCheck
make format        # Format with shfmt
make test          # Run bats-core tests
make check         # Run all checks (CI target)
```

## Adding Deployment Steps

Edit `bin/deploy.sh` and add your logic in the marked section:

```bash
# --- Add your deployment steps below ---
checks::require_root
packages::install curl wget nginx
firewall::enable
firewall::allow_ports 22 80 443
services::enable_and_start nginx
# --- End deployment steps ---
```

## License

[MIT](LICENSE)
