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
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Required Options:"
    echo "  -u, --user     Remote SSH username"
    echo "  -h, --host     Remote host IP or hostname"
    echo "  -p, --path     Remote directory path for the stack"
    echo "  -i, --item     Vaultwarden item name (ignored if --new is used)"
    echo ""
    echo "Optional Options:"
    echo "  -n, --new      New deployment mode (interactive prompts, skip rbw)"
    echo "  --folder       Vaultwarden folder name"
    echo "  --help         Show this help message"
    echo ""
    echo "Commands:"
    echo "  deploy         Sync files and run: pull, build, up (Default)"
    echo "  logs [args]    Stream logs (e.g., -f -t --tail 100)"
    echo "  ps             Show running containers"
    echo "  stop/down      Stop or remove the stack"
    echo "  exec [svc]     Execute command in service (e.g., manage.sh exec db mysql)"
    echo ""
    echo "Example (Deploy):"
    echo "  $0 -u john -h 1.2.3.4 -p ~/stack -i .env deploy"
    echo ""
    echo "Example (Logs):"
    echo "  $0 -u john -h 1.2.3.4 -p ~/stack -i .env logs -f -t"
    exit 1
}

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)   REMOTE_USER="$2";   shift 2 ;;
        -h|--host)   REMOTE_HOST="$2";   shift 2 ;;
        -p|--path)   REMOTE_PATH="$2";   shift 2 ;;
        -i|--item)   VAULT_ITEM="$2";    shift 2 ;;
        --folder)    VAULT_FOLDER="$2";  shift 2 ;;
        -n|--new)    NEW_DEPLOYMENT=true; shift 1 ;;
        --help)      usage ;;
        deploy|logs|ps|stop|down|exec) COMMAND="$1"; shift; break ;;
        *)           echo "Unknown option/command: $1"; usage ;;
    esac
done

# Default command if none provided
COMMAND="${COMMAND:-deploy}"
EXTRA_ARGS="$@"

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
        VAULT_SECRETS="$VAULT_SECRETS $var='$val'"
        echo "$var=$val" >> "$BOOTSTRAP_FILE"
    done
    echo ""
    echo "📝 All variables have been saved to local file: $BOOTSTRAP_FILE"
else
    echo "🔍 Checking local Vault (rbw)..."
    
    RBW_CMD="rbw get"
    [ -n "$VAULT_FOLDER" ] && RBW_CMD="$RBW_CMD --folder \"$VAULT_FOLDER\""
    RBW_CMD="$RBW_CMD \"$VAULT_ITEM\""

    if rbw unlock >/dev/null 2>&1; then
        echo "🔓 Vault is unlocked. Fetching secrets..."
        VAULT_SECRETS=$(eval "$RBW_CMD" 2>/dev/null | grep '=' | tr '\n' ' ')
        
        if [ -n "$VAULT_SECRETS" ]; then
            echo "✅ Secrets retrieved from vault."
        else
            echo "⚠️ Could not find or read '$VAULT_ITEM' (Folder: ${VAULT_FOLDER:-None})."
            exit 1
        fi
    else
        echo "❌ rbw is locked or not configured."
        exit 1
    fi
fi

# Execute based on command
case $COMMAND in
    deploy)
        echo "Syncing files to $REMOTE_HOST:$REMOTE_PATH..."
        rsync -avz \
            --filter=':- .gitignore' \
            --exclude='.git' \
            --exclude='deploy.sh' \
            --exclude='manage.sh' \
            --exclude='logs.sh' \
            ./ "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"

        REMOTE_CMD="cd $REMOTE_PATH && \
                    $VAULT_SECRETS docker compose pull && \
                    $VAULT_SECRETS docker compose build --pull && \
                    $VAULT_SECRETS docker compose up -d --remove-orphans"
        
        echo "🚀 Deploying and updating on remote server..."
        ssh -t "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_CMD"
        ;;
    
    logs)
        echo "Streaming logs from $REMOTE_HOST..."
        REMOTE_CMD="cd $REMOTE_PATH && $VAULT_SECRETS docker compose logs $EXTRA_ARGS"
        ssh -t "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_CMD"
        ;;

    ps|stop|down|exec)
        echo "Running 'docker compose $COMMAND' on $REMOTE_HOST..."
        REMOTE_CMD="cd $REMOTE_PATH && $VAULT_SECRETS docker compose $COMMAND $EXTRA_ARGS"
        ssh -t "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_CMD"
        ;;
esac
