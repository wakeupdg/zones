import AppKit
import ApplicationServices
import Foundation

// PanelProbe: throwaway spike for T03 (SPK-002, SPK-009, SPK-001). Not part of the Zones packages.

// MARK: - Pure helpers (covered by --self-test)

struct Stats {
  let sorted: [Double]
  init(samples: [Double]) { sorted = samples.sorted() }
  var count: Int { sorted.count }
  /// Nearest-rank percentile, q in 0...1.
  func percentile(_ q: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    let rank = Swift.max(1, Int((q * Double(sorted.count)).rounded(.up)))
    return sorted[Swift.min(rank, sorted.count) - 1]
  }
  var p50: Double { percentile(0.50) }
  var p95: Double { percentile(0.95) }
  var p99: Double { percentile(0.99) }
  var max: Double { sorted.last ?? .nan }
  /// Fraction of samples strictly above `limit`.
  func shareOver(_ limit: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    return Double(sorted.filter { $0 > limit }.count) / Double(sorted.count)
  }
}

func markdownTable(header: [String], rows: [[String]]) -> String {
  var out = "| " + header.joined(separator: " | ") + " |\n"
  out += "| " + header.map { _ in "---" }.joined(separator: " | ") + " |\n"
  for r in rows { out += "| " + r.joined(separator: " | ") + " |\n" }
  return out
}

// MARK: - Panel recipe (ADR-0023), prototype of App's PanelOverlayPresenter panel

/// One click-through, never-key panel per screen at level .screenSaver. Frame = screen.frame (PanelModel.frame).
final class ProbePanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(screen: NSScreen, joinAllApplications: Bool) {
    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    if joinAllApplications { behavior.insert(.canJoinAllApplications) }
    collectionBehavior = behavior
    isFloatingPanel = true
    // Finding: isFloatingPanel = true resets level to .floating, so level must be set AFTER it.
    level = .screenSaver
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = true
    ignoresMouseEvents = true
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    animationBehavior = .none
    isReleasedWhenClosed = false
    setFrame(screen.frame, display: false)
  }
}

// MARK: - Report: stdout plus out/<mode>-<date>.md (out/ is not committed)

func ptTime(_ date: Date = Date(), format: String = "h:mm:ss a") -> String {
  let df = DateFormatter()
  df.locale = Locale(identifier: "en_US_POSIX")
  df.timeZone = TimeZone(identifier: "America/Los_Angeles")
  df.dateFormat = format
  return df.string(from: date) + " PT"
}

@MainActor final class Report {
  private let handle: FileHandle?
  let path: String?

  init(mode: String) {
    let fm = FileManager.default
    var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
    if let o = ProcessInfo.processInfo.environment["PANELPROBE_OUT"] {
      dir = URL(fileURLWithPath: o)
    } else if fm.fileExists(atPath: dir.appendingPathComponent("Spikes/PanelProbe").path) {
      dir = dir.appendingPathComponent("Spikes/PanelProbe/out")
    } else {
      dir = dir.appendingPathComponent("out")
    }
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(identifier: "America/Los_Angeles")
    df.dateFormat = "yyyy-MM-dd"
    let url = dir.appendingPathComponent("\(mode)-\(df.string(from: Date())).md")
    if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
    handle = try? FileHandle(forWritingTo: url)
    _ = try? handle?.seekToEnd()
    path = handle == nil ? nil : url.path
  }

  func emit(_ text: String) {
    print(text)
    if let data = (text + "\n").data(using: .utf8) { try? handle?.write(contentsOf: data) }
  }

  func table(_ title: String?, header: [String], rows: [[String]]) {
    if let title { emit("\n### \(title)\n") }
    emit(markdownTable(header: header, rows: rows))
  }

