import CoreGraphics
import Foundation
import ZonesCore

public struct SnapPlan: Hashable, Sendable {
  public var window: WindowRef
  public var display: DisplayKey
  public var zones: Set<Int>
  public var target: CGRect
  public var mode: SnapMode
  public var via: CapturePath
  /// Mouse path: the mouse-down frame.
  public var originalFrame: CGRect?
  public init(
    window: WindowRef, display: DisplayKey, zones: Set<Int>, target: CGRect, mode: SnapMode,
    via: CapturePath, originalFrame: CGRect?
  ) {
    self.window = window
    self.display = display
    self.zones = zones
    self.target = target
    self.mode = mode
    self.via = via
    self.originalFrame = originalFrame
  }
}

/// Unresponsive cooldown, Clock-driven (AC-077). The methods belong to the health ticket.
public struct AppHealth: Hashable, Sendable {
  public var unresponsiveSince: [pid_t: TimeInterval]
  public init(unresponsiveSince: [pid_t: TimeInterval] = [:]) {
    self.unresponsiveSince = unresponsiveSince
  }
}

public struct RecoveryRecord: Hashable, Codable, Sendable {
  public var bundleID: String
  public var pid: Int32
  public var launchDate: Date
  public var priorEnhancedUI: Bool
  public init(bundleID: String, pid: Int32, launchDate: Date, priorEnhancedUI: Bool) {
    self.bundleID = bundleID
    self.pid = pid
    self.launchDate = launchDate
    self.priorEnhancedUI = priorEnhancedUI
  }
}
