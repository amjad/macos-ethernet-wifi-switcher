# macOS Ethernet Wi-Fi Switcher

Automatically disable **Wi-Fi when Ethernet is connected** and turn Wi-Fi back on when Ethernet is disconnected.

The watcher runs in the background on macOS and uses Apple's `SystemConfiguration` framework to react to network changes instead of polling every few seconds.

## Why this exists

macOS normally allows Wi-Fi and Ethernet to stay enabled at the same time.

That is usually fine, but in some environments it can lead to unwanted behavior such as:

- SMB or file-sharing connections using an unexpected IP address
- a Mac being reachable through multiple network addresses
- inconsistent local-network routing
- applications switching between wired and wireless paths
- Wi-Fi remaining active when a wired dock is already being used

This utility automatically prefers your chosen Ethernet connection.

## What it does

```text
Ethernet / dock connected
        ↓
Ethernet interface detected
        ↓
Wi-Fi OFF


Ethernet / dock disconnected
        ↓
Ethernet interface disappears
        ↓
Wi-Fi ON
```

The utility runs as a per-user macOS `LaunchAgent`.

## Event-driven

This is not a polling script.

The Swift watcher subscribes to network configuration changes through:

```text
SystemConfiguration
SCDynamicStore
```

macOS notifies the watcher when relevant network state changes occur.

The watcher then uses Apple's built-in `networksetup` command to enable or disable Wi-Fi.

## Detection modes

The utility supports two Ethernet detection modes.

### Presence mode

This is the default.

```text
presence
```

Wi-Fi is disabled when the selected Ethernet interface exists on the Mac.

This is particularly useful for:

- USB-C docks
- Thunderbolt docks
- USB Ethernet adapters
- docking stations whose Ethernet interface disappears when disconnected

Presence mode does not wait for Ethernet link negotiation, so it may respond sooner than active-link detection.

Example:

```bash
./install.sh --ethernet en7 --mode presence
```

### Active mode

```text
active
```

Wi-Fi is disabled only when the selected interface reports:

```text
status: active
```

through `ifconfig`.

This mode is better if your Ethernet adapter stays connected to the Mac while the Ethernet cable itself may be unplugged.

Example:

```bash
./install.sh --ethernet en7 --mode active
```

## Requirements

- macOS
- Apple Command Line Tools
- Swift compiler
- Ethernet adapter, dock, or built-in Ethernet interface

Check whether Swift is installed:

```bash
swiftc --version
```

If it is not available:

```bash
xcode-select --install
```

## Installation

Clone the repository:

```bash
git clone https://github.com/amjad/macos-ethernet-wifi-switcher.git
cd macos-ethernet-wifi-switcher
```

Run the installer:

```bash
./install.sh
```

The installer automatically detects the Mac's Wi-Fi interface.

It then displays the available network interfaces and asks which Ethernet interface should be monitored.

Example:

```text
en0      Wi-Fi
en7      USB 10/100/1G/2.5G LAN
```

Enter the Ethernet device:

```text
en7
```

The installer will then:

- compile the Swift watcher
- install it under your user account
- create a LaunchAgent
- start the watcher
- configure it to start automatically at login

## Install without the prompt

If you already know your Ethernet interface:

```bash
./install.sh --ethernet en7
```

Presence mode is used by default.

Explicitly select presence mode:

```bash
./install.sh --ethernet en7 --mode presence
```

Or use active-link mode:

```bash
./install.sh --ethernet en7 --mode active
```

## Find your network interfaces

Run:

```bash
networksetup -listallhardwareports
```

Example output:

```text
Hardware Port: USB 10/100/1G/2.5G LAN
Device: en7
Ethernet Address: xx:xx:xx:xx:xx:xx

Hardware Port: Wi-Fi
Device: en0
Ethernet Address: xx:xx:xx:xx:xx:xx
```

In this example:

```text
Wi-Fi:    en0
Ethernet: en7
```

You can inspect an interface directly:

```bash
ifconfig en7
```