  /// Machine block required by every verdict note.
  func machineHeader() {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var buf = [CChar](repeating: 0, count: Swift.max(size, 1))
    sysctlbyname("hw.model", &buf, &size, nil, 0)
    let model = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    emit("\n## Run \(ptTime())\n")
    emit("- machine: \(model)")
    emit("- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    emit("- separate Spaces per display (screensHaveSeparateSpaces): \(NSScreen.screensHaveSeparateSpaces)")
    emit("")
    table(
      "Displays",
      header: ["#", "name", "frame", "visibleFrame", "maxFPS", "scale"],
      rows: NSScreen.screens.enumerated().map { i, s in
        [
          "\(i)", s.localizedName, "\(s.frame)", "\(s.visibleFrame)",
          "\(s.maximumFramesPerSecond)", "\(s.backingScaleFactor)",
        ]
      })
  }
}

// MARK: - Window server and focus snapshots

struct WinInfo: Sendable {
  var number: Int
  var pid: Int32
  var layer: Int
  var bounds: CGRect  // CG coordinates: top-left origin
  var onScreen: Bool
  var owner: String
}

/// Front-to-back window list. `.optionAll` includes windows on other Spaces; otherwise on-screen only.
func windowList(all: Bool) -> [WinInfo] {
  let opts: CGWindowListOption = all ? [.optionAll] : [.optionOnScreenOnly]
  guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
  return raw.compactMap { d in
    guard let n = d[kCGWindowNumber as String] as? Int,
      let pid = d[kCGWindowOwnerPID as String] as? Int32 ?? (d[kCGWindowOwnerPID as String] as? Int).map({ Int32($0) }),
      let layer = d[kCGWindowLayer as String] as? Int,
      let bd = d[kCGWindowBounds as String] as? [String: Any],
      let rect = CGRect(dictionaryRepresentation: bd as CFDictionary)
    else { return nil }
    return WinInfo(
      number: n, pid: pid, layer: layer, bounds: rect,
      onScreen: (d[kCGWindowIsOnscreen as String] as? Bool) ?? false,
      owner: (d[kCGWindowOwnerName as String] as? String) ?? "?")
  }
}

/// Cocoa (bottom-left) screen point to CG (top-left) point, relative to the primary display.
@MainActor func cgPoint(fromCocoa p: NSPoint) -> CGPoint {
  let h = NSScreen.screens.first?.frame.height ?? 0
  return CGPoint(x: p.x, y: h - p.y)
}

struct FocusSnapshot: Sendable {
  var label: String
  var frontPid: Int32?
  var frontName: String
  var nsKeyWindow: String
  var topWindow: String  // frontmost layer-0 window not owned by us: proxy for the key window
  var axFocused: String
  var panelLayers: [Int]  // CGWindowList layers of our panels that are on screen right now
  var panelNumbers: [Int]
}

@MainActor func focusSnapshot(_ label: String, panels: [NSWindow]) -> FocusSnapshot {
  let front = NSWorkspace.shared.frontmostApplication
  let me = ProcessInfo.processInfo.processIdentifier
  let wins = windowList(all: false)
  let top = wins.first { $0.layer == 0 && $0.pid != me && $0.bounds.width > 50 }
  let nums = Set(panels.map { $0.windowNumber })
  let mine = wins.filter { nums.contains($0.number) }
  var ax = "AX not trusted"
  if AXIsProcessTrusted() {
    ax = "none"
    let sys = AXUIElementCreateSystemWide()
    var app: CFTypeRef?
    if AXUIElementCopyAttributeValue(sys, kAXFocusedApplicationAttribute as CFString, &app) == .success,
      let app, CFGetTypeID(app) == AXUIElementGetTypeID()
    {
      var win: CFTypeRef?
      if AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &win) == .success,
        let win, CFGetTypeID(win) == AXUIElementGetTypeID()
      {
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title)
        ax = "\((title as? String) ?? "untitled")"
      }
    }
  }
  return FocusSnapshot(
    label: label, frontPid: front?.processIdentifier, frontName: front?.localizedName ?? "none",
    nsKeyWindow: NSApp.keyWindow.map { "#\($0.windowNumber)" } ?? "nil",
    topWindow: top.map { "\($0.owner) #\($0.number) pid \($0.pid)" } ?? "none",
    axFocused: ax, panelLayers: mine.map { $0.layer }, panelNumbers: mine.map { $0.number })
}

func focusRows(_ snaps: [FocusSnapshot]) -> [[String]] {
  snaps.map { s in
    [
      s.label, s.frontPid.map { "\($0)" } ?? "nil", s.frontName, s.nsKeyWindow, s.topWindow, s.axFocused,
      s.panelLayers.isEmpty ? "none on screen" : s.panelLayers.map(String.init).joined(separator: ","),
    ]
  }
}
let focusHeader = ["phase", "frontmost pid", "frontmost app", "NSApp.keyWindow", "top window (key proxy)", "AX focused window", "panel layers on screen"]

/// True when frontmost pid and key proxy are identical across all snapshots.
func focusUnchanged(_ snaps: [FocusSnapshot]) -> Bool {
  guard let f = snaps.first else { return true }
  return snaps.allSatisfy { $0.frontPid == f.frontPid && $0.topWindow == f.topWindow && $0.axFocused == f.axFocused && $0.nsKeyWindow == "nil" }
}

// MARK: - Panel mode

