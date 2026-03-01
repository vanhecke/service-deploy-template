# Bash Deploy Template Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reusable Bash framework as a GitHub template repository for scaffolding Debian/Ubuntu VM deployment projects.

**Architecture:** Modular `bin/` + `lib/` layout with `::` namespaced functions. Core libraries (logging, config, checks, utils) provide the foundation; module libraries (packages, firewall, services, network) provide domain-specific deployment primitives. Entry-point scripts in `bin/` source libraries and follow a `main()` orchestration pattern with strict mode.

**Tech Stack:** Bash 4+, bats-core (testing), ShellCheck (linting), shfmt (formatting), GNU Make (task runner), GitHub Actions (CI)

**Reference:** All design decisions and code patterns are documented in `research.md` at project root.

---

### Task 1: Project scaffolding — config files and directory structure

**Files:**
- Create: `.editorconfig`
- Create: `.gitignore`
- Create: `.shellcheckrc`
- Create: `etc/.env.example`
- Create: `etc/templates/.gitkeep`
- Create: `tests/test_helper/common-setup.bash`

**Step 1: Create `.editorconfig`**

```ini
root = true

[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
trim_trailing_whitespace = true

[*.sh]
indent_style = space
indent_size = 4
shell_variant = bash

[*.bash]
indent_style = space
indent_size = 4
shell_variant = bash

[*.bats]
indent_style = space
indent_size = 4

[Makefile]
indent_style = tab
indent_size = 4

[*.{yml,yaml}]
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false
```

**Step 2: Create `.gitignore`**

```
.env
*.log
tmp/
.scratch/
*.swp
*.swo
*~
.DS_Store
```

**Step 3: Create `.shellcheckrc`**

```
source-path=SCRIPTDIR
external-sources=true
```

**Step 4: Create `etc/.env.example`**

```bash
# PROJECTNAME Configuration
# Copy to .env and adjust values

# Deploy target
DEPLOY_USER=deploy
DEPLOY_HOST=example.com

# Application
APP_NAME=PROJECTNAME
APP_PORT=8080
APP_ENV=production

# Logging
LOG_LEVEL=INFO
# LOG_FILE=/var/log/PROJECTNAME/deploy.log

# Firewall
FIREWALL_ENABLED=true
ALLOWED_PORTS="22 80 443"

# Packages (space-separated)
EXTRA_PACKAGES=""
```

**Step 5: Create directories with placeholders**

```bash
mkdir -p etc/templates && touch etc/templates/.gitkeep
mkdir -p tests/test_helper
mkdir -p lib/core lib/modules
mkdir -p bin
mkdir -p docs
mkdir -p .github/workflows .github/ISSUE_TEMPLATE
```

**Step 6: Create `tests/test_helper/common-setup.bash`**

```bash
#!/usr/bin/env bash

_common_setup() {
    export BATS_LIB_PATH="${BATS_LIB_PATH:-/usr/lib}"
    bats_load_library bats-support
    bats_load_library bats-assert
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PROJECT_ROOT
    export NO_COLOR=1
}
```

**Step 7: Commit**

```bash
git add .editorconfig .gitignore .shellcheckrc etc/ tests/test_helper/ lib/ bin/ docs/ .github/
git commit -m "feat: add project scaffolding and config files"
```

---

### Task 2: Core library — `lib/core/logging.sh`

**Files:**
- Create: `lib/core/logging.sh`
- Create: `tests/logging.bats`

**Step 1: Write `lib/core/logging.sh`**

