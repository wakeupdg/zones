import AppKit
import ApplicationServices
import ColorSync
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

// MARK: displays (SPK-012)

/// Mirrors CONTRACTS `DisplayKey`: `.uuid` is stable, `.unstable` is session only.
enum DisplayKey: Hashable {
  case uuid(String), unstable(String)
}

struct DisplayRecord {
  let displayID: CGDirectDisplayID
  let uuid: String?
  let vendor: UInt32
  let model: UInt32
  let serial: UInt32
  let name: String
  let isMain: Bool
  let frame: CGRect

  /// vendor-model-serial-bounds fallback fingerprint, used when UUID is nil or serial is 0.
  var fallbackFingerprint: String {
    "v\(vendor)-m\(model)-s\(serial)-\(Int(frame.width))x\(Int(frame.height))@\(Int(frame.origin.x)),\(Int(frame.origin.y))"
  }

  var key: DisplayKey {
    if let uuid { return .uuid(uuid) }
    return .unstable(fallbackFingerprint)
  }
}

func displayUUID(_ id: CGDirectDisplayID) -> String? {
  guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
  let uuid = unmanaged.takeRetainedValue()
  return CFUUIDCreateString(nil, uuid) as String?
}

@MainActor
func currentDisplays() -> [DisplayRecord] {
  NSScreen.screens.compactMap { screen in
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else { return nil }
    let id = CGDirectDisplayID(number.uint32Value)
    return DisplayRecord(
      displayID: id,
      uuid: displayUUID(id),
      vendor: CGDisplayVendorNumber(id),
      model: CGDisplayModelNumber(id),
      serial: CGDisplaySerialNumber(id),
      name: screen.localizedName,
      isMain: CGDisplayIsMain(id) != 0,
      frame: screen.frame
    )
  }
}

@MainActor
func printDisplays(_ label: String) -> [DisplayRecord] {
  let records = currentDisplays()
  log("displays[\(label)] count=\(records.count)")
  for (index, d) in records.enumerated() {
    log(
      "displays[\(label)] #\(index) id=\(d.displayID) uuid=\(d.uuid ?? "nil") vendor=\(d.vendor) model=\(d.model) serial=\(d.serial) name=\"\(d.name)\" main=\(d.isMain) frame=\(d.frame)"
    )
    if d.uuid == nil || d.serial == 0 {
      log("displays[\(label)] #\(index) fallback fingerprint=\(d.fallbackFingerprint) (uuid nil=\(d.uuid == nil), zero serial=\(d.serial == 0))")
    }
  }
  return records
}

@MainActor
func runDisplays() -> Int32 {
  log("displays macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
  let records = printDisplays("now")
  let uuids = records.compactMap(\.uuid)
  let allDistinct = uuids.count == records.count && Set(uuids).count == uuids.count
  log("displays distinct-uuid check: \(allDistinct ? "PASS" : "FAIL") (\(Set(uuids).count) distinct of \(records.count))")

  // Same-model groups: the case SPK-012 cares about.
  let groups = Dictionary(grouping: records, by: { "\($0.vendor)-\($0.model)" })
  let identical = groups.filter { $0.value.count > 1 }
  if identical.isEmpty {
    log("displays identical-model: UNTESTED (no two same vendor/model Displays attached)")
  } else {
    for (model, members) in identical {
      let distinct = Set(members.compactMap(\.uuid)).count == members.count
      let zeroSerials = members.allSatisfy { $0.serial == 0 }
      log("displays identical-model \(model): \(members.count) Displays, UUIDs distinct=\(distinct ? "PASS" : "FAIL"), all serials zero=\(zeroSerials)")
    }
  }
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
  case "displays":
    return runDisplays()
  default:
    FileHandle.standardError.write(Data("unknown command: \(command)\n\(usage)\n".utf8))
    return 64
  }
}

exit(run(Array(CommandLine.arguments.dropFirst())))
