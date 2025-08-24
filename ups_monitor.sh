#!/usr/bin/bash
################################################################################
#
# Universal UPS Status Monitor (v4.0.1 - Caching Hub Edition)
#
# Features:
# - Configurable shutdown delay.
# - Shutdown cancellation if power is restored.
# - Stateful operation using a flag file.
# - External configuration via an .env file.
# - Universal logging for Synology DSM and standard Linux.
# New in version 4.0.0:
# - Introduces hub functionality
# - Fetches configuration from a central "UPS Hub" REST API.
# - Falls back to a local ups.env file if the API is unreachable.
# - Requires `curl` and `jq` to be installed.
# New in version 4.0.1:
# - Updates the local ups.env file to cache the last successful config.
# - Reads uppercase variable names from the API response.
#
################################################################################

# --- Load Local Fallback Configuration ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
CONFIG_FILE="$SCRIPT_DIR/ups.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    logger -t "UPS_Monitor_Core" "CRITICAL ERROR: Local config file not found at $CONFIG_FILE. Exiting."
    exit 1
fi

# --- Set default values ---
UPS_NAME="${UPS_NAME:-ups@localhost}"
SHUTDOWN_DELAY_MINUTES="${SHUTDOWN_DELAY_MINUTES:-15}"
FLAG_FILE="${FLAG_FILE:-/tmp/ups_shutdown_pending.flag}"
LOG_TAG="${LOG_TAG:-UPS_Shutdown_Script}"

# --- Universal logging function ---
send_log() {
    local level="${1:-info}"
    shift
    local msg="$*"
    if [ -x /usr/syno/bin/synologset1 ]; then
        /usr/syno/bin/synologset1 sys "$level" 0x11100000 "$msg"
    else
        logger -t "$LOG_TAG" -p "user.$level" "$msg"
    fi
}

# --- Function to get the primary IP of this machine ---
get_primary_ip() {
    ip route get 1.1.1.1 | awk '{print $7}' | head -n 1
}

# --- Configuration Fetching Logic ---
if [[ -n "$API_SERVER_URI" && -n "$API_TOKEN" ]]; then
    send_log "info" "API server is configured. Attempting to fetch remote configuration."
    
    CLIENT_IP=$(get_primary_ip)
    API_URL="${API_SERVER_URI}/config?ip=${CLIENT_IP}"
    
    API_RESPONSE=$(curl --fail --silent --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${API_TOKEN}" "$API_URL")
    
    if [ $? -eq 0 ]; then
        # --- CHANGES ARE HERE ---
        # Read uppercase keys from the JSON response
        REMOTE_UPS_NAME=$(echo "$API_RESPONSE" | jq -e -r '.UPS_NAME')
        REMOTE_SHUTDOWN_DELAY=$(echo "$API_RESPONSE" | jq -e -r '.SHUTDOWN_DELAY_MINUTES')

        if [[ -n "$REMOTE_UPS_NAME" && -n "$REMOTE_SHUTDOWN_DELAY" ]]; then
            send_log "info" "Successfully fetched remote config. Using UPS: '$REMOTE_UPS_NAME', Delay: '$REMOTE_SHUTDOWN_DELAY' minutes."
            
            # Update local variables for the current run
            UPS_NAME="$REMOTE_UPS_NAME"
            SHUTDOWN_DELAY_MINUTES="$REMOTE_SHUTDOWN_DELAY"

            # Update the local ups.env file to cache the new values
            send_log "info" "Updating local fallback configuration at $CONFIG_FILE."
            # Use sed to replace the values in-place. The delimiter | is used to avoid issues with slashes in paths.
            sed -i "s|^UPS_NAME=.*|UPS_NAME=\"$UPS_NAME\"|" "$CONFIG_FILE"
            sed -i "s|^SHUTDOWN_DELAY_MINUTES=.*|SHUTDOWN_DELAY_MINUTES=$SHUTDOWN_DELAY_MINUTES|" "$CONFIG_FILE"

        else
            send_log "warn" "API response was invalid (check key names: UPS_NAME, SHUTDOWN_DELAY_MINUTES). Falling back to local configuration."
        fi
    else
        send_log "warn" "Failed to connect to API Hub at $API_SERVER_URI. Falling back to local configuration."
    fi
else
    send_log "info" "API server not configured. Using local configuration."
fi

# --- MAIN SCRIPT LOGIC ---
SHUTDOWN_DELAY_SECONDS=$((SHUTDOWN_DELAY_MINUTES * 60))
CURRENT_STATUS=$(upsc "$UPS_NAME" ups.status 2>/dev/null)

if [ -z "$CURRENT_STATUS" ]; then
    send_log "err" "ERROR: Could not get status from UPS server ($UPS_NAME). Check connection."
    exit 1
fi

if [[ "$CURRENT_STATUS" == "OB LB" ]]; then
    if [ ! -f "$FLAG_FILE" ]; then
        send_log "warn" "Low battery detected! Starting $SHUTDOWN_DELAY_MINUTES minute countdown to system shutdown."
        date +%s > "$FLAG_FILE"
    else
        START_TIME=$(cat "$FLAG_FILE")
        CURRENT_TIME=$(date +%s)
        ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
        if [ "$ELAPSED_TIME" -ge "$SHUTDOWN_DELAY_SECONDS" ]; then
            send_log "err" "Shutdown delay of $SHUTDOWN_DELAY_MINUTES minutes has passed. Shutting down NOW."
            rm -f "$FLAG_FILE"
            /sbin/shutdown -h now
            exit 0
        fi
    fi
elif [[ "$CURRENT_STATUS" == "OL" ]]; then
    if [ -f "$FLAG_FILE" ]; then
        send_log "info" "Mains power has been restored. Cancelling shutdown countdown."
        rm -f "$FLAG_FILE"
    fi
fi

exit 0