```bash
#!/usr/bin/env bash
# @description Structured logging with 5 levels, NO_COLOR support, timestamps.
# @see https://no-color.org/

# Guard against double-sourcing
[[ -n "${_LOGGING_SH_LOADED:-}" ]] && return 0
readonly _LOGGING_SH_LOADED=1

# Log level constants (lower = more verbose)
declare -gA _LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [FATAL]=4)

# @description Initialize ANSI color variables based on NO_COLOR, FORCE_COLOR, and terminal detection.
logging::setup_colors() {
    if [[ -n "${NO_COLOR:-}" ]]; then
        RED='' GREEN='' YELLOW='' CYAN='' BOLD_RED='' NC='' BOLD=''
    elif [[ -n "${FORCE_COLOR:-}" ]] || [[ -t 2 ]]; then
        RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
        CYAN='\033[0;36m' BOLD_RED='\033[1;31m' NC='\033[0m' BOLD='\033[1m'
    else
        RED='' GREEN='' YELLOW='' CYAN='' BOLD_RED='' NC='' BOLD=''
    fi
}

# @description Log a message at the specified level with ISO 8601 timestamp.
#
# @arg $1 string Log level (DEBUG|INFO|WARN|ERROR|FATAL)
# @arg $@ string Message to log
#
# @exitcode 0 Always succeeds
# @stderr WARN/ERROR/FATAL messages
# @stdout DEBUG/INFO messages
logging::log() {
    local level="${1:?Missing log level}"
    shift
    local message="$*"

    local current_level="${LOG_LEVEL:-INFO}"
    local level_num="${_LOG_LEVELS[$level]:-1}"
    local current_num="${_LOG_LEVELS[$current_level]:-1}"

    # Filter by log level
    (( level_num < current_num )) && return 0

    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    local color=""
    case "$level" in
        DEBUG) color="${CYAN:-}" ;;
        INFO)  color="${GREEN:-}" ;;
        WARN)  color="${YELLOW:-}" ;;
        ERROR) color="${RED:-}" ;;
        FATAL) color="${BOLD_RED:-}" ;;
    esac

    local formatted
    formatted="${color}[${timestamp}] [${level}]${NC:-} ${message}"

    # WARN/ERROR/FATAL go to stderr; DEBUG/INFO go to stdout
    if (( level_num >= 2 )); then
        printf '%b\n' "$formatted" >&2
    else
        printf '%b\n' "$formatted"
    fi
}

# @description Convenience wrappers for each log level.
logging::debug() { logging::log DEBUG "$@"; }
logging::info()  { logging::log INFO  "$@"; }
logging::warn()  { logging::log WARN  "$@"; }
logging::error() { logging::log ERROR "$@"; }
logging::fatal() { logging::log FATAL "$@"; exit 1; }

# Initialize colors on source
logging::setup_colors
```

**Step 2: Write `tests/logging.bats`**

```bash
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
```

**Step 3: Commit**

```bash
git add lib/core/logging.sh tests/logging.bats
git commit -m "feat: add structured logging library with tests"
```

---

### Task 3: Core library — `lib/core/config.sh`

**Files:**
- Create: `lib/core/config.sh`
- Create: `tests/config.bats`

**Step 1: Write `lib/core/config.sh`**

```bash
#!/usr/bin/env bash
# @description Safe .env configuration loading with layered strategy and validation.
# Loading priority: defaults → .env.defaults → .env → environment variables (highest).

[[ -n "${_CONFIG_SH_LOADED:-}" ]] && return 0
readonly _CONFIG_SH_LOADED=1

# @description Load a .env file safely using line-by-line parsing.
# Skips comments, blank lines, and lines without '='.
# Does NOT override existing environment variables.
#
# @arg $1 string Path to env file (default: .env)
# @exitcode 0 Always succeeds (missing file is not an error)
config::load_env_file() {
    local env_file="${1:-.env}"
    [[ -f "$env_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        local key="${line%%=*}"
        local value="${line#*=}"
        # Skip lines without =
        [[ "$key" == "$line" ]] && continue
        # Trim leading/trailing whitespace from key
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        # Strip surrounding quotes from value
        value="${value#\"}" ; value="${value%\"}"
        value="${value#\'}" ; value="${value%\'}"
        # Only set if not already in environment
        if [[ -z "${!key:-}" ]]; then
            printf -v "$key" '%s' "$value"
            export "$key"
        fi
    done < "$env_file"
}

# @description Load configuration with layered strategy.
# Order: .env.defaults → .env (both relative to provided dir or PROJECT_ROOT)
#
# @arg $1 string Config directory (default: PROJECT_ROOT/etc or .)
config::load() {
    local config_dir="${1:-${PROJECT_ROOT:-.}/etc}"
    config::load_env_file "${config_dir}/.env.defaults"
    config::load_env_file "${config_dir}/.env"
}

# @description Validate that all required variables are set.
#
# @arg $@ string Variable names to check
# @exitcode 0 All variables are set
# @exitcode 1 One or more variables are missing
config::require_vars() {
    local missing=()
    for var in "$@"; do
        [[ -z "${!var:-}" ]] && missing+=("$var")
    done
    if (( ${#missing[@]} > 0 )); then
        printf 'Missing required variables: %s\n' "${missing[*]}" >&2
        return 1
    fi
}

# @description Check if a value is truthy (true, 1, yes, on).
#
# @arg $1 string Value to check
# @exitcode 0 Value is truthy
# @exitcode 1 Value is falsy
config::is_true() {
    local val="${1,,}" # lowercase
    [[ "$val" =~ ^(true|1|yes|on)$ ]]
}

# @description Validate a port number (1-65535).
#
# @arg $1 string Port to validate
# @exitcode 0 Valid port
# @exitcode 1 Invalid port
config::is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}
```

