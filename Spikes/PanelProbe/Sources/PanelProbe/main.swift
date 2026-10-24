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

// MARK: - Display and Space helpers (pure parts covered by --self-test)

/// NSScreen frame (bottom-left origin) to CG coordinates (top-left origin on the primary display).
@MainActor func screenCGFrame(_ s: NSScreen) -> CGRect {
  let h = NSScreen.screens.first?.frame.height ?? 0
  return CGRect(x: s.frame.minX, y: h - s.frame.maxY, width: s.frame.width, height: s.frame.height)
}

func nearlyEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat = 1.5) -> Bool {
  abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
}

/// Heuristic: a layer-0 window exactly covering the display means a full-screen Space (or a maximised borderless window).
func fullScreenGuess(screenCG: CGRect, windows: [WinInfo]) -> Bool {
  windows.contains { $0.layer == 0 && $0.onScreen && nearlyEqual($0.bounds, screenCG) }
}

/// Menu bar windows live at layer 24; absent on a full-screen Space (or with the bar auto-hidden and retracted).
func menuBarPresent(screenCG: CGRect, windows: [WinInfo]) -> Bool {
  windows.contains {
    $0.layer == 24 && $0.onScreen && $0.bounds.width >= screenCG.width * 0.5
      && $0.bounds.minY <= screenCG.minY + 40 && $0.bounds.minX >= screenCG.minX - 1 && $0.bounds.maxX <= screenCG.maxX + 1
  }
}

func screenIndex(forCG p: CGPoint, screens: [CGRect]) -> Int? { screens.firstIndex { $0.contains(p) } }

func describe(_ o: NSApplication.PresentationOptions) -> String {
  var names: [String] = []
  let table: [(NSApplication.PresentationOptions, String)] = [
    (.autoHideMenuBar, "autoHideMenuBar"), (.hideMenuBar, "hideMenuBar"), (.autoHideDock, "autoHideDock"),
    (.hideDock, "hideDock"), (.fullScreen, "fullScreen"),
  ]
  for (flag, name) in table where o.contains(flag) { names.append(name) }
  return "raw \(o.rawValue) [\(names.isEmpty ? "default" : names.joined(separator: ","))]"
}

// MARK: - Panel mode

@MainActor final class PanelRig {
  let panels: [ProbePanel]
  init(joinAllApplications: Bool) {
    panels = NSScreen.screens.map { ProbePanel(screen: $0, joinAllApplications: joinAllApplications) }
  }
  var windows: [NSWindow] { panels }
  /// show(): once per drag session. Never makeKey, never activate.
  private(set) var isShown = false
  func show() { isShown = true; panels.forEach { $0.orderFrontRegardless() } }
  /// reassert(): the same orderFrontRegardless, called again after an active-Space change.
  func reassert() { if isShown { panels.forEach { $0.orderFrontRegardless() } } }
  /// hide() and orderOut() are the same call in this probe: hide the panel, keep the object.
  func orderOut() { isShown = false; panels.forEach { $0.orderOut(nil) } }

  /// One row per display: geometry, whether our panel is really on screen there, menu bar and full-screen state.
  func displayRows() -> [[String]] {
    let wins = windowList(all: false)
    return NSScreen.screens.enumerated().map { i, s in
      let cg = screenCGFrame(s)
      let panel = i < panels.count ? panels[i] : nil
      let onScreen = panel.map { p in wins.contains { $0.number == p.windowNumber && $0.layer == 1000 } } ?? false
      let topInset = s.frame.maxY - s.visibleFrame.maxY
      let bottomInset = s.visibleFrame.minY - s.frame.minY
      return [
        "\(i)", s.localizedName, "\(s.frame)", "\(s.visibleFrame)",
        "top \(topInset) / bottom \(bottomInset)",
        onScreen ? "yes" : "no", (panel?.isOnActiveSpace).map { $0 ? "yes" : "no" } ?? "n/a",
        (panel?.occlusionState.contains(.visible)).map { $0 ? "yes" : "no" } ?? "n/a",
        menuBarPresent(screenCG: cg, windows: wins) ? "yes" : "no",
        fullScreenGuess(screenCG: cg, windows: wins.filter { $0.pid != ProcessInfo.processInfo.processIdentifier }) ? "yes" : "no",
      ]
    }
  }
}

