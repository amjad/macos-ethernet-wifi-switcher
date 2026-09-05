#!/bin/bash

set -euo pipefail

LABEL="io.github.amjad.macos-ethernet-wifi-switcher"
INSTALL_DIR="$HOME/.local/lib/macos-ethernet-wifi-switcher"
BINARY="$INSTALL_DIR/ethernet-wifi-watcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

MODE="presence"
ETHERNET_INTERFACE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --ethernet)
            ETHERNET_INTERFACE="${2:-}"
            shift 2
            ;;
        -h|--help)
            echo "Usage:"
            echo "  ./install.sh"
            echo "  ./install.sh --ethernet en7"
            echo "  ./install.sh --ethernet en7 --mode active"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "$MODE" != "presence" && "$MODE" != "active" ]]; then
    echo "Mode must be 'presence' or 'active'."
    exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
    echo "Swift compiler not found."
    echo
    echo "Install Apple's Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

WIFI_INTERFACE=$(
    /usr/sbin/networksetup -listallhardwareports |
    awk '
        /Hardware Port: Wi-Fi/ {
            getline
            if ($1 == "Device:") {
                print $2
                exit
            }
        }
    '
)

if [[ -z "$WIFI_INTERFACE" ]]; then
    echo "Could not detect the Wi-Fi interface."
    exit 1
fi

echo
echo "Detected Wi-Fi interface: $WIFI_INTERFACE"
echo

if [[ -z "$ETHERNET_INTERFACE" ]]; then
    echo "Available network interfaces:"
    echo

    /usr/sbin/networksetup -listallhardwareports |
    awk '
        /^Hardware Port:/ {
            port=$0
            sub(/^Hardware Port: /, "", port)
        }
        /^Device:/ {
            printf "  %-8s %s\n", $2, port
        }
    '

    echo
    read -r -p "Enter Ethernet interface to monitor (example: en7): " ETHERNET_INTERFACE
fi

if [[ ! "$ETHERNET_INTERFACE" =~ ^[A-Za-z0-9]+$ ]]; then
    echo "Invalid Ethernet interface."
    exit 1
fi

if [[ "$ETHERNET_INTERFACE" == "$WIFI_INTERFACE" ]]; then
    echo "Ethernet interface cannot be the same as Wi-Fi."
    exit 1
fi

echo
echo "Installing macOS Ethernet Wi-Fi Switcher"
echo
echo "Wi-Fi:    $WIFI_INTERFACE"
echo "Ethernet: $ETHERNET_INTERFACE"
echo "Mode:     $MODE"
echo

mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

/usr/bin/swiftc \
    -framework SystemConfiguration \
    "$(pwd)/Sources/EthernetWiFiWatcher.swift" \
    -o "$BINARY"

chmod +x "$BINARY"

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
        <string>--wifi</string>
        <string>$WIFI_INTERFACE</string>
        <string>--ethernet</string>
        <string>$ETHERNET_INTERFACE</string>
        <string>--mode</string>
        <string>$MODE</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/macos-ethernet-wifi-switcher.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/macos-ethernet-wifi-switcher-error.log</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$PLIST"

launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo
echo "Installation complete."
echo
echo "The watcher will automatically start when you log in."
