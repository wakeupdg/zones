import AppKit
import Carbon.HIToolbox
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
  hotkey     [--activate|--no-activate] [--simulate] [--exit-after S]  SPK-014
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

// MARK: hotkey (SPK-014)

/// Mirrors CONTRACTS `HotkeyRegistration`.
enum HotkeyRegistration { case registered, inUse, invalid }

/// A plain titled window that echoes typed characters, so "typing lands" is observable.
final class ProbeWindow: NSWindow {
  var typed = ""
  var onType: ((String) -> Void)?
  override var canBecomeKey: Bool { true }
  override func keyDown(with event: NSEvent) {
    let chars = event.characters ?? ""
    typed += chars
    onType?(typed)
    log("hotkey keyDown reached window: chars=\"\(chars)\" typed=\"\(typed)\"")
  }
}

@MainActor
final class HotkeyProbe {
  static let shared = HotkeyProbe()
  var activateFirst = true
  var window: ProbeWindow?
  var label: NSTextField?
  var presses = 0
  var hotKeyRef: EventHotKeyRef?

  func register() -> HotkeyRegistration {
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        MainActor.assumeIsolated { HotkeyProbe.shared.handlerFired() }
        return noErr
      }, 1, &spec, nil, nil)
    guard installStatus == noErr else {
      log("hotkey InstallEventHandler failed: \(installStatus)")
      return .invalid
    }
    let id = EventHotKeyID(signature: OSType(0x5A4F4E45), id: 1)  // 'ZONE'
    let status = RegisterEventHotKey(
      UInt32(kVK_ANSI_Comma), UInt32(controlKey | optionKey), id,
      GetApplicationEventTarget(), 0, &hotKeyRef)
    switch status {
    case noErr: return .registered
    case OSStatus(eventHotKeyExistsErr): return .inUse
    default:
      log("hotkey RegisterEventHotKey status=\(status)")
      return .invalid
    }
  }

  func snapshot(_ label: String) {
    let w = window
    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
    log(
      "hotkey[\(label)] isVisible=\(w?.isVisible ?? false) isKeyWindow=\(w?.isKeyWindow ?? false) isMainWindow=\(w?.isMainWindow ?? false) NSApp.isActive=\(NSApp.isActive) frontmost=\"\(front)\" onActiveSpace=\(w?.isOnActiveSpace ?? false)"
    )
  }

  func handlerFired() {
    presses += 1
    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
    log("hotkey PRESS #\(presses) in handler; frontmost-before=\"\(front)\" mode=\(activateFirst ? "--activate" : "--no-activate")")
    if window == nil { makeWindow() }
    guard let w = window else { return }
    w.typed = ""
    label?.stringValue = "type here (mode \(activateFirst ? "activate" : "no-activate"))"
    if activateFirst { NSApp.activate() }
    w.orderFrontRegardless()
    snapshot("immediately after orderFront")
    for (ms, name) in [(150, "+150ms"), (600, "+600ms")] {
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
        MainActor.assumeIsolated { HotkeyProbe.shared.snapshot(name) }
      }
    }
  }

  func makeWindow() {
    let w = ProbeWindow(
      contentRect: NSRect(x: 200, y: 400, width: 420, height: 140),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.title = "HardwareProbe hotkey"
    w.isReleasedWhenClosed = false
    let field = NSTextField(labelWithString: "type here")
    field.frame = NSRect(x: 16, y: 50, width: 388, height: 40)
    w.contentView?.addSubview(field)
    w.onType = { text in field.stringValue = "typed: \(text)" }
    label = field
    window = w
  }
}

/// Post Control+Option+Comma from this process so the run can be driven without a human.
/// Needs Accessibility trust to reach other apps' event queue; the result is logged either way.
func postSyntheticChord() {
  let source = CGEventSource(stateID: .hidSystemState)
  for down in [true, false] {
    let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Comma), keyDown: down)
    e?.flags = [.maskControl, .maskAlternate]
    e?.post(tap: .cghidEventTap)
  }
  log("hotkey --simulate: posted Control+Option+Comma (trusted=\(AXIsProcessTrusted()))")
}

/// Post a plain key after the chord: it lands in the window only if the window is key.
func postSyntheticKey(_ key: CGKeyCode) {
  let source = CGEventSource(stateID: .hidSystemState)
  for down in [true, false] {
    let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
    e?.flags = []
    e?.post(tap: .cghidEventTap)
  }
  log("hotkey --simulate: posted plain key 'z'")
}

@MainActor
func runHotkey(_ args: [String]) -> Int32 {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)  // mimics ADR 0019 LSUIElement
  HotkeyProbe.shared.activateFirst = !args.contains("--no-activate")
  log("hotkey macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) mode=\(HotkeyProbe.shared.activateFirst ? "--activate" : "--no-activate")")
  let result = HotkeyProbe.shared.register()
  log("hotkey registration: \(result)")
  guard result == .registered else { return 1 }
  log("hotkey ready: bring TextEdit frontmost, press Control+Option+Comma, then type. Ctrl-C to quit.")
  if args.contains("--simulate") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { postSyntheticChord() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { postSyntheticKey(CGKeyCode(kVK_ANSI_Z)) }
  }
  if let seconds = args.firstIndex(of: "--exit-after").flatMap({ Double(args[safe: $0 + 1] ?? "") }) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
  }
  app.run()
  return 0
}

extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: sleepwake (SPK-018)

let sleepWakeStatePath = NSTemporaryDirectory() + "HardwareProbe-sleepwake.json"
let sleepWakePidPath = NSTemporaryDirectory() + "HardwareProbe-sleepwake.pid"