**Step 2: Write `tests/config.bats`**

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/config.sh"
}

@test "config::load_env_file loads key=value pairs" {
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf 'MY_VAR=hello\n' > "$env_file"
    unset MY_VAR
    config::load_env_file "$env_file"
    [[ "$MY_VAR" == "hello" ]]
}

@test "config::load_env_file skips comments" {
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf '# this is a comment\nVALID_VAR=yes\n' > "$env_file"
    unset VALID_VAR
    config::load_env_file "$env_file"
    [[ "$VALID_VAR" == "yes" ]]
}

@test "config::load_env_file skips blank lines" {
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf '\n\nSOME_VAR=value\n\n' > "$env_file"
    unset SOME_VAR
    config::load_env_file "$env_file"
    [[ "$SOME_VAR" == "value" ]]
}

@test "config::load_env_file strips quotes" {
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf 'QUOTED="hello world"\n' > "$env_file"
    unset QUOTED
    config::load_env_file "$env_file"
    [[ "$QUOTED" == "hello world" ]]
}

@test "config::load_env_file does not override existing env vars" {
    export EXISTING_VAR="original"
    local env_file="$BATS_TEST_TMPDIR/test.env"
    printf 'EXISTING_VAR=overwritten\n' > "$env_file"
    config::load_env_file "$env_file"
    [[ "$EXISTING_VAR" == "original" ]]
}

@test "config::load_env_file returns 0 for missing file" {
    run config::load_env_file "/nonexistent/path/.env"
    assert_success
}

@test "config::require_vars succeeds when all vars set" {
    export REQ_A="a" REQ_B="b"
    run config::require_vars REQ_A REQ_B
    assert_success
}

@test "config::require_vars fails and lists missing vars" {
    unset MISSING_X MISSING_Y 2>/dev/null || true
    run config::require_vars MISSING_X MISSING_Y
    assert_failure
    assert_output --partial "MISSING_X"
    assert_output --partial "MISSING_Y"
}

@test "config::is_true accepts truthy values" {
    config::is_true "true"
    config::is_true "1"
    config::is_true "yes"
    config::is_true "on"
    config::is_true "TRUE"
}

@test "config::is_true rejects falsy values" {
    ! config::is_true "false"
    ! config::is_true "0"
    ! config::is_true "no"
    ! config::is_true ""
}

@test "config::is_valid_port accepts valid ports" {
    config::is_valid_port 80
    config::is_valid_port 443
    config::is_valid_port 65535
    config::is_valid_port 1
}

@test "config::is_valid_port rejects invalid ports" {
    ! config::is_valid_port 0
    ! config::is_valid_port 65536
    ! config::is_valid_port "abc"
    ! config::is_valid_port ""
}
```

**Step 3: Commit**

```bash
git add lib/core/config.sh tests/config.bats
git commit -m "feat: add safe .env config loader with tests"
```

---

### Task 4: Core library — `lib/core/checks.sh`

**Files:**
- Create: `lib/core/checks.sh`
- Create: `tests/checks.bats`

**Step 1: Write `lib/core/checks.sh`**

```bash
#!/usr/bin/env bash
# @description OS detection, dependency checking, root verification, architecture detection.

[[ -n "${_CHECKS_SH_LOADED:-}" ]] && return 0
readonly _CHECKS_SH_LOADED=1

# @description Detect the OS by parsing /etc/os-release.
# Sets global variables: OS_ID, OS_VERSION_ID, OS_CODENAME
#
# @exitcode 0 Supported OS detected
# @exitcode 1 Unsupported or undetectable OS
checks::detect_os() {
    local release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ ! -f "$release_file" ]]; then
        printf 'Cannot detect OS: %s not found\n' "$release_file" >&2
        return 1
    fi

    # Parse key=value pairs safely (no sourcing)
    local id="" version_id="" codename=""
    while IFS='=' read -r key value; do
        value="${value#\"}" ; value="${value%\"}"
        case "$key" in
            ID) id="$value" ;;
            VERSION_ID) version_id="$value" ;;
            VERSION_CODENAME) codename="$value" ;;
        esac
    done < "$release_file"

    OS_ID="$id"
    OS_VERSION_ID="$version_id"
    OS_CODENAME="$codename"
    export OS_ID OS_VERSION_ID OS_CODENAME

    # Validate supported OS
    case "$id" in
        ubuntu|debian) ;;
        *)
            printf 'Unsupported OS: %s\n' "$id" >&2
            return 1
            ;;
    esac

    printf '%s %s (%s)\n' "$id" "$version_id" "$codename"
}

