import CoreGraphics
import Foundation
import ZonesCore

public enum TopologyEvent: Hashable, Sendable {
  case raw(RawDisplayChange), snapshot(TopologySnapshot, nilUUIDs: Int), timer(TimerID)
  case assignmentPicked(DisplayKey, LayoutID)
}

public enum TopologyEffect: Hashable, Sendable {
  case schedule(TimerID, TimeInterval), cancel(TimerID), readSnapshot, topologyChanged(TopologySnapshot)
  case resizePanels(TopologySnapshot)
  case persistAssignment(PersistentDisplayKey, Assignment), sessionAssignment(DisplayKey, LayoutID)
  case notice(NoticeFlag)
}

public struct TopologyState: Hashable, Sendable {
  public var current: TopologySnapshot?
  public var previous: TopologySnapshot?
  public var uuidRetries: Int
  public var session: [DisplayKey: LayoutID]
  public var noticed: Set<NoticeFlag>
  /// Mirror member -> master, from the last commit.
  public var mirrorMaster: [DisplayKey: DisplayKey]

  public init(
    current: TopologySnapshot? = nil, previous: TopologySnapshot? = nil, uuidRetries: Int = 0,
    session: [DisplayKey: LayoutID] = [:], noticed: Set<NoticeFlag> = [],
    mirrorMaster: [DisplayKey: DisplayKey] = [:]
  ) {
    self.current = current
    self.previous = previous
    self.uuidRetries = uuidRetries
    self.session = session
    self.noticed = noticed
    self.mirrorMaster = mirrorMaster
  }
}

/// The display topology reducer (US-094...US-101). `now` is unused: all timing goes through `.schedule` effects.
public enum TopologyMonitor {
  public static let nilUUIDRetryLimit = 3
  public static let nilUUIDRetryInterval: TimeInterval = 1.0

  /// Displays whose UUID could not be read: `.unstable` keys the provider spelled `nil:<id>`.
  public static func nilUUIDCount(in snapshot: TopologySnapshot) -> Int {
    snapshot.displays.filter {
      if case .unstable(let text) = $0.key { text.hasPrefix("nil:") } else { false }
    }.count
  }

  public static func reduce(
    _ s: TopologyState, _ e: TopologyEvent, assignments: [String: Assignment], now: TimeInterval
  ) -> (TopologyState, [TopologyEffect]) {
    var state = s
    switch e {
    case .raw:
      state.uuidRetries = 0
      return (
        state,
        [.cancel(.nilUUIDRetry), .cancel(.topologyDebounce), .schedule(.topologyDebounce, Constants.topologyDebounce)]
      )
    case .timer(let id):
      switch id {
      case .topologyDebounce, .nilUUIDRetry: return (state, [.readSnapshot])
      default: return (state, [])
      }
    case .snapshot(let snapshot, _):
      return commit(snapshot, into: state, assignments: assignments)
    case .assignmentPicked(let key, let layout):
      return pick(layout, for: state.mirrorMaster[key] ?? key, in: state, assignments: assignments)
    }
  }

  private static func commit(
    _ snapshot: TopologySnapshot, into s: TopologyState, assignments: [String: Assignment]
  ) -> (TopologyState, [TopologyEffect]) {
    var state = s
    state.uuidRetries = 0
    let snapshot = collapseMirrors(snapshot, into: &state)
    guard snapshot != state.current else { return (state, []) }
    state.previous = state.current
    state.current = snapshot
    var effects: [TopologyEffect] = []
    if !snapshot.separateSpaces, state.noticed.insert(.separateSpacesOff).inserted {
      effects.append(.notice(.separateSpacesOff))
    }
    effects += persistEffects(for: snapshot, assignments: assignments) + [
      .topologyChanged(snapshot), .resizePanels(snapshot),
    ]
    return (state, effects)
  }

  /// A mirror group acts as its master: members are dropped and remembered as member -> master.
  private static func collapseMirrors(_ snapshot: TopologySnapshot, into state: inout TopologyState) -> TopologySnapshot {
    let present = Set(snapshot.displays.map(\.key))
    var collapsed = snapshot
    var masters: [DisplayKey: DisplayKey] = [:]
    collapsed.displays = snapshot.displays.filter { display in
      guard let master = display.mirrorOf, present.contains(master) else { return true }
      masters[display.key] = master
      return false
    }
    state.mirrorMaster = masters
    return collapsed
  }

  /// A UUID pick is persisted; an unstable key's pick lives for the session only.
  private static func pick(
    _ layout: LayoutID, for key: DisplayKey, in s: TopologyState, assignments: [String: Assignment]
  ) -> (TopologyState, [TopologyEffect]) {
    var state = s
    switch key {
    case .unstable:
      state.session[key] = layout
      return (state, [.sessionAssignment(key, layout)])
    case .uuid(let uuid):
      let existing = assignments[uuid]
      let display = state.current?.display(key)
      let record = Assignment(
        layout: layout, displayName: display?.name ?? existing?.displayName ?? "",
        lastVisibleFrame: display?.visibleFrame ?? existing?.lastVisibleFrame ?? .zero,
        lastScale: display?.scale ?? existing?.lastScale ?? 1, lastSeen: existing?.lastSeen)
      return (state, [.persistAssignment(PersistentDisplayKey(uuid: uuid), record)])
    }
  }

  /// A known UUID whose name, visible frame or scale drifted gets one write; layout and lastSeen are untouched.
  private static func persistEffects(
    for snapshot: TopologySnapshot, assignments: [String: Assignment]
  ) -> [TopologyEffect] {
    snapshot.displays.compactMap { display in
      guard case .uuid(let uuid) = display.key, var record = assignments[uuid] else { return nil }
      guard
        record.displayName != display.name || record.lastVisibleFrame != display.visibleFrame
          || record.lastScale != display.scale
      else { return nil }
      record.displayName = display.name
      record.lastVisibleFrame = display.visibleFrame
      record.lastScale = display.scale
      return .persistAssignment(PersistentDisplayKey(uuid: uuid), record)
    }
  }
}
