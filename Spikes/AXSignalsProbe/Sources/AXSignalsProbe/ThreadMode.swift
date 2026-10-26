import ApplicationServices
import AppKit
import Foundation

/// `thread` mode.
/// Part A: custom run-loop source on the dedicated thread, signalled at t=0 and after `--idle`.
/// Part B (AX trust): an AXObserver source on the same thread for Calculator; the window is
/// nudged 10 px and back at t=0 and after `--idle`; callbacks must land on `ax-observer`.
func runThreadMode(_ args: [String]) -> Int32 {
  let idle = Double(argValue("--idle", in: args) ?? "60") ?? 60
  let target = argValue("--target", in: args) ?? "calculator"
  guard target == "calculator" else { fail("unsupported --target \(target)", code: 64) }
  probeLog.open(mode: "thread", app: target)
  let trusted = AXIsProcessTrusted()
  probeLog.emit(["event": "start", "mode": "thread", "idle": idle, "trusted": trusted])

  // Part B preparation on main (trusted only): launch Calculator, build the observer.
  var win: AXUIElement?
  var observerBox: UncheckedBox<AXObserver>?
  var watch: AXWatch?
  let th = ObserverThread()
  if trusted {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", "Calculator"]
    try? open.run()
    open.waitUntilExit()
    var pid: pid_t?
    for _ in 0..<50 where pid == nil {
      pid = runningPID(bundleID: "com.apple.calculator")
      if pid == nil { Thread.sleep(forTimeInterval: 0.2) }
    }
    if let pid {
      let app = appElement(pid: pid)
      for _ in 0..<50 where win == nil {
        win = firstWindow(of: app, front: false)
        if win == nil { Thread.sleep(forTimeInterval: 0.2) }
      }
      if let win, let obs = makeObserver(pid: pid) {
        let w = AXWatch { name, _ in th.noteCallback(source: "ax", detail: name) }
        watch = w
        observerBox = UncheckedBox(value: obs)
        addNotification(obs, win, kAXMovedNotification, w, label: "window")
        addNotification(obs, win, kAXWindowMovedNotification, w, label: "window")
      }
    }
    probeLog.emit(["event": "calculator", "pid": Int(pid ?? -1), "haveWindow": win != nil])
  }

  // Source is added on the dedicated thread, in .defaultMode, before CFRunLoopRun.
  let setupBox = observerBox
  th.start {
    if let setupBox {
      CFRunLoopAddSource(
        CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(setupBox.value), .defaultMode)
    }
  }

  func nudge(_ label: String) -> Double? {
    guard let win, let p0 = windowPosition(win) else { return nil }
    let t0 = now()
    let e1 = setWindowPosition(win, CGPoint(x: p0.x + 10, y: p0.y))
    Thread.sleep(forTimeInterval: 0.15)
    let e2 = setWindowPosition(win, p0)
    probeLog.emit([
      "event": "nudge", "label": label, "setRaw": [Int(e1.rawValue), Int(e2.rawValue)],
    ])
    return t0
  }
  func firstAXCallback(after t0: Double) -> ObserverThread.Callback? {
    for _ in 0..<20 {
      if let c = th.recorded.first(where: { $0.source == "ax" && $0.t >= t0 }) { return c }
      Thread.sleep(forTimeInterval: 0.1)
    }
    return nil
  }

  th.signalCustom()
  let nudge0 = nudge("t0")
  let ax0 = nudge0.flatMap(firstAXCallback(after:))
  Thread.sleep(forTimeInterval: 0.5)
  probeLog.emit(["event": "idle-begin", "seconds": idle])
  Thread.sleep(forTimeInterval: idle)
  probeLog.emit(["event": "idle-end"])
  th.signalCustom()
  let nudge1 = nudge("afterIdle")
  let ax1 = nudge1.flatMap(firstAXCallback(after:))
  Thread.sleep(forTimeInterval: 0.5)

  let custom = th.recorded.filter { $0.source == "custom" }
  let customOK = custom.count == 2
    && custom.allSatisfy { $0.onObserverThread && !$0.onMain && $0.threadName == ObserverThread.threadName }
  let early = th.returnedEarly
  let partA = customOK && !early
  probeLog.emit([
    "event": "partA", "pass": partA, "callbacks": custom.count,
    "runLoopReturnedEarly": early,
  ])
  print("partA: \(partA ? "PASS" : "FAIL") callbacks=\(custom.count) runLoopReturnedEarly=\(early)")

  var partB = false
  if trusted {
    func onThread(_ c: ObserverThread.Callback?) -> Bool {
      guard let c else { return false }
      return c.onObserverThread && !c.onMain && c.threadName == ObserverThread.threadName
    }
    partB = onThread(ax0) && onThread(ax1)
    let lat0 = ax0.flatMap { c in nudge0.map { (c.t - $0) * 1000 } }
    let lat1 = ax1.flatMap { c in nudge1.map { (c.t - $0) * 1000 } }
    probeLog.emit([
      "event": "partB", "pass": partB, "callbackAtT0": ax0 != nil, "callbackAfterIdle": ax1 != nil,
      "latencyMsT0": lat0.map { Decimal(string: String(format: "%.2f", $0)) ?? 0 } ?? NSNull(),
      "latencyMsAfterIdle": lat1.map { Decimal(string: String(format: "%.2f", $0)) ?? 0 } ?? NSNull(),
    ])
    print("partB: \(partB ? "PASS" : "FAIL") t0=\(ax0 != nil) afterIdle=\(ax1 != nil) latencyMs=\(lat0 ?? -1)/\(lat1 ?? -1)")
  }
  th.stop()
  Thread.sleep(forTimeInterval: 0.2)
  withExtendedLifetime(watch) {}  // refcon is unretained; keep alive to here

  if !partA { return 1 }
  if !trusted {
    print("SKIP not trusted")
    return 3
  }
  return partB ? 0 : 1
}
