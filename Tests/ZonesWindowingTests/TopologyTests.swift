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

  static func uuid(_ d: DisplaySnapshot) -> String {
    guard case .uuid(let text) = d.key else { fatalError("not a uuid key") }
    return text
  }

  static func record(
    _ d: DisplaySnapshot, layout: String, lastSeen: Date? = nil, name: String? = nil
  ) -> Assignment {
    Assignment(
      layout: LayoutID(rawValue: layout), displayName: name ?? d.name, lastVisibleFrame: d.visibleFrame,
      lastScale: d.scale, lastSeen: lastSeen)
  }

  static func commit(
    _ state: TopologyState, _ t: TopologySnapshot, assignments: [String: Assignment] = [:]
  ) -> (TopologyState, [TopologyEffect]) {
    TopologyMonitor.reduce(state, .snapshot(t, nilUUIDs: TopologyMonitor.nilUUIDCount(in: t)), assignments: assignments, now: 0)
  }

  /// AC-118: a removed Display keeps its Assignment and emits no move; a returning UUID gets it back.
  @Test func assignmentsSurviveReconnect() {
    let records = [
      Self.uuid(Self.a): Self.record(Self.a, layout: "builtin:focus:1"),
      Self.uuid(Self.b): Self.record(Self.b, layout: "builtin:columns:2"),
    ]
    let both = Self.topology([Self.a, Self.b])
    var (state, _) = Self.commit(TopologyState(), both, assignments: records)

    let (afterRemove, removeEffects) = Self.commit(state, Self.topology([Self.a]), assignments: records)
    #expect(removeEffects == [.topologyChanged(Self.topology([Self.a])), .resizePanels(Self.topology([Self.a]))])
    for effect in removeEffects {
      switch effect {
      case .topologyChanged, .resizePanels: break
      default: Issue.record("unexpected effect \(effect)")
      }
    }
    #expect(
      AssignmentLookup.layoutID(for: Self.b.key, in: records, session: afterRemove.session)
        == LayoutID(rawValue: "builtin:columns:2"))
    state = afterRemove

    let (afterReturn, returnEffects) = Self.commit(state, both, assignments: records)
    #expect(returnEffects == [.topologyChanged(both), .resizePanels(both)])
    #expect(
      AssignmentLookup.layoutID(for: Self.b.key, in: records, session: afterReturn.session)
        == LayoutID(rawValue: "builtin:columns:2"))

    // A new UUID gets the default and no write.
    let withC = Self.topology([Self.a, Self.b, Self.c])
    let (afterNew, newEffects) = Self.commit(afterReturn, withC, assignments: records)
    #expect(AssignmentLookup.layoutID(for: Self.c.key, in: records, session: afterNew.session) == LayoutID(rawValue: "builtin:priorityGrid:3"))
    #expect(!newEffects.contains { if case .persistAssignment = $0 { true } else { false } })
  }

  @Test func persistsNameFrameScale() {
    let seen = Date(timeIntervalSince1970: 1_000)
    let known = Self.record(Self.a, layout: "builtin:focus:1", lastSeen: seen)
    let records = [Self.uuid(Self.a): known]
    let key = PersistentDisplayKey(uuid: Self.uuid(Self.a))

    // Unchanged Display, no persist (first commit includes the record already matching).
    let (state, first) = Self.commit(TopologyState(), Self.topology([Self.a]), assignments: records)
    #expect(!first.contains { if case .persistAssignment = $0 { true } else { false } })

    // Name, visible frame and scale changed: one persist with the new values and the old layout/lastSeen.
    var changed = Self.a
    changed.name = "Renamed"
    changed.visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1000)
    changed.scale = 2
    let (_, effects) = Self.commit(state, Self.topology([changed]), assignments: records)
    let expected = Assignment(
      layout: known.layout, displayName: "Renamed", lastVisibleFrame: changed.visibleFrame, lastScale: 2,
      lastSeen: seen)
    let persists = effects.filter { if case .persistAssignment = $0 { true } else { false } }
    #expect(persists == [.persistAssignment(key, expected)])

    // Persist comes before topologyChanged.
    #expect(effects == [.persistAssignment(key, expected), .topologyChanged(Self.topology([changed])), .resizePanels(Self.topology([changed]))])

    // No record: nothing. Unstable key: nothing.
    var unstable = Self.b
    unstable.key = .unstable("nil:7")
    let stray = Self.topology([changed, unstable])
    let (_, strayEffects) = Self.commit(state, stray, assignments: records.filter { _ in false })
    #expect(!strayEffects.contains { if case .persistAssignment = $0 { true } else { false } })
    let (_, unstableEffects) = Self.commit(state, Self.topology([Self.a, unstable]), assignments: records)
    #expect(!unstableEffects.contains { if case .persistAssignment = $0 { true } else { false } })
  }

  /// AC-121
  @Test func separateSpacesNoticeOnce() {
    let off = Self.topology([Self.a], separateSpaces: false)
    let (state, first) = Self.commit(TopologyState(), off)
    #expect(first.filter { $0 == .notice(.separateSpacesOff) }.count == 1)
    #expect(first.first == .notice(.separateSpacesOff))
    #expect(state.noticed == [.separateSpacesOff])

    var moved = Self.a
    moved.visibleFrame = CGRect(x: 0, y: 0, width: 1800, height: 1000)
    let (_, later) = Self.commit(state, Self.topology([moved], separateSpaces: false))
    #expect(!later.contains(.notice(.separateSpacesOff)))
    #expect(later.contains(.topologyChanged(Self.topology([moved], separateSpaces: false))))

    let seeded = TopologyState(noticed: [.separateSpacesOff])
    let (_, none) = Self.commit(seeded, off)
    #expect(!none.contains(.notice(.separateSpacesOff)))

    // Separate Spaces on: no notice.
    let (_, on) = Self.commit(TopologyState(), Self.topology([Self.a]))
    #expect(!on.contains(.notice(.separateSpacesOff)))
  }

  /// AC-122
  @Test func mirrorKeyedByMaster() {
    var mirrored = Self.b
    mirrored.mirrorOf = Self.a.key
    let bRecord = Self.record(Self.b, layout: "builtin:columns:2")
    var records = [Self.uuid(Self.b): bRecord]

    let (state, effects) = Self.commit(TopologyState(), Self.topology([Self.a, mirrored]), assignments: records)
    let collapsed = Self.topology([Self.a])
    #expect(effects.contains(.topologyChanged(collapsed)))
    #expect(state.current == collapsed)
    #expect(state.mirrorMaster == [Self.b.key: Self.a.key])

    let picked = LayoutID(rawValue: "builtin:focus:1")
    let keyA = PersistentDisplayKey(uuid: Self.uuid(Self.a))
    let expected = Assignment(
      layout: picked, displayName: Self.a.name, lastVisibleFrame: Self.a.visibleFrame, lastScale: Self.a.scale,
      lastSeen: nil)
    for target in [Self.a.key, Self.b.key] {
      let (next, out) = TopologyMonitor.reduce(
        state, .assignmentPicked(target, picked), assignments: records, now: 0)
      #expect(out == [.persistAssignment(keyA, expected)])
      #expect(next.session.isEmpty)
    }

    // The app writes the persisted record; then the Displays unmirror.
    records[keyA.uuid] = expected
    let (after, back) = Self.commit(state, Self.topology([Self.a, Self.b]), assignments: records)
    #expect(back.contains(.topologyChanged(Self.topology([Self.a, Self.b]))))
    #expect(after.mirrorMaster.isEmpty)
    #expect(AssignmentLookup.layoutID(for: Self.a.key, in: records, session: after.session) == picked)
    #expect(records[Self.uuid(Self.b)] == bRecord)
    #expect(
      AssignmentLookup.layoutID(for: Self.b.key, in: records, session: after.session) == bRecord.layout)

    // A mirrorOf naming an absent Display is left as is.
    var orphan = Self.b
    orphan.mirrorOf = Self.c.key
    let (kept, _) = Self.commit(TopologyState(), Self.topology([Self.a, orphan]))
    #expect(kept.current?.displays.count == 2)
    #expect(kept.mirrorMaster.isEmpty)
  }
}
