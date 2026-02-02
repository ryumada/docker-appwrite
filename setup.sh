#!/bin/bash
set -e

# Detect Repository Owner to run non-root commands as that user
CURRENT_DIR=$(dirname "$(readlink -f "$0")")
CURRENT_DIR_USER=$(stat -c '%U' "$CURRENT_DIR")
PATH_TO_REPO=$(sudo -u "$CURRENT_DIR_USER" git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)
SERVICE_NAME=$(basename "$PATH_TO_REPO")
REPOSITORY_OWNER=$(stat -c '%U' "$PATH_TO_REPO")

# Configuration
ENV_FILE=".env"
UPDATE_SCRIPT="./scripts/update_env_file.sh"

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

log_info "Starting Appwrite configuration setup..."

# Self-elevate to root if not already
if [ "$(id -u)" -ne 0 ]; then
    log_info "Elevating permissions to root..."
    exec sudo "$0" "$@"
    log_error "Failed to elevate to root. Please run with sudo."
    exit 1
fi

if [ -x "$UPDATE_SCRIPT" ]; then
    log_info "Running update script: $UPDATE_SCRIPT"
    sudo -u "$REPOSITORY_OWNER" "$UPDATE_SCRIPT"
else
    # Try to make it executable if it exists but isn't x
    if [ -f "$UPDATE_SCRIPT" ]; then
         chmod +x "$UPDATE_SCRIPT"
         log_info "Made $UPDATE_SCRIPT executable. Running..."
         sudo -u "$REPOSITORY_OWNER" "$UPDATE_SCRIPT"
    else
        log_error "Error: $UPDATE_SCRIPT not found!"
        exit 1
    fi
fi

generate_secret() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

generate_passphrase() {
    local consonants="bcdfghjklmnpqrstvwxyz"
    local vowels="aeiou"
    local word=""
    for i in {1..4}; do
        word+="${consonants:RANDOM%21:1}"
        word+="${vowels:RANDOM%5:1}"
    done
    echo "$word"
}

# Function to check if a variable has the default value
is_default_value() {
    local var_name="$1"
    local default_val="$2"
    local current_val
    current_val=$(grep "^${var_name}=" "$ENV_FILE" | cut -d'=' -f2-)

    if [ "$current_val" == "$default_val" ]; then
        return 0 # True, it is default
    else
        return 1 # False, it has been changed
    fi
}

log_info "Checking if secrets need generation..."

# Defaults from .env.example
DEFAULT_OPENSSL_KEY="your-secret-key"
DEFAULT_EXECUTOR_SECRET="your-secret-key"
DEFAULT_DB_PASS="password"
DEFAULT_DB_ROOT_PASS="rootsecretpassword"
DEFAULT_DB_USER="user"
# _APP_OPENSSL_KEY_V1
if is_default_value "_APP_OPENSSL_KEY_V1" "$DEFAULT_OPENSSL_KEY"; then
    log_info "Generating _APP_OPENSSL_KEY_V1..."
    NEW_KEY=$(generate_secret 32)
    sudo -u "$REPOSITORY_OWNER" sed -i "s|^_APP_OPENSSL_KEY_V1=.*|_APP_OPENSSL_KEY_V1=${NEW_KEY}|" "$ENV_FILE"
fi

# _APP_EXECUTOR_SECRET
if is_default_value "_APP_EXECUTOR_SECRET" "$DEFAULT_EXECUTOR_SECRET"; then
    log_info "Generating _APP_EXECUTOR_SECRET..."
    NEW_SECRET=$(generate_secret 32)
    sudo -u "$REPOSITORY_OWNER" sed -i "s|^_APP_EXECUTOR_SECRET=.*|_APP_EXECUTOR_SECRET=${NEW_SECRET}|" "$ENV_FILE"
fi

# _APP_DB_USER
if is_default_value "_APP_DB_USER" "$DEFAULT_DB_USER"; then
    log_info "Generating _APP_DB_USER..."
    NEW_USER="$(generate_passphrase)-$(generate_passphrase)-$(generate_passphrase)"
    sudo -u "$REPOSITORY_OWNER" sed -i "s|^_APP_DB_USER=.*|_APP_DB_USER=${NEW_USER}|" "$ENV_FILE"
    log_success "Generated DB User: ${NEW_USER}"
fi

# _APP_DB_PASS
if is_default_value "_APP_DB_PASS" "$DEFAULT_DB_PASS"; then
    log_info "Generating _APP_DB_PASS..."
    NEW_PASS="$(generate_passphrase)-$(generate_passphrase)-$(generate_passphrase)"
    sudo -u "$REPOSITORY_OWNER" sed -i "s|^_APP_DB_PASS=.*|_APP_DB_PASS=${NEW_PASS}|" "$ENV_FILE"
    log_success "Generated DB User Password: ${NEW_PASS}"
fi

# _APP_DB_ROOT_PASS
if is_default_value "_APP_DB_ROOT_PASS" "$DEFAULT_DB_ROOT_PASS"; then
    log_info "Generating _APP_DB_ROOT_PASS..."
    # Generate a longer phrase for root
    PHRASES="$(generate_passphrase)-$(generate_passphrase)-$(generate_passphrase)"
    sudo -u "$REPOSITORY_OWNER" sed -i "s|^_APP_DB_ROOT_PASS=.*|_APP_DB_ROOT_PASS=${PHRASES}|" "$ENV_FILE"
    log_success "Generated DB Root Password: ${PHRASES}"
fi
log_success "Setup complete! Your Appwrite environment is ready in ${ENV_FILE}"
