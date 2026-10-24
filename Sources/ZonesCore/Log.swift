import Foundation
import os

public enum LogCategory: String, Codable, CaseIterable, Sendable {
  case core, layout, windowing, input, permission, topology, snap, restore, shortcuts, overlay, diagnostics, app
}

public enum LogLevel: String, Codable, Sendable { case debug, info, notice, error }

/// Has NO title field, ever (AC-154).
public struct LogEvent: Hashable, Codable, Sendable {
  public var time: TimeInterval
  public var category: LogCategory
  public var level: LogLevel
  public var message: String
  public var bundleID: String?
  public var pid: Int32?
  public var skip: SkipReason?
  public init(
    time: TimeInterval, category: LogCategory, level: LogLevel, message: String, bundleID: String? = nil,
    pid: Int32? = nil, skip: SkipReason? = nil
  ) {
    self.time = time
    self.category = category
    self.level = level
    self.message = message
    self.bundleID = bundleID
    self.pid = pid
    self.skip = skip
  }
}

public protocol LogSink: Sendable { func write(_ event: LogEvent) }

/// Bounded recent-event buffer. `append` is added by the diagnostics ticket.
public struct EventRing: Sendable {
  public let capacity: Int
  public var events: [LogEvent]
  /// Grouped by bundle identifier.
  public var skipCounts: [String: [SkipReason: Int]]

  public init(capacity: Int = Constants.ringCapacity) {
    self.capacity = capacity
    self.events = []
    self.skipCounts = [:]
  }
}

/// Facade: sinks are UnifiedLogSink (production) or ArrayLogSink (tests). Methods are added by the diagnostics ticket.
public final class Log: Sendable {
  struct State: Sendable {
    var sink: (any LogSink)?
    var ring = EventRing()
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  public static let shared = Log()

  private init() {}
}
