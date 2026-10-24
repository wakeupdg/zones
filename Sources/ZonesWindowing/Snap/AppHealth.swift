import Foundation
import ZonesCore

/// Unresponsive cooldown, Clock-driven (AC-077, ADR-0015 amendment C7). A plain value passed `inout`.
/// A pid marked at `t` is unresponsive while `now < t + Constants.unresponsiveCooldown`; after that
/// `consumeRetry` allows exactly one attempt, until the pid is marked again.
public struct AppHealth: Hashable, Sendable {
  /// Clock time at which each pid was last marked unresponsive.
  public var unresponsiveSince: [pid_t: TimeInterval]
  /// Pids whose one post-cooldown attempt has already been handed out.
  var retryConsumed: Set<pid_t>

  public init(unresponsiveSince: [pid_t: TimeInterval] = [:]) {
    self.unresponsiveSince = unresponsiveSince
    self.retryConsumed = []
  }

  public mutating func markUnresponsive(_ pid: pid_t, now: TimeInterval) {
    unresponsiveSince[pid] = now
    retryConsumed.remove(pid)
  }

  public func isUnresponsive(_ pid: pid_t, now: TimeInterval) -> Bool {
    guard let since = unresponsiveSince[pid] else { return false }
    return now < since + Constants.unresponsiveCooldown
  }

  /// True exactly once after the cooldown has ended; false before it, after it was used, and for
  /// a pid that was never marked.
  public mutating func consumeRetry(_ pid: pid_t, now: TimeInterval) -> Bool {
    guard unresponsiveSince[pid] != nil, !isUnresponsive(pid, now: now),
      !retryConsumed.contains(pid)
    else { return false }
    retryConsumed.insert(pid)
    return true
  }
}
