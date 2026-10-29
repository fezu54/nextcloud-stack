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
    "APPAPI_SHARED_KEY"
    "HOST_AUTH_LOG_PATH"
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
    echo "  mute [scenario] Mute noisy scenario alerts (suppresses ntfy notifications)"
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
        deploy|logs|ps|stop|down|exec|mute) COMMAND="$1"; shift; break ;;
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
        if [ "$var" = "HOST_AUTH_LOG_PATH" ]; then
            echo ""
            echo "⚙️  Configuring Host SSH log path for CrowdSec..."
            detected_path=""
            if [ -n "$REMOTE_USER" ] && [ -n "$REMOTE_HOST" ]; then
                if ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" "[ -f /var/log/auth.log ]" 2>/dev/null; then
                    detected_path="/var/log/auth.log"
                elif ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" "[ -f /var/log/secure ]" 2>/dev/null; then
                    detected_path="/var/log/secure"
                fi
            fi

            default_choice="1"
            [ "$detected_path" = "/var/log/secure" ] && default_choice="2"

            echo "Select Host OS for SSH intrusion detection:"
            echo "  1) Debian / Ubuntu (/var/log/auth.log)"
            echo "  2) RHEL / CentOS / Rocky / Fedora (/var/log/secure)"
            echo "  3) Custom path"
            if [ -n "$detected_path" ]; then
                echo "  💡 Auto-detected on $REMOTE_HOST: $detected_path"
            fi

            read -rp "Enter choice [1-3] (default: $default_choice): " os_choice
            os_choice="${os_choice:-$default_choice}"
            case "$os_choice" in
                2) val="/var/log/secure" ;;
                3) read -rp "Enter full path to host auth log: " val ;;
                *) val="/var/log/auth.log" ;;
            esac
            echo "Setting HOST_AUTH_LOG_PATH=$val"
        else
            read -rsp "Enter value for $var: " val
            echo " (captured)"
        fi
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
            --exclude='mute.sh' \
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

    mute)
        PROFILES_FILE="crowdsec/profiles.yaml.local"
        SCENARIO="$EXTRA_ARGS"

        if [ ! -f "$PROFILES_FILE" ]; then
            echo "❌ Error: $PROFILES_FILE does not exist."
            exit 1
        fi

        # If no scenario argument was provided, offer interactive selection
        if [ -z "$SCENARIO" ]; then
            echo "🔍 Fetching recent alert scenarios from $REMOTE_HOST..."
            RECENT_ALERTS=$(ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_PATH && $VAULT_SECRETS docker compose exec -T crowdsec cscli alerts list -l 20 -o raw" 2>/dev/null | awk -F',' 'NR>1 {print $4}' | grep -v '^$' | sort -u)

            scenarios=()
            if [ -n "$RECENT_ALERTS" ]; then
                while IFS= read -r sc; do
                    [ -z "$sc" ] && continue
                    # Filter out scenarios that are already muted
                    if ! grep -Fq "\"$sc\"" "$PROFILES_FILE" 2>/dev/null; then
                        scenarios+=("$sc")
                    fi
                done <<< "$RECENT_ALERTS"
            fi

            if [ "${#scenarios[@]}" -gt 0 ]; then
                echo ""
                echo "Recently triggered scenarios (not yet muted):"
                idx=1
                for sc in "${scenarios[@]}"; do
                    echo "  $idx) $sc"
                    ((idx++))
                done
                echo "  $idx) Custom (enter scenario name manually)"
                
                read -rp "Select scenario to mute [1-$idx]: " choice
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$idx" ]; then
                    SCENARIO="${scenarios[$((choice-1))]}"
                else
                    read -rp "Enter scenario name to mute (e.g., crowdsecurity/http-wordpress-scan): " SCENARIO
                fi
            else
                echo ""
                echo "ℹ️  All recent alerts are already in your muted scenarios list!"
                read -rp "Enter custom scenario name to mute (or press Enter to cancel): " SCENARIO
            fi
        fi

        SCENARIO=$(echo "$SCENARIO" | xargs)
        if [ -z "$SCENARIO" ]; then
            echo "No scenario specified. Exiting."
            exit 0
        fi

        # Check if already in profiles.yaml.local
        if grep -Fq "\"$SCENARIO\"" "$PROFILES_FILE"; then
            echo "ℹ️  '$SCENARIO' is already present in $PROFILES_FILE. Nothing to do."
            exit 0
        fi

        sed -i "/^[[:space:]]*\]/i \      \"$SCENARIO\"," "$PROFILES_FILE"
        echo "✅ Added '$SCENARIO' to local $PROFILES_FILE."

        # Sync profiles.yaml.local to remote server
        echo "📤 Syncing $PROFILES_FILE to $REMOTE_HOST:$REMOTE_PATH/$PROFILES_FILE..."
        rsync -avz "$PROFILES_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/$PROFILES_FILE"

        # Restart crowdsec container on remote server to reload configuration instantly
        echo "🔄 Reloading CrowdSec on $REMOTE_HOST..."
        ssh -t "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_PATH && $VAULT_SECRETS docker compose restart crowdsec"

        echo "🎉 Done! Alerts for '$SCENARIO' are now muted."
        echo "   (Traffic matching this scenario will still be banned silently by the firewall bouncer)."

        # Ask if the user wants to contribute the muted scenario back to upstream
        echo ""
        read -rp "Would you like to contribute this muted scenario back to upstream via a Pull Request? [y/N]: " contribute_choice
        case "$contribute_choice" in
            [yY]|[yY][eE][sS])
                echo ""
                echo "🚀 Preparing Pull Request..."

                # 1. Check if git repo
                if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    echo "❌ Not inside a git repository. Cannot create a Pull Request."
                    exit 0
                fi

                # 2. Check if GitHub CLI is installed
                if ! command -v gh >/dev/null 2>&1; then
                    echo "⚠️  GitHub CLI ('gh') is required to automatically open a Pull Request."
                    echo "   Install it from https://cli.github.com/ or submit a PR manually."
                    exit 0
                fi

                # 3. Check if user is authenticated with gh
                if ! gh auth status >/dev/null 2>&1; then
                    echo "⚠️  You are not logged into GitHub CLI."
                    echo "   Please run 'gh auth login' to authenticate, then re-run to create a PR."
                    exit 0
                fi

                ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "feat/vaultwarden")
                BRANCH_SLUG=$(echo "$SCENARIO" | tr '/' '-' | tr -cd '[:alnum:]-_')
                PR_BRANCH="mute/${BRANCH_SLUG}"

                echo "🌿 Creating branch '$PR_BRANCH'..."
                git checkout -B "$PR_BRANCH"

                git add "$PROFILES_FILE"
                git commit -m "feat(crowdsec): mute noisy scenario $SCENARIO"

                echo "📤 Pushing branch to remote..."
                # Try pushing to origin; if user has no push access, set up fork via gh
                if ! git push -u origin "$PR_BRANCH" 2>/dev/null; then
                    echo "🍴 Setting up fork via GitHub CLI..."
                    gh repo fork fezu54/nextcloud-stack --remote --remote-name "fork" 2>/dev/null || true
                    git push -u fork "$PR_BRANCH"
                fi

                echo "📤 Creating Pull Request on fezu54/nextcloud-stack..."
                PR_TITLE="feat(crowdsec): mute $SCENARIO"
                PR_BODY="This PR adds \`$SCENARIO\` to \`crowdsec/profiles.yaml.local\`.

