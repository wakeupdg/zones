import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing
import os

/// Wraps FakeClock, FakePermissionProbe, a state and a config. `send` runs `reduce` and interprets the effects:
/// `schedule` and `cancel` drive the clock, `probe` answers from the fake probe, and `recreateTap`/`heartbeat`
/// are only logged for the test to answer by hand. Never touches the real AX API.
final class PermissionHarness: Sendable {
  private struct Inner {
    var state: PermissionState
    var config: PermissionConfig
    var handles: [TimerID: TimerHandle] = [:]
    var log: [PermissionEffect] = []
    var events: [PermissionEvent] = []
  }

  let clock = FakeClock()
  let probe: FakePermissionProbe
  private let inner: OSAllocatedUnfairLock<Inner>

  init(
    state: PermissionState = .notGranted, launchedAtLogin: Bool = false, heartbeatEnabled: Bool = false,
    reducerIdle: Bool = true
  ) {
    probe = FakePermissionProbe(clock: clock)
    inner = OSAllocatedUnfairLock(
      initialState: Inner(
        state: state,
        config: PermissionConfig(
          launchedAtLogin: launchedAtLogin, heartbeatEnabled: heartbeatEnabled, reducerIdle: reducerIdle)))
  }

  var state: PermissionState {
    get { inner.withLock { $0.state } }
    set { inner.withLock { $0.state = newValue } }
  }
  var config: PermissionConfig {
    get { inner.withLock { $0.config } }
    set { inner.withLock { $0.config = newValue } }
  }
  /// Every effect emitted so far, in order.
  var log: [PermissionEffect] { inner.withLock { $0.log } }
  /// Every event fed so far, in order (timer fires included).
  var events: [PermissionEvent] { inner.withLock { $0.events } }
  var probeCalls: Int { probe.calls.filter { $0 == .isTrusted }.count }

  /// What the driver does at boot or after a state is forced: arm a timer by hand.
  func arm(_ id: TimerID, after seconds: TimeInterval) { run([.schedule(id, seconds)]) }

  @discardableResult
  func send(_ event: PermissionEvent) -> [PermissionEffect] {
    let (s, c, now) = (state, config, clock.now)
    let (next, effects) = PermissionMachine.reduce(s, event, config: c, now: now)
    inner.withLock {
      $0.state = next
      $0.events.append(event)
      $0.log += effects
    }
    run(effects)
    return effects
  }

  func run(_ effects: [PermissionEffect]) {
    for effect in effects {
      switch effect {
      case .schedule(let id, let seconds):
        let handle = clock.schedule(id, after: seconds, repeats: false) { [self] in send(.timer(id)) }
        inner.withLock { $0.handles[id] = handle }
      case .cancel(let id):
        if let handle = inner.withLock({ $0.handles.removeValue(forKey: id) }) { clock.cancel(handle) }
      case .probe:
        send(.probe(probe.isTrusted()))
      default: break
      }
    }
  }
}

