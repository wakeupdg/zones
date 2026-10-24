import Foundation
import ZonesCore

/// The pure Accessibility permission machine (T20, ADR-0021). No Clock, no actor, no AppKit: timers are
/// `schedule`/`cancel` effects that the driver turns into one-shot Clock timers. Every `schedule` of an id that may
/// already be pending is preceded by `cancel` of that id, so at most one timer per id exists.
public enum PermissionMachine {
  public static func reduce(
    _ s: PermissionState, _ e: PermissionEvent, config: PermissionConfig, now: TimeInterval
  ) -> (PermissionState, [PermissionEffect]) {
    let (next, effects) = step(s, e, config: config, now: now)
    guard config.launchedAtLogin else { return (next, effects) }
    // Launched at login: no window effects. The badge and the "Grant Accessibility" item carry the message.
    return (next, effects.filter { $0 != .showOnboarding && $0 != .dismissOnboarding })
  }

  private static func rearm(_ id: TimerID, _ seconds: TimeInterval) -> [PermissionEffect] {
    [.cancel(id), .schedule(id, seconds)]
  }

  private static func step(
    _ s: PermissionState, _ e: PermissionEvent, config: PermissionConfig, now: TimeInterval
  ) -> (PermissionState, [PermissionEffect]) {
    switch s {
    case .notGranted: return notGranted(e)
    case .granted: return granted(e, config: config)
    case .suspect, .revoked, .needsRelaunch: return (s, [])
    }
  }

  private static var grantedEntry: [PermissionEffect] {
    [.badge(false), .grantMenuItem(false), .registerWindowHotkeys] + rearm(.healthTick, Constants.healthTick)
  }

  private static func notGranted(_ e: PermissionEvent) -> (PermissionState, [PermissionEffect]) {
    switch e {
    case .timer(.trustPoll): return (.notGranted, [.probe])
    case .probe(false): return (.notGranted, [.schedule(.trustPoll, Constants.trustPoll)])
    case .probe(true):
      return (.granted, [.cancel(.trustPoll), .dismissOnboarding, .startTap] + grantedEntry)
    default: return (.notGranted, [])
    }
  }

  private static func granted(_ e: PermissionEvent, config: PermissionConfig) -> (PermissionState, [PermissionEffect]) {
    switch e {
    case .timer(.healthTick): return (.granted, rearm(.healthTick, Constants.healthTick))
    default: return (.granted, [])
    }
  }
}