### Why?
This scenario generates noisy notifications for attacks that this Nextcloud stack is not vulnerable to. Adding it to \`profiles.yaml.local\` ensures attackers are still actively banned by the firewall bouncer, but suppresses spammy ntfy push notifications.

*Submitted automatically via \`./mute.sh\`.*"

                # Try creating PR with 'crowdsec' label; if label fails, create without label
                if PR_URL=$(gh pr create --repo fezu54/nextcloud-stack --base "$ORIGINAL_BRANCH" --title "$PR_TITLE" --body "$PR_BODY" --label "crowdsec" 2>/dev/null); then
                    echo "✅ Pull Request created with label 'crowdsec'!"
                    echo "   🔗 $PR_URL"
                elif PR_URL=$(gh pr create --repo fezu54/nextcloud-stack --base "$ORIGINAL_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"); then
                    echo "✅ Pull Request created successfully!"
                    echo "   🔗 $PR_URL"
                else
                    echo "❌ Failed to create Pull Request via gh CLI."
                    echo "   You can create the PR manually on GitHub."
                fi

                # Switch back to the original branch without merging locally to prevent divergence with GitHub's squash merge
                git checkout "$ORIGINAL_BRANCH" >/dev/null 2>&1
                echo ""
                echo "✅ Switched back to '$ORIGINAL_BRANCH'."
                echo "   💡 Once the PR is merged on GitHub, run 'git pull' to update your local branch."
                ;;
            *)
                echo "No PR requested. Exiting."
                ;;
        esac
        ;;

    ps|stop|down|exec)
        echo "Running 'docker compose $COMMAND' on $REMOTE_HOST..."
        REMOTE_CMD="cd $REMOTE_PATH && $VAULT_SECRETS docker compose $COMMAND $EXTRA_ARGS"
        ssh -t "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_CMD"
        ;;
esac
