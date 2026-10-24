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
}
