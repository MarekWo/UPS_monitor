#!/usr/bin/bash
################################################################################
#
# Universal UPS Status Monitor (v4.3.0 - API-Only Edition)
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
# - NEW: Reports client status back to the server
# New in version 4.2.0:
# - Report `online` status not only when the power is restored, but always
# New in version 4.3.0:
# - BREAKING CHANGE: Completely replaced upsc command with API calls
# - No longer requires nut-client installation on client machines
# - Uses /upsc API endpoint for UPS status checking
# - API server configuration (API_SERVER_URI, API_TOKEN) is now mandatory
# - Unified approach with Windows PowerShell version
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

# Function to send API status
send_status_update() {
    local status="$1"
    local remaining_seconds="${2:-null}"
    local shutdown_delay="${3:-null}"
    
    if [[ -n "$API_SERVER_URI" && -n "$API_TOKEN" ]]; then
        local client_ip
        client_ip=$(get_primary_ip)
        local api_url="${API_SERVER_URI}/status"
        
        # JSON payload creation
        local payload
        payload=$(printf '{"ip": "%s", "status": "%s", "remaining_seconds": %s, "shutdown_delay": %s}' \
            "$client_ip" "$status" "$remaining_seconds" "$shutdown_delay")
        
        # Sending data in the background to avoid blocking the script
        curl -s -X POST -H "Content-Type: application/json" \
             -H "Authorization: Bearer ${API_TOKEN}" \
             -d "$payload" "$api_url" &
    fi
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
        REMOTE_SHUTDOWN_DELAY=$(echo "$API_RESPONSE" | jq -e -r '.SHUTDOWN_DELAY_MINUTES')
        REMOTE_IGNORE_SIMULATION=$(echo "$API_RESPONSE" | jq -e -r '.IGNORE_SIMULATION // "false"')

        if [[ -n "$REMOTE_SHUTDOWN_DELAY" ]]; then
            send_log "info" "Successfully fetched remote config. Using delay: '$REMOTE_SHUTDOWN_DELAY' minutes, IGNORE_SIMULATION: '$REMOTE_IGNORE_SIMULATION'."

            # Update local variables for the current run
            SHUTDOWN_DELAY_MINUTES="$REMOTE_SHUTDOWN_DELAY"
            IGNORE_SIMULATION="$REMOTE_IGNORE_SIMULATION"

            # Update the local ups.env file to cache the new values
            send_log "info" "Updating local fallback configuration at $CONFIG_FILE."
            # Use sed to replace the values in-place. The delimiter | is used to avoid issues with slashes in paths.
            sed -i "s|^SHUTDOWN_DELAY_MINUTES=.*|SHUTDOWN_DELAY_MINUTES=$SHUTDOWN_DELAY_MINUTES|" "$CONFIG_FILE"

            # Update or add IGNORE_SIMULATION in the config file
            if grep -q "^IGNORE_SIMULATION=" "$CONFIG_FILE"; then
                sed -i "s|^IGNORE_SIMULATION=.*|IGNORE_SIMULATION=\"$IGNORE_SIMULATION\"|" "$CONFIG_FILE"
            else
                echo "IGNORE_SIMULATION=\"$IGNORE_SIMULATION\"" >> "$CONFIG_FILE"
            fi

        else
            send_log "warn" "API response was invalid (check key name: SHUTDOWN_DELAY_MINUTES). Falling back to local configuration."
        fi
    else
        send_log "warn" "Failed to connect to API Hub at $API_SERVER_URI. Falling back to local configuration."
    fi
else
    send_log "info" "API server not configured. Using local configuration."
fi

# --- MAIN SCRIPT LOGIC ---
SHUTDOWN_DELAY_SECONDS=$((SHUTDOWN_DELAY_MINUTES * 60))

# Get UPS status via API endpoint
if [[ -z "$API_SERVER_URI" || -z "$API_TOKEN" ]]; then
    send_log "err" "ERROR: API server configuration is required. Please set API_SERVER_URI and API_TOKEN in ups.env"
    exit 1
fi

UPS_STATUS_URL="${API_SERVER_URI}/upsc"
UPS_RESPONSE=$(curl --fail --silent --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${API_TOKEN}" "$UPS_STATUS_URL")

if [ $? -ne 0 ]; then
    send_log "err" "ERROR: Could not get status from UPS server API ($UPS_STATUS_URL). Check connection and API configuration."
    exit 1
fi

# Extract status and simulation flag from JSON response using jq
CURRENT_STATUS=$(echo "$UPS_RESPONSE" | jq -e -r '.ups.status')
STATUS_EXIT_CODE=$?
UPS_SIMULATION=$(echo "$UPS_RESPONSE" | jq -r '.ups.simulation // false')

if [ $STATUS_EXIT_CODE -ne 0 ] || [ -z "$CURRENT_STATUS" ] || [ "$CURRENT_STATUS" = "null" ]; then
    send_log "err" "ERROR: Could not parse UPS status from API response. Expected 'ups.status' field in JSON."
    exit 1
fi

if [[ "$CURRENT_STATUS" == "OB LB" ]]; then
    # Check if we should ignore this status due to simulation mode
    if [[ "$UPS_SIMULATION" == "true" && "$IGNORE_SIMULATION" == "true" ]]; then
        send_log "info" "UPS is in simulation mode and IGNORE_SIMULATION is enabled. Ignoring OB LB status."
        # Cancel any pending shutdown
        if [ -f "$FLAG_FILE" ]; then
            send_log "info" "Cancelling pending shutdown due to simulation mode."
            rm -f "$FLAG_FILE"
        fi
        # Report online status since we're ignoring the simulated power failure
        send_status_update "online"
    else
        # Normal shutdown procedure
        if [ ! -f "$FLAG_FILE" ]; then
            send_log "warn" "Low battery detected! Starting $SHUTDOWN_DELAY_MINUTES minute countdown..."
            date +%s > "$FLAG_FILE"
            send_status_update "shutdown_pending" "$SHUTDOWN_DELAY_SECONDS" "$SHUTDOWN_DELAY_MINUTES"
        else
            START_TIME=$(cat "$FLAG_FILE")
            CURRENT_TIME=$(date +%s)
            ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
            REMAINING_SECONDS=$((SHUTDOWN_DELAY_SECONDS - ELAPSED_TIME))

            if [ "$ELAPSED_TIME" -ge "$SHUTDOWN_DELAY_SECONDS" ]; then
                send_log "err" "Shutdown delay passed. Shutting down NOW."
                send_status_update "shutting_down"
                rm -f "$FLAG_FILE"
                /sbin/shutdown -h now
                exit 0
            else
                # Wysyłaj aktualizację co minutę
                send_status_update "shutdown_pending" "$REMAINING_SECONDS" "$SHUTDOWN_DELAY_MINUTES"
            fi
        fi
    fi
elif [[ "$CURRENT_STATUS" == "OL" ]]; then
    if [ -f "$FLAG_FILE" ]; then
        send_log "info" "Mains power restored. Cancelling shutdown."
        rm -f "$FLAG_FILE"
    fi
    # Always report that the client is online and healthy on every successful run
    send_status_update "online"
fi

exit 0