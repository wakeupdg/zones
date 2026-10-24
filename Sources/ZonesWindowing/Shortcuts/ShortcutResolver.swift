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
    var mode: SnapMode
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
    // Same rule as ExclusionPolicy.phaseTwo: a size-locked window gets a position-only Snap, never a size write
    // (ADR-0018 C4, AC-144). The verdict passed in is phase one's, which always allows `.full`.
    if !focused.facts.sizeSettable { mode = .positionOnly }
    let key = focused.record.handle.key
    switch a {
    case .sendToZone(let n):
      guard let layout = zones(for: a, focused, topology, layouts) else { return .noOp(.zoneAbsent) }
      guard (1...layout.zones.count).contains(n) else {
        return noOp(.zoneAbsent, "\(describe(a)): Layout has \(layout.zones.count) Zones", focused)
      }
      return .snap(snapPlan(zone: n, layout: layout, focused: focused, mode: mode))
    case .cycleRight, .cycleLeft:
      guard let layout = zones(for: a, focused, topology, layouts) else { return .noOp(.zoneAbsent) }
      let last = registry.lastSnap(key)
      let matched = CycleResolver.matchedRecord(last, frame: focused.frame, layout: layout)
      let base = CycleResolver.base(last, frame: focused.frame, layout: layout)
      let span = matched.map(\.zones).flatMap { $0.count >= 2 ? $0 : nil }
      let n = CycleResolver.next(
        from: base, direction: a == .cycleRight ? .right : .left, count: layout.zones.count, span: span)
      return .snap(snapPlan(zone: n, layout: layout, focused: focused, mode: mode))
    case .restore:
      guard let entry = registry.entry(key) else {
        return noOp(.noEntry, "restore: no Original Frame", focused)
      }
      switch RestorePlanner.plan(entry, window: focused.record.ref, facts: focused.facts, topology: topology) {
      case .success(let target): return .restore(entry, target: target)
      case .failure(let reason): return noOp(reason, "restore: \(reason.rawValue)", focused)
      }
    case .openEditor, .openSettings:
      return .noOp(.windowAbsent)  // unreachable: filtered above
    }
  }

  /// The Layout of the Display the window overlaps most, or the no-op log line when there is none (no Zones).
  static func zones(
    for a: ShortcutAction, _ focused: FocusedWindow, _ topology: TopologySnapshot,
    _ layouts: [DisplayKey: ResolvedLayout]
  ) -> ResolvedLayout? {
    if let layout = layout(for: focused, topology: topology, layouts: layouts) { return layout }
    _ = noOp(.zoneAbsent, "\(describe(a)): no Zones on this Display", focused)
    return nil
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
