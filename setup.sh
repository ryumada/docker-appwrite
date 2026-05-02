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

# Function to get a variable value from .env
get_env_value() {
    local var_name="$1"
    grep "^${var_name}=" "$ENV_FILE" | cut -d'=' -f2-
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

# _APP_TRAEFIK_DOMAINS
if is_default_value "_APP_TRAEFIK_DOMAINS" "localhost"; then
    CURRENT_DOMAIN=$(get_env_value "_APP_DOMAIN")
    if [ "$CURRENT_DOMAIN" != "localhost" ]; then
        log_info "Generating _APP_TRAEFIK_DOMAINS based on _APP_DOMAIN..."
        NEW_TRAEFIK_DOMAINS="appwrite.${CURRENT_DOMAIN},api.${CURRENT_DOMAIN}"
        sudo -u "$REPOSITORY_OWNER" sed -i "s|^_APP_TRAEFIK_DOMAINS=.*|_APP_TRAEFIK_DOMAINS=${NEW_TRAEFIK_DOMAINS}|" "$ENV_FILE"
        log_success "Generated Traefik Domains: ${NEW_TRAEFIK_DOMAINS}"
    fi
fi

# --- Docker Compose Generation ---
COMPOSE_EXAMPLE="docker-compose.yml.example"
COMPOSE_FILE="docker-compose.yml"

if [ -f "$COMPOSE_EXAMPLE" ]; then
    log_info "Generating ${COMPOSE_FILE} from ${COMPOSE_EXAMPLE}..."
    cp "$COMPOSE_EXAMPLE" "$COMPOSE_FILE"

    PROXY_MODE=$(get_env_value "_APP_PROXY_MODE")

    if [ "$PROXY_MODE" == "traefik" ]; then
        log_info "Traefik mode enabled. Keeping Traefik configuration."
        # Just remove the markers themselves
        sed -i '/# <TRAEFIK_ONLY>/d; /# <\/TRAEFIK_ONLY>/d' "$COMPOSE_FILE"
        # Remove NO_TRAEFIK sections including the markers
        sed -i '/# <NO_TRAEFIK>/,/# <\/NO_TRAEFIK>/d' "$COMPOSE_FILE"
    else
        log_info "Traefik mode disabled. Removing Traefik configuration section."
        # Remove the blocks including the markers
        sed -i '/# <TRAEFIK_ONLY>/,/# <\/TRAEFIK_ONLY>/d' "$COMPOSE_FILE"
        # Keep NO_TRAEFIK sections but remove markers
        sed -i '/# <NO_TRAEFIK>/d; /# <\/NO_TRAEFIK>/d' "$COMPOSE_FILE"
    fi
    chown "$REPOSITORY_OWNER": "$COMPOSE_FILE"
    log_success "${COMPOSE_FILE} generated successfully."
else
    log_warn "${COMPOSE_EXAMPLE} not found. Skipping docker-compose generation."
fi

# --- Proxy Network Setup ---
PROXY_MODE=$(get_env_value "_APP_PROXY_MODE")
TRAEFIK_NETWORK=$(get_env_value "_APP_TRAEFIK_PROXY_NETWORK")

if [ "$PROXY_MODE" == "traefik" ] && [ -n "$TRAEFIK_NETWORK" ]; then
    log_info "Proxy mode is set to traefik. Checking for network: ${TRAEFIK_NETWORK}..."
    if ! docker network inspect "$TRAEFIK_NETWORK" >/dev/null 2>&1; then
        log_info "Creating external network: ${TRAEFIK_NETWORK}..."
        docker network create "$TRAEFIK_NETWORK"
        log_success "Network ${TRAEFIK_NETWORK} created."
    else
        log_success "Network ${TRAEFIK_NETWORK} already exists."
    fi
fi

log_success "Setup complete! Your Appwrite environment is ready in ${ENV_FILE}"
