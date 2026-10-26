import Foundation
import ZonesCore

/// The pure Accessibility permission machine (T20, ADR-0021). No Clock, no actor, no AppKit: timers are
/// `schedule`/`cancel` effects that the driver turns into one-shot Clock timers. Every `schedule` of an id that may
/// already be pending is preceded by `cancel` of that id, so at most one timer per id exists.
public enum PermissionMachine {
  public static func reduce(
    _ s: PermissionState, _ e: PermissionEvent, config: PermissionConfig, now: TimeInterval
  ) -> (PermissionState, [PermissionEffect]) {
    let (next, effects): (PermissionState, [PermissionEffect])
    switch e {
    case .wake: (next, effects) = (s, [.revalidateTap, .probe, .forceTopologySnapshot, .orderPanelsOut])
    case .quit:
      (next, effects) = (
        s, [.cancel(.trustPoll), .cancel(.healthTick), .cancel(.suspectResolve), .cancel(.relaunchGate), .disableTap]
      )
    default: (next, effects) = step(s, e, config: config, now: now)
    }
    guard config.launchedAtLogin else { return (next, effects) }
    // Launched at login: no window effects. The badge and the "Grant Accessibility" item carry the message, so
    // arriving at (or re-confirming) notGranted emits them in place of the window (AC-012). A trust-poll timer
    // fire stays silent: the badge is already up.
    var kept = effects.filter { $0 != .showOnboarding && $0 != .dismissOnboarding }
    if next == .notGranted, s != .notGranted || e == .probe(false) {
      kept += [.badge(true), .grantMenuItem(true)]
    }
    return (next, kept)
  }

  /// Timer due times are `scheduledAt + delay`; subtracting `scheduledAt` again can land a hair under `delay`.
  private static let slack = 1e-9

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
    case .revoked(let failures, let firstFailure):
      return revoked(e, failures: failures, firstFailure: firstFailure, now: now)
    case .needsRelaunch: return needsRelaunch(e)
    }
  }

  private static var grantedEntry: [PermissionEffect] {
    [.badge(false), .grantMenuItem(false), .registerWindowHotkeys] + rearm(.healthTick, Constants.healthTick)
  }

  private static func notGranted(_ e: PermissionEvent) -> (PermissionState, [PermissionEffect]) {
    switch e {
    case .timer(.trustPoll): return (.notGranted, [.probe])
    case .probe(false): return (.notGranted, rearm(.trustPoll, Constants.trustPoll))
    case .probe(true):
      return (.granted, [.cancel(.trustPoll), .dismissOnboarding, .startTap] + grantedEntry)
    default: return (.notGranted, [])
    }
  }

  private static func granted(
    _ e: PermissionEvent, config: PermissionConfig, now: TimeInterval
  ) -> (PermissionState, [PermissionEffect]) {
    switch e {
    case .timer(.healthTick):
      // C12 (SPK-006): after revocation only the trust probe reads false, so every tick asks it. Its answer re-arms.
      return (.granted, [.probe])
    case .probe(true):
      // One heartbeat in flight at most: its result re-arms the tick, so here the tick is only cancelled.
      if config.heartbeatEnabled && config.reducerIdle { return (.granted, [.cancel(.healthTick), .heartbeat]) }
      return (.granted, rearm(.healthTick, Constants.healthTick))
    case .heartbeat(.apiDisabled), .apiDisabled, .tapNil, .probe(false):
      return (
        .suspect(since: now),
        [.cancel(.healthTick), .recreateTap] + rearm(.suspectResolve, Constants.suspectWindow)
      )
    case .heartbeat: return (.granted, rearm(.healthTick, Constants.healthTick))
    case .reonboard:
      // Re-run onboarding: the tap and every store stay as they are. The next true probe's `startTap` is idempotent.
      return (.notGranted, [.cancel(.healthTick), .showOnboarding] + rearm(.trustPoll, Constants.trustPoll))
    default: return (.granted, [])
    }
  }

  private static func suspect(
    _ e: PermissionEvent, since: TimeInterval, now: TimeInterval
  ) -> (PermissionState, [PermissionEffect]) {
    let stay = PermissionState.suspect(since: since)
    switch e {
    // C12 (SPK-006): after revocation the tap stays enabled and AX reads still succeed, so neither proves a grant.
    // Only the trust probe asked after `tapRecreated(true)` does; a false answer waits for the resolve timer.
    case .tapRecreated(true): return (stay, [.probe])
    case .probe(true): return (.granted, [.cancel(.suspectResolve)] + rearm(.healthTick, Constants.healthTick))
    case .timer(.suspectResolve) where now - since >= Constants.suspectWindow - slack:
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

  /// Leaving revoked or needsRelaunch for granted: the tap works again.
  private static var recovery: [PermissionEffect] {
    [.cancel(.relaunchGate), .cancel(.trustPoll), .dismissOnboarding] + grantedEntry
  }

  private static func revoked(
    _ e: PermissionEvent, failures: Int, firstFailure: TimeInterval?, now: TimeInterval
  ) -> (PermissionState, [PermissionEffect]) {
    let stay = PermissionState.revoked(failures: failures, firstFailure: firstFailure)
    let reset = PermissionState.revoked(failures: 0, firstFailure: nil)
    switch e {
    case .timer(.trustPoll): return (stay, [.probe])
    case .probe(false): return (reset, [.cancel(.relaunchGate)] + rearm(.trustPoll, Constants.trustPoll))
    case .probe(true): return (stay, [.recreateTap] + rearm(.trustPoll, Constants.trustPoll))
    case .tapRecreated(false):
      let first = firstFailure ?? now
      let next = PermissionState.revoked(failures: failures + 1, firstFailure: first)
      return (next, firstFailure == nil ? rearm(.relaunchGate, Constants.relaunchGateWindow) : [])
    case .timer(.relaunchGate):
      if failures >= Constants.relaunchGateFailures, let first = firstFailure,
        now - first >= Constants.relaunchGateWindow - slack
      {
        return (.needsRelaunch, [.offerRelaunch(true)])
      }
      return (reset, [])
    case .tapRecreated(true): return (.granted, recovery)
    case .reonboard: return (stay, [.showOnboarding])
    default: return (stay, [])
    }
  }

  private static func needsRelaunch(_ e: PermissionEvent) -> (PermissionState, [PermissionEffect]) {
    switch e {
    case .timer(.trustPoll): return (.needsRelaunch, [.probe])
    case .probe(true): return (.needsRelaunch, [.recreateTap] + rearm(.trustPoll, Constants.trustPoll))
    case .probe(false):
      return (
        .revoked(failures: 0, firstFailure: nil), [.offerRelaunch(false)] + rearm(.trustPoll, Constants.trustPoll)
      )
    case .tapRecreated(true): return (.granted, [.offerRelaunch(false)] + recovery)
    case .reonboard: return (.needsRelaunch, [.showOnboarding])
    default: return (.needsRelaunch, [])
    }
  }
}