@MainActor
final class SleepWakeProbe {
  static let shared = SleepWakeProbe()
  var tap: CFMachPort?
  var panels: [CGDirectDisplayID: NSPanel] = [:]
  var eventCount = 0

  func installTap() {
    let mask: CGEventMask =
      (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
      | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
      eventsOfInterest: mask,
      callback: { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
          log("sleepwake tap DISABLED by system: \(type)")
        } else {
          MainActor.assumeIsolated { SleepWakeProbe.shared.eventCount += 1 }
        }
        return Unmanaged.passUnretained(event)
      }, userInfo: nil)
    guard let tap else {
      log("sleepwake tap creation FAILED (nil): Input Monitoring not granted to this process?")
      return
    }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    log("sleepwake tap created and enabled")
  }

  func rebuildPanels() {
    for panel in panels.values { panel.orderOut(nil) }
    panels = [:]
    for screen in NSScreen.screens {
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { continue }
      let panel = NSPanel(
        contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false)
      panel.isOpaque = false
      panel.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
      panel.level = .statusBar
      panel.ignoresMouseEvents = true  // click-through
      panel.hasShadow = false
      panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
      panel.isReleasedWhenClosed = false
      panel.setFrame(screen.frame, display: false)
      panel.orderFrontRegardless()
      panels[CGDirectDisplayID(number.uint32Value)] = panel
    }
    log("sleepwake panels rebuilt: \(panels.count)")
  }

  func printState(_ label: String) {
    let tapState = tap.map { CGEvent.tapIsEnabled(tap: $0) ? "enabled" : "DISABLED" } ?? "none"
    log("sleepwake[\(label)] tap=\(tapState) eventsSeen=\(eventCount)")
    for (id, panel) in panels.sorted(by: { $0.key < $1.key }) {
      log("sleepwake[\(label)] panel display=\(id) isVisible=\(panel.isVisible) frame=\(panel.frame)")
    }
    let records = currentDisplays()
    log("sleepwake[\(label)] displays=\(records.count) uuids=\(records.map { $0.uuid ?? "nil" })")
    let missing = Set(panels.keys).subtracting(records.map(\.displayID))
    if !missing.isEmpty { log("sleepwake[\(label)] panels for vanished displayIDs: \(missing.sorted())") }
  }

  func saveSnapshot() {
    let uuids = currentDisplays().map { $0.uuid ?? "nil" }
    if let data = try? JSONEncoder().encode(uuids) {
      try? data.write(to: URL(fileURLWithPath: sleepWakeStatePath))
    }
  }
}

@MainActor
func runSleepWake(_ args: [String]) -> Int32 {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let probe = SleepWakeProbe.shared
  log("sleepwake macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) pid=\(getpid())")
  try? "\(getpid())".write(toFile: sleepWakePidPath, atomically: true, encoding: .utf8)
  probe.installTap()
  probe.rebuildPanels()
  probe.printState("startup")
  probe.saveSnapshot()

  let center = NSWorkspace.shared.notificationCenter
  center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
    MainActor.assumeIsolated {
      log("sleepwake willSleep")
      probe.printState("before-sleep")
      probe.saveSnapshot()
    }
  }
  center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    MainActor.assumeIsolated {
      log("sleepwake didWake")
      probe.printState("wake+0s (before recreate)")
      for delay in [2, 8] {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
          MainActor.assumeIsolated { probe.printState("wake+\(delay)s") }
        }
      }
    }
  }
  NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
  ) { _ in
    MainActor.assumeIsolated {
      log("sleepwake screen parameters changed")
      probe.printState("screen-change")
    }
  }

  signal(SIGUSR1, SIG_IGN)
  let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
  usr1.setEventHandler { MainActor.assumeIsolated { probe.printState("post-wake (SIGUSR1)") } }
  usr1.resume()

  if let seconds = args.firstIndex(of: "--exit-after").flatMap({ Double(args[safe: $0 + 1] ?? "") }) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
  }
  log("sleepwake ready: close the lid on the docked Mac, wait, wake it, then run `HardwareProbe post-wake`.")
  app.run()
  return 0
}

/// Separate process: nudge the running sleepwake probe to re-print, and compare UUIDs to the saved snapshot.
@MainActor
func runPostWake() -> Int32 {
  let records = currentDisplays()
  let now = records.map { $0.uuid ?? "nil" }
  log("post-wake displays=\(records.count) uuids=\(now)")
  if let data = FileManager.default.contents(atPath: sleepWakeStatePath),
    let saved = try? JSONDecoder().decode([String].self, from: data)
  {
    let same = Set(saved) == Set(now)
    log("post-wake UUIDs vs pre-sleep snapshot: \(same ? "PASS (persisted)" : "FAIL (changed)") saved=\(saved)")
  } else {
    log("post-wake: no pre-sleep snapshot found; run `sleepwake` first")
  }
  if let pidText = try? String(contentsOfFile: sleepWakePidPath, encoding: .utf8),
    let pid = Int32(pidText), kill(pid, 0) == 0
  {
    kill(pid, SIGUSR1)
    log("post-wake: asked sleepwake pid \(pid) to re-print its tap/panel state")
  } else {
    log("post-wake: no live sleepwake probe process")
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
  case "hotkey":
    return runHotkey(Array(args.dropFirst()))
  case "sleepwake":
    return runSleepWake(Array(args.dropFirst()))
  case "post-wake":
    return runPostWake()
  default:
    FileHandle.standardError.write(Data("unknown command: \(command)\n\(usage)\n".utf8))
    return 64
  }
}

exit(run(Array(CommandLine.arguments.dropFirst())))
