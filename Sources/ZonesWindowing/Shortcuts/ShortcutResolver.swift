import CoreGraphics
import Foundation
import ZonesCore

/// What one window-action press does to the focused window (CONTRACTS 3.7).
public enum CommandPlan: Hashable, Sendable {
  case snap(SnapPlan)
  case restore(OriginalFrameEntry, target: CGRect)
  case noOp(NoOpReason)
}

/// The focused window, read back before any write.
public struct FocusedWindow: Hashable, Sendable {
  public var record: WindowRecord
  public var facts: WindowFacts
  public var frame: CGRect
  public init(record: WindowRecord, facts: WindowFacts, frame: CGRect) {
    self.record = record
    self.facts = facts
    self.frame = frame
  }
}

/// Pure: turns one window-action press into a plan. Makes no write and never mutates the registry.
public enum ShortcutResolver {
  public static func plan(
    _ a: ShortcutAction, focused: FocusedWindow?, verdict: Verdict, topology: TopologySnapshot,
    layouts: [DisplayKey: ResolvedLayout], registry: OriginalFrameRegistry
  ) -> CommandPlan {
    // The dispatcher keeps openEditor and openSettings out of here; answering windowAbsent without a log keeps the
    // function total.
    guard a.isWindowAction else { return .noOp(.windowAbsent) }
    // Gates, first hit wins, one log line each: no window, then the verdict, then the facts (belt and braces).
    guard let focused else { return noOp(.windowAbsent, "\(describe(a)): no focused window", nil) }
    let mode: SnapMode
    switch verdict {
    case .skip(let reason):
      Log.skip(reason, focused.record.ref, category: .shortcuts)
      switch reason {
      case .fullScreen: return .noOp(.fullScreen)
      case .positionNotSettable: return .noOp(.positionNotSettable)
      default: return .noOp(.excluded)
      }
    case .allow(let allowed): mode = allowed
    }
    if focused.facts.isFullScreen { return noOp(.fullScreen, "\(describe(a)): window is full-screen", focused) }
    if !focused.facts.positionSettable {
      return noOp(.positionNotSettable, "\(describe(a)): position is not settable", focused)
    }
    switch a {
    case .sendToZone(let n):
      guard let layout = layout(for: focused, topology: topology, layouts: layouts) else {
        return noOp(.zoneAbsent, "\(describe(a)): no Zones on this Display", focused)
      }
      guard (1...layout.zones.count).contains(n) else {
        return noOp(.zoneAbsent, "\(describe(a)): Layout has \(layout.zones.count) Zones", focused)
      }
      return .snap(snapPlan(zone: n, layout: layout, focused: focused, mode: mode))
    default:
      return .noOp(.windowAbsent)
    }
  }

  /// The resolved Layout of the Display the window overlaps most; nil when it overlaps none or the Display has no Layout.
  static func layout(
    for focused: FocusedWindow, topology: TopologySnapshot, layouts: [DisplayKey: ResolvedLayout]
  ) -> ResolvedLayout? {
    guard let display = CoordinateSpace.display(for: focused.frame, in: topology) else { return nil }
    return layouts[display.key]
  }

  /// A keyboard Snap to one Zone; the Original Frame is the pre-write read-back (ADR-0009, amended).
  static func snapPlan(zone n: Int, layout: ResolvedLayout, focused: FocusedWindow, mode: SnapMode) -> SnapPlan {
    SnapPlan(
      window: focused.record.ref, display: layout.display, zones: [n], target: layout.zones[n - 1].frame, mode: mode,
      via: .keyboard, originalFrame: focused.frame)
  }

  static func describe(_ a: ShortcutAction) -> String {
    switch a {
    case .sendToZone(let n): "sendToZone(\(n))"
    case .cycleRight: "cycleRight"
    case .cycleLeft: "cycleLeft"
    case .restore: "restore"
    case .openEditor: "openEditor"
    case .openSettings: "openSettings"
    }
  }

  /// The one log line of a no-op. The message names the action and a count, never a window title (LI-003).
  static func noOp(_ reason: NoOpReason, _ message: String, _ focused: FocusedWindow?) -> CommandPlan {
    let ref = focused?.record.ref
    Log.shared.event(
      LogEvent(
        time: ProcessInfo.processInfo.systemUptime, category: .shortcuts, level: .info,
        message: "noOp \(reason.rawValue): " + message, bundleID: ref?.bundleID, pid: ref?.pid))
    return .noOp(reason)
  }
}
