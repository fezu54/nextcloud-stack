#!/bin/bash

# Default values
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_PATH=""
VAULT_ITEM=""
VAULT_FOLDER=""
NEW_DEPLOYMENT=false

# List of essential variables to prompt for in --new mode
REQUIRED_VARS=(
    "MYSQL_ROOT_PASSWORD"
    "MYSQL_DATABASE"
    "MYSQL_USER"
    "MYSQL_PASSWORD"
    "DNS_ADDRESS"
    "NEXTCLOUD_PREFIX"
    "VAULTWARDEN_PREFIX"
    "LETSENCRYPT_EMAIL"
    "TZ"
    "BORG_PASSPHRASE"
    "VOLUME_TARGET"
    "NTFY_PREFIX"
    "NTFY_TOPIC"
    "NTFY_TOKEN"
    "FRESH_RSS_PREFIX"
    "FRESH_RSS_DB_PASSWORD"
)

# Function to check local dependencies
check_dependencies() {
    local deps=("rsync" "ssh")
    [ "$NEW_DEPLOYMENT" = false ] && deps+=("rbw")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "❌ Error: Required tool '$dep' is not installed locally."
            exit 1
        fi
    done
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  -u, --user     Remote SSH username"
    echo "  -h, --host     Remote host IP or hostname"
    echo "  -p, --path     Remote directory path for the stack"
    echo "  -i, --item     Vaultwarden item name (ignored if --new is used)"
    echo ""
    echo "Optional Options:"
    echo "  -n, --new      New deployment mode (interactive prompts, skip rbw)"
    echo "  -f, --folder   Vaultwarden folder name"
    echo "  --help         Show this help message"
    echo ""
    echo "Example (Standard):"
    echo "  $0 -u john -h 1.2.3.4 -p ~/stack -i .env"
    echo ""
    echo "Example (New Deployment):"
    echo "  $0 -u john -h 1.2.3.4 -p ~/stack --new"
    exit 1
}

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)   REMOTE_USER="$2";   shift 2 ;;
        -h|--host)   REMOTE_HOST="$2";   shift 2 ;;
        -p|--path)   REMOTE_PATH="$2";   shift 2 ;;
        -i|--item)   VAULT_ITEM="$2";    shift 2 ;;
        -f|--folder) VAULT_FOLDER="$2";  shift 2 ;;
        -n|--new)    NEW_DEPLOYMENT=true; shift 1 ;;
        --help)      usage ;;
        *)           echo "Unknown option: $1"; usage ;;
    esac
done

# Validate required arguments
if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_PATH" ] || { [ "$NEW_DEPLOYMENT" = false ] && [ -z "$VAULT_ITEM" ]; }; then
    echo "❌ Error: Missing required arguments."
    usage
fi

# Check for local tools
check_dependencies

VAULT_SECRETS=""

if [ "$NEW_DEPLOYMENT" = true ]; then
    echo "🆕 NEW DEPLOYMENT MODE"
    echo "Please enter the values for your environment variables (input is hidden):"
    
    BOOTSTRAP_FILE=".env.bootstrap"
    echo "# Generated during bootstrap on $(date)" > "$BOOTSTRAP_FILE"
    chmod 600 "$BOOTSTRAP_FILE"

    for var in "${REQUIRED_VARS[@]}"; do
        read -rsp "Enter value for $var: " val
        echo " (captured)"
        # 1. For the remote command (escaped for shell)
        VAULT_SECRETS="$VAULT_SECRETS $var='$val'"
        # 2. For the local bootstrap file (raw KEY=VALUE)
        echo "$var=$val" >> "$BOOTSTRAP_FILE"
    done
    echo ""
    echo "📝 All variables have been saved to local file: $BOOTSTRAP_FILE"
    echo "   You can use this file to copy-paste your secrets into Vaultwarden later."
else
    echo "🔍 Checking local Vault (rbw)..."
    
    # 1. Construct rbw command
    RBW_CMD="rbw get"
    if [ -n "$VAULT_FOLDER" ]; then
        RBW_CMD="$RBW_CMD --folder \"$VAULT_FOLDER\""
        echo "📂 Folder: $VAULT_FOLDER"
    fi
    RBW_CMD="$RBW_CMD \"$VAULT_ITEM\""
    echo "🔑 Item:   $VAULT_ITEM"

    # 2. Try to fetch secrets from rbw
    if rbw unlock --check >/dev/null 2>&1; then
        echo "🔓 Vault is unlocked. Fetching secrets..."
        
        # Execute the constructed rbw command
        VAULT_SECRETS=$(eval "$RBW_CMD" 2>/dev/null | grep '=' | tr '\n' ' ')
        
        if [ -n "$VAULT_SECRETS" ]; then
            echo "✅ Secrets retrieved from vault."
        else
            echo "⚠️ Could not find or read '$VAULT_ITEM' (Folder: ${VAULT_FOLDER:-None})."
            echo "   Exiting."
            exit 1
        fi
    else
        echo "❌ rbw is locked or not configured. (Run 'rbw unlock' first or use --new mode)"
        exit 1
    fi
fi

# 3. Sync local files to remote
echo "Syncing files to $REMOTE_HOST:$REMOTE_PATH..."
rsync -avz \
    --filter=':- .gitignore' \
    --exclude='.git' \
    --exclude='deploy.sh' \
    ./ "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"

# 4. Construct and execute the remote command
# We prepend the secrets to each command to ensure they are available
REMOTE_CMD="cd $REMOTE_PATH && \
            $VAULT_SECRETS docker compose pull && \
            $VAULT_SECRETS docker compose build --pull && \
            $VAULT_SECRETS docker compose up -d --remove-orphans"

echo "🚀 Deploying and updating on remote server..."
ssh -t "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_CMD"