let displayHeader = [
  "display", "name", "frame", "visibleFrame", "insets (frame minus visibleFrame)", "panel on screen at layer 1000 (CGWindowList)",
  "panel.isOnActiveSpace", "panel occlusion visible", "menu bar window present", "full-screen guess",
]

/// Subscribes to NSWorkspace.activeSpaceDidChangeNotification; logs panel visibility with and without reassert().
@MainActor final class SpaceWatcher {
  let rig: PanelRig
  let report: Report
  let reassert: Bool
  var count = 0
  var token: NSObjectProtocol?

  init(rig: PanelRig, report: Report, reassert: Bool) {
    self.rig = rig
    self.report = report
    self.reassert = reassert
  }

  func start() {
    token = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.changed() }
    }
  }

  func changed() {
    count += 1
    let n = count
    let shown = rig.isShown
    report.emit("\n#### Active Space change \(n) at \(ptTime()) (panels ordered front: \(shown ? "yes" : "no"))\n")
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(300))
      report.table("Change \(n): 300 ms after notification, no reassert yet", header: displayHeader, rows: rig.displayRows())
      report.emit("- presentation options: \(describe(NSApp.currentSystemPresentationOptions))")
      if reassert, shown {
        rig.reassert()
        try? await Task.sleep(for: .milliseconds(300))
        report.table("Change \(n): 300 ms after reassert()", header: displayHeader, rows: rig.displayRows())
      }
    }
  }
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
  var armedRows: [[String]] = []
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
        armedRows = []
      }
      if phase == .armed {
        draggedEvents += 1
        if during == nil, Date().timeIntervalSince(armedAt) >= 0.15 {
          during = focusSnapshot("during", panels: rig.windows)
          armedRows = rig.displayRows()
        }
      }
    case .leftMouseUp:
      guard phase == .armed, let w = grabbed, let before else { phase = .idle; return }
      phase = .idle
      let during = self.during ?? focusSnapshot("during(at mouseUp)", panels: rig.windows)
      let events = draggedEvents
      if armedRows.isEmpty { armedRows = rig.displayRows() }
      let armed = armedRows
      let presentation = describe(NSApp.currentSystemPresentationOptions)
      rig.orderOut()
      run += 1
      let n = run
      let label = self.label
      let t = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(200))  // let the window server settle the drop
        let after = focusSnapshot("after", panels: rig.windows)
        let now = windowList(all: false).first { $0.number == w.number }
        self.finishRun(n: n, label: label, start: w, end: now, events: events, snaps: [before, during, after], armed: armed, presentation: presentation)
      }
      pending.append(t)
    default: break
    }
  }

  func finishRun(n: Int, label: String, start: WinInfo, end: WinInfo?, events: Int, snaps: [FocusSnapshot], armed: [[String]], presentation: String) {
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
    report.table("Run \(n): display state while armed", header: displayHeader, rows: armed)
    let screensCG = NSScreen.screens.map { screenCGFrame($0) }
    let from = screenIndex(forCG: CGPoint(x: start.bounds.midX, y: start.bounds.midY), screens: screensCG)
    let to = end.flatMap { screenIndex(forCG: CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), screens: screensCG) }
    let toIsFullScreen = to.map { $0 < armed.count && armed[$0].last == "yes" }
    report.table(
      nil, header: ["from display", "dropped on display", "dropped display full-screen (guess)", "window ended where", "presentation options"],
      rows: [[
        from.map(String.init) ?? "?", to.map(String.init) ?? "?", toIsFullScreen.map { $0 ? "yes" : "no" } ?? "?",
        end.map { "\($0.bounds)" } ?? "not on screen", presentation,
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
    let watcher = SpaceWatcher(rig: rig, report: report, reassert: args.contains("--reassert"))
    watcher.start()
    KeepAlive.watcher = watcher
    report.emit("- reassert on Space change: \(args.contains("--reassert") ? "yes" : "no (observe only)")")
    if args.contains("--hold") {
      rig.show()
      report.emit("- --hold: panels stay ordered front; switch Spaces and read the per-change tables")
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(300))
        report.table("Display state at start (300 ms after show)", header: displayHeader, rows: rig.displayRows())
        report.emit("- presentation options: \(describe(NSApp.currentSystemPresentationOptions))")
      }
    }
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

@MainActor enum KeepAlive {
  static var probe: DragProbe?
  static var watcher: SpaceWatcher?
  static var frameTimer: FrameTimer?
}

// MARK: - Frame-time mode (SPK-009)

/// 4x3 style grid of `count` zone rects inside `rect` (panel-local coordinates).
func zoneGrid(in rect: CGRect, count: Int, inset: CGFloat = 24, gap: CGFloat = 12) -> [CGRect] {
  let area = rect.insetBy(dx: inset, dy: inset)
  let cols = Int((Double(count) * Double(area.width / area.height)).squareRoot().rounded(.up))
  let rows = (count + cols - 1) / cols
  let w = (area.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
  let h = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
  return (0..<count).map { i in
    CGRect(x: area.minX + CGFloat(i % cols) * (w + gap), y: area.minY + CGFloat(i / cols) * (h + gap), width: w, height: h)
  }
}

func hitZone(_ p: CGPoint, zones: [CGRect]) -> Int? { zones.firstIndex { $0.contains(p) } }

/// Deterministic Lissajous sweep that crosses most zones; stands in for the cursor in synthetic runs.
func scanPath(index i: Int, in rect: CGRect) -> CGPoint {
  let t = Double(i)
  return CGPoint(
    x: rect.midX + CGFloat(sin(t * 0.021)) * rect.width * 0.45,
    y: rect.midY + CGFloat(sin(t * 0.034 + 1.0)) * rect.height * 0.45)
}

let frameBudgetMs = 1000.0 / 120.0  // 8.33 ms

/// SPK-009 pass rule: p99 within one 120 Hz frame and under 1 percent of events over it.
func frameTimeVerdict(_ s: Stats) -> Bool { s.p99 <= frameBudgetMs && s.shareOver(frameBudgetMs) < 0.01 }

@MainActor protocol HighlightRenderer: AnyObject {
  var name: String { get }
  /// Apply one dragged event: pick the zone under `point` and move the highlight.
  func update(at point: CGPoint)
  /// Push the change toward the window server. `flush` additionally forces CATransaction.flush().
  func commit(flush: Bool)
}

/// Persistent CALayers (ADR-0023 recipe): 12 zone layers plus one highlight layer, created once.
@MainActor final class LayerRenderer: HighlightRenderer {
  let name = "CALayer"
  let zones: [CGRect]
  private let zoneLayers: [CALayer]
  private let highlight = CALayer()

  init(panel: NSPanel, zones: [CGRect]) {
    self.zones = zones
    let root = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
    root.wantsLayer = true
    var layers: [CALayer] = []
    for z in zones {
      let l = CALayer()
      l.frame = z
      l.cornerRadius = 8
      l.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
      l.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
      l.borderWidth = 1
      l.opacity = 0.6
      root.layer?.addSublayer(l)
      layers.append(l)
    }
    zoneLayers = layers
    highlight.cornerRadius = 8
    highlight.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.55).cgColor
    highlight.isHidden = true
    root.layer?.addSublayer(highlight)
    panel.contentView = root
  }

  func update(at point: CGPoint) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let hit = hitZone(point, zones: zones)
    for (i, l) in zoneLayers.enumerated() { l.opacity = i == hit ? 1 : 0.6 }
    if let hit {
      highlight.frame = zones[hit]
      highlight.isHidden = false
    } else {
      highlight.isHidden = true
    }
  }

  func commit(flush: Bool) {
    CATransaction.commit()
    if flush { CATransaction.flush() }
  }
}

