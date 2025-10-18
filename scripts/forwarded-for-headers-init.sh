#!/bin/bash
set -euo pipefail

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

# Maximum time to wait for Nextcloud/occ to become available (seconds)
MAX_WAIT=300
SLEEP_INTERVAL=5
WAITED=0

log "nextcloud-init: waiting for Nextcloud (occ) to become available..."
while ! php /var/www/html/occ status >/dev/null 2>&1; do
  sleep $SLEEP_INTERVAL
  WAITED=$((WAITED + SLEEP_INTERVAL))
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    log "timeout waiting for Nextcloud occ to be available after ${MAX_WAIT}s"
    exit 1
  fi
done
log "occ is available"

# Resolve proxy IP. If you want to override detection, supply PROXY_IP env var.
proxy_ip=""
if [ -n "${PROXY_IP:-}" ]; then
  proxy_ip="$PROXY_IP"
  log "Using PROXY_IP from environment: $proxy_ip"
else
  # Resolve the 'proxy' service hostname on the proxy-tier network
  proxy_ip=$(getent hosts proxy | awk '{print $1}' || true)
  if [ -n "$proxy_ip" ]; then
    log "Resolved proxy service IP: $proxy_ip"
  else
    log "Could not resolve 'proxy' hostname. You may set PROXY_IP environment variable in docker-compose if automatic discovery fails."
    exit 1
  fi
fi

# Function to run occ commands and capture output
occ() {
  php /var/www/html/occ "$@"
}

# Configure trusted_proxies (append if not present)
existing_trusted=$(occ config:system:get trusted_proxies 2>/dev/null || true)
if echo "$existing_trusted" | grep -F "$proxy_ip" >/dev/null 2>&1; then
  log "Proxy IP $proxy_ip already present in trusted_proxies; skipping add."
else
  # If no existing value, set to array with proxy_ip; otherwise set to existing + proxy_ip.
  if [ -z "$existing_trusted" ]; then
    log "Setting trusted_proxies to [\"$proxy_ip\"]"
    occ config:system:set trusted_proxies --value="[\"$proxy_ip\"]" --type=array
  else
    # Best-effort: attempt to preserve existing values by reading them and creating a merged JSON array.
    # existing_trusted sometimes prints a human-readable array; try to extract lines with IPs.
    ips=$(echo "$existing_trusted" | sed -n 's/^[[:space:]]*-\s*\(.*\)$/\1/p' | tr '\n' ',' | sed 's/,$//')
    # If extraction failed, fall back to set only the proxy IP (safer than leaving proxy untrusted).
    if [ -z "$ips" ]; then
      log "Could not parse existing trusted_proxies reliably; setting to [\"$proxy_ip\"] to ensure proxy is trusted."
      occ config:system:set trusted_proxies --value="[\"$proxy_ip\"]" --type=array
    else
      # Build JSON array merging existing IPs and proxy_ip if missing
      # Note: this is simple textual merging; for complex existing values adjust manually.
      merged="["
      IFS=',' read -r -a arr <<< "$ips"
      for v in "${arr[@]}"; do
        v_trim=$(echo "$v" | sed 's/^[[:space:]\"]*//;s/[[:space:]\"]*$//')
        [ -n "$v_trim" ] && merged="$merged\"$v_trim\","
      done
      # Add the detected proxy IP unless present
      if ! echo "$merged" | grep -F "\"$proxy_ip\"" >/dev/null 2>&1; then
        merged="$merged\"$proxy_ip\","
      fi
      merged="${merged%,}]"
      log "Setting trusted_proxies to $merged"
      occ config:system:set trusted_proxies --value="$merged" --type=array
    fi
  fi
fi

# Restrict forwarded headers to a safe subset (X-Forwarded-For)
log "Setting forwarded_for_headers to [\"HTTP_X_FORWARDED_FOR\"]"
occ config:system:set forwarded_for_headers --value='["HTTP_X_FORWARDED_FOR"]' --type=array

log "nextcloud-init: finished successfully"
