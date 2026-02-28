# Reusable Bash framework as a GitHub template repository

**The optimal Bash framework template combines a `bin/` + `lib/` modular architecture, bats-core testing, structured logging with NO_COLOR support, safe `.env` loading, ShellCheck + shfmt CI via GitHub Actions, and a self-documenting Makefile** — all wrapped in a GitHub template repository with a self-rewriting bootstrap workflow. This design hits the sweet spot between practical utility and maintainability for a senior engineer scaffolding Debian/Ubuntu VM deployment projects. The research below covers every layer needed to build this template, with specific code patterns, tool recommendations, and architectural decisions drawn from the most successful open-source Bash projects.

## Repository structure and modular architecture

The directory layout should follow conventions established by bash3boilerplate (~2.1k stars), natelandau/shell-scripting-templates (~500 stars), and the Google Shell Style Guide. The recommended structure for a deployment-focused Bash framework:

```
project-name/
├── bin/                     # Executable entry-point scripts (user-facing)
│   └── deploy.sh
├── lib/                     # Shared function libraries (sourced, not executed)
│   ├── core/
│   │   ├── logging.sh       # Log levels, colors, output formatting
│   │   ├── config.sh        # .env loading, validation, defaults
│   │   ├── checks.sh        # OS detection, dependency checking, root check
│   │   └── utils.sh         # Common utilities (backup, template, lock file)
│   └── modules/             # Domain-specific libraries
│       ├── packages.sh      # apt-get wrappers, idempotent install
│       ├── firewall.sh      # UFW rule management
│       ├── services.sh      # systemd enable/start/status
│       └── network.sh       # IP validation, DNS helpers
├── etc/                     # Configuration files and templates
│   ├── .env.example         # Environment variable template
│   └── templates/           # Config file templates (for envsubst)
├── tests/                   # bats-core test files
│   ├── test_helper/
│   │   └── common-setup.bash
│   ├── logging.bats
│   ├── config.bats
│   └── checks.bats
├── docs/                    # Usage guides, architecture docs
│   └── api.md               # Auto-generated from shdoc annotations
├── .github/
│   ├── workflows/
│   │   ├── ci.yml           # ShellCheck + shfmt + bats
│   │   └── template-bootstrap.yml  # Self-rewriting setup
│   ├── ISSUE_TEMPLATE/
│   │   └── bug_report.md
│   └── PULL_REQUEST_TEMPLATE.md
├── .editorconfig
├── .gitignore
├── .shellcheckrc
├── Makefile                 # Self-documenting task runner
├── LICENSE                  # MIT recommended
├── README.md
└── CHANGELOG.md
```

**Naming conventions** follow the Google Shell Style Guide: executables in `bin/` omit the `.sh` extension or keep it; library files in `lib/` **must** have `.sh` extension. Function names use `lowercase_with_underscores`. Library functions use a namespace prefix with `::` separator (e.g., `logging::info`, `config::load`). Constants use `ALL_CAPS` with `readonly`. Local variables inside functions always use the `local` keyword.

The critical sourcing pattern uses `BASH_SOURCE` to resolve paths reliably:

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${PROJECT_ROOT}/lib/core/logging.sh"
source "${PROJECT_ROOT}/lib/core/config.sh"
source "${PROJECT_ROOT}/lib/core/checks.sh"
```

Every script in `bin/` follows the Google Style Guide's `main` function pattern — all function definitions at the top, a `main()` function that orchestrates the logic, and `main "$@"` as the last line. Library files in `lib/` are **never** executed directly; they only define functions and variables when sourced. For files that must work both ways, the dual-use guard is `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"`.

## bats-core is the clear choice for testing

After comparing **bats-core** (~5,700 stars, MIT), **shunit2** (~1,700 stars, slow development), **ShellSpec** (~1,300 stars, BDD-style), and **bashunit** (~364 stars, newest), **bats-core dominates on every metric that matters for this use case**: largest community, lowest learning curve, official GitHub Action (`bats-core/bats-action@3.0.1`), and the richest ecosystem of helper libraries.

The three essential helper libraries are **bats-support** (base test helpers), **bats-assert** (assertion functions like `assert_success`, `assert_output`, `assert_line`), and **bats-file** (filesystem assertions like `assert_file_exists`, `assert_dir_exists`). Install these via the official GitHub Action in CI, and via npm or git clone locally.