enum EndPoint: String { case commit, flush }

struct FrameTimeResult {
  var variant: String
  var endPoint: String
  var source: String
  var stats: Stats
  var frameIntervals: Stats?
}

@MainActor final class Stopper { var action: () -> Void = {} }

@MainActor final class DisplayLinkTarget: NSObject {
  var onTick: ((CADisplayLink) -> Void)?
  @objc func tick(_ link: CADisplayLink) { onTick?(link) }
}

/// Times each handler call (update through commit) with ContinuousClock.
@MainActor final class FrameTimer {
  let renderer: HighlightRenderer
  let endPoint: EndPoint
  let visible: CGRect
  private(set) var samplesMs: [Double] = []
  private let clock = ContinuousClock()
  private var seen = 0
  let warmup = 60

  init(renderer: HighlightRenderer, endPoint: EndPoint, visible: CGRect) {
    self.renderer = renderer
    self.endPoint = endPoint
    self.visible = visible
  }

  /// One dragged event. `point` is panel-local.
  func handleEvent(_ point: CGPoint) {
    let t0 = clock.now
    renderer.update(at: point)
    renderer.commit(flush: endPoint == .flush)
    let d = clock.now - t0
    seen += 1
    if seen > warmup {
      samplesMs.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
    }
  }
}

