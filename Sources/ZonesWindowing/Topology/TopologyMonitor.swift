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
    case .assignmentPicked:
      return (state, [])
    }
  }

  private static func commit(
    _ snapshot: TopologySnapshot, into s: TopologyState, assignments: [String: Assignment]
  ) -> (TopologyState, [TopologyEffect]) {
    var state = s
    state.uuidRetries = 0
    guard snapshot != state.current else { return (state, []) }
    state.previous = state.current
    state.current = snapshot
    let effects = persistEffects(for: snapshot, assignments: assignments) + [
      .topologyChanged(snapshot), .resizePanels(snapshot),
    ]
    return (state, effects)
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
