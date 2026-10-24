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
    print("check CGEvent window-under-pointer == CGWindowList id: not run")
    let ok = identityOK == n && includingOK == n
    print(ok ? "PASS spk004 (partial: event field not run)" : "FAIL spk004")
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