@MainActor func panelLocalVisible(_ screen: NSScreen) -> CGRect {
  screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
}

/// Synthetic run: one event per display-link tick (the screen's native rate), `events` timed events after warm-up.
@MainActor func runSynthetic(
  renderer: HighlightRenderer, endPoint: EndPoint, screen: NSScreen, events: Int, visible: CGRect, timerHz: Double? = nil
) async -> FrameTimeResult {
  let timer = FrameTimer(renderer: renderer, endPoint: endPoint, visible: visible)
  let target = DisplayLinkTarget()
  var stamps: [Double] = []
  var index = 0
  var source = "synthetic (display link, requested \(screen.maximumFramesPerSecond) Hz)"
  await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
    var resumed = false
    let stopper = Stopper()
    let tick: @MainActor (Double) -> Void = { ts in
      timer.handleEvent(scanPath(index: index, in: visible))
      index += 1
      stamps.append(ts)
      if timer.samplesMs.count >= events, !resumed {
        resumed = true
        stopper.action()
        cont.resume()
      }
    }
    if let timerHz {
      source = "synthetic (run-loop timer \(Int(timerHz)) Hz)"
      let t = Timer(timeInterval: 1 / timerHz, repeats: true) { _ in
        MainActor.assumeIsolated { tick(ProcessInfo.processInfo.systemUptime) }
      }
      RunLoop.main.add(t, forMode: .common)
      stopper.action = { t.invalidate() }
    } else {
      let link = screen.displayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
      let hz = Float(screen.maximumFramesPerSecond)
      link.preferredFrameRateRange = CAFrameRateRange(minimum: hz / 2, maximum: hz, preferred: hz)
      link.add(to: .main, forMode: .common)
      target.onTick = { l in tick(l.timestamp) }
      stopper.action = { link.invalidate() }
    }
  }
  let deltas = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }
  return FrameTimeResult(
    variant: renderer.name, endPoint: endPoint.rawValue, source: source,
    stats: Stats(samples: timer.samplesMs), frameIntervals: Stats(samples: deltas))
}

