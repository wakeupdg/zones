import Foundation
import ZonesCore

public enum PermissionState: Hashable, Sendable {
  case notGranted, granted, suspect(since: TimeInterval)
  case revoked(failures: Int, firstFailure: TimeInterval?)
  case needsRelaunch
}

public enum PermissionEvent: Hashable, Sendable {
  case probe(Bool), apiDisabled, tapNil, tapRecreated(Bool), trivialRead(AXStatus), heartbeat(AXStatus)
  case timer(TimerID), wake, reonboard, quit
}

public enum PermissionEffect: Hashable, Sendable {
  case schedule(TimerID, TimeInterval), cancel(TimerID), probe, heartbeat, startTap, revalidateTap, recreateTap
  case dismissOnboarding, showOnboarding, badge(Bool), grantMenuItem(Bool), offerRelaunch(Bool)
  case registerWindowHotkeys, unregisterWindowHotkeys
  case drainEnhancedUI, forceTopologySnapshot, orderPanelsOut, disableTap, invalidateTap, removeRecoveryRecord
}

public struct PermissionConfig: Hashable, Sendable {
  public var launchedAtLogin: Bool
  /// SPK-006.
  public var heartbeatEnabled: Bool
  public var reducerIdle: Bool
  public init(launchedAtLogin: Bool, heartbeatEnabled: Bool, reducerIdle: Bool) {
    self.launchedAtLogin = launchedAtLogin
    self.heartbeatEnabled = heartbeatEnabled
    self.reducerIdle = reducerIdle
  }
}

public enum TapState: Hashable, Sendable { case alive, dead, unavailable }
