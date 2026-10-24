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

@MainActor
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

// MARK: - Entry

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "spk004":
    exit(MainActor.assumeIsolated { runSpk004() })
case "spk008", "spk016":
    print("FAIL \(args.first!): unimplemented")
    exit(1)
default:
    print("usage: WindowIDProbe spk004|spk008|spk016")
    exit(64)
}