@MainActor final class PanelRig {
  let panels: [ProbePanel]
  init(joinAllApplications: Bool) {
    panels = NSScreen.screens.map { ProbePanel(screen: $0, joinAllApplications: joinAllApplications) }
  }
  var windows: [NSWindow] { panels }
  /// show(): once per drag session. Never makeKey, never activate.
  func show() { panels.forEach { $0.orderFrontRegardless() } }
  /// hide() and orderOut() are the same call in this probe: hide the panel, keep the object.
  func orderOut() { panels.forEach { $0.orderOut(nil) } }
}

enum DragPhase { case idle, pressed, armed }

/// Global monitor driven Shift + title-bar drag probe (slice 3).
@MainActor final class DragProbe {
  let rig: PanelRig
  let report: Report
  var label: String
  var phase: DragPhase = .idle
  var grabbed: WinInfo?
  var before: FocusSnapshot?
  var during: FocusSnapshot?
  var downPoint = CGPoint.zero
  var armedAt = Date.distantPast
  var draggedEvents = 0
  var run = 0
  var rows: [[String]] = []
  var pending: [Task<Void, Never>] = []

  init(rig: PanelRig, report: Report, label: String) {
    self.rig = rig
    self.report = report
    self.label = label
  }

  func start() {
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
    _ = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
      let type = event.type
      MainActor.assumeIsolated { self?.handle(type) }
    }
    report.emit("Listening for Shift + title-bar drags (label: \(label)). Ctrl-C to stop.")
  }

  func handle(_ type: NSEvent.EventType) {
    let me = ProcessInfo.processInfo.processIdentifier
    let loc = cgPoint(fromCocoa: NSEvent.mouseLocation)
    switch type {
    case .leftMouseDown:
      phase = .idle
      guard let w = windowList(all: false).first(where: { $0.layer == 0 && $0.pid != me && $0.bounds.contains(loc) }) else { return }
      guard loc.y - w.bounds.minY <= 52 else { return }  // title-bar heuristic: top 52 pt
      grabbed = w
      downPoint = loc
      before = focusSnapshot("before", panels: rig.windows)
      draggedEvents = 0
      phase = .pressed
    case .leftMouseDragged:
      if phase == .pressed, NSEvent.modifierFlags.contains(.shift),
        hypot(loc.x - downPoint.x, loc.y - downPoint.y) >= 3
      {
        phase = .armed
        armedAt = Date()
        rig.show()  // the one and only orderFrontRegardless of this drag session
        during = nil
      }
      if phase == .armed {
        draggedEvents += 1
        if during == nil, Date().timeIntervalSince(armedAt) >= 0.15 {
          during = focusSnapshot("during", panels: rig.windows)
        }
      }
    case .leftMouseUp:
      guard phase == .armed, let w = grabbed, let before else { phase = .idle; return }
      phase = .idle
      let during = self.during ?? focusSnapshot("during(at mouseUp)", panels: rig.windows)
      let events = draggedEvents
      rig.orderOut()
      run += 1
      let n = run
      let label = self.label
      let t = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(200))  // let the window server settle the drop
        let after = focusSnapshot("after", panels: rig.windows)
        let now = windowList(all: false).first { $0.number == w.number }
        self.finishRun(n: n, label: label, start: w, end: now, events: events, snaps: [before, during, after])
      }
      pending.append(t)
    default: break
    }
  }

  func finishRun(n: Int, label: String, start: WinInfo, end: WinInfo?, events: Int, snaps: [FocusSnapshot]) {
    let layerOK = snaps[1].panelLayers.contains(1000) && snaps[0].panelLayers.isEmpty && snaps[2].panelLayers.isEmpty
    let moved = end.map { $0.bounds.origin != start.bounds.origin } ?? false
    report.emit("\n#### Run \(n) [\(label)] at \(ptTime())\n")
    report.table(nil, header: focusHeader, rows: focusRows(snaps))
    report.table(
      nil, header: ["run", "label", "dragged events after arm", "frontmost+key unchanged", "panel layer 1000 only while armed", "dragged window moved", "grabbed", "ended at"],
      rows: [[
        "\(n)", label, "\(events)", focusUnchanged(snaps) ? "yes" : "NO", layerOK ? "yes" : "NO", moved ? "yes" : "no",
        "\(start.owner) #\(start.number) \(start.bounds)", end.map { "\($0.bounds)" } ?? "not on screen",
      ]])
    report.emit("Operator: did the drag stay smooth and continuous the whole time? (record yes/no in the note)")
  }
}

