import Dispatch
import Foundation
import ZonesCore
import os

/// `Clock` over `DispatchSourceTimer`. `now` is monotonic seconds; every handle carries its own token, so a stale
/// `cancel` never touches a newer timer. `cancel` is idempotent. A callback runs on a private serial queue.
final class ProductionClock: Clock, Sendable {
  private struct State {
    var nextToken: UInt64 = 1
    var timers: [UInt64: DispatchSourceTimer] = [:]
  }

  private let state = OSAllocatedUnfairLock(uncheckedState: State())
  private let queue = DispatchQueue(label: "dev.zones.clock", qos: .userInitiated)

  var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  func schedule(
    _ id: TimerID, after seconds: TimeInterval, repeats: Bool, _ fire: @Sendable @escaping () -> Void
  ) -> TimerHandle {
    let delay = max(seconds, 0)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    let token = state.withLockUnchecked { s -> UInt64 in
      let token = s.nextToken
      s.nextToken += 1
      s.timers[token] = timer
      return token
    }
    if repeats {
      timer.schedule(deadline: .now() + delay, repeating: max(delay, 0.001), leeway: .milliseconds(1))
    } else {
      timer.schedule(deadline: .now() + delay, leeway: .milliseconds(1))
    }
    timer.setEventHandler { [weak self, weak timer] in
      guard let self, let timer, !timer.isCancelled else { return }
      // A one-shot leaves the table before it runs, so a `cancel` from inside the callback is a no-op.
      if !repeats { self.remove(token) }
      fire()
    }
    timer.resume()
    return TimerHandle(id: id, token: token)
  }

  func cancel(_ handle: TimerHandle) { remove(handle.token) }

  private func remove(_ token: UInt64) {
    let timer = state.withLockUnchecked { $0.timers.removeValue(forKey: token) }
    timer?.cancel()
  }
}
