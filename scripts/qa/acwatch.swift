// acwatch — read-only watcher for the manual permission ACs (AC-005, AC-009, T56 help line).
// It never presses, sets or changes anything. Polls every 50 ms and prints one line per change:
// "<epoch> <event>". Watches every Zones process (alive, AX window titles and static texts, status-item
// description) and every System Settings switch whose row mentions "Zones" (AXValue).
// Exits 20 s after a toggle off -> on sequence, or after maxSeconds (first argument, default 1800).
// Build: swiftc -O -o .build/acwatch scripts/qa/acwatch.swift   Needs Accessibility for the host terminal.
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IOLBF, 0)
let maxSeconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 1800

func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
  var v: AnyObject?
  return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func emit(_ s: String) { print(String(format: "%.3f ", Date().timeIntervalSince1970) + s) }

func pids(_ bundle: String) -> [pid_t] {
  NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundle }.map(\.processIdentifier).sorted()
}

/// Static texts inside a window, to see the onboarding help line appear.
func texts(_ e: AXUIElement, depth: Int = 0, out: inout [String]) {
  if depth > 12 || out.count > 20 { return }
  if str(e, kAXRoleAttribute) == kAXStaticTextRole as String {
    let t = str(e, kAXValueAttribute as String)
    if !t.isEmpty { out.append(t) }
  }
  for k in kids(e) { texts(k, depth: depth + 1, out: &out) }
}

func zonesState(_ pid: pid_t) -> String {
  let app = AXUIElementCreateApplication(pid)
  let wins = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
  var parts: [String] = []
  for w in wins {
    var t: [String] = []
    texts(w, out: &t)
    parts.append("\(str(w, kAXTitleAttribute)): \(t.count) texts, help=\(t.contains { $0.contains("minus button") })")
  }
  var status = "?"
  if let bar = attr(app, "AXExtrasMenuBar") {
    status = kids(bar as! AXUIElement).map { str($0, kAXDescriptionAttribute) }.joined(separator: "|")
  }
  return "windows=\(parts) status=\"\(status)\""
}

func rowText(_ e: AXUIElement, depth: Int = 0) -> String {
  if depth > 3 { return "" }
  var t = [str(e, kAXTitleAttribute), str(e, kAXDescriptionAttribute), str(e, kAXValueAttribute as String)]
  for k in kids(e) { t.append(rowText(k, depth: depth + 1)) }
  return t.joined(separator: " ")
}
func findSwitches(_ e: AXUIElement, parent: AXUIElement?, depth: Int, out: inout [AXUIElement]) {
  if depth > 30 || out.count > 8 { return }
  if str(e, kAXRoleAttribute) == kAXCheckBoxRole as String || str(e, kAXSubroleAttribute) == "AXSwitch" {
    let label = str(e, kAXTitleAttribute) + " " + str(e, kAXDescriptionAttribute)
    if (label + " " + (parent.map { rowText($0) } ?? "")).contains("Zones") { out.append(e); return }
  }
  for k in kids(e) { findSwitches(k, parent: e, depth: depth + 1, out: &out) }
}

var last: [String: String] = [:]
func report(_ key: String, _ value: String) {
  if last[key] != value { last[key] = value; emit("\(key) \(value)") }
}

let start = Date()
var switches: [AXUIElement] = []
var lastScan = Date.distantPast
var sawOff = false
var onAfterOff: Date?
emit("start pid=\(getpid()) trusted=\(AXIsProcessTrusted())")
while Date().timeIntervalSince(start) < maxSeconds {
  let zp = pids("com.dganesh.zones")
  report("zones.pids", "\(zp)")
  for p in zp { report("zones[\(p)]", zonesState(p)) }

  if let s = pids("com.apple.systempreferences").first {
    if switches.isEmpty && Date().timeIntervalSince(lastScan) > 0.3 {
      lastScan = Date()
      var found: [AXUIElement] = []
      for w in (attr(AXUIElementCreateApplication(s), kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        findSwitches(w, parent: nil, depth: 0, out: &found)
      }
      switches = found
      report("settings.switches", "\(found.count)")
    }
    var vals: [String] = []
    var stale = false
    for sw in switches {
      if let v = attr(sw, kAXValueAttribute as String) as? NSNumber { vals.append(v.intValue == 1 ? "on" : "off") } else { stale = true }
    }
    if stale { switches = []; report("settings.switches", "stale, rescanning") }
    report("toggle", vals.isEmpty ? "none" : vals.joined(separator: ","))
    if vals.contains("off") { sawOff = true }
    if sawOff, !vals.isEmpty, !vals.contains("off"), onAfterOff == nil {
      onAfterOff = Date(); emit("sequence off->on seen; 20 s more")
    }
  } else {
    switches = []
    report("settings", "not running")
  }
  if let t = onAfterOff, Date().timeIntervalSince(t) > 20 { emit("done"); exit(0) }
  // Spin the run loop, not usleep: NSWorkspace.runningApplications only updates while it runs.
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
emit("timeout")
