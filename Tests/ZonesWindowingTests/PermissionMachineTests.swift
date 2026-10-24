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
}
