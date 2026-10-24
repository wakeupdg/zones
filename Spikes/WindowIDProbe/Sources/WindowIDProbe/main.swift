// WindowIDProbe: standalone spike for T05 (SPK-004, SPK-008, SPK-016).
// Public API only. Never requests window names or Screen Recording.
import AppKit
import CoreGraphics
import Foundation

// MARK: - Local mirrors of the contract shapes (the probe cannot import ZonesCore)

struct WindowRef {
    var id: UInt32
    var pid: pid_t
    var frame: CGRect
    var layer: Int32
}

// MARK: - CoreGraphics helpers

/// Decode one CGWindowList dictionary. Ignores names on purpose.
func windowRef(_ d: [String: Any]) -> WindowRef? {
    guard let num = d[kCGWindowNumber as String] as? UInt32 ?? (d[kCGWindowNumber as String] as? Int).map({ UInt32($0) }),
          let pid = d[kCGWindowOwnerPID as String] as? Int,
          let bd = d[kCGWindowBounds as String] as? NSDictionary,
          let frame = CGRect(dictionaryRepresentation: bd as CFDictionary)
    else { return nil }
    let layer = (d[kCGWindowLayer as String] as? Int).map { Int32($0) } ?? 0
    return WindowRef(id: num, pid: pid_t(pid), frame: frame, layer: layer)
}

func cgInfo(_ option: CGWindowListOption, _ id: CGWindowID = kCGNullWindowID) -> [[String: Any]] {
    (CGWindowListCopyWindowInfo(option, id) as? [[String: Any]]) ?? []
}

func osVersionLine() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}


// MARK: - Event tap helper

/// Written by the tap callback and read by the probe, both on the main run loop.
final class TapBox: @unchecked Sendable {
    var fieldPointer: Int64 = -1      // kCGMouseEventWindowUnderMousePointer
    var fieldCanHandle: Int64 = -1    // ...ThatCanHandleThisEvent
    var hits = 0
}

/// Listen-only session tap for leftMouseDown. Returns nil if the OS refuses it.
func makeMouseDownTap(box: TapBox, annotated: Bool) -> CFMachPort? {
    let mask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue
    return CGEvent.tapCreate(
        tap: annotated ? .cgAnnotatedSessionEventTap : .cgSessionEventTap,
        place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: mask,
        callback: { _, type, event, info in
            if type == .leftMouseDown, let info {
                let b = Unmanaged<TapBox>.fromOpaque(info).takeUnretainedValue()
                b.fieldPointer = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
                b.fieldCanHandle = event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
                b.hits += 1
            }
            return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(box).toOpaque())
}

/// Topmost layer-0 on-screen window containing the point (CG list is front to back).
func topWindow(at p: CGPoint) -> WindowRef? {
    cgInfo([.optionOnScreenOnly, .excludeDesktopElements]).compactMap { windowRef($0) }
        .first { $0.layer == 0 && $0.frame.contains(p) }
}

@MainActor
func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// Pump NSApplication events (windows only react to events dispatched through sendEvent).
@MainActor
func pump(_ seconds: TimeInterval) {
    let end = Date().addingTimeInterval(seconds)
    repeat {
        if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.004), inMode: .default, dequeue: true) {
            NSApp.sendEvent(e)
        }
    } while Date() < end
}

func post(_ type: CGEventType, at p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

// MARK: - spk004

@MainActor
func makeProbeWindows(count: Int) -> [NSWindow] {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
    let cols = 10
    let rows = (count + cols - 1) / cols
    let cellW = area.width / CGFloat(cols)
    let cellH = area.height / CGFloat(rows)
    var windows: [NSWindow] = []
    for i in 0..<count {
        let col = i % cols
        let row = i / cols
        // Vary size inside each cell: 55% to 95% of the cell.
        let fw = 0.55 + 0.4 * CGFloat((i * 7) % 10) / 9
        let fh = 0.55 + 0.4 * CGFloat((i * 3) % 10) / 9
        let w = max(60, (cellW * fw).rounded())
        let h = max(60, (cellH * fh).rounded())
        let x = area.minX + CGFloat(col) * cellW + 2
        let y = area.maxY - CGFloat(row + 1) * cellH + 2
        let borderless = i % 3 == 0
        let style: NSWindow.StyleMask = borderless ? [.borderless] : [.titled, .closable, .resizable]
        let win = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h),
                           styleMask: style, backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.title = "probe-\(i)"
        win.backgroundColor = borderless ? .systemTeal : .windowBackgroundColor
        win.orderFrontRegardless()
        windows.append(win)
    }
    return windows
}

