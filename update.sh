#!/bin/bash

# A simple script to download the latest version of ups_monitor.sh from GitHub.

# --- CONFIGURATION ---
# IMPORTANT: Replace this URL with the raw content URL from your own GitHub repository.
SCRIPT_URL="https://raw.github.com/MarekWo/UPS_monitor/main/ups_monitor.sh"

# The local path where the script should be saved.
# This should be the same directory where your ups.env file is located.
INSTALL_DIR="/opt/ups-monitor" # Example: /opt/ups-monitor or /volume1/scripts

# --- SCRIPT LOGIC ---
echo "Downloading latest version of the UPS monitor script..."
curl -s -L -o "$INSTALL_DIR/ups_monitor.sh.tmp" "$SCRIPT_URL"

if [ $? -eq 0 ] && [ -s "$INSTALL_DIR/ups_monitor.sh.tmp" ]; then
    # Download was successful and file is not empty
    mv "$INSTALL_DIR/ups_monitor.sh.tmp" "$INSTALL_DIR/ups_monitor.sh"
    chmod +x "$INSTALL_DIR/ups_monitor.sh"
    echo "Update successful. The script is now executable."
else
    # Download failed
    echo "ERROR: Failed to download the script. Please check the URL and your network connection."
    rm -f "$INSTALL_DIR/ups_monitor.sh.tmp"
fi