@MainActor func frameTimeRows(_ results: [FrameTimeResult], screen: NSScreen) -> [[String]] {
  func f(_ v: Double) -> String { String(format: "%.3f", v) }
  return results.map { r in
    let s = r.stats
    return [
      r.variant, r.endPoint, r.source, "\(s.count)", f(s.p50), f(s.p95), f(s.p99), f(s.max),
      String(format: "%.2f%%", s.shareOver(frameBudgetMs) * 100), "\(screen.maximumFramesPerSecond)",
      ProcessInfo.processInfo.operatingSystemVersionString, frameTimeVerdict(s) ? "PASS" : "FAIL",
    ]
  }
}
let frameTimeHeader = [
  "variant", "end point", "source", "events", "p50 ms", "p95 ms", "p99 ms", "max ms", "share > 8.33 ms", "maxFPS", "OS", "verdict",
]

/// Panel on the chosen screen, ordered front so commits reach the window server.
@MainActor func makeLoadPanel(on screen: NSScreen) -> ProbePanel {
  let panel = ProbePanel(screen: screen, joinAllApplications: false)
  panel.orderFrontRegardless()
  return panel
}

@MainActor func runFrameTimeMode(_ args: [String]) {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let report = Report(mode: "frametime")
  report.machineHeader()
  func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
  let events = value("--events").flatMap(Int.init) ?? 2400
  let screens = NSScreen.screens
  let screen: NSScreen =
    value("--display").flatMap(Int.init).flatMap { screens.indices.contains($0) ? screens[$0] : nil }
    ?? screens.max { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond } ?? NSScreen.main!
  let variant = value("--variant") ?? "layers"
  let endPoint = EndPoint(rawValue: value("--endpoint") ?? "commit") ?? .commit
  report.emit("- load screen: \(screen.localizedName) at \(screen.maximumFramesPerSecond) Hz; events per run: \(events); budget \(String(format: "%.2f", frameBudgetMs)) ms")

  Task { @MainActor in
    var results: [FrameTimeResult] = []
    let visible = panelLocalVisible(screen)
    let zones = zoneGrid(in: visible, count: 12)
    if args.contains("--synthetic") {
      var configs: [(String, EndPoint)] = []
      switch variant {
      case "layers": configs = [("layers", .commit), ("layers", .flush)]
      default: configs = [("layers", .commit), ("layers", .flush)]
      }
      var drivers: [Double?] = [nil]
      if let hz = value("--timer-hz").flatMap(Double.init) { drivers.append(hz) }
      for (v, ep) in configs {
        for hzSel in drivers {
          let panel = makeLoadPanel(on: screen)
          let renderer: HighlightRenderer = makeRenderer(v, panel: panel, zones: zones)
          try? await Task.sleep(for: .milliseconds(300))
          results.append(await runSynthetic(renderer: renderer, endPoint: ep, screen: screen, events: events, visible: visible, timerHz: hzSel))
          panel.orderOut(nil)
        }
      }
      report.table("Frame time (synthetic)", header: frameTimeHeader, rows: frameTimeRows(results, screen: screen))
      for r in results {
        if let fi = r.frameIntervals {
          report.emit(String(format: "- %@/%@ [%@] event interval p50 %.3f ms, p99 %.3f ms, max %.3f ms", r.variant, r.endPoint, r.source, fi.p50, fi.p99, fi.max))
        }
      }
      exit(results.allSatisfy { frameTimeVerdict($0.stats) } ? 0 : 1)
    } else {
      let panel = makeLoadPanel(on: screen)
      let renderer = makeRenderer(variant, panel: panel, zones: zones)
      let timer = FrameTimer(renderer: renderer, endPoint: endPoint, visible: visible)
      KeepAlive.frameTimer = timer
      report.emit("Real drag run: drag any window (or the mouse button held) in circles over the \(screen.localizedName) display until \(events) events are timed. The panel is click-through.")
      var last: Double?
      var intervals: [Double] = []
      var finished = false
      _ = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { event in
        let ts = event.timestamp
        MainActor.assumeIsolated {
          guard !finished else { return }
          let loc = NSEvent.mouseLocation
          if let last { intervals.append((ts - last) * 1000) }
          last = ts
          timer.handleEvent(CGPoint(x: loc.x - screen.frame.minX, y: loc.y - screen.frame.minY))
          if timer.samplesMs.count >= events {
            finished = true
            let r = FrameTimeResult(variant: renderer.name, endPoint: endPoint.rawValue, source: "real drag", stats: Stats(samples: timer.samplesMs), frameIntervals: Stats(samples: intervals))
            report.table("Frame time (real drag)", header: frameTimeHeader, rows: frameTimeRows([r], screen: screen))
            if let fi = r.frameIntervals {
              report.emit(String(format: "- dragged-event interval p50 %.3f ms, p99 %.3f ms", fi.p50, fi.p99))
            }
            exit(frameTimeVerdict(r.stats) ? 0 : 1)
          }
        }
      }
    }
  }
  app.run()
}