@MainActor
func runSpk004() -> Int32 {
    let n = 50
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let windows = makeProbeWindows(count: n)
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))

    let all = cgInfo(.optionAll)
    let allByNumber = Dictionary(uniqueKeysWithValues: all.compactMap { d in
        windowRef(d).map { ($0.id, d) }
    })
    var identityOK = 0
    var includingOK = 0
    for w in windows {
        let id = UInt32(truncatingIfNeeded: w.windowNumber)
        let present = allByNumber[id].flatMap { windowRef($0) }?.pid == getpid()
        if present { identityOK += 1 }
        // optionIncludingWindow ALONE (no companion option).
        let alone = cgInfo(.optionIncludingWindow, CGWindowID(id)).compactMap { windowRef($0) }
        if alone.count == 1, alone[0].id == id, alone[0].pid == getpid() { includingOK += 1 }
    }
    print("SPK-004 \(osVersionLine())")
    print("check windowNumber == kCGWindowNumber (optionAll): \(identityOK) of \(n)")
    print("check optionIncludingWindow alone returns the window: \(includingOK) of \(n)")

    // Event field: click the center of each window, read the window-under-pointer fields.
    // Two taps: plain session tap and annotated session tap (the window fields are
    // filled in by the window server annotation stage).
    let boxS = TapBox(), boxA = TapBox()
    guard let tapS = makeMouseDownTap(box: boxS, annotated: false),
          let tapA = makeMouseDownTap(box: boxA, annotated: true) else {
        print("BLOCKED spk004: CGEvent.tapCreate returned nil (host app needs Accessibility/Input Monitoring grant)")
        return 2
    }
    let srcS = CFMachPortCreateRunLoopSource(nil, tapS, 0)
    let srcA = CFMachPortCreateRunLoopSource(nil, tapA, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), srcS, .commonModes)
    CFRunLoopAddSource(CFRunLoopGetMain(), srcA, .commonModes)
    CGEvent.tapEnable(tap: tapS, enable: true)
    CGEvent.tapEnable(tap: tapA, enable: true)
    var annCanHandleOK = 0, annPointerOK = 0, sessCanHandleOK = 0, sessPointerOK = 0, hitTestOK = 0, delivered = 0
    var mismatches: [String] = []
    for (i, w) in windows.enumerated() {
        let id = UInt32(truncatingIfNeeded: w.windowNumber)
        guard let ref = cgInfo(.optionIncludingWindow, CGWindowID(id)).compactMap({ windowRef($0) }).first else { continue }
        let center = CGPoint(x: ref.frame.midX, y: ref.frame.midY)
        for b in [boxS, boxA] { b.hits = 0; b.fieldPointer = -1; b.fieldCanHandle = -1 }
        post(.mouseMoved, at: center)
        spin(0.03)
        post(.leftMouseDown, at: center)
        let deadline = Date().addingTimeInterval(0.5)
        while (boxS.hits == 0 || boxA.hits == 0) && Date() < deadline { spin(0.01) }
        post(.leftMouseUp, at: center)
        spin(0.03)
        if boxA.hits > 0 { delivered += 1 }
        if boxA.fieldCanHandle == Int64(id) { annCanHandleOK += 1 }
        else { mismatches.append("window#\(i) id=\(id) annotated canHandle=\(boxA.fieldCanHandle) hits=\(boxA.hits)") }
        if boxA.fieldPointer == Int64(id) { annPointerOK += 1 }
        if boxS.fieldCanHandle == Int64(id) { sessCanHandleOK += 1 }
        if boxS.fieldPointer == Int64(id) { sessPointerOK += 1 }
        if topWindow(at: center)?.id == id { hitTestOK += 1 }
    }
    for t in [tapS, tapA] { CGEvent.tapEnable(tap: t, enable: false) }
    for s in [srcS, srcA] { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
    print("events delivered to annotated tap: \(delivered) of \(n)")
    print("check event field ...ThatCanHandleThisEvent == id (annotated session tap): \(annCanHandleOK) of \(n)")
    print("info  event field WindowUnderMousePointer == id (annotated session tap): \(annPointerOK) of \(n)")
    print("info  ...ThatCanHandleThisEvent == id (plain session tap): \(sessCanHandleOK) of \(n)")
    print("info  WindowUnderMousePointer == id (plain session tap): \(sessPointerOK) of \(n)")
    print("info  CGWindowList hit test (top layer-0 under center) == id: \(hitTestOK) of \(n)")
    for m in mismatches.prefix(10) { print("mismatch \(m)") }
    let ok = identityOK == n && includingOK == n && annCanHandleOK == n
    print(ok ? "PASS spk004" : "FAIL spk004")
    return ok ? 0 : 1
}


