import Foundation
import ZonesCore

/// Preview always comes first, then copy (AC-154).
public enum DiagnosticsEffect: Hashable, Sendable { case preview(String), copy(String) }

public enum Diagnostics {
  public static func report(
    bundle: BundleInfo, permission: PermissionState, tap: TapState, topology: TopologySnapshot?,
    assignments: [String: Assignment], prefs: Preferences, ring: EventRing
  ) -> DiagnosticsReport {
    DiagnosticsReport(
      version: bundle.version, build: bundle.build, signingIdentity: bundle.signingIdentity,
      macOS: bundle.macOS, permission: String(describing: permission), tap: String(describing: tap),
      displays: (topology?.displays ?? []).map {
        DisplaySnapshotReport(
          key: keyText($0.key), frame: $0.frame, visibleFrame: $0.visibleFrame, scale: $0.scale)
      },
      assignments: assignments, preferences: prefs, events: Array(ring.events.suffix(Constants.ringCapacity)),
      skipCounts: ring.skipCounts)
  }

  /// Exactly `[.preview(text), .copy(text)]`.
  public static func effects(for report: DiagnosticsReport) -> [DiagnosticsEffect] {
    let text = report.render()
    return [.preview(text), .copy(text)]
  }

  private static func keyText(_ key: DisplayKey) -> String {
    switch key {
    case .uuid(let s), .unstable(let s): s
    }
  }
}