# @description Detect CPU architecture and map to Debian package naming.
# Sets global variable: OS_ARCH
#
# @stdout Architecture name (amd64, arm64, etc.)
checks::detect_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64)  OS_ARCH="amd64" ;;
        aarch64) OS_ARCH="arm64" ;;
        armv7l)  OS_ARCH="armhf" ;;
        *)       OS_ARCH="$machine" ;;
    esac
    export OS_ARCH
    printf '%s\n' "$OS_ARCH"
}

# @description Check that all required commands are available in PATH.
#
# @arg $@ string Command names to check
# @exitcode 0 All commands available
# @exitcode 1 One or more commands missing
checks::require_commands() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        printf 'Missing required commands: %s\n' "${missing[*]}" >&2
        return 1
    fi
}

# @description Verify the script is running as root.
#
# @exitcode 0 Running as root
# @exitcode 1 Not running as root
checks::require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        printf 'This script must be run as root\n' >&2
        return 1
    fi
}

# @description Verify minimum Bash version.
#
# @arg $1 int Minimum major version (default: 4)
# @exitcode 0 Version meets requirement
# @exitcode 1 Version too old
checks::require_bash_version() {
    local min_version="${1:-4}"
    if (( BASH_VERSINFO[0] < min_version )); then
        printf 'Bash %s+ required, found %s\n' "$min_version" "$BASH_VERSION" >&2
        return 1
    fi
}
```

**Step 2: Write `tests/checks.bats`**

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/checks.sh"
}

@test "checks::detect_os identifies Ubuntu" {
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    cat > "$OS_RELEASE_FILE" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
EOF
    run checks::detect_os
    assert_success
    assert_output --partial "ubuntu"
    assert_output --partial "24.04"
}

@test "checks::detect_os identifies Debian" {
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    cat > "$OS_RELEASE_FILE" <<'EOF'
ID=debian
VERSION_ID="12"
VERSION_CODENAME=bookworm
EOF
    run checks::detect_os
    assert_success
    assert_output --partial "debian"
}

@test "checks::detect_os rejects unsupported OS" {
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    printf 'ID=fedora\nVERSION_ID="39"\n' > "$OS_RELEASE_FILE"
    run checks::detect_os
    assert_failure
    assert_output --partial "Unsupported"
}

@test "checks::detect_os fails when file missing" {
    export OS_RELEASE_FILE="/nonexistent/os-release"
    run checks::detect_os
    assert_failure
    assert_output --partial "not found"
}

@test "checks::detect_arch returns a value" {
    run checks::detect_arch
    assert_success
    assert_output --regexp '^(amd64|arm64|armhf|.+)$'
}

@test "checks::require_commands succeeds for available commands" {
    run checks::require_commands bash cat
    assert_success
}

@test "checks::require_commands fails for missing commands" {
    run checks::require_commands nonexistent_command_xyz
    assert_failure
    assert_output --partial "Missing"
    assert_output --partial "nonexistent_command_xyz"
}

@test "checks::require_bash_version passes for current bash" {
    run checks::require_bash_version 4
    assert_success
}

@test "checks::require_bash_version fails for impossibly high version" {
    run checks::require_bash_version 999
    assert_failure
}
```

**Step 3: Commit**

```bash
git add lib/core/checks.sh tests/checks.bats
git commit -m "feat: add OS detection and dependency checks with tests"
```

---

### Task 5: Core library — `lib/core/utils.sh`

**Files:**
- Create: `lib/core/utils.sh`
- Create: `tests/utils.bats`

**Step 1: Write `lib/core/utils.sh`**

