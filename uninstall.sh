#!/bin/bash

set -euo pipefail

LABEL="io.github.amjad.macos-ethernet-wifi-switcher"
INSTALL_DIR="$HOME/.local/lib/macos-ethernet-wifi-switcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "Removing macOS Ethernet Wi-Fi Switcher..."

launchctl bootout \
    "gui/$(id -u)" \
    "$PLIST" \
    2>/dev/null || true

rm -f "$PLIST"
rm -rf "$INSTALL_DIR"

echo
echo "Removed successfully."
echo "The current Wi-Fi state was left unchanged."