A well-structured test file for the framework:

```bash
#!/usr/bin/env bats

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    source "$DIR/../lib/core/checks.sh"
}

@test "detect_os identifies Ubuntu correctly" {
    # Mock /etc/os-release
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    echo 'ID=ubuntu' > "$OS_RELEASE_FILE"
    echo 'VERSION_ID="24.04"' >> "$OS_RELEASE_FILE"
    run detect_os
    assert_success
    assert_output --partial "ubuntu"
}

@test "require_commands fails on missing command" {
    run require_commands nonexistent_command_xyz
    assert_failure
    assert_output --partial "Missing"
}
```

The shared test helper (`tests/test_helper/common-setup.bash`) loads libraries and sets up the `PROJECT_ROOT`:

```bash
_common_setup() {
    export BATS_LIB_PATH="${BATS_LIB_PATH:-/usr/lib}"
    bats_load_library bats-support
    bats_load_library bats-assert
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}
```

ShellSpec is the strongest alternative — it offers built-in mocking/stubbing, code coverage via kcov, and multi-shell support — but bats-core's ubiquity and official GitHub Action make it the pragmatic default.

## Structured logging with color and NO_COLOR support

The logging library should implement five levels (**DEBUG, INFO, WARN, ERROR, FATAL**) with convenience wrapper functions, ANSI colorized output, and full compliance with the **NO_COLOR convention** (no-color.org). The design draws from cyberark/bash-lib, bashio, and b-log.

Key architectural decisions for `lib/core/logging.sh`:

- **stderr for WARN/ERROR/FATAL**, stdout for INFO/DEBUG — this prevents log messages from contaminating function return values captured via command substitution
- **Color detection** checks three things in order: `NO_COLOR` env var (disables), `FORCE_COLOR` env var (forces on), and `[[ -t 2 ]]` terminal check (auto-detect)
- **Timestamps** in ISO 8601 format (`date -u '+%Y-%m-%dT%H:%M:%SZ'`)
- **Log level filtering** via `LOG_LEVEL` env var, defaulting to `INFO`
- **Tee to logfile** with `exec > >(tee -a "$LOG_FILE") 2>&1` at script entry when `LOG_FILE` is set

A production-ready logging function:

```bash
setup_colors() {
    if [[ -n "${NO_COLOR:-}" ]]; then
        RED='' GREEN='' YELLOW='' CYAN='' BOLD_RED='' NC='' BOLD=''
    elif [[ -n "${FORCE_COLOR:-}" ]] || [[ -t 2 ]]; then
        RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
        CYAN='\033[0;36m' BOLD_RED='\033[1;31m' NC='\033[0m' BOLD='\033[1m'
    else
        RED='' GREEN='' YELLOW='' CYAN='' BOLD_RED='' NC='' BOLD=''
    fi
}
```