```bash
#!/usr/bin/env bash
# @description Common utilities: backup, lock file, template rendering, idempotent file ops.

[[ -n "${_UTILS_SH_LOADED:-}" ]] && return 0
readonly _UTILS_SH_LOADED=1

# @description Create a timestamped backup of a file.
#
# @arg $1 string File path to back up
# @exitcode 0 Backup created (or source doesn't exist)
# @exitcode 1 Backup failed
utils::backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local backup="${file}.backup.$(date '+%Y%m%d%H%M%S')"
    cp -a "$file" "$backup"
    printf '%s\n' "$backup"
}

# @description Acquire an exclusive lock file using flock.
#
# @arg $1 string Lock file path
# @exitcode 0 Lock acquired
# @exitcode 1 Lock already held
utils::acquire_lock() {
    local lock_file="$1"
    LOCK_FILE="$lock_file"
    exec 200>"$lock_file"
    if ! flock -n 200; then
        printf 'Cannot acquire lock: %s\n' "$lock_file" >&2
        return 1
    fi
}

# @description Render a template file by substituting environment variables via envsubst.
#
# @arg $1 string Template file path
# @arg $2 string Output file path
# @exitcode 0 Template rendered
# @exitcode 1 Template file not found
utils::render_template() {
    local template="$1"
    local output="$2"
    if [[ ! -f "$template" ]]; then
        printf 'Template not found: %s\n' "$template" >&2
        return 1
    fi
    envsubst < "$template" > "$output"
}

# @description Idempotently ensure a line exists in a file.
# Uses a marker string to check presence.
#
# @arg $1 string File path
# @arg $2 string Line to add
# @arg $3 string Marker to search for (default: same as line)
utils::ensure_line() {
    local file="$1"
    local line="$2"
    local marker="${3:-$line}"
    [[ -f "$file" ]] || touch "$file"
    grep -qF "$marker" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

# @description Create a directory idempotently with optional ownership.
#
# @arg $1 string Directory path
# @arg $2 string Owner:group (optional)
# @arg $3 string Permissions mode (optional, e.g., 0755)
utils::ensure_dir() {
    local dir="$1"
    local owner="${2:-}"
    local mode="${3:-}"
    mkdir -p "$dir"
    [[ -n "$owner" ]] && chown "$owner" "$dir"
    [[ -n "$mode" ]] && chmod "$mode" "$dir"
}

# @description Create a symlink idempotently.
#
# @arg $1 string Link target
# @arg $2 string Link name
utils::ensure_symlink() {
    local target="$1"
    local link_name="$2"
    ln -sfn "$target" "$link_name"
}
```

**Step 2: Write `tests/utils.bats`**

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/lib/core/utils.sh"
}

@test "utils::backup_file creates backup with timestamp" {
    local original="$BATS_TEST_TMPDIR/myfile.conf"
    printf 'content' > "$original"
    run utils::backup_file "$original"
    assert_success
    # Output is the backup path
    assert_output --regexp '\.backup\.[0-9]{14}$'
    # Backup file exists
    [[ -f "$(echo "$output")" ]]
}

@test "utils::backup_file returns 0 for missing file" {
    run utils::backup_file "/nonexistent/file"
    assert_success
}

@test "utils::ensure_line adds missing line" {
    local file="$BATS_TEST_TMPDIR/lines.txt"
    printf 'existing line\n' > "$file"
    utils::ensure_line "$file" "new line"
    grep -qF "new line" "$file"
}

@test "utils::ensure_line is idempotent" {
    local file="$BATS_TEST_TMPDIR/lines.txt"
    printf 'existing line\n' > "$file"
    utils::ensure_line "$file" "new line"
    utils::ensure_line "$file" "new line"
    local count
    count=$(grep -cF "new line" "$file")
    [[ "$count" -eq 1 ]]
}

@test "utils::ensure_line creates file if missing" {
    local file="$BATS_TEST_TMPDIR/new_file.txt"
    utils::ensure_line "$file" "first line"
    [[ -f "$file" ]]
    grep -qF "first line" "$file"
}

@test "utils::ensure_dir creates directory" {
    local dir="$BATS_TEST_TMPDIR/newdir/subdir"
    utils::ensure_dir "$dir"
    [[ -d "$dir" ]]
}

@test "utils::ensure_symlink creates symlink" {
    local target="$BATS_TEST_TMPDIR/target_file"
    local link="$BATS_TEST_TMPDIR/my_link"
    printf 'data' > "$target"
    utils::ensure_symlink "$target" "$link"
    [[ -L "$link" ]]
    [[ "$(readlink "$link")" == "$target" ]]
}

@test "utils::ensure_symlink is idempotent" {
    local target="$BATS_TEST_TMPDIR/target_file"
    local link="$BATS_TEST_TMPDIR/my_link"
    printf 'data' > "$target"
    utils::ensure_symlink "$target" "$link"
    utils::ensure_symlink "$target" "$link"
    [[ -L "$link" ]]
}

@test "utils::render_template substitutes env vars" {
    local template="$BATS_TEST_TMPDIR/template.conf"
    local output="$BATS_TEST_TMPDIR/output.conf"
    export MY_SETTING="hello"
    printf 'value=${MY_SETTING}\n' > "$template"
    utils::render_template "$template" "$output"
    grep -qF "value=hello" "$output"
}

