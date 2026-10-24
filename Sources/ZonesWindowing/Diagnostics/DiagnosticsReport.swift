import CoreGraphics
import Foundation
import ZonesCore

public struct DisplaySnapshotReport: Hashable, Codable, Sendable {
  public var key: String
  public var frame: CGRect
  public var visibleFrame: CGRect
  public var scale: Double
  public init(key: String, frame: CGRect, visibleFrame: CGRect, scale: Double) {
    self.key = key
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.scale = scale
  }
}

/// Carries no window text of any kind (LI-003).
public struct DiagnosticsReport: Hashable, Codable, Sendable {
  public var version: String
  public var build: String
  public var signingIdentity: String
  public var macOS: String
  public var permission: String
  public var tap: String
  public var displays: [DisplaySnapshotReport]
  public var assignments: [String: Assignment]
  public var preferences: Preferences
  public var events: [LogEvent]
  public var skipCounts: [String: [SkipReason: Int]]

  public init(
    version: String, build: String, signingIdentity: String, macOS: String, permission: String, tap: String,
    displays: [DisplaySnapshotReport], assignments: [String: Assignment], preferences: Preferences,
    events: [LogEvent], skipCounts: [String: [SkipReason: Int]]
  ) {
    self.version = version
    self.build = build
    self.signingIdentity = signingIdentity
    self.macOS = macOS
    self.permission = permission
    self.tap = tap
    self.displays = displays
    self.assignments = assignments
    self.preferences = preferences
    self.events = events
    self.skipCounts = skipCounts
  }

  /// Deterministic plain text: one `label: value` line per scalar, then the sections.
  public func render() -> String {
    var out = [
      "version: \(version)", "build: \(build)", "signingIdentity: \(signingIdentity)", "macOS: \(macOS)",
      "permission: \(permission)", "tap: \(tap)",
    ]
    out.append("displays: \(displays.count)")
    for d in displays {
      out.append("  \(d.key) frame=\(d.frame) visibleFrame=\(d.visibleFrame) scale=\(d.scale)")
    }
    out.append("assignments: \(assignments.count)")
    for key in assignments.keys.sorted() {
      guard let a = assignments[key] else { continue }
      out.append(
        "  \(key) layout=\(a.layout.rawValue) display=\(a.displayName) "
          + "visibleFrame=\(a.lastVisibleFrame) scale=\(a.lastScale)")
    }
    out.append("preferences:")
    out += preferenceLines()
    out.append("events: \(events.count)")
    for e in events { out.append("  " + Self.line(e)) }
    out.append("skipCounts:")
    for bundle in skipCounts.keys.sorted() {
      let reasons = (skipCounts[bundle] ?? [:]).sorted { $0.key.rawValue < $1.key.rawValue }
      out.append("  \(bundle): " + reasons.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " "))
    }
    return out.joined(separator: "\n")
  }

  private func preferenceLines() -> [String] {
    let p = preferences
    return [
      "  schemaVersion: \(p.schemaVersion)", "  activationModifier: \(p.activationModifier.rawValue)",
      "  spanModifier: \(p.spanModifier.rawValue)", "  shortcuts: \(p.shortcuts.count)",
      "  appearance: \(p.appearance)", "  exclusions: \(p.exclusions.sorted().joined(separator: ","))",
      "  enhancedUI: \(p.enhancedUI.rawValue)",
      "  notices: \(p.notices.map(\.rawValue).sorted().joined(separator: ","))",
    ]
  }

  private static func line(_ e: LogEvent) -> String {
    var parts = ["\(e.time)", e.category.rawValue, e.level.rawValue, e.message]
    if let b = e.bundleID { parts.append(b) }
    if let pid = e.pid { parts.append("\(pid)") }
    if let s = e.skip { parts.append(s.rawValue) }
    return parts.joined(separator: " ")
  }
}