@Suite struct PermissionMachineTests {
  // AC-006
  @Test func pollScheduleMatchesState() {
    // Probe false: exactly one trust poll, one probe per second.
    let h = PermissionHarness()
    h.arm(.trustPoll, after: Constants.trustPoll)
    #expect(h.clock.pending == [.trustPoll])
    for n in 1...3 {
      h.clock.advance(by: 1)
      #expect(h.probeCalls == n)
      #expect(h.clock.pending == [.trustPoll])
      #expect(h.state == .notGranted)
    }

    // First true probe: dismissOnboarding before startTap, trust poll gone, one health tick.
    h.probe.enqueue(.trusted(true))
    h.clock.advance(by: 1)
    #expect(h.state == .granted)
    let log = h.log
    let dismiss = log.firstIndex(of: .dismissOnboarding)
    let start = log.firstIndex(of: .startTap)
    #expect(dismiss != nil && start != nil)
    if let dismiss, let start { #expect(dismiss < start) }
    #expect(h.clock.pending == [.healthTick])

    // Granted: one health tick every 5 s, no trust poll, no further probes.
    let probesBefore = h.probeCalls
    for n in 1...3 {
      h.clock.advance(by: 5)
      #expect(h.clock.pending == [.healthTick])
      #expect(h.events.filter { $0 == .timer(.healthTick) }.count == n)
    }
    #expect(h.probeCalls == probesBefore)
    #expect(h.events.filter { $0 == .timer(.trustPoll) }.count == 4)
  }

  // AC-007
  @Test func suspectResolvesToGrantedOrRevoked() {
    let suspectEntry: [PermissionEffect] = [
      .cancel(.healthTick), .recreateTap, .cancel(.suspectResolve), .schedule(.suspectResolve, 3),
    ]
    for signal in [PermissionEvent.apiDisabled, .tapNil, .heartbeat(.apiDisabled), .probe(false)] {
      let h = PermissionHarness(state: .granted)
      h.arm(.healthTick, after: Constants.healthTick)
      h.clock.advance(by: 7)  // one health tick, then idle in granted
      let at = h.clock.now
      #expect(h.send(signal) == suspectEntry, "\(signal)")
      #expect(h.state == .suspect(since: at))
      #expect(h.clock.pending == [.suspectResolve])
      // Repeat signals, a failed recreation and an unrelated read change nothing.
      for noise in [PermissionEvent.apiDisabled, .tapNil, .tapRecreated(false), .trivialRead(.timedOut), .reonboard] {
        #expect(h.send(noise).isEmpty, "\(noise)")
        #expect(h.state == .suspect(since: at))
      }
    }

    // Path A: recreation succeeds, one trivial read comes back ok -> granted with one health tick.
    let a = PermissionHarness(state: .granted)
    a.send(.tapNil)
    #expect(a.send(.tapRecreated(true)) == [.heartbeat])
    #expect(a.state == .suspect(since: 0))
    #expect(a.send(.trivialRead(.ok)) == [.cancel(.suspectResolve), .cancel(.healthTick), .schedule(.healthTick, 5)])
    #expect(a.state == .granted)
    #expect(a.clock.pending == [.healthTick])

    // Path B: recreation fails; the timer at +2.9 s is ignored, at +3 s the state is revoked.
    let b = PermissionHarness(state: .granted)
    b.send(.apiDisabled)
    b.send(.tapRecreated(false))
    b.clock.advance(by: 2.9)
    #expect(b.send(.timer(.suspectResolve)).isEmpty)
    #expect(b.state == .suspect(since: 0))
    b.clock.advance(by: 0.2)  // the real timer fires at exactly 3.0
    #expect(b.state == .revoked(failures: 0, firstFailure: nil))
    #expect(
      b.log.suffix(8) == [
        .cancel(.healthTick), .badge(true), .grantMenuItem(true), .showOnboarding, .unregisterWindowHotkeys,
        .drainEnhancedUI, .cancel(.trustPoll), .schedule(.trustPoll, 1),
      ])
    #expect(b.clock.pending == [.trustPoll])
  }

  private static let recovery: [PermissionEffect] = [
    .cancel(.relaunchGate), .cancel(.trustPoll), .dismissOnboarding, .badge(false), .grantMenuItem(false),
    .registerWindowHotkeys, .cancel(.healthTick), .schedule(.healthTick, 5),
  ]