@test "utils::render_template fails for missing template" {
    run utils::render_template "/nonexistent/template" "/tmp/out"
    assert_failure
    assert_output --partial "not found"
}
```

**Step 3: Commit**

```bash
git add lib/core/utils.sh tests/utils.bats
git commit -m "feat: add utility functions with tests"
```

---

### Task 6: Module libraries — `lib/modules/`

**Files:**
- Create: `lib/modules/packages.sh`
- Create: `lib/modules/firewall.sh`
- Create: `lib/modules/services.sh`
- Create: `lib/modules/network.sh`

**Step 1: Write `lib/modules/packages.sh`**

```bash
#!/usr/bin/env bash
# @description apt-get wrappers with idempotent installs and cache-aware updates.

[[ -n "${_PACKAGES_SH_LOADED:-}" ]] && return 0
readonly _PACKAGES_SH_LOADED=1

readonly _APT_CACHE_MAX_AGE=3600 # 1 hour in seconds

# @description Update apt cache if older than _APT_CACHE_MAX_AGE.
packages::update_cache() {
    local stamp="/var/lib/apt/periodic/update-success-stamp"
    local now
    now="$(date +%s)"
    if [[ -f "$stamp" ]]; then
        local last
        last="$(stat -c %Y "$stamp" 2>/dev/null || stat -f %m "$stamp" 2>/dev/null)"
        if (( now - last < _APT_CACHE_MAX_AGE )); then
            return 0
        fi
    fi
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
}

