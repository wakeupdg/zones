import Foundation
import ZonesCore

/// Automatic skips (ADR-0018). Phase 1 decides from CoreGraphics facts alone, so no Accessibility
/// call happens before it; phase 2 decides from Accessibility facts. Both are pure.
public enum ExclusionPolicy {
  /// Bundle identifiers of system agents whose windows Zones never moves.
  public static let systemAgents: Set<String> = [
    "com.apple.dock", "com.apple.WindowManager", "com.apple.notificationcenterui",
    "com.apple.controlcenter", "com.apple.loginwindow", "com.apple.UserNotificationCenter",
  ]

  /// Order: ownProcess, systemAgent, excludedBundle, unresponsive. A nil bundle id matches neither
  /// systemAgent nor excludedBundle. Never returns `ambiguousMatch` (candidate resolution does).
  public static func phaseOne(
    _ ref: WindowRef, ownPid: pid_t, exclusions: Set<String>, health: AppHealth, now: TimeInterval
  ) -> Verdict {
    if ref.pid == ownPid { return .skip(.ownProcess) }
    if let bundleID = ref.bundleID {
      if systemAgents.contains(bundleID) { return .skip(.systemAgent) }
      if exclusions.contains(bundleID) { return .skip(.excludedBundle) }
    }
    if health.isUnresponsive(ref.pid, now: now) { return .skip(.unresponsive) }
    return .allow(.full)
  }

  /// Order: sheet or popover, system dialog, other non-standard subroles, full screen, position not
  /// settable, then size not settable (position-only Snap, ADR-0018 amendment C4).
  public static func phaseTwo(_ facts: WindowFacts) -> Verdict {
    switch facts.subrole {
    case .sheet, .popover: return .skip(.sheetOrPopover)
    case .systemDialog, .systemFloatingWindow: return .skip(.systemDialog)
    case .dialog, .floating, .unknown: return .skip(.nonStandardSubrole)
    case .standard: break
    }
    if facts.isFullScreen { return .skip(.fullScreen) }
    if !facts.positionSettable { return .skip(.positionNotSettable) }
    if !facts.sizeSettable { return .allow(.positionOnly) }
    return .allow(.full)
  }
}