// MARK: - Sampling helpers (shared by spk008 and spk016)

func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

func sleepUntil(_ ns: UInt64) {
    while true {
        let t = nowNs()
        if t >= ns { return }
        let rem = ns - t
        if rem > 2_000_000 { usleep(UInt32((rem - 1_000_000) / 1000)) }
    }
}

/// CG description read by id. Matches by kCGWindowNumber, never by array index.
func cgDescriptionOrigins(ids: [UInt32]) -> [UInt32: CGPoint] {
    var cfIDs = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    guard let arr = CFArrayCreate(nil, &cfIDs, cfIDs.count, nil),
          let list = CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]] else { return [:] }
    var out: [UInt32: CGPoint] = [:]
    for d in list { if let r = windowRef(d) { out[r.id] = r.frame.origin } }
    return out
}

struct AXRead {
    var byTitle: [String: CGPoint] = [:]   // our own windows only; titles are the probe's
    var timeouts = 0
    var errors = 0
}

/// AX frame read of every window of `pid` with a 250 ms messaging timeout (ADR-0015).
/// Must NOT run on the main thread when `pid` is this process.
func axTitlePositions(pid: pid_t) -> AXRead {
    var res = AXRead()
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    var v: CFTypeRef?
    let e = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v)
    if e == .cannotComplete { res.timeouts += 1; return res }
    guard e == .success, let wins = v as? [AXUIElement] else { res.errors += 1; return res }
    for w in wins {
        AXUIElementSetMessagingTimeout(w, 0.25)
        var t: CFTypeRef?, p: CFTypeRef?
        let e1 = AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
        let e2 = AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p)
        if e1 == .cannotComplete || e2 == .cannotComplete { res.timeouts += 1; continue }
        guard e1 == .success, e2 == .success, let title = t as? String, let pv = p,
              CFGetTypeID(pv) == AXValueGetTypeID() else { res.errors += 1; continue }
        var pt = CGPoint.zero
        if AXValueGetValue(pv as! AXValue, .cgPoint, &pt) { res.byTitle[title] = pt } else { res.errors += 1 }
    }
    return res
}

/// Thread-safe sample sink.
final class SampleStore<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    private var finished = false
    func add(_ x: T) { lock.lock(); items.append(x); lock.unlock() }
    func finish() { lock.lock(); finished = true; lock.unlock() }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}

// MARK: - spk008

struct StackSample: Sendable {
    var tick: Int
    var tMs: Double
    var cgChanged: [Int]
    var axChanged: [Int]
    var axAvailable: Bool
    var cgReadMs: Double
    var axReadMs: Double
}

