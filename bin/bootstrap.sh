#!/usr/bin/env bash
# @description Bootstrap script for getting the deploy tool onto a box.
#
# Usage: curl -fsSL https://raw.githubusercontent.com/REPO_OWNER/PROJECTNAME/main/bin/bootstrap.sh | bash
#   or:  wget -qO- https://raw.githubusercontent.com/REPO_OWNER/PROJECTNAME/main/bin/bootstrap.sh | bash

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/REPO_OWNER/PROJECTNAME}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/PROJECTNAME}"

printf '=== PROJECTNAME Bootstrap ===\n'

# Ensure git is available
if ! command -v git &>/dev/null; then
    printf 'Installing git...\n'
    apt-get update -qq && apt-get install -y -qq git curl
fi

# Clone or update
if [[ -d "${DEPLOY_DIR}/.git" ]]; then
    printf 'Updating existing checkout in %s\n' "$DEPLOY_DIR"
    cd "$DEPLOY_DIR" && git pull --ff-only
else
    printf 'Cloning to %s\n' "$DEPLOY_DIR"
    rm -rf "$DEPLOY_DIR"
    git clone "$REPO_URL" "$DEPLOY_DIR"
fi

cd "$DEPLOY_DIR"

# Create .env if missing — stop and let the user configure
if [[ ! -f etc/.env ]]; then
    cp etc/.env.example etc/.env
    printf '\n>>> Configuration created at %s/etc/.env\n' "$DEPLOY_DIR"
    printf '>>> Edit it with your values, then run:\n'
    printf '>>>   cd %s && sudo ./bin/deploy.sh\n\n' "$DEPLOY_DIR"
    exit 0
fi

# Config exists — deploy
printf 'Running deployment...\n'
sudo ./bin/deploy.sh