# @description Install packages idempotently.
#
# @arg $@ string Package names to install
packages::install() {
    local to_install=()
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        fi
    done
    if (( ${#to_install[@]} > 0 )); then
        packages::update_cache
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${to_install[@]}"
    fi
}

# @description Check if a package is installed.
#
# @arg $1 string Package name
# @exitcode 0 Installed
# @exitcode 1 Not installed
packages::is_installed() {
    dpkg -s "$1" &>/dev/null
}

# @description Remove packages.
#
# @arg $@ string Package names to remove
packages::remove() {
    local to_remove=()
    for pkg in "$@"; do
        if dpkg -s "$pkg" &>/dev/null; then
            to_remove+=("$pkg")
        fi
    done
    if (( ${#to_remove[@]} > 0 )); then
        DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "${to_remove[@]}"
    fi
}
```

**Step 2: Write `lib/modules/firewall.sh`**

```bash
#!/usr/bin/env bash
# @description UFW firewall rule management with idempotent operations.

[[ -n "${_FIREWALL_SH_LOADED:-}" ]] && return 0
readonly _FIREWALL_SH_LOADED=1

# @description Enable UFW with default deny incoming.
firewall::enable() {
    if ! ufw status | grep -qF "active"; then
        ufw default deny incoming
        ufw default allow outgoing
        ufw --force enable
    fi
}

# @description Allow a port through UFW idempotently.
#
# @arg $1 string Port number or service name
# @arg $2 string Protocol (tcp/udp, default: tcp)
firewall::allow_port() {
    local port="$1"
    local proto="${2:-tcp}"
    local rule="${port}/${proto}"
    if ! ufw status | grep -qF "$rule"; then
        ufw allow "$rule"
    fi
}

# @description Allow multiple ports.
#
# @arg $@ string Port numbers (space-separated)
firewall::allow_ports() {
    for port in "$@"; do
        firewall::allow_port "$port"
    done
}

# @description Deny a port through UFW.
#
# @arg $1 string Port number
# @arg $2 string Protocol (default: tcp)
firewall::deny_port() {
    local port="$1"
    local proto="${2:-tcp}"
    ufw deny "${port}/${proto}"
}
```

**Step 3: Write `lib/modules/services.sh`**

```bash
#!/usr/bin/env bash
# @description systemd service management helpers.

[[ -n "${_SERVICES_SH_LOADED:-}" ]] && return 0
readonly _SERVICES_SH_LOADED=1

# @description Enable and start a systemd service idempotently.
#
# @arg $1 string Service name
services::enable_and_start() {
    local service="$1"
    if ! systemctl is-enabled "$service" &>/dev/null; then
        systemctl enable "$service"
    fi
    if ! systemctl is-active "$service" &>/dev/null; then
        systemctl start "$service"
    fi
}

# @description Restart a service.
#
# @arg $1 string Service name
services::restart() {
    systemctl restart "$1"
}

# @description Reload a service configuration.
#
# @arg $1 string Service name
services::reload() {
    systemctl reload "$1"
}

# @description Check if a service is active.
#
# @arg $1 string Service name
# @exitcode 0 Active
# @exitcode 1 Not active
services::is_active() {
    systemctl is-active "$1" &>/dev/null
}

# @description Reload the systemd daemon after unit file changes.
services::daemon_reload() {
    systemctl daemon-reload
}
```

**Step 4: Write `lib/modules/network.sh`**

```bash
#!/usr/bin/env bash
# @description IP validation, port checking, and DNS helpers.

[[ -n "${_NETWORK_SH_LOADED:-}" ]] && return 0
readonly _NETWORK_SH_LOADED=1

# @description Validate an IPv4 address.
#
# @arg $1 string IP address
# @exitcode 0 Valid IPv4
# @exitcode 1 Invalid
network::is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        (( octet <= 255 )) || return 1
    done
}

# @description Check if a TCP port is open on a host.
#
# @arg $1 string Host
# @arg $2 int Port
# @arg $3 int Timeout in seconds (default: 3)
# @exitcode 0 Port is open
# @exitcode 1 Port is closed or timeout
network::is_port_open() {
    local host="$1"
    local port="$2"
    local timeout="${3:-3}"
    timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
}

# @description Wait for a port to become available.
#
# @arg $1 string Host
# @arg $2 int Port
# @arg $3 int Max wait time in seconds (default: 30)
# @exitcode 0 Port became available
# @exitcode 1 Timeout
network::wait_for_port() {
    local host="$1"
    local port="$2"
    local max_wait="${3:-30}"
    local elapsed=0
    while (( elapsed < max_wait )); do
        network::is_port_open "$host" "$port" 1 && return 0
        sleep 1
        (( elapsed++ ))
    done
    return 1
}

# @description Get the primary local IP address.
#
# @stdout IP address
network::get_local_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}'
}
```

**Step 5: Commit**

```bash
git add lib/modules/
git commit -m "feat: add module libraries for packages, firewall, services, network"
```

---

### Task 7: Entry point — `bin/deploy.sh`

**Files:**
- Create: `bin/deploy.sh`

**Step 1: Write `bin/deploy.sh`**

```bash
#!/usr/bin/env bash
# PROJECTNAME — REPO_DESCRIPTION
#
# Usage: ./bin/deploy.sh [options]
#
# Options:
#   -h, --help       Show this help message
#   -v, --verbose    Enable debug logging
#   -n, --dry-run    Show what would be done without making changes
#   -c, --config     Path to config directory (default: etc/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core libraries
source "${PROJECT_ROOT}/lib/core/logging.sh"
source "${PROJECT_ROOT}/lib/core/config.sh"
source "${PROJECT_ROOT}/lib/core/checks.sh"
source "${PROJECT_ROOT}/lib/core/utils.sh"

# Source module libraries
source "${PROJECT_ROOT}/lib/modules/packages.sh"
source "${PROJECT_ROOT}/lib/modules/firewall.sh"
source "${PROJECT_ROOT}/lib/modules/services.sh"
source "${PROJECT_ROOT}/lib/modules/network.sh"

# Globals
DRY_RUN=false
CONFIG_DIR="${PROJECT_ROOT}/etc"

cleanup() {
    local exit_code=$?
    [[ -n "${SCRATCH_DIR:-}" ]] && rm -rf "$SCRATCH_DIR"
    [[ -n "${LOCK_FILE:-}" ]] && rm -f "$LOCK_FILE"
    exit "$exit_code"
}
trap cleanup EXIT

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

PROJECTNAME deploy script.
REPO_DESCRIPTION

Options:
    -h, --help       Show this help message
    -v, --verbose    Enable debug logging
    -n, --dry-run    Show what would be done without making changes
    -c, --config     Path to config directory (default: etc/)

Environment Variables:
    APP_NAME         Application name
    APP_PORT         Application port (default: 8080)
    LOG_LEVEL        Log level: DEBUG|INFO|WARN|ERROR|FATAL (default: INFO)
    LOG_FILE         Path to log file (optional, logs to file when set)

Examples:
    $(basename "$0")                  # Deploy with default config
    $(basename "$0") -v               # Deploy with debug logging
    $(basename "$0") -n               # Dry run
    $(basename "$0") -c /etc/myapp    # Custom config directory
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -v | --verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            -n | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -c | --config)
                CONFIG_DIR="$2"
                shift 2
                ;;
            *)
                logging::error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    logging::info "Starting PROJECTNAME deployment"

    # Load configuration
    config::load "$CONFIG_DIR"
    config::require_vars APP_NAME

    # Preflight checks
    checks::require_bash_version 4
    checks::detect_os
    checks::detect_arch
    logging::info "Detected OS: ${OS_ID} ${OS_VERSION_ID} (${OS_ARCH})"

    if [[ "$DRY_RUN" == true ]]; then
        logging::info "[DRY RUN] Would deploy ${APP_NAME}"
        exit 0
    fi

    # --- Add your deployment steps below ---
    #
    # Example:
    #   checks::require_root
    #   packages::install curl wget unzip
    #   firewall::enable
    #   firewall::allow_ports 22 80 443 "${APP_PORT:-8080}"
    #   services::enable_and_start your-service
    #
    # --- End deployment steps ---

    logging::info "PROJECTNAME deployment complete"
}