  // AC-008
  @Test func relaunchOnlyAfterGateWithProbeTrue() {
    // Probe true: three failed recreations at t=0, 1, 2; the gate opens at t=10 and not before.
    let h = PermissionHarness(state: .revoked(failures: 0, firstFailure: nil))
    h.probe.enqueue(.trusted(true))
    h.send(.probe(true))
    #expect(h.log.contains(.recreateTap))
    #expect(h.send(.tapRecreated(false)) == [.cancel(.relaunchGate), .schedule(.relaunchGate, 10)])
    #expect(h.state == .revoked(failures: 1, firstFailure: 0))
    h.clock.advance(by: 1)
    #expect(h.send(.tapRecreated(false)).isEmpty)
    h.clock.advance(by: 1)
    #expect(h.send(.tapRecreated(false)).isEmpty)
    #expect(h.state == .revoked(failures: 3, firstFailure: 0))
    for _ in 3...9 {
      h.clock.advance(by: 1)
      #expect(!h.log.contains(.offerRelaunch(true)))
      #expect(h.state == .revoked(failures: 3, firstFailure: 0))
    }
    h.clock.advance(by: 1)  // t = 10: the gate timer fires
    #expect(h.state == .needsRelaunch)
    #expect(h.log.filter { $0 == .offerRelaunch(true) }.count == 1)

    // Fewer than three failures at the gate: nothing is offered and the count starts over.
    let few = PermissionHarness(state: .revoked(failures: 0, firstFailure: nil))
    few.send(.tapRecreated(false))
    few.send(.tapRecreated(false))
    few.clock.advance(by: 10)
    #expect(few.state == .revoked(failures: 0, firstFailure: nil))
    #expect(!few.log.contains(.offerRelaunch(true)))

    // Probe false: 100 poll cycles over 100 s stay revoked, never recreate, never offer the button.
    let off = PermissionHarness(state: .revoked(failures: 0, firstFailure: nil))
    off.probe.enqueue(.trusted(false))
    off.arm(.trustPoll, after: Constants.trustPoll)
    for _ in 1...100 {
      off.clock.advance(by: 1)
      #expect(off.state == .revoked(failures: 0, firstFailure: nil))
      #expect(off.clock.pending == [.trustPoll])
    }
    #expect(off.probeCalls == 100)
    #expect(!off.log.contains(.offerRelaunch(true)) && !off.log.contains(.recreateTap))

    // A probe false in the middle of a gate run drops it.
    let mid = PermissionHarness(state: .revoked(failures: 0, firstFailure: nil))
    mid.send(.tapRecreated(false))
    mid.send(.tapRecreated(false))
    #expect(mid.send(.probe(false)) == [.cancel(.relaunchGate), .schedule(.trustPoll, 1)])
    #expect(mid.state == .revoked(failures: 0, firstFailure: nil))
    #expect(mid.clock.pending == [.trustPoll])

    // A successful recreation from revoked or from needsRelaunch returns to granted.
    let fromRevoked = PermissionHarness(state: .revoked(failures: 2, firstFailure: 0))
    fromRevoked.arm(.trustPoll, after: 1)
    #expect(fromRevoked.send(.tapRecreated(true)) == Self.recovery)
    #expect(fromRevoked.state == .granted)
    #expect(fromRevoked.clock.pending == [.healthTick])
    let fromRelaunch = PermissionHarness(state: .needsRelaunch)
    fromRelaunch.arm(.trustPoll, after: 1)
    #expect(fromRelaunch.send(.tapRecreated(true)) == [.offerRelaunch(false)] + Self.recovery)
    #expect(fromRelaunch.state == .granted)
    #expect(fromRelaunch.clock.pending == [.healthTick])

    // needsRelaunch keeps polling; probe true retries the tap, probe false drops back to revoked.
    let rl = PermissionHarness(state: .needsRelaunch)
    rl.probe.enqueue(.trusted(true))
    #expect(rl.send(.timer(.trustPoll)) == [.probe])
    #expect(rl.state == .needsRelaunch)
    #expect(rl.send(.probe(true)) == [.recreateTap, .schedule(.trustPoll, 1)])
    #expect(rl.state == .needsRelaunch)
    #expect(rl.send(.tapRecreated(false)).isEmpty)
    #expect(rl.send(.probe(false)) == [.offerRelaunch(false), .schedule(.trustPoll, 1)])
    #expect(rl.state == .revoked(failures: 0, firstFailure: nil))

    Self.offerRelaunchOnlyOnEntryAndNeverAfterProbeFalse()
  }

