import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing
import os

/// AC-156: with no Drag Session, tap recovery or Display reconfiguration in flight, exactly the permission-state
/// timers exist; the transient timers exist only while their trigger is pending.
///
/// One `FakeClock` drives all three machines. Every `schedule` effect becomes a clock timer that feeds the matching
/// machine its `.timer(id)`; every `cancel` cancels the handle. A `schedule` does NOT replace a pending timer of the
/// same id, so a reducer that forgot its `cancel` would show two timers of one id in `pending`.
private final class IdleRig: Sendable {
  private struct Inner {
    var permission: PermissionState = .notGranted
    var config = PermissionConfig(launchedAtLogin: false, heartbeatEnabled: false, reducerIdle: true)
    var tap = TapRecovery()
    var topology = TopologyState()
    var handles: [TimerID: TimerHandle] = [:]
    /// The answer to a `probe` effect.
    var trusted = false
    var snapshot = Fixtures.threeDisplays
    var nilUUIDsOnRead = 0
    var nilUUIDSchedules = 0
  }

  let clock = FakeClock()
  private let inner = OSAllocatedUnfairLock(initialState: Inner())

  var permission: PermissionState { inner.withLock { $0.permission } }
  var tap: TapRecovery { inner.withLock { $0.tap } }
  var topology: TopologyState { inner.withLock { $0.topology } }
  var nilUUIDSchedules: Int { inner.withLock { $0.nilUUIDSchedules } }
  var trusted: Bool {
    get { inner.withLock { $0.trusted } }
    set { inner.withLock { $0.trusted = newValue } }
  }
  var nilUUIDsOnRead: Int {
    get { inner.withLock { $0.nilUUIDsOnRead } }
    set { inner.withLock { $0.nilUUIDsOnRead = newValue } }
  }

  /// A rig whose permission machine has been through boot (`probe(false)`) and, when `trusted`, its first true poll.
  static func booted(granted: Bool) -> IdleRig {
    let rig = IdleRig()
    rig.send(.probe(false))
    if granted {
      rig.trusted = true
      rig.clock.advance(by: Constants.trustPoll)
    }
    return rig
  }

  func send(_ event: PermissionEvent) {
    let (state, config, now) = inner.withLock { ($0.permission, $0.config, clock.now) }
    let (next, effects) = PermissionMachine.reduce(state, event, config: config, now: now)
    inner.withLock { $0.permission = next }
    for effect in effects {
      switch effect {
      case .schedule(let id, let seconds): schedule(id, after: seconds)
      case .cancel(let id): cancel(id)
      case .probe: send(.probe(trusted))
      default: break
      }
    }
  }

  func signal(_ signal: TapSignal) {
    let now = clock.now
    run(inner.withLock { $0.tap.reduce(signal, timer: nil, now: now) })
  }

  func sendTopology(_ event: TopologyEvent) {
    let (state, now) = inner.withLock { ($0.topology, clock.now) }
    let (next, effects) = TopologyMonitor.reduce(state, event, assignments: [:], now: now)
    inner.withLock { $0.topology = next }
    for effect in effects {
      switch effect {
      case .schedule(let id, let seconds):
        if id == .nilUUIDRetry { inner.withLock { $0.nilUUIDSchedules += 1 } }
        schedule(id, after: seconds)
      case .cancel(let id): cancel(id)
      case .readSnapshot:
        let (snapshot, nils) = inner.withLock { ($0.snapshot, $0.nilUUIDsOnRead) }
        sendTopology(.snapshot(snapshot, nilUUIDs: nils))
      default: break
      }
    }
  }

  private func run(_ effects: [TapRecoveryEffect]) {
    for effect in effects {
      switch effect {
      case .schedule(let id, let seconds): schedule(id, after: seconds)
      case .cancel(let id): cancel(id)
      default: break
      }
    }
  }

  private func schedule(_ id: TimerID, after seconds: TimeInterval) {
    let handle = clock.schedule(id, after: seconds, repeats: false) { [self] in fire(id) }
    inner.withLock { $0.handles[id] = handle }
  }

  private func cancel(_ id: TimerID) {
    if let handle = inner.withLock({ $0.handles.removeValue(forKey: id) }) { clock.cancel(handle) }
  }

  /// A clock timer went off: hand it to the machine that owns the id.
  private func fire(_ id: TimerID) {
    switch id {
    case .trustPoll, .healthTick, .suspectResolve, .relaunchGate: send(.timer(id))
    case .deadTapRetry:
      let now = clock.now
      run(inner.withLock { $0.tap.reduce(nil, timer: id, now: now) })
    case .topologyDebounce, .nilUUIDRetry: sendTopology(.timer(id))
    case .frameSample, .unresponsiveCooldown: break
    }
  }

  /// The timers in firing order, as strings so a failure prints them.
  var pending: [String] { clock.pending.map(\.rawValue) }
}

@Suite struct IdleScheduleTests {
  private static func expectPending(_ rig: IdleRig, _ expected: [TimerID], _ note: String) {
    let actual = rig.clock.pending
    #expect(Set(actual).count == actual.count, "\(note): two timers share an id: \(actual)")
    #expect(actual.map(\.rawValue).sorted() == expected.map(\.rawValue).sorted(), "\(note): pending \(actual)")
  }

  // Slice 12 (AC-156)
  @Test func exactTimersPerState() {
    // notGranted: a 1 s trust poll and nothing else, however long it idles.
    let notGranted = IdleRig.booted(granted: false)
    #expect(notGranted.permission == .notGranted)
    Self.expectPending(notGranted, [.trustPoll], "notGranted")
    notGranted.clock.advance(by: 60)
    #expect(notGranted.permission == .notGranted)
    Self.expectPending(notGranted, [.trustPoll], "notGranted after 60 s")

    // granted: a 5 s health tick and no trust poll.
    let granted = IdleRig.booted(granted: true)
    #expect(granted.permission == .granted)
    Self.expectPending(granted, [.healthTick], "granted")
    granted.clock.advance(by: 60)
    #expect(granted.permission == .granted)
    Self.expectPending(granted, [.healthTick], "granted after 60 s")

    // suspect: its 3 s resolve timer, no trust poll, no health tick.
    granted.send(.apiDisabled)
    #expect({ if case .suspect = granted.permission { true } else { false } }())
    Self.expectPending(granted, [.suspectResolve], "suspect")
    granted.clock.advance(by: 2.9)
    Self.expectPending(granted, [.suspectResolve], "suspect after 2.9 s")

    // revoked: unrecovered, the resolve timer ends it and the 1 s trust poll takes over.
    granted.clock.advance(by: 0.1)
    #expect({ if case .revoked = granted.permission { true } else { false } }(), "state \(granted.permission)")
    Self.expectPending(granted, [.trustPoll], "revoked")

    // needsRelaunch: trusted again, three failed tap re-creations inside the 10 s gate.
    granted.clock.advance(by: 1)
    for _ in 0..<3 { granted.send(.tapRecreated(false)) }
    Self.expectPending(granted, [.trustPoll, .relaunchGate], "revoked with the relaunch gate open")
    granted.clock.advance(by: Constants.relaunchGateWindow)
    #expect(granted.permission == .needsRelaunch)
    Self.expectPending(granted, [.trustPoll], "needsRelaunch")
    granted.clock.advance(by: 60)
    #expect(granted.permission == .needsRelaunch)
    Self.expectPending(granted, [.trustPoll], "needsRelaunch after 60 s")
  }
}
