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

/// Facade: sinks are UnifiedLogSink (production) or ArrayLogSink (tests).
public final class Log: Sendable {
  struct State: Sendable {
    var sink: (any LogSink)?
    var ring: EventRing
  }

  private let state: OSAllocatedUnfairLock<State>

  public static let shared = Log()

  public init(capacity: Int = Constants.ringCapacity) {
    state = OSAllocatedUnfairLock(initialState: State(sink: nil, ring: EventRing(capacity: capacity)))
  }

  public func install(sink: any LogSink) {
    state.withLock { $0.sink = sink }
  }

  /// Appends to the ring and calls the sink once.
  public func event(_ e: LogEvent) {
    let sink = state.withLock { state -> (any LogSink)? in
      state.ring.append(e)
      return state.sink
    }
    sink?.write(e)
  }

  /// A copy of the current ring.
  public func ring() -> EventRing { state.withLock { $0.ring } }

  /// One event per skip (AC-155). The message never names a window or an owner (LI-003).
  public func skip(_ reason: SkipReason, _ ref: WindowRef?, category: LogCategory) {
    event(
      LogEvent(
        time: ProcessInfo.processInfo.systemUptime, category: category, level: .info,
        message: "skip " + reason.rawValue, bundleID: ref?.bundleID, pid: ref?.pid, skip: reason))
  }

  public static func skip(_ reason: SkipReason, _ ref: WindowRef?, category: LogCategory) {
    shared.skip(reason, ref, category: category)
  }
}