  /// A causal driver model for the random walk: a `tapRecreated` answers an outstanding `recreateTap` (a probe false
  /// drops the outstanding ones) and a `timer` event is one that the machine armed and has not seen fire or cancel.
  private static func offerRelaunchOnlyOnEntryAndNeverAfterProbeFalse() {
    let trials: [UInt64] = [1, 2, 3, 7, 42, 99, 2026, 12345]
    var entries = 0
    for seed in trials {
      var g = Generator(seed: seed)
      var state = PermissionState.notGranted
      var now = 0.0
      var timers: [TimerID] = [.trustPoll]
      var outstanding = 0
      var lastProbe: Bool?
      let config = PermissionConfig(launchedAtLogin: false, heartbeatEnabled: true, reducerIdle: true)
      for step in 0..<200 {
        now += g.double(0...4)
        let event = randomEvent(&g, state: state, timers: timers, outstanding: outstanding)
        if case .probe(let p) = event { lastProbe = p }
        let (next, fx) = PermissionMachine.reduce(state, event, config: config, now: now)
        let note = Comment(rawValue: "seed \(seed) step \(step) \(state) --\(event)--> \(next) \(fx)")
        if fx.contains(.offerRelaunch(true)) {
          #expect(state != .needsRelaunch && next == .needsRelaunch, note)
          #expect(lastProbe != false, note)
        }
        if state != .needsRelaunch, next == .needsRelaunch {
          entries += 1
          #expect(fx.contains(.offerRelaunch(true)), note)
        }
        if fx.contains(.offerRelaunch(false)) { #expect(state == .needsRelaunch, note) }
        if case .timer(let id) = event, let at = timers.firstIndex(of: id) { timers.remove(at: at) }
        for effect in fx {
          switch effect {
          case .cancel(let id): timers.removeAll { $0 == id }
          case .schedule(let id, _): timers.append(id)
          case .recreateTap: outstanding += 1
          default: break
          }
        }
        if case .tapRecreated = event { outstanding -= 1 }
        if event == .probe(false) { outstanding = 0 }
        state = next
      }
    }
    #expect(entries > 0, "the walk never reached needsRelaunch, so the property proved nothing")
  }

  private static func randomEvent(
    _ g: inout Generator, state: PermissionState, timers: [TimerID], outstanding: Int
  ) -> PermissionEvent {
    // Most of the time in revoked, push on the relaunch gate so the walk reaches needsRelaunch.
    if case .revoked = state, g.int(0...9) < 7 {
      var steer: [PermissionEvent] = [.probe(true), .probe(true), .probe(true), .probe(false)]
      if outstanding > 0 { steer += [.tapRecreated(false), .tapRecreated(false), .tapRecreated(false), .tapRecreated(true)] }
      return g.pick(steer + timers.map { .timer($0) })
    }
    let statuses: [AXStatus] = [.ok, .timedOut, .elementGone, .apiDisabled, .refused(-25200)]
    var pool: [PermissionEvent] = [
      .probe(true), .probe(true), .probe(false), .apiDisabled, .tapNil, .trivialRead(g.pick(statuses)),
      .heartbeat(g.pick(statuses)), .wake, .reonboard, .quit,
    ]
    if outstanding > 0 { pool += [.tapRecreated(false), .tapRecreated(false), .tapRecreated(true)] }
    pool += timers.map { .timer($0) } + timers.map { .timer($0) }
    return g.pick(pool)
  }

  // AC-021
  @Test func reonboardLeavesStoresUntouched() throws {
    let fs = FakeFileSystem()
    let store = DocumentStore(fs: fs, directory: URL(fileURLWithPath: "/virtual/Zones"), clock: FakeClock())
    try store.save(ZonesDocument(), as: .layouts)
    try store.save(ZonesDocument(), as: .assignments)
    _ = store.load(.layouts)
    let calls = fs.calls
    let files = fs.files
    #expect(!calls.isEmpty)

    let h = PermissionHarness(state: .granted)
    h.arm(.healthTick, after: Constants.healthTick)
    let effects = h.send(.reonboard)
    #expect(h.state == .notGranted)
    #expect(effects == [.cancel(.healthTick), .showOnboarding, .cancel(.trustPoll), .schedule(.trustPoll, 1)])
    #expect(!effects.contains(.invalidateTap) && !effects.contains(.removeRecoveryRecord))
    #expect(!effects.contains(.disableTap))
    #expect(h.clock.pending == [.trustPoll])
    #expect(fs.calls == calls)
    #expect(fs.files == files)

    // The next true probe is the ordinary first grant again.
    h.probe.enqueue(.trusted(true))
    h.clock.advance(by: 1)
    #expect(h.state == .granted)
  }

  static let everyState: [PermissionState] = [
    .notGranted, .granted, .suspect(since: 4), .revoked(failures: 0, firstFailure: nil),
    .revoked(failures: 2, firstFailure: 1), .needsRelaunch,
  ]

  // AC-024, machine half
  @Test(arguments: everyState) func wakeEffects(state: PermissionState) {
    let (next, fx) = PermissionMachine.reduce(
      state, .wake, config: PermissionConfig(launchedAtLogin: false, heartbeatEnabled: true, reducerIdle: true),
      now: 9)
    #expect(next == state)
    #expect(fx == [.revalidateTap, .probe, .forceTopologySnapshot, .orderPanelsOut])
  }

  @Test(arguments: everyState) func quitCancelsTimersAndDisablesTap(state: PermissionState) {
    let (next, fx) = PermissionMachine.reduce(
      state, .quit, config: PermissionConfig(launchedAtLogin: false, heartbeatEnabled: true, reducerIdle: true),
      now: 9)
    #expect(next == state)
    #expect(fx == [.cancel(.trustPoll), .cancel(.healthTick), .cancel(.suspectResolve), .cancel(.relaunchGate), .disableTap])
  }
}
