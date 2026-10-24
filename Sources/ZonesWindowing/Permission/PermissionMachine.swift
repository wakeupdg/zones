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
    case .granted: return granted(e, config: config, now: now)
    case .suspect(let since): return suspect(e, since: since, now: now)
    case .revoked, .needsRelaunch: return (s, [])
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

  private static func granted(
    _ e: PermissionEvent, config: PermissionConfig, now: TimeInterval
  ) -> (PermissionState, [PermissionEffect]) {
    switch e {
    case .timer(.healthTick): return (.granted, rearm(.healthTick, Constants.healthTick))
    case .apiDisabled, .tapNil, .heartbeat(.apiDisabled), .probe(false):
      return (
        .suspect(since: now),
        [.cancel(.healthTick), .recreateTap] + rearm(.suspectResolve, Constants.suspectWindow)
      )
    default: return (.granted, [])
    }
  }

  private static func suspect(
    _ e: PermissionEvent, since: TimeInterval, now: TimeInterval
  ) -> (PermissionState, [PermissionEffect]) {
    let stay = PermissionState.suspect(since: since)
    switch e {
    case .tapRecreated(true): return (stay, [.heartbeat])
    case .trivialRead(.ok), .heartbeat(.ok):
      return (.granted, [.cancel(.suspectResolve)] + rearm(.healthTick, Constants.healthTick))
    case .timer(.suspectResolve) where now - since >= Constants.suspectWindow:
      return (
        .revoked(failures: 0, firstFailure: nil),
        [
          .cancel(.healthTick), .badge(true), .grantMenuItem(true), .showOnboarding, .unregisterWindowHotkeys,
          .drainEnhancedUI,
        ] + rearm(.trustPoll, Constants.trustPoll)
      )
    default: return (stay, [])
    }
  }
}
