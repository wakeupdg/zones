import AppKit
import Foundation
import ServiceManagement

// HardwareProbe: throwaway spike for T08 (SPK-011, SPK-012, SPK-014, SPK-018).
// Each subcommand runs alone. Output is timestamped plain text.

func stamp() -> String {
  let f = DateFormatter()
  f.locale = Locale(identifier: "en_US_POSIX")
  f.timeZone = TimeZone(identifier: "America/Los_Angeles")
  f.dateFormat = "h:mm:ss a 'PT'"
  return f.string(from: Date())
}

func log(_ message: String) {
  print("[\(stamp())] \(message)")
  fflush(stdout)
}

let usage = """
  HardwareProbe <command> [options]

  login      [status|register|unregister|open-settings]   SPK-011
  displays                                                SPK-012
  hotkey     [--activate|--no-activate]                   SPK-014
  sleepwake                                               SPK-018
  post-wake                                               SPK-018 (re-print state)
  """


// MARK: login (SPK-011)

/// Mirrors CONTRACTS `LoginItemStatus` so verdicts map straight onto it.
enum LoginItemStatus: String {
  case enabled, requiresApproval, notFound, notRegistered
}

func mapStatus(_ status: SMAppService.Status) -> LoginItemStatus {
  switch status {
  case .enabled: .enabled
  case .requiresApproval: .requiresApproval
  case .notFound: .notFound
  case .notRegistered: .notRegistered
  @unknown default: .notFound
  }
}

func quarantineValue(of path: String) -> String {
  let size = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0)
  guard size > 0 else { return "none" }
  var buffer = [UInt8](repeating: 0, count: size)
  let read = getxattr(path, "com.apple.quarantine", &buffer, size, 0, 0)
  return read > 0 ? String(decoding: buffer.prefix(read), as: UTF8.self) : "unreadable"
}

@MainActor
func printLoginState(_ label: String) {
  let bundle = Bundle.main
  let status = mapStatus(SMAppService.mainApp.status)
  log("login[\(label)] status=\(status.rawValue) (raw \(SMAppService.mainApp.status.rawValue))")
  log("login[\(label)] bundlePath=\(bundle.bundlePath)")
  log("login[\(label)] bundleID=\(bundle.bundleIdentifier ?? "nil") isApp=\(bundle.bundlePath.hasSuffix(".app"))")
  log("login[\(label)] quarantine=\(quarantineValue(of: bundle.bundlePath))")
  log("login[\(label)] macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
}

@MainActor
func runLogin(_ args: [String]) -> Int32 {
  let action = args.first ?? "status"
  printLoginState("before")
  switch action {
  case "status":
    return 0
  case "register":
    do {
      try SMAppService.mainApp.register()
      log("login register: ok")
    } catch {
      let ns = error as NSError
      log("login register: FAILED domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
    }
  case "unregister":
    do {
      try SMAppService.mainApp.unregister()
      log("login unregister: ok")
    } catch {
      let ns = error as NSError
      log("login unregister: FAILED domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
    }
  case "open-settings":
    SMAppService.openSystemSettingsLoginItems()
    log("login open-settings: requested")
  default:
    FileHandle.standardError.write(Data("login: unknown action \(action)\n".utf8))
    return 64
  }
  printLoginState("after")
  return 0
}

@MainActor
func run(_ args: [String]) -> Int32 {
  guard let command = args.first else {
    print(usage)
    return 64
  }
  switch command {
  case "-h", "--help", "help":
    print(usage)
    return 0
  case "login":
    return runLogin(Array(args.dropFirst()))
  default:
    FileHandle.standardError.write(Data("unknown command: \(command)\n\(usage)\n".utf8))
    return 64
  }
}

exit(run(Array(CommandLine.arguments.dropFirst())))
