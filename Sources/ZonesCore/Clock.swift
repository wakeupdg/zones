import Foundation

public enum TimerID: String, Codable, Sendable {
  case trustPoll, healthTick, suspectResolve, relaunchGate, deadTapRetry, nilUUIDRetry, topologyDebounce,
    frameSample, unresponsiveCooldown
}

public struct TimerHandle: Hashable, Sendable {
  public let id: TimerID
  public let token: UInt64
  public init(id: TimerID, token: UInt64) {
    self.id = id
    self.token = token
  }
}

/// The time seam. Intentionally shadows Swift's `Clock` inside any file that imports ZonesCore.
public protocol Clock: Sendable {
  /// Monotonic seconds.
  var now: TimeInterval { get }
  func schedule(
    _ id: TimerID, after seconds: TimeInterval, repeats: Bool, _ fire: @Sendable @escaping () -> Void
  ) -> TimerHandle
  func cancel(_ handle: TimerHandle)
}
