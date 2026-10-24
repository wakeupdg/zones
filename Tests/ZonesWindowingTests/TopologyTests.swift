import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing
import os

/// Timers the harness's clock fires, waiting to be turned into `.timer` events.
private final class TimerInbox: Sendable {
  private let ids = OSAllocatedUnfairLock<[TimerID]>(initialState: [])
  func push(_ id: TimerID) { ids.withLock { $0.append(id) } }
  func drain() -> [TimerID] { ids.withLock { held in defer { held = [] }; return held } }
}

/// FakeClock + FakeDisplayProvider driving `TopologyMonitor.reduce`: interprets `.schedule`, `.cancel` and
/// `.readSnapshot`, records every effect.
private struct Harness {
  var state = TopologyState()
  var assignments: [String: Assignment] = [:]
  var effects: [TopologyEffect] = []
  var readTimes: [TimeInterval] = []
  let clock = FakeClock()
  let provider: FakeDisplayProvider
  private let inbox = TimerInbox()
  private var handles: [TimerID: TimerHandle] = [:]

  init(seed: TopologyState = TopologyState(), assignments: [String: Assignment] = [:]) {
    state = seed
    self.assignments = assignments
    provider = FakeDisplayProvider(clock: clock)
  }

  mutating func send(_ event: TopologyEvent) {
    let (next, out) = TopologyMonitor.reduce(state, event, assignments: assignments, now: clock.now)
    state = next
    effects += out
    for effect in out { interpret(effect) }
  }

  private mutating func interpret(_ effect: TopologyEffect) {
    switch effect {
    case .schedule(let id, let seconds):
      if let old = handles[id] { clock.cancel(old) }
      let inbox = inbox
      handles[id] = clock.schedule(id, after: seconds, repeats: false) { inbox.push(id) }
    case .cancel(let id):
      if let old = handles.removeValue(forKey: id) { clock.cancel(old) }
    case .readSnapshot:
      readTimes.append(clock.now)
      let snapshot = provider.snapshot()
      send(.snapshot(snapshot, nilUUIDs: TopologyMonitor.nilUUIDCount(in: snapshot)))
    default: break
    }
  }

  /// Moves the clock, then delivers every timer that fired.
  mutating func advance(by seconds: TimeInterval) {
    clock.advance(by: seconds)
    while case let fired = inbox.drain(), !fired.isEmpty {
      for id in fired {
        handles[id] = nil
        send(.timer(id))
      }
    }
  }

  var reads: Int { effects.filter { $0 == .readSnapshot }.count }
  var changes: [TopologySnapshot] {
    effects.compactMap { if case .topologyChanged(let t) = $0 { t } else { nil } }
  }
  var resizes: [TopologySnapshot] {
    effects.compactMap { if case .resizePanels(let t) = $0 { t } else { nil } }
  }
}

@Suite struct TopologyTests {
  static let a = Fixtures.threeDisplays.displays[0]
  static let b = Fixtures.threeDisplays.displays[1]
  static let c = Fixtures.threeDisplays.displays[2]

  static func topology(_ displays: [DisplaySnapshot], separateSpaces: Bool = true) -> TopologySnapshot {
    TopologySnapshot(
      displays: displays, separateSpaces: separateSpaces, primaryFrame: displays.first?.frame ?? .zero)
  }

  /// AC-124: a storm of callbacks becomes one read and one commit, 200 ms after the last.
  @Test func stormCoalescesAndResizes() throws {
    var h = Harness()
    h.provider.enqueue(.snapshot(Self.topology([Self.a])))
    for _ in 0..<5 {
      h.send(.raw(.reconfiguration))
      h.advance(by: 0.03)
    }
    h.advance(by: 0.19 - 0.03)
    #expect(h.reads == 0)
    h.advance(by: 0.05)
    #expect(h.reads == 1)
    #expect(h.changes.count == 1)
    #expect(h.resizes.count == 1)

    // Part 2: the same UUID at a new resolution commits a resize; zones follow the fractions.
    var moved = Self.a
    moved.frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    moved.visibleFrame = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    moved.scale = 2
    moved.resolution = CGSize(width: 5120, height: 2880)
    let second = Self.topology([moved])
    h.provider.enqueue(.snapshot(second))
    h.send(.raw(.screenParameters))
    h.advance(by: 0.2)
    #expect(h.reads == 2)
    #expect(h.changes == [Self.topology([Self.a]), second])
    #expect(h.resizes == [Self.topology([Self.a]), second])
    let newDisplay = try #require(h.resizes.last?.displays.first)
    #expect(h.resizes.last?.displays.map(\.frame) == [moved.frame])

    let before = LayoutMath.resolve(Fixtures.nineZone, display: Self.a)
    let after = LayoutMath.resolve(Fixtures.nineZone, display: newDisplay)
    #expect(after.zones.count == 9)
    #expect(after.visibleFrame == moved.visibleFrame)
    #expect(after.zones.map(\.frame) != before.zones.map(\.frame))
    // 3 x 3 thirds of the visible frame inset by the 8 pt Margin: zone 1 starts at the Margin, top-left.
    let zone1 = try #require(after.zones.first { $0.number == 1 }).frame
    #expect(zone1.minX == moved.visibleFrame.minX + 8)
    #expect(zone1.maxY == moved.visibleFrame.maxY - 8)
    let zone9 = try #require(after.zones.first { $0.number == 9 }).frame
    #expect(zone9.maxX == moved.visibleFrame.maxX - 8)
    #expect(zone9.minY == moved.visibleFrame.minY + 8)

    // An identical snapshot returns no effects.
    let (_, quiet) = TopologyMonitor.reduce(h.state, .snapshot(second, nilUUIDs: 0), assignments: [:], now: 0)
    #expect(quiet.isEmpty)
  }
}
