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
    guard let focused, case .allow(let mode) = verdict else { return .noOp(.windowAbsent) }
    switch a {
    case .sendToZone(let n):
      guard let layout = layout(for: focused, topology: topology, layouts: layouts) else {
        return .noOp(.zoneAbsent)
      }
      guard (1...layout.zones.count).contains(n) else { return .noOp(.zoneAbsent) }
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
}
