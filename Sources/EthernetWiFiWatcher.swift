import Foundation
import SystemConfiguration

enum DetectionMode: String {
    case presence
    case active
}

struct Configuration {
    let wifiInterface: String
    let ethernetInterface: String
    let mode: DetectionMode
}

func printUsage() {
    print("""
    Usage:
      ethernet-wifi-watcher --wifi <interface> --ethernet <interface> [--mode presence|active]
    """)
}

func parseArguments() -> Configuration? {
    let arguments = Array(CommandLine.arguments.dropFirst())

    var wifiInterface: String?
    var ethernetInterface: String?
    var mode: DetectionMode = .presence

    var index = 0

    while index < arguments.count {
        switch arguments[index] {
        case "--wifi":
            guard index + 1 < arguments.count else { return nil }
            wifiInterface = arguments[index + 1]
            index += 2

        case "--ethernet":
            guard index + 1 < arguments.count else { return nil }
            ethernetInterface = arguments[index + 1]
            index += 2

        case "--mode":
            guard index + 1 < arguments.count,
                  let parsedMode = DetectionMode(rawValue: arguments[index + 1]) else {
                return nil
            }

            mode = parsedMode
            index += 2

        case "--help", "-h":
            printUsage()
            exit(0)

        default:
            return nil
        }
    }

    guard let wifi = wifiInterface,
          let ethernet = ethernetInterface else {
        return nil
    }

    return Configuration(
        wifiInterface: wifi,
        ethernetInterface: ethernet,
        mode: mode
    )
}

guard let parsedConfig = parseArguments() else {
    printUsage()
    exit(1)
}

enum Runtime {
    static var config: Configuration!
}

Runtime.config = parsedConfig

func run(_ executable: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        NSLog("Failed to run \(executable): \(error)")
    }
}

func wifiIsOn() -> Bool {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    process.arguments = ["-getairportpower", Runtime.config.wifiInterface]
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output.contains(": On")
    } catch {
        return false
    }
}

func ethernetIsPresent() -> Bool {
    let process = Process()

    process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    process.arguments = [Runtime.config.ethernetInterface]
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func ethernetIsActive() -> Bool {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    process.arguments = [Runtime.config.ethernetInterface]
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output.contains("status: active")
    } catch {
        return false
    }
}

func ethernetShouldDisableWiFi() -> Bool {
    switch Runtime.config.mode {
    case .presence:
        return ethernetIsPresent()

    case .active:
        return ethernetIsActive()
    }
}

func updateWiFi() {
    let ethernetReady = ethernetShouldDisableWiFi()
    let wifiOn = wifiIsOn()

    if ethernetReady && wifiOn {
        NSLog("Ethernet detected — disabling Wi-Fi")

        run(
            "/usr/sbin/networksetup",
            ["-setairportpower", Runtime.config.wifiInterface, "off"]
        )

    } else if !ethernetReady && !wifiOn {
        NSLog("Ethernet unavailable — enabling Wi-Fi")

        run(
            "/usr/sbin/networksetup",
            ["-setairportpower", Runtime.config.wifiInterface, "on"]
        )
    }
}

func callback(
    store: SCDynamicStore,
    changedKeys: CFArray,
    info: UnsafeMutableRawPointer?
) {
    updateWiFi()
}

var context = SCDynamicStoreContext(
    version: 0,
    info: nil,
    retain: nil,
    release: nil,
    copyDescription: nil
)

guard let store = SCDynamicStoreCreate(
    nil,
    "io.github.amjad.macos-ethernet-wifi-switcher" as CFString,
    callback,
    &context
) else {
    exit(1)
}

let patterns = [
    "State:/Network/Interface/\(Runtime.config.ethernetInterface)/.*",
    "State:/Network/Global/.*"
] as CFArray

SCDynamicStoreSetNotificationKeys(store, nil, patterns)

guard let source =
    SCDynamicStoreCreateRunLoopSource(nil, store, 0)
else {
    exit(1)
}

CFRunLoopAddSource(
    CFRunLoopGetCurrent(),
    source,
    CFRunLoopMode.defaultMode
)

updateWiFi()
CFRunLoopRun()