@MainActor func makeRenderer(_ variant: String, panel: ProbePanel, zones: [CGRect]) -> HighlightRenderer {
  LayerRenderer(panel: panel, zones: zones)
}

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
    let vis = CGRect(x: 100, y: 50, width: 1200, height: 800)
    let grid = zoneGrid(in: vis, count: 12)
    check(grid.count == 12, "zoneGrid.count")
    check(grid.allSatisfy { vis.contains($0) }, "zoneGrid.insideVisibleFrame")
    var overlap = false
    for i in grid.indices { for j in grid.indices where j > i && grid[i].intersects(grid[j]) { overlap = true } }
    check(!overlap, "zoneGrid.noOverlap")
    check(hitZone(CGPoint(x: grid[5].midX, y: grid[5].midY), zones: grid) == 5, "hitZone.inside")
    check(hitZone(CGPoint(x: -10, y: -10), zones: grid) == nil, "hitZone.outside")
    let path = (0..<500).map { scanPath(index: $0, in: vis) }
    check(path.allSatisfy { vis.contains($0) }, "scanPath.insideVisibleFrame")
    check(Set(path.compactMap { hitZone($0, zones: grid) }).count >= 8, "scanPath.visitsMostZones")
    check(frameTimeVerdict(Stats(samples: [1, 2, 3, 4, 5])), "verdict.pass")
    check(!frameTimeVerdict(Stats(samples: [1, 2, 3, 4, 9])), "verdict.failMax-p99")
    let scr = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let fs = WinInfo(number: 1, pid: 9, layer: 0, bounds: scr, onScreen: true, owner: "Safari")
    let normal = WinInfo(number: 2, pid: 9, layer: 0, bounds: CGRect(x: 10, y: 30, width: 600, height: 400), onScreen: true, owner: "Safari")
    let bar = WinInfo(number: 3, pid: 8, layer: 24, bounds: CGRect(x: 0, y: 0, width: 1000, height: 24), onScreen: true, owner: "Window Server")
    check(fullScreenGuess(screenCG: scr, windows: [fs]), "fullScreenGuess.true")
    check(!fullScreenGuess(screenCG: scr, windows: [normal, bar]), "fullScreenGuess.false")
    check(menuBarPresent(screenCG: scr, windows: [bar]), "menuBarPresent.true")
    check(!menuBarPresent(screenCG: scr, windows: [fs]), "menuBarPresent.false")
    check(screenIndex(forCG: CGPoint(x: 1500, y: 100), screens: [scr, CGRect(x: 1000, y: 0, width: 1000, height: 800)]) == 1, "screenIndex")
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
case "frametime": runFrameTimeMode(Array(args.dropFirst()))
default:
  print("usage: PanelProbe --self-test | panel [--synthetic] [--join-all-apps] [--reassert] [--hold] [--label L] [--duration S] | frametime [--synthetic] [--variant layers|swiftui] [--endpoint commit|flush] [--events N] [--display I] | witness")
  exit(64)
}