For progress indicators, the spinner pattern runs a background process with braille dot characters (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`), attached to a long-running command's PID. The spinner auto-stops when the command completes. This is useful for `apt-get install` or large file downloads in deployment scripts.

The **fidian/ansi** library (~788 stars) provides the most comprehensive ANSI escape code coverage as a standalone tool, but for a framework template, a self-contained `logging.sh` of ~80 lines is preferable to avoid external dependencies.

## Safe .env configuration with layered loading

The configuration system should support a **three-layer loading strategy**: built-in defaults → `.env.defaults` file → `.env` file → actual environment variables (highest priority). This pattern matches Docker Compose conventions and gives operators maximum flexibility.

**The safe line-by-line parser is strongly recommended over `source .env`** because `source` executes arbitrary shell code, making it a security risk with untrusted input. The safe pattern uses `printf -v` for assignment:

```bash
load_env_file() {
    local env_file="${1:-.env}"
    [[ -f "$env_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        local key="${line%%=*}"
        local value="${line#*=}"
        [[ "$key" == "$line" ]] && continue
        # Strip surrounding quotes
        value="${value#\"}" ; value="${value%\"}"
        value="${value#\'}" ; value="${value%\'}"
        # Only set if not already in environment (env vars take priority)
        if [[ -z "${!key:-}" ]]; then
            printf -v "$key" '%s' "$value"
            export "$key"
        fi
    done < "$env_file"
}
```

For more complex needs, **ko1nksm/shdotenv** is the best dedicated library — it's POSIX-compliant, supports multiple dialects (Docker, Node, Ruby, Python), and parses via awk for safety. However, for a lightweight framework template, the built-in parser above covers **95%** of use cases.

Validation follows a `require_vars` pattern that checks all required variables at once and reports all missing ones:

```bash
require_vars() {
    local missing=()
    for var in "$@"; do
        [[ -z "${!var:-}" ]] && missing+=("$var")
    done
    if (( ${#missing[@]} > 0 )); then
        log_error "Missing required variables: ${missing[*]}"
        return 1
    fi
}
```

Type-specific validators (`is_valid_port`, `is_valid_ip`, `is_true`) live in `lib/core/config.sh` alongside the loader. The `.env.example` file serves as both documentation and a validation reference — a `check_env_completeness` function compares it against the loaded environment.

## GitHub Actions CI with ShellCheck, shfmt, and bats-core

The CI workflow should run three jobs in parallel — **ShellCheck** for static analysis, **shfmt** for formatting consistency, and **bats-core** for testing — with tests gated on linting passing first. ShellCheck comes **pre-installed on GitHub's Ubuntu runners**, so no action setup is needed for basic usage.

The recommended complete workflow:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ludeeus/action-shellcheck@master
        with:
          scandir: './lib'
          severity: warning
          additional_files: 'bin/*'

  shfmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          curl -sSL "https://github.com/mvdan/sh/releases/latest/download/shfmt_linux_amd64" \
            -o /usr/local/bin/shfmt && chmod +x /usr/local/bin/shfmt
      - run: shfmt -d -i 4 -ci .

  test:
    runs-on: ubuntu-latest
    needs: [shellcheck, shfmt]
    steps:
      - uses: actions/checkout@v4
      - id: setup-bats
        uses: bats-core/bats-action@3.0.1
      - run: bats --print-output-on-failure tests/
        env:
          BATS_LIB_PATH: ${{ steps.setup-bats.outputs.lib-path }}
          TERM: xterm
```

The `.shellcheckrc` should enable `source-path=SCRIPTDIR` and `external-sources=true` to handle the modular sourcing pattern without false positives on SC1090/SC1091. The `.editorconfig` configures shfmt: `indent_style = space`, `indent_size = 4`, `shell_variant = bash`.

For PR-level feedback, **reviewdog/action-shellcheck** posts inline comments directly on changed lines — a significant DX improvement over checking CI logs.

## GitHub template repository with self-rewriting bootstrap

Mark the repository as a template in **Settings → Template repository**. When someone clicks "Use this template," they get a clean single-commit copy of all files — no history, no issues, no settings carried over. GitHub Actions workflows **are** included, which enables the key trick: a **self-rewriting bootstrap workflow**.

The bootstrap workflow runs only once in new repos (not in the template itself), reads the new repo's name and description from the GitHub API, and replaces placeholders throughout the project:

```yaml
name: Template Bootstrap
on: [push]
jobs:
  setup:
    if: github.repository != 'yourorg/bash-deploy-template'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - name: Customize template
        env:
          REPO_NAME: ${{ github.event.repository.name }}
          REPO_DESC: ${{ github.event.repository.description }}
          OWNER: ${{ github.repository_owner }}
        run: |
          find . -type f -not -path './.git/*' -exec sed -i \
            -e "s/PROJECTNAME/${REPO_NAME}/g" \
            -e "s/REPO_DESCRIPTION/${REPO_DESC}/g" \
            -e "s/REPO_OWNER/${OWNER}/g" {} +
          rm .github/workflows/template-bootstrap.yml
      - uses: peter-evans/create-pull-request@v6
        with:
          commit-message: "chore: initialize from template"
          branch: template-init
          title: "Initialize project from bash-deploy-template"
```

Using `peter-evans/create-pull-request` instead of a direct force-push works around the limitation that GitHub Actions tokens cannot modify workflow files. The PR approach also gives the user a chance to review the substitutions before merging.

**License choice: MIT.** It maximizes adoption with minimal friction and is the standard for utility scripts and templates. Apache 2.0 is the alternative if patent protection matters.

## Infrastructure scripting patterns for Debian/Ubuntu

Every deployment script should open with the strict-mode header and a cleanup trap:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core/logging.sh"
source "${SCRIPT_DIR}/../lib/core/config.sh"
source "${SCRIPT_DIR}/../lib/core/checks.sh"

cleanup() {
    local exit_code=$?
    [[ -n "${SCRATCH_DIR:-}" ]] && rm -rf "$SCRATCH_DIR"
    [[ -n "${LOCK_FILE:-}" ]] && rm -f "$LOCK_FILE"
    exit "$exit_code"
}
trap cleanup EXIT
```

**Idempotency is the single most important pattern** for deployment scripts. Every function must be safe to run repeatedly. The check-before-act pattern applies everywhere: `dpkg -s "$pkg"` before installing, `id "$user"` before creating, `grep -qF` before appending to files, `systemctl is-enabled` before enabling services. Fatih Arslan's "How to write idempotent Bash scripts" is the canonical reference. Key examples:

- **Packages**: `dpkg -s "$pkg" &>/dev/null || apt-get install -y "$pkg"`
- **Directories**: Always `mkdir -p` (inherently idempotent)
- **Symlinks**: Always `ln -sfn` (force + no-dereference)
- **Firewall rules**: `ufw status | grep -qF "$rule" || ufw $rule`
- **File lines**: `grep -qF "$marker" "$file" || echo "$line" >> "$file"`

**OS detection** parses `/etc/os-release` (the standard since systemd era) rather than `lsb_release` (which requires a separate package). The `detect_os` function sources the file to get `ID`, `VERSION_ID`, and `VERSION_CODENAME`, then validates against supported versions (Ubuntu 22.04/24.04, Debian 11/12). Architecture detection maps `uname -m` output to Debian package names (`x86_64` → `amd64`, `aarch64` → `arm64`).

**Lock files** use `flock` for atomicity: `exec 200>"$LOCK_FILE" && flock -n 200 || exit 1`. The lock auto-releases when the file descriptor closes at script exit — no manual cleanup needed.

**apt-get best practices for scripts**: Always use `apt-get` (not `apt`, which is for interactive use), set `DEBIAN_FRONTEND=noninteractive`, use `-y -qq --no-install-recommends`, and cache the update with a timestamp check to avoid unnecessary re-fetches within the same hour.

**Sudo handling**: Either require root at the top with `[[ $EUID -ne 0 ]] && exec sudo "$0" "$@"` (re-execute with sudo), or use the principle of least privilege by running as a regular user and calling `sudo` only on specific commands that need it. The re-execute pattern is cleaner for deployment scripts that need root throughout.

## Self-documenting Makefile as the task runner

**Make is the right choice for a Bash project template** — it's pre-installed on every target system, every developer expects `make test` and `make lint`, and every CI system supports it natively. The alternatives (`just`, `task`) add a dependency for marginal benefit.

The complete Makefile uses the `##@` section header and `## comment` self-documenting pattern (from marmelab.com) to generate formatted help output:

```makefile
SHELL := /bin/bash
.DEFAULT_GOAL := help

SCRIPTS := $(shell find lib bin -type f -name '*.sh' 2>/dev/null)

##@ Development
.PHONY: lint
lint: ## Run ShellCheck on all scripts
	shellcheck -x $(SCRIPTS)

.PHONY: format
format: ## Format scripts with shfmt
	shfmt -w -i 4 -ci $(SCRIPTS)

.PHONY: format-check
format-check: ## Check formatting without modifying
	shfmt -d -i 4 -ci $(SCRIPTS)

.PHONY: test
test: ## Run bats-core tests
	bats tests/

.PHONY: check
check: lint format-check test ## Run all checks

##@ Helpers
.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS=":.*##";printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/{printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2} \
	/^##@/{printf "\n\033[1m%s\033[0m\n",substr($$0,5)}' $(MAKEFILE_LIST)
```

The `make check` target is the CI meta-target. Locally, `make lint`, `make test`, and `make format` are the most-used commands. `make help` as the default target means running bare `make` shows available commands — essential for discoverability.

## Documentation with shdoc annotations and a structured README

Inline documentation follows a hybrid of the **Google Shell Style Guide** function headers (Globals, Arguments, Outputs, Returns sections) and **shdoc annotations** (`@description`, `@arg`, `@exitcode`, `@stdout`, `@see`). The shdoc tool (~339 stars) generates Markdown API docs from these annotations: `shdoc < lib/core/logging.sh > docs/logging.md`.

A concrete function documentation example:

```bash
# @description Log a message at the specified level with timestamp.
# Respects LOG_LEVEL filtering and NO_COLOR convention.
#
# @arg $1 string Log level (DEBUG|INFO|WARN|ERROR|FATAL)
# @arg $@ string Message to log
#
# @exitcode 0 Always succeeds
#
# @stderr Outputs formatted log message for WARN/ERROR/FATAL
# @stdout Outputs formatted log message for DEBUG/INFO
log() { ... }
```

The README template should include: project name, one-line description, CI badges, prerequisites (Bash 4+, specific tools), quick start with copy-pasteable commands, configuration reference (.env variables), project structure diagram, testing instructions, and contributing guidelines. Placeholder text uses `PROJECTNAME`, `REPO_DESCRIPTION`, and `REPO_OWNER` markers that the bootstrap workflow replaces.

Every `bin/` script implements `--help` via a `usage()` function using a heredoc that covers options, arguments, examples, and environment variables.

## Existing templates worth studying

Five projects serve as the strongest inspiration for this framework:

- **pforret/bashew** (~203 stars) — The only existing GitHub template repo in this space. Generates both standalone scripts and full project scaffolding with CI, tests, and `.env` support. Its auto-generated `--help` from a DSL definition block is clever but adds complexity.
- **kvz/bash3boilerplate** (~2.1k stars) — The "delete-key-friendly" philosophy is excellent: start with everything, remove what you don't need. Its arg-parsing-from-help-text pattern avoids duplication. Targets Bash 3 for portability.
- **xwmx/bash-boilerplate** (~730 stars) — Provides multiple template files at different complexity levels. The "program with subcommands" template is the most sophisticated. Its conventions around explicit naming (`_explicit_variable_name`) and `printf` over `echo` are worth adopting.
- **ralish/bash-script-template** (~900 stars) — Clean single-file template with thorough inline documentation of every design decision. Good model for the `bin/deploy.sh` entry point.
- **natelandau/shell-scripting-templates** (~500 stars) — Has the richest utility function library (arrays, dates, files, strings, logging, OS detection). The three-section architecture (`_mainScript_` → functions → initialization) is a proven pattern.

**None of these are specifically designed for infrastructure/deployment scripts on Debian/Ubuntu**, which is the gap this template fills. The framework should borrow bashew's template-repo approach, b3bp's delete-key-friendly philosophy, and natelandau's rich utility library — but focused entirely on the VM deployment use case.

## Consolidated implementation plan

The template repository should contain **32-40 files** across the structure defined above. Here is the priority-ordered implementation sequence with the key design decisions locked in:

- **Core libraries** (`lib/core/`): logging.sh (~80 lines, 5 levels, NO_COLOR, stderr for errors), config.sh (~100 lines, safe parser, layered loading, validation), checks.sh (~80 lines, OS detection, dependency checking, root check, architecture detection), utils.sh (~100 lines, backup, lock file, template rendering, idempotent file operations)
- **Module libraries** (`lib/modules/`): packages.sh (apt-get wrappers with cache-aware update), firewall.sh (UFW idempotent rules), services.sh (systemd enable/start/verify), network.sh (IP/port validation)
- **Example entry point** (`bin/deploy.sh`): Sources all libs, parses args, calls `main()`, demonstrates the full pattern
- **Testing** (`tests/`): One `.bats` file per library file, shared `common-setup.bash`, minimum 15-20 test cases demonstrating assertions on functions
- **CI** (`.github/workflows/ci.yml`): Three parallel jobs (shellcheck, shfmt, bats) with the exact YAML shown above
- **Template bootstrap** (`.github/workflows/template-bootstrap.yml`): Self-rewriting PR workflow
- **Makefile**: Self-documenting with help, lint, format, test, check targets
- **Configuration**: `.shellcheckrc` (source-path, external-sources), `.editorconfig` (4-space indent, bash variant), `.gitignore` (`.env`, `*.log`, `tmp/`)
- **Documentation**: README.md with placeholders, `docs/` for generated API docs, `.env.example` with every variable documented
- **Metadata**: LICENSE (MIT), CHANGELOG.md, issue/PR templates

The framework's **guiding principle is practical minimalism** — every file earns its place by solving a real problem that comes up when deploying services on Debian/Ubuntu VMs. No OOP abstractions, no exotic Bash features, no external dependencies beyond ShellCheck and bats-core for development. The target user should be able to clone, rename, delete the modules they don't need, add their deployment logic to `bin/deploy.sh`, and ship within an hour.