@MainActor
func runSpk008(single: Bool) -> Int32 {
    let trials = 20, stackCount = 4, ticks = 8
    let streamCount = single ? 0 : 20     // dragged events after the first one
    let tickNs: UInt64 = 16_666_667
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let axTrusted = AXIsProcessTrusted()

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let content = NSRect(x: screen.visibleFrame.midX - 200, y: screen.visibleFrame.midY - 100, width: 400, height: 200)
    var windows: [NSWindow] = []
    for i in 0..<stackCount {
        let w = NSWindow(contentRect: content, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = "stack-\(i)"
        w.orderFrontRegardless()
        windows.append(w)
    }
    let frame = windows[0].frame
    let ids = windows.map { UInt32(truncatingIfNeeded: $0.windowNumber) }
    spin(0.5)
    if ProcessInfo.processInfo.environment["PROBE_DIAG"] != nil {
        let w0 = windows[0]
        print("diag frame \(w0.frame) contentLayoutRect \(w0.contentLayoutRect) movable \(w0.isMovable) cg \(cgInfo(.optionIncludingWindow, CGWindowID(ids[0])).compactMap { windowRef($0) }.first!.frame)")
    }

    print("SPK-008 \(osVersionLine())  AX trusted: \(axTrusted)  mode: \(single ? "single dragged event" : "dragged stream at 125 Hz")")
    let diag = ProcessInfo.processInfo.environment["PROBE_DIAG"] != nil
    if diag {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { e in
            print("diag NSEvent \(e.type.rawValue) win=\(e.windowNumber) loc=\(e.locationInWindow)"); return e
        }
    }
    var order: [Int] = (0..<trials).map { $0 % stackCount }
    order.shuffle()

    struct Trial { var top: Int; var samples: [StackSample] }
    var results: [Trial] = []
    var lastFrames: [CGFloat] = []
    let pid = getpid()

    for (trial, top) in order.enumerated() {
        // Reset all four to the same origin, then raise `top` to the front.
        for w in windows { w.setFrame(frame, display: true) }
        for (i, w) in windows.enumerated() where i != top { w.orderFrontRegardless() }
        windows[top].orderFrontRegardless()
        spin(0.25)
        // Z-order check from CG (front to back).
        let z = cgInfo([.optionOnScreenOnly, .excludeDesktopElements]).compactMap { windowRef($0) }
        let cgTop = z.first { ids.contains($0.id) }.flatMap { r in ids.firstIndex(of: r.id) }
        let base = cgDescriptionOrigins(ids: ids)
        let ref = cgInfo(.optionIncludingWindow, CGWindowID(ids[top])).compactMap { windowRef($0) }.first!

        let p0 = CGPoint(x: ref.frame.midX, y: ref.frame.minY + 12)   // title bar
        let p1 = CGPoint(x: p0.x + 40, y: p0.y + 25)
        let lastPoint = CGPoint(x: p1.x + CGFloat(streamCount) * 3, y: p1.y + CGFloat(streamCount) * 2)
        let store = SampleStore<StackSample>()
        let titles = (0..<stackCount).map { "stack-\($0)" }
        let baseAXCopy = axBaseline(pid: pid, trusted: axTrusted, titles: titles, spinning: true)
        // The title-bar mouse-down enters AppKit's drag tracking loop on the main thread and
        // blocks it until mouse-up, so every event is posted from a driver thread while the
        // main thread pumps NSApp events.
        DispatchQueue.global(qos: .userInteractive).async {
            post(.mouseMoved, at: p0); usleep(40_000)
            post(.leftMouseDown, at: p0); usleep(60_000)
            let t0 = nowNs()
            post(.leftMouseDragged, at: p1)       // the first dragged event
            if streamCount > 0 {                  // then a 125 Hz stream, like a real mouse
                DispatchQueue.global(qos: .userInteractive).async {
                    for k in 1...streamCount {
                        sleepUntil(t0 + UInt64(k) * 8_000_000)
                        post(.leftMouseDragged, at: CGPoint(x: p1.x + CGFloat(k) * 3, y: p1.y + CGFloat(k) * 2))
                    }
                }
            }
            for tick in 1...ticks {
                sleepUntil(t0 + UInt64(tick) * tickNs)
                let a = nowNs()
                let cg = cgDescriptionOrigins(ids: ids)
                let b = nowNs()
                let ax = axTrusted ? axTitlePositions(pid: pid) : AXRead()
                let c = nowNs()
                var cgCh: [Int] = [], axCh: [Int] = []
                for (i, id) in ids.enumerated() {
                    if let o = cg[id], let o0 = base[id], abs(o.x - o0.x) > 0.5 || abs(o.y - o0.y) > 0.5 { cgCh.append(i) }
                    if let o = ax.byTitle[titles[i]], let o0 = baseAXCopy[titles[i]], abs(o.x - o0.x) > 0.5 || abs(o.y - o0.y) > 0.5 { axCh.append(i) }
                }
                store.add(StackSample(tick: tick, tMs: Double(a - t0) / 1e6, cgChanged: cgCh, axChanged: axCh,
                                      axAvailable: axTrusted && ax.byTitle.count == titles.count,
                                      cgReadMs: Double(b - a) / 1e6, axReadMs: Double(c - b) / 1e6))
            }
            usleep(80_000)
            post(.leftMouseUp, at: lastPoint); usleep(100_000)
            store.finish()
        }
        let deadline = Date().addingTimeInterval(5)
        while !store.isFinished && Date() < deadline { pump(0.005) }
        pump(0.1)
        if diag { print("diag after trial: top window frame \(windows[top].frame)") }
        lastFrames.append(windows[top].frame.origin.x - frame.origin.x)
        results.append(Trial(top: cgTop ?? -1, samples: store.all))
        _ = trial
    }

    // Report.
    func firstChange(_ t: Trial, ax: Bool) -> (tick: Int, set: [Int])? {
        for s in t.samples { let c = ax ? s.axChanged : s.cgChanged; if !c.isEmpty { return (s.tick, c) } }
        return nil
    }
    print("trial | top(cg z) | tick1 changed cg / ax | first change cg (tick: set) | first change ax (tick: set)")
    var strictCG = 0, strictAX = 0, relaxedCG = 0, relaxedAX = 0, topMatches = 0
    for (i, t) in results.enumerated() {
        let s1 = t.samples.first
        let cg1 = s1?.cgChanged ?? [], ax1 = s1?.axChanged ?? []
        if cg1.count == 1 { strictCG += 1 }
        if ax1.count == 1 { strictAX += 1 }
        let fc = firstChange(t, ax: false), fa = firstChange(t, ax: true)
        if fc?.set.count == 1 { relaxedCG += 1 }
        if fa?.set.count == 1 { relaxedAX += 1 }
        if let m = fc?.set.first, fc?.set.count == 1, m == t.top { topMatches += 1 }
        func fmt(_ x: (tick: Int, set: [Int])?) -> String { x.map { "\($0.tick): \($0.set)" } ?? "none" }
        print(String(format: "%5d | %9d | %@ / %@ | %@ | %@", i + 1, t.top, "\(cg1)", "\(ax1)", fmt(fc), fmt(fa)))
    }
    let cgMs = results.flatMap { $0.samples }.map { $0.cgReadMs }.sorted()
    let axMs = results.flatMap { $0.samples }.map { $0.axReadMs }.sorted()
    func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * p))] }
    print(String(format: "read cost ms: cg p50 %.2f p95 %.2f max %.2f | ax p50 %.2f p95 %.2f max %.2f",
                 pct(cgMs, 0.5), pct(cgMs, 0.95), cgMs.last ?? 0, pct(axMs, 0.5), pct(axMs, 0.95), axMs.last ?? 0))
    print("strict (tick 1 after the dragged event, exactly one candidate changed): cg \(strictCG) of \(trials), ax \(strictAX) of \(trials)")
    print("relaxed (first tick with any change, exactly one changed): cg \(relaxedCG) of \(trials), ax \(relaxedAX) of \(trials)")
    print("net x displacement of the dragged window after each trial (pt): \(lastFrames.map { Int($0) })")
    print("moved candidate equals CG z-order top window: \(topMatches) of \(trials)")
    // Verdict source: the CG description sample (the candidate-resolution source). The AX source
    // is reported alongside; same-process AX reads are served by the main thread that is inside
    // AppKit's drag tracking loop, so its lag here is a caveat, not a clean measurement.
    let ok = strictCG == trials
    print("AX source at tick 1: \(strictAX == trials ? "PASS" : "FAIL") (\(strictAX) of \(trials)); at first changed tick: \(relaxedAX == trials ? "PASS" : "FAIL") (\(relaxedAX) of \(trials))")
    print(ok ? "PASS spk008 (CG description source)" : "FAIL spk008 (CG description source)")
    return ok ? 0 : 1
}

/// AX baseline taken from a background thread (own-process AX cannot be read on the main thread).
@MainActor
func axBaseline(pid: pid_t, trusted: Bool, titles: [String], spinning: Bool) -> [String: CGPoint] {
    guard trusted else { return [:] }
    let store = SampleStore<AXRead>()
    DispatchQueue.global().async { store.add(axTitlePositions(pid: pid)); store.finish() }
    let deadline = Date().addingTimeInterval(2)
    while !store.isFinished && Date() < deadline { pump(0.005) }
    return store.all.first?.byTitle ?? [:]
}

// MARK: - Entry

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "spk004":
    exit(MainActor.assumeIsolated { runSpk004() })
case "spk008":
    let single = args.contains("--single")
    exit(MainActor.assumeIsolated { runSpk008(single: single) })
case "spk016":
    print("FAIL \(args.first!): unimplemented")
    exit(1)
default:
    print("usage: WindowIDProbe spk004|spk008|spk016")
    exit(64)
}
