import Foundation
import ZonesCore
import os

/// A `LogSink` that keeps events in a lock-guarded array. `enqueue(_:)` preloads an event without
/// logging a call, for tests that read events back.
public final class ArrayLogSink: LogSink, Sendable {
  public enum Call: Hashable, Sendable { case write(LogEvent) }

  private let stored = OSAllocatedUnfairLock(initialState: [LogEvent]())
  private let recorder: CallRecorder<Call>

  public init(clock: FakeClock = FakeClock()) { recorder = CallRecorder(clock: clock) }

  public var events: [LogEvent] { stored.withLock { $0 } }
  public func enqueue(_ event: LogEvent) { stored.withLock { $0.append(event) } }
  public var calls: [Call] { recorder.calls }
  /// Calls whose `latency` has elapsed on the clock.
  public var completed: [Call] { recorder.completed }
  public var inFlight: Int { recorder.inFlight }
  public var latency: TimeInterval {
    get { recorder.latency }
    set { recorder.latency = newValue }
  }

  public func write(_ event: LogEvent) {
    recorder.record(.write(event))
    stored.withLock { $0.append(event) }
  }

  public func reset() {
    stored.withLock { $0.removeAll() }
    recorder.reset()
  }
}
