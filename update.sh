#!/bin/bash

# A simple script to download the latest version of ups_monitor.sh from GitHub.

# --- CONFIGURATION ---
SCRIPT_URL="https://raw.githubusercontent.com/MarekWo/UPS_monitor/main/ups_monitor.sh"
INSTALL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- SCRIPT LOGIC ---
echo "Downloading latest version of the UPS monitor script..."
# Download to a temporary file first
curl -s -L -o "$INSTALL_DIR/ups_monitor.sh.tmp" "$SCRIPT_URL"

# Check if download was successful and the file is not empty
if [ $? -eq 0 ] && [ -s "$INSTALL_DIR/ups_monitor.sh.tmp" ]; then
    # Overwrite the old script only if the new one is valid
    mv "$INSTALL_DIR/ups_monitor.sh.tmp" "$INSTALL_DIR/ups_monitor.sh"
    chmod +x "$INSTALL_DIR/ups_monitor.sh"
    echo "Update successful. The script is now executable."
else
    echo "ERROR: Failed to download a valid script. No changes were made."
    # Clean up the failed download
    rm -f "$INSTALL_DIR/ups_monitor.sh.tmp"
fi