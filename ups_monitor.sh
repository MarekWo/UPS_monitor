#!/bin/bash

################################################################################
#
# Universal UPS Status Monitor (v3.1.0)
#
# This script monitors a NUT (Network UPS Tools) server and safely shuts down
# the local system in case of a power failure. It is designed to be run from
# cron every minute.
#
# Features:
# - Configurable shutdown delay.
# - Shutdown cancellation if power is restored.
# - Stateful operation using a flag file.
# - External configuration via an .env file.
# - Universal logging for Synology DSM and standard Linux.
#
################################################################################

# --- Load external configuration ---
# Find the directory where the script is located to source the .env file.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
CONFIG_FILE="$SCRIPT_DIR/ups.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Use standard logger here as the custom function isn't defined yet.
    logger -t "UPS_Monitor_Core" "CRITICAL ERROR: Configuration file not found at $CONFIG_FILE. Exiting."
    exit 1
fi

# --- Set default values for variables if they are not in the .env file ---
UPS_NAME="${UPS_NAME:-ups@localhost}"
SHUTDOWN_DELAY_MINUTES="${SHUTDOWN_DELAY_MINUTES:-5}"
FLAG_FILE="${FLAG_FILE:-/tmp/ups_shutdown_pending.flag}"
LOG_TAG="${LOG_TAG:-UPS_Shutdown_Script}"

# --- Universal logging function ---
send_log() {
    # Arguments: level message
    # level: info, warn, err
    local level="${1:-info}"
    shift
    local msg="$*"

    # Check for Synology DSM environment
    if [ -x /usr/syno/bin/synologset1 ]; then
        # Use Synology's specific logging tool
        /usr/syno/bin/synologset1 sys "$level" 0x11100000 "$msg"
    else
        # Use standard logger for other Linux systems, mapping level to priority
        logger -t "$LOG_TAG" -p "user.$level" "$msg"
    fi
}

# --- MAIN SCRIPT LOGIC - DO NOT EDIT BELOW ---

# Calculate delay in seconds for the internal counter
SHUTDOWN_DELAY_SECONDS=$((SHUTDOWN_DELAY_MINUTES * 60))

# Get the current UPS status. Errors are redirected to /dev/null.
CURRENT_STATUS=$(upsc "$UPS_NAME" ups.status 2>/dev/null)

# Check if the connection to the UPS server was successful
if [ -z "$CURRENT_STATUS" ]; then
    send_log "err" "ERROR: Could not get status from UPS server ($UPS_NAME). Check connection."
    exit 1
fi

# --- Main decision loop ---
if [[ "$CURRENT_STATUS" == "OB LB" ]]; then
    # STATUS: On Battery, Low Battery

    if [ ! -f "$FLAG_FILE" ]; then
        # Flag file does not exist - this is the FIRST detection of a low battery state.
        # Start the countdown.
        send_log "warn" "Low battery detected! Starting $SHUTDOWN_DELAY_MINUTES minute countdown to system shutdown."
        
        # Write the current timestamp (seconds since epoch) to the flag file.
        date +%s > "$FLAG_FILE"
    else
        # Flag file already exists - the countdown is in progress.
        # Check if the delay has passed.
        
        START_TIME=$(cat "$FLAG_FILE")
        CURRENT_TIME=$(date +%s)
        ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

        if [ "$ELAPSED_TIME" -ge "$SHUTDOWN_DELAY_SECONDS" ]; then
            # The delay has passed. Execute immediate shutdown.
            send_log "err" "Shutdown delay of $SHUTDOWN_DELAY_MINUTES minutes has passed. Shutting down NOW."
            
            # Remove the flag file before shutting down
            rm -f "$FLAG_FILE"
            
            # Execute immediate shutdown
            /sbin/shutdown -h now
            exit 0
        fi
    fi

elif [[ "$CURRENT_STATUS" == "OL" ]]; then
    # STATUS: On Line (Mains power)

    if [ -f "$FLAG_FILE" ]; then
        # Flag file exists - this means a countdown was in progress.
        # Cancel it.
        send_log "info" "Mains power has been restored. Cancelling shutdown countdown."
        
        # Cancellation is as simple as removing the flag file.
        rm -f "$FLAG_FILE"
    fi
fi

exit 0