/// Self-driven cycle with no mouse: show, snapshot, orderOut, snapshot. Verifies layer 1000 and unchanged focus.
@MainActor func runSyntheticPanel(rig: PanelRig, report: Report, label: String) async -> Bool {
  var snaps = [focusSnapshot("before", panels: rig.windows)]
  rig.show()
  try? await Task.sleep(for: .milliseconds(300))
  snaps.append(focusSnapshot("during (armed)", panels: rig.windows))
  rig.orderOut()
  try? await Task.sleep(for: .milliseconds(300))
  snaps.append(focusSnapshot("after (orderOut)", panels: rig.windows))
  let layerOK = snaps[1].panelLayers.contains(1000) && snaps[0].panelLayers.isEmpty && snaps[2].panelLayers.isEmpty
  let unchanged = focusUnchanged(snaps)
  report.table("Synthetic show/orderOut cycle [\(label)]", header: focusHeader, rows: focusRows(snaps))
  report.table(
    nil, header: ["check", "result"],
    rows: [
      ["frontmost pid, key proxy and NSApp.keyWindow unchanged", unchanged ? "pass" : "FAIL"],
      ["CGWindowList layer 1000 only while armed (all \(rig.panels.count) panels shown: \(snaps[1].panelNumbers.count))", layerOK ? "pass" : "FAIL"],
    ])
  return layerOK && unchanged
}

@MainActor func runPanelMode(_ args: [String]) {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let report = Report(mode: "panel")
  report.machineHeader()
  func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
  let joinAll = args.contains("--join-all-apps")
  let label = value("--label") ?? "unlabelled"
  let rig = PanelRig(joinAllApplications: joinAll)
  report.emit("- variant: \(joinAll ? "with" : "without") canJoinAllApplications; label: \(label)")
  if args.contains("--synthetic") {
    Task { @MainActor in
      let ok = await runSyntheticPanel(rig: rig, report: report, label: label)
      exit(ok ? 0 : 1)
    }
  } else {
    let probe = DragProbe(rig: rig, report: report, label: label)
    probe.start()
    if let d = value("--duration").flatMap(Double.init) {
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(d))
        exit(0)
      }
    }
    KeepAlive.probe = probe
  }
  app.run()
}

@MainActor enum KeepAlive { static var probe: DragProbe? }

@MainActor func selfTest() -> Bool {
  var failures = 0
  func check(_ ok: Bool, _ name: String) {
    if !ok { failures += 1; print("FAIL \(name)") } else { print("ok   \(name)") }
  }
  let samples = (1...100).map { Double($0) / 10.0 }  // 0.1 ... 10.0 ms
  let s = Stats(samples: samples)
  check(abs(s.p50 - 5.0) < 1e-9, "p50")
  check(abs(s.p95 - 9.5) < 1e-9, "p95")
  check(abs(s.p99 - 9.9) < 1e-9, "p99")
  check(abs(s.max - 10.0) < 1e-9, "max")
  check(abs(s.shareOver(8.33) - 0.17) < 1e-9, "shareOver8.33")
  let t = markdownTable(header: ["a", "b"], rows: [["1", "2"], ["3", "4"]])
  check(t == "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n", "table")
  do {
    NSApplication.shared.setActivationPolicy(.accessory)
    if let screen = NSScreen.main ?? NSScreen.screens.first {
      for joinAll in [false, true] {
        let panel = ProbePanel(screen: screen, joinAllApplications: joinAll)
        let tag = joinAll ? "panel(+canJoinAllApplications)" : "panel"
        check(panel.ignoresMouseEvents, "\(tag).ignoresMouseEvents")
        check(!panel.canBecomeKey, "\(tag).canBecomeKey==false")
        check(!panel.canBecomeMain, "\(tag).canBecomeMain==false")
        check(panel.level == .screenSaver, "\(tag).level==screenSaver")
        check(!panel.hasShadow, "\(tag).hasShadow==false")
        check(panel.backgroundColor == .clear && !panel.isOpaque, "\(tag).clearBackground")
        let need: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        check(panel.collectionBehavior.contains(need), "\(tag).collectionBehavior")
        check(panel.collectionBehavior.contains(.canJoinAllApplications) == joinAll, "\(tag).canJoinAllApplications==\(joinAll)")
        check(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless), "\(tag).styleMask")
        check(panel.frame == screen.frame, "\(tag).frame==screen.frame")
        check(NSApp.activationPolicy() == .accessory, "\(tag).activationPolicy==accessory")
        check(!panel.isVisible, "\(tag).notVisibleUntilShown")
      }
    } else {
      print("skip panel checks: no NSScreen available")
    }
  }
  return failures == 0
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "--self-test": exit(selfTest() ? 0 : 1)
case "panel": runPanelMode(Array(args.dropFirst()))
default:
  print("usage: PanelProbe --self-test | panel [--synthetic] [--join-all-apps] [--label L] [--duration S] | frametime | witness")
  exit(64)
}
