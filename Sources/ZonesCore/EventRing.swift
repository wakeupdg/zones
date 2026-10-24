import Foundation

/// Bounded recent-event buffer. `skipCounts` is cumulative: eviction never decrements it.
public struct EventRing: Sendable {
  public let capacity: Int
  public var events: [LogEvent]
  /// Grouped by bundle identifier; events without one count under "unknown".
  public var skipCounts: [String: [SkipReason: Int]]

  public init(capacity: Int = Constants.ringCapacity) {
    self.capacity = capacity
    self.events = []
    self.skipCounts = [:]
  }

  public mutating func append(_ e: LogEvent) {
    if let skip = e.skip { skipCounts[e.bundleID ?? "unknown", default: [:]][skip, default: 0] += 1 }
    guard capacity > 0 else { return }
    events.append(e)
    if events.count > capacity { events.removeFirst(events.count - capacity) }
  }
}
