import ApplicationServices
import AppKit
import Foundation

// MARK: - Pure summary (selftest-covered)

struct CadenceEvent: Sendable {
  var name: String
  var t: Double
  var element: String = "window"
}

struct CadenceSummary: Equatable {
  var name: String
  var count: Int
  var betweenDownUp: Int
  var within50msAfterUp: Int
  var interArrival: SeriesStats?
  var verdict: String
}

func cadenceVerdict(count: Int, betweenDownUp: Int, gestures: Int) -> String {
  if count == 0 || gestures == 0 { return "no-data" }
  return betweenDownUp == 0 ? "end-of-gesture-only" : "continuous"
}

func summarizeCadence(events: [CadenceEvent], downs: [Double], ups: [Double]) -> [CadenceSummary] {
  let sortedUps = ups.sorted()
  // A gesture is a down paired with the first later up.
  let gestures: [(down: Double, up: Double)] = downs.sorted().compactMap { d in
    sortedUps.first(where: { $0 > d }).map { (d, $0) }
  }
  return Dictionary(grouping: events, by: \.name).keys.sorted().map { name in
    let times = events.filter { $0.name == name }.map(\.t).sorted()
    let between = times.filter { t in gestures.contains { $0.down <= t && t < $0.up } }.count
    let after = times.filter { t in gestures.contains { $0.up <= t && t <= $0.up + 0.05 } }.count
    return CadenceSummary(
      name: name, count: times.count, betweenDownUp: between, within50msAfterUp: after,
      interArrival: seriesStats(interArrivalMs(times)),
      verdict: cadenceVerdict(count: times.count, betweenDownUp: between, gestures: gestures.count))
  }
}

// MARK: - cadence mode

/// Spike-only: lock-guarded recorder shared between the observer thread and the main-loop tap.
final class CadenceRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [CadenceEvent] = []
  private var downs: [Double] = []
  private var ups: [Double] = []
  func add(_ e: CadenceEvent) { lock.lock(); events.append(e); lock.unlock() }
  func down() { lock.lock(); downs.append(now()); lock.unlock() }
  func up() { lock.lock(); ups.append(now()); lock.unlock() }
  func snapshot() -> (events: [CadenceEvent], downs: [Double], ups: [Double]) {
    lock.lock()
    defer { lock.unlock() }
    return (events, downs, ups)
  }
}

func runCadenceMode(_ args: [String]) -> Int32 {
  let bundles = ["finder": "com.apple.finder", "safari": "com.apple.Safari", "chrome": "com.google.Chrome"]
  guard let appKey = argValue("--app", in: args), let bundle = bundles[appKey] else {
    fail("cadence needs --app finder|safari|chrome", code: 64)
  }
  let seconds = Double(argValue("--seconds", in: args) ?? "40") ?? 40
  probeLog.open(mode: "cadence", app: appKey)
  let trusted = AXIsProcessTrusted()
  probeLog.emit(["event": "start", "mode": "cadence", "app": appKey, "seconds": seconds, "trusted": trusted])
  guard trusted else {
    print("SKIP not trusted")
    return 3
  }
  guard let pid = runningPID(bundleID: bundle) else {
    print("app not running: \(bundle)")
    return 2
  }
  let app = appElement(pid: pid)
  if appKey == "chrome" {
    // Chrome builds its AX tree lazily; this is the documented opt-in, an app-scoped AX write.
    let e = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    probeLog.emit(["event": "chromeManualAccessibility", "raw": Int(e.rawValue)])
  }
  let win = firstWindow(of: app)
  probeLog.emit(["event": "frontWindow", "found": win != nil])

  let rec = CadenceRecorder()
  let th = ObserverThread()
  let names = [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXMovedNotification, kAXResizedNotification]
  let windowWatch = AXWatch { name, _ in
    rec.add(CadenceEvent(name: name, t: now(), element: "window"))
    probeLog.emit(["event": "ax", "notification": name, "registeredOn": "window"])
  }
  let appWatch = AXWatch { name, _ in
    rec.add(CadenceEvent(name: name, t: now(), element: "app"))
    probeLog.emit(["event": "ax", "notification": name, "registeredOn": "app"])
  }
  var observerBox: UncheckedBox<AXObserver>?
  if let obs = makeObserver(pid: pid) {
    observerBox = UncheckedBox(value: obs)
    for n in names {
      if let win { addNotification(obs, win, n, windowWatch, label: "window") }
      addNotification(obs, app, n, appWatch, label: "app")
    }
  }
  let setupBox = observerBox
  th.start {
    if let setupBox {
      CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(setupBox.value), .defaultMode)
    }
  }

  let tap = ListenOnlyTap { type in
    if type == .leftMouseDown {
      rec.down()
      probeLog.emit(["marker": "down"])
    } else if type == .leftMouseUp {
      rec.up()
      probeLog.emit(["marker": "up"])
    }
  }
  let tapOK = tap.install(types: [.leftMouseDown, .leftMouseUp])
  probeLog.emit(["event": "tap", "created": tapOK])
  if !tapOK { probeLog.emit(["event": "tapNil"]) }

  CFRunLoopRunInMode(.defaultMode, seconds, false)  // main loop services the tap
  th.stop()
  Thread.sleep(forTimeInterval: 0.2)

  let snap = rec.snapshot()
  let rows = summarizeCadence(events: snap.events, downs: snap.downs, ups: snap.ups)
  print("cadence app=\(appKey) downs=\(snap.downs.count) ups=\(snap.ups.count) events=\(snap.events.count)")
  for r in rows {
    let ia = r.interArrival
    func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "-" }
    print("  \(r.name): count=\(r.count) betweenDownUp=\(r.betweenDownUp) within50msAfterUp=\(r.within50msAfterUp) interArrivalMs min/med/max=\(f(ia?.min))/\(f(ia?.median))/\(f(ia?.max)) verdict=\(r.verdict)")
    probeLog.emit([
      "event": "summary", "app": appKey, "notification": r.name, "count": r.count,
      "betweenDownUp": r.betweenDownUp, "within50msAfterUp": r.within50msAfterUp,
      "minMs": ia.map { Decimal(string: String(format: "%.2f", $0.min)) ?? 0 } ?? NSNull(),
      "medianMs": ia.map { Decimal(string: String(format: "%.2f", $0.median)) ?? 0 } ?? NSNull(),
      "maxMs": ia.map { Decimal(string: String(format: "%.2f", $0.max)) ?? 0 } ?? NSNull(),
      "verdict": r.verdict,
    ])
  }
  if rows.isEmpty { print("  no notifications observed (zero counts)") }
  withExtendedLifetime((windowWatch, appWatch, tap)) {}
  return 0
}