To see its link state:

```bash
ifconfig en7 | grep -E "status:|media:"
```

## Installed files

The compiled watcher is installed at:

```text
~/.local/lib/macos-ethernet-wifi-switcher/ethernet-wifi-watcher
```

The LaunchAgent is installed at:

```text
~/Library/LaunchAgents/io.github.amjad.macos-ethernet-wifi-switcher.plist
```

## Check whether it is running

Run:

```bash
launchctl print \
gui/$(id -u)/io.github.amjad.macos-ethernet-wifi-switcher
```

## Check Wi-Fi state

Run:

```bash
networksetup -getairportpower en0
```

Your Wi-Fi interface may be different from `en0`.

The installer detects it automatically.

## Logs

Standard output:

```text
/tmp/macos-ethernet-wifi-switcher.log
```

Errors:

```text
/tmp/macos-ethernet-wifi-switcher-error.log
```

You can also inspect macOS unified logs:

```bash
log show \
--predicate 'process == "ethernet-wifi-watcher"' \
--last 10m
```

Or watch events live:

```bash
log stream \
--predicate 'process == "ethernet-wifi-watcher"'
```

## Change the Ethernet interface

Run the installer again with another interface:

```bash
./install.sh --ethernet en8
```

The LaunchAgent configuration will be replaced.

## Change detection mode

Switch to active mode:

```bash
./install.sh --ethernet en7 --mode active
```

Switch back to presence mode:

```bash
./install.sh --ethernet en7 --mode presence
```

## Uninstall

Run:

```bash
./uninstall.sh
```

The uninstaller removes:

```text
~/Library/LaunchAgents/io.github.amjad.macos-ethernet-wifi-switcher.plist
```

and:

```text
~/.local/lib/macos-ethernet-wifi-switcher/
```

It intentionally leaves the current Wi-Fi state unchanged.

## Presence mode caveat

Presence mode assumes that the existence of the selected Ethernet interface means Ethernet should be preferred.

Some docks keep their Ethernet interface present even when there is no active Ethernet cable.

In that situation Wi-Fi may remain disabled even though the wired connection is not usable.

Use active mode instead:

```bash
./install.sh --ethernet en7 --mode active
```

## Response time

The watcher itself is event-driven and therefore has no fixed polling interval.

Actual response time also depends on how quickly macOS enumerates or removes the Ethernet interface.

USB-C, Thunderbolt, and Ethernet hardware can take several seconds to initialize after being connected.

## Privacy

This utility runs completely locally.

It:

- makes no external network requests
- collects no analytics
- contains no telemetry
- sends no data anywhere
- requires no cloud service

## How the watcher works

The main watcher is written in Swift.

Its behavior is approximately:

```text
macOS network event
       ↓
SCDynamicStore callback
       ↓
Check selected Ethernet interface
       ↓
Compare desired Wi-Fi state
       ↓
networksetup -setairportpower
```

The watcher avoids changing Wi-Fi when the current state already matches the desired state.

## Project structure

```text
macos-ethernet-wifi-switcher/
├── Sources/
│   └── EthernetWiFiWatcher.swift
├── install.sh
├── uninstall.sh
├── README.md
├── LICENSE
└── .gitignore
```

## Background

This project originated while troubleshooting local SMB/file-sharing behavior on a Mac connected simultaneously through Wi-Fi and Ethernet.

The Mac had two active network interfaces and therefore two local IP addresses. Using the wired address resolved the immediate SMB issue.

Rather than manually disabling Wi-Fi whenever the dock was connected, the process was automated.

The initial implementation used periodic polling.

It was later replaced with an event-driven Swift watcher using macOS `SystemConfiguration`.

## Compatibility

The project is designed for modern versions of macOS that provide:

- `SystemConfiguration`
- `SCDynamicStore`
- `networksetup`
- `launchd`

Interface naming varies between Macs and adapters, which is why Ethernet interfaces are configurable instead of hard-coded.

## License

MIT License.