main "$@"
```

**Step 2: Make executable**

```bash
chmod +x bin/deploy.sh
```

**Step 3: Commit**

```bash
git add bin/deploy.sh
git commit -m "feat: add example deploy entry-point script"
```

---

### Task 8: Makefile

**Files:**
- Create: `Makefile`

**Step 1: Write `Makefile`**

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
	bats --print-output-on-failure tests/

.PHONY: check
check: lint format-check test ## Run all checks (CI target)

##@ Helpers
.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS=":.*##";printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/{printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2} \
	/^##@/{printf "\n\033[1m%s\033[0m\n",substr($$0,5)}' $(MAKEFILE_LIST)
```

**Step 2: Commit**

```bash
git add Makefile
git commit -m "feat: add self-documenting Makefile"
```

---

### Task 9: GitHub Actions CI and template bootstrap

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/template-bootstrap.yml`

**Step 1: Write `.github/workflows/ci.yml`**

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

**Step 2: Write `.github/workflows/template-bootstrap.yml`**

```yaml
name: Template Bootstrap
on: [push]
jobs:
  setup:
    if: github.repository != 'REPO_OWNER/PROJECTNAME'
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
            -e "s/REPO_DESCRIPTION/${REPO_DESC:-A deployment script}/g" \
            -e "s/REPO_OWNER/${OWNER}/g" {} +
          rm .github/workflows/template-bootstrap.yml
      - uses: peter-evans/create-pull-request@v6
        with:
          commit-message: "chore: initialize from template"
          branch: template-init
          title: "Initialize project from bash-deploy-template"
          body: |
            This PR was auto-generated by the template bootstrap workflow.
            It replaces placeholder values with your repository details.
```

**Step 3: Commit**

```bash
git add .github/workflows/
git commit -m "feat: add CI workflow and template bootstrap"
```

---

### Task 10: GitHub templates (issue/PR)

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`

**Step 1: Write `.github/ISSUE_TEMPLATE/bug_report.md`**

```markdown
---
name: Bug report
about: Report a problem with the deployment scripts
labels: bug
---

## Describe the bug

A clear description of what went wrong.

## To reproduce

1. Run '...'
2. See error

## Expected behavior

What you expected to happen.

## Environment

- OS: [e.g., Ubuntu 24.04]
- Bash version: [e.g., 5.2]
- Script: [e.g., bin/deploy.sh]

## Logs

```
Paste relevant log output here
```
```

**Step 2: Write `.github/PULL_REQUEST_TEMPLATE.md`**

```markdown
## Summary

Brief description of changes.

## Changes

- ...

## Testing

- [ ] `make check` passes
- [ ] Tested on target OS

## Notes

Any additional context.
```

**Step 3: Commit**

```bash
git add .github/ISSUE_TEMPLATE/ .github/PULL_REQUEST_TEMPLATE.md
git commit -m "feat: add GitHub issue and PR templates"
```

---

### Task 11: Documentation and metadata

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `CHANGELOG.md`

**Step 1: Write `README.md`**

```markdown
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
```

**Step 2: Write `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 REPO_OWNER

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Step 3: Write `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Core libraries: logging, config, checks, utils
- Module libraries: packages, firewall, services, network
- Example deploy script (`bin/deploy.sh`)
- bats-core test suite
- CI workflow (ShellCheck, shfmt, bats-core)
- Template bootstrap workflow
- Self-documenting Makefile
```

**Step 4: Commit**

```bash
git add README.md LICENSE CHANGELOG.md
git commit -m "feat: add README, LICENSE, and CHANGELOG"
```

---

### Task 12: Verify everything works together

**Step 1: Check ShellCheck passes**

Run: `make lint`
Expected: No errors

**Step 2: Check shfmt formatting**

Run: `make format-check`
Expected: No diffs

**Step 3: Run tests (requires bats-core installed)**

Run: `make test`
Expected: All tests pass

**Step 4: Verify deploy script help**

Run: `./bin/deploy.sh --help`
Expected: Usage information printed

**Step 5: Verify dry run**

Run: `./bin/deploy.sh -n`
Expected: Dry run message, no changes made

**Step 6: Final commit if any formatting fixes needed**

```bash
make format
git add -A
git commit -m "fix: apply shfmt formatting"
```
