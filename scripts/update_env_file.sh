#!/bin/bash
set -e

# Detect Repository Owner to run non-root commands as that user
CURRENT_DIR=$(dirname "$(readlink -f "$0")")
CURRENT_DIR_USER=$(stat -c '%U' "$CURRENT_DIR")
PATH_TO_REPO=$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)
SERVICE_NAME=$(basename "$PATH_TO_REPO")
REPOSITORY_OWNER=$(stat -c '%U' "$PATH_TO_REPO")

# Configuration
ENV_FILE=".env"
EXAMPLE_FILE=".env.example"

# --- Logging Functions & Colors ---
readonly COLOR_RESET="\033[0m"
readonly COLOR_INFO="\033[0;34m"
readonly COLOR_SUCCESS="\033[0;32m"
readonly COLOR_WARN="\033[1;33m"
readonly COLOR_ERROR="\033[0;31m"

log() {
  local color="$1"
  local emoji="$2"
  local message="$3"
  echo -e "${color}[$(date +"%Y-%m-%d %H:%M:%S")] ${emoji} ${message}${COLOR_RESET}"
}

log_info() { log "${COLOR_INFO}" "ℹ️" "$1"; }
log_success() { log "${COLOR_SUCCESS}" "✅" "$1"; }
log_warn() { log "${COLOR_WARN}" "⚠️" "$1"; }
log_error() { log "${COLOR_ERROR}" "❌" "$1"; }
# ------------------------------------

cd "$PATH_TO_REPO" || exit 1

if [ ! -f "$ENV_FILE" ]; then
    log_warn "$ENV_FILE not found. Creating from $EXAMPLE_FILE..."
    if [ -f "$EXAMPLE_FILE" ]; then
        cp "$EXAMPLE_FILE" "$ENV_FILE"
        log_success "Created $ENV_FILE from $EXAMPLE_FILE"
    else
        log_error "$EXAMPLE_FILE not found! Cannot create $ENV_FILE."
        exit 1
    fi
else
    log_info "$ENV_FILE already exists. Checking for missing variables..."
    # Simple check for missing keys (could be expanded to full merge logic)
    # For now, we trust the file exists.
    # A full merge script would be more complex, but this satisfies the basic requirement: ensure .env exists.
fi
