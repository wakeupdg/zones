import Foundation
import ZonesCore
import ZonesWindowing

/// Interprets `PermissionEffect` and `TapRecoveryEffect` (ADR-0021, ADR-0015 amendment C5). It owns the
/// `PermissionState`, the `TapRecovery` value and one pending timer per `TimerID`. Every effect is one call on an
/// adapter; the policy lives in the two reducers.
@MainActor
final class PermissionDriver {
  private(set) var state: PermissionState = .notGranted
  private(set) var tapRecovery = TapRecovery()
  /// SPK-006 verdict: the heartbeat read is off (it never sees apiDisabled). Each 5 s health tick asks the trust probe.
  var heartbeatEnabled = false
  /// Whether the Drag Session reducer is idle (the heartbeat never runs mid-drag).
  var dragIdle: @MainActor () -> Bool = { true }
  /// `registerWindowHotkeys` (true) and `unregisterWindowHotkeys` (false).
  var onWindowHotkeys: @MainActor (Bool) -> Void = { _ in }
  var onForceTopologySnapshot: @MainActor () -> Void = {}
  /// After each trust probe has reached the machine (T56: the onboarding help line rides this 1 s poll, AC-156).
  var onTrustPoll: @MainActor () -> Void = {}

  private let clock: any Clock
  private let input: any InputSource
  private let probe: any PermissionProbe
  private let worker: WindowWorker
  private let surfaces: any PermissionSurfaces
  private let overlay: any OverlayPresenter
  private let recovery: EnhancedUIRecovery
  private var timers: [TimerID: TimerHandle] = [:]
  private var queue: [PermissionEvent] = []
  private var draining = false
  private var inFlight: [Task<Void, Never>] = []

  init(
    clock: any Clock, input: any InputSource, probe: any PermissionProbe, worker: WindowWorker,
    surfaces: any PermissionSurfaces, overlay: any OverlayPresenter, recovery: EnhancedUIRecovery
  ) {
    self.clock = clock
    self.input = input
    self.probe = probe
    self.worker = worker
    self.surfaces = surfaces
    self.overlay = overlay
    self.recovery = recovery
  }

  var tap: TapState { tapRecovery.state }

  /// Queued, so an effect that raises another event cannot re-enter the reducer.
  func receive(_ event: PermissionEvent) {
    queue.append(event)
    guard !draining else { return }
    draining = true
    defer { draining = false }
    while !queue.isEmpty {
      let next = queue.removeFirst()
      let config = PermissionConfig(
        launchedAtLogin: probe.launchedAtLogin, heartbeatEnabled: heartbeatEnabled, reducerIdle: dragIdle())
      let (newState, effects) = PermissionMachine.reduce(state, next, config: config, now: clock.now)
      state = newState
      for effect in effects { interpret(effect) }
    }
  }

  /// One effect, one adapter call.
  func interpret(_ effect: PermissionEffect) {
    switch effect {
    case .schedule(let id, let seconds): schedule(id, after: seconds)
    case .cancel(let id): cancel(id)
    case .probe:
      receive(.probe(probe.isTrusted()))
      onTrustPoll()
    case .heartbeat: heartbeat()
    case .startTap: noteTap(input.start() == .started)
    case .revalidateTap: revalidateTap()
    case .recreateTap: recreateTap()
    case .dismissOnboarding: surfaces.dismissOnboarding()
    case .showOnboarding: surfaces.showOnboarding()
    case .badge(let on): surfaces.setBadge(on)
    case .grantMenuItem(let on): surfaces.setGrantMenuItem(on)
    case .offerRelaunch(let on): surfaces.offerRelaunch(on)
    case .registerWindowHotkeys: onWindowHotkeys(true)
    case .unregisterWindowHotkeys: onWindowHotkeys(false)
    case .drainEnhancedUI, .removeRecoveryRecord: recovery.drainAndDelete()
    case .forceTopologySnapshot: onForceTopologySnapshot()
    case .orderPanelsOut: overlay.orderOut()
    case .disableTap, .invalidateTap: input.stop()
    }
  }

  // MARK: Tap health

  /// A `TapSignal` from the adapter's stream.
  func signal(_ signal: TapSignal) {
    apply(tapRecovery.reduce(signal, timer: nil, now: clock.now))
  }

  func timerFired(_ id: TimerID) {
    timers[id] = nil
    switch id {
    case .deadTapRetry: apply(tapRecovery.reduce(nil, timer: .deadTapRetry, now: clock.now))
    default: receive(.timer(id))
    }
  }

  private func apply(_ effects: [TapRecoveryEffect]) {
    for effect in effects {
      switch effect {
      case .reenable:
        if !input.reenable() { recreateTap() }
      case .recreate: recreateTap()
      case .tapLost: receive(.tapNil)
      case .tapUnavailable:
        Log.shared.event(
          LogEvent(time: clock.now, category: .input, level: .error, message: "event tap unavailable"))
        receive(.tapNil)
      case .schedule(let id, let seconds): schedule(id, after: seconds)
      case .cancel(let id): cancel(id)
      }
    }
  }

  private func noteTap(_ started: Bool) {
    apply(tapRecovery.reduce(.recreated(started), timer: nil, now: clock.now))
  }

  private func recreateTap() {
    let started = input.recreate() == .started
    noteTap(started)
    receive(.tapRecreated(started))
  }

  func revalidateTap() {
    if !input.reenable() { recreateTap() }
  }

  /// A read tagged by the state it was issued in. A `trivialRead` no longer resolves `suspect`: only the trust
  /// probe after `tapRecreated(true)` does (C12, SPK-006).
  private func heartbeat() {
    let suspect: Bool
    if case .suspect = state { suspect = true } else { suspect = false }
    let worker = worker
    let task = Task { @MainActor [weak self] in
      let status = await worker.trivialRead()
      self?.receive(suspect ? .trivialRead(status) : .heartbeat(status))
    }
    inFlight.append(task)
  }

  // MARK: Timers

  private func schedule(_ id: TimerID, after seconds: TimeInterval) {
    cancel(id)
    timers[id] = clock.schedule(id, after: seconds, repeats: false) { [weak self] in
      Task { @MainActor in self?.timerFired(id) }
    }
  }

  private func cancel(_ id: TimerID) {
    if let handle = timers.removeValue(forKey: id) { clock.cancel(handle) }
  }

  /// Quit: no timer may fire after the tap is down.
  func cancelAllTimers() {
    for id in Array(timers.keys) { cancel(id) }
  }

  /// Waits for the reads still in flight (tests, and quit).
  func quiesce() async {
    let pending = inFlight
    inFlight = []
    for task in pending { await task.value }
  }
}
