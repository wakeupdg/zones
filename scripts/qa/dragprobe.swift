// dragprobe — read-only probe for AC-044 (drag uninterrupted). It never presses, sets or changes anything.
// Polls every 50 ms and prints one line per change: "<epoch> front=<pid> app=<name> key=<title> zones=<layers>".
// "zones" lists the layer of every on-screen Zones window (CGWindowList); the Overlay panels show as 1000.
// Exits after maxSeconds (first argument, default 120).
// Build: swiftc -O -o .build/dragprobe scripts/qa/dragprobe.swift   Needs Accessibility for the host terminal.
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IOLBF, 0)
let maxSeconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 120

func keyWindowTitle(_ pid: pid_t) -> String {
  let app = AXUIElementCreateApplication(pid)
  var win: AnyObject?
  guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success,
        let w = win else { return "-" }
  var title: AnyObject?
  AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &title)
  return (title as? String).map { $0.isEmpty ? "(untitled)" : $0 } ?? "-"
}

func zonesLayers() -> String {
  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
  let layers = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Zones" }
    .compactMap { $0[kCGWindowLayer as String] as? Int }.sorted()
  return layers.isEmpty ? "none" : layers.map(String.init).joined(separator: ",")
}

let start = Date()
var last = ""
while Date().timeIntervalSince(start) < maxSeconds {
  let front = NSWorkspace.shared.frontmostApplication
  let pid = front?.processIdentifier ?? 0
  let line = "front=\(pid) app=\(front?.localizedName ?? "-") key=\(keyWindowTitle(pid)) zones=\(zonesLayers())"
  if line != last {
    print(String(format: "%.3f ", Date().timeIntervalSince1970) + line)
    last = line
  }
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
