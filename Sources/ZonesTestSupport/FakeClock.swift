import Foundation
import ZonesCore
import os

/// A scriptable `Clock`. Time moves only through `advance(by:)`; timers fire in due-time order.
/// State lives under an unfair lock and callbacks run outside it.
public final class FakeClock: Clock, Sendable {
  private struct Timer {
    var id: TimerID
    var token: UInt64
    var due: TimeInterval
    var interval: TimeInterval?
    var action: @Sendable () -> Void
  }

  private struct State {
    var now: TimeInterval = 0
    var nextToken: UInt64 = 1
    var timers: [Timer] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  public init() {}

  public var now: TimeInterval { state.withLock { $0.now } }

  /// Timer ids in the order they will fire.
  public var pending: [TimerID] {
    state.withLock { s in s.timers.sorted(by: Self.fireOrder).map(\.id) }
  }

  public func schedule(
    _ id: TimerID, after seconds: TimeInterval, repeats: Bool, _ fire: @Sendable @escaping () -> Void
  ) -> TimerHandle {
    state.withLock { s in
      let token = s.nextToken
      s.nextToken += 1
      // A zero interval would never let `advance` finish.
      let delay = max(seconds, 1e-9)
      s.timers.append(
        Timer(id: id, token: token, due: s.now + delay, interval: repeats ? delay : nil, action: fire))
      return TimerHandle(id: id, token: token)
    }
  }

  public func cancel(_ handle: TimerHandle) {
    state.withLock { s in s.timers.removeAll { $0.token == handle.token } }
  }

  /// Moves time forward, firing every timer that falls due, earliest first. Repeating timers reschedule.
  public func advance(by seconds: TimeInterval) {
    let target = state.withLock { $0.now + max(seconds, 0) }
    while let action = takeNextDue(upTo: target) { action() }
    state.withLock { $0.now = target }
  }

  /// Fires the earliest pending timer with this id without moving time. A one-shot is removed.
  public func fire(_ id: TimerID) {
    let action: (@Sendable () -> Void)? = state.withLock { s in
      guard let index = s.timers.indices.filter({ s.timers[$0].id == id })
        .min(by: { Self.fireOrder(s.timers[$0], s.timers[$1]) })
      else { return nil }
      let timer = s.timers[index]
      if timer.interval == nil { s.timers.remove(at: index) }
      return timer.action
    }
    action?()
  }

  private func takeNextDue(upTo target: TimeInterval) -> (@Sendable () -> Void)? {
    state.withLock { s in
      guard let index = s.timers.indices.filter({ s.timers[$0].due <= target })
        .min(by: { Self.fireOrder(s.timers[$0], s.timers[$1]) })
      else { return nil }
      let timer = s.timers[index]
      s.now = max(s.now, timer.due)
      if let interval = timer.interval {
        s.timers[index].due = timer.due + interval
      } else {
        s.timers.remove(at: index)
      }
      return timer.action
    }
  }

  private static func fireOrder(_ a: Timer, _ b: Timer) -> Bool {
    a.due != b.due ? a.due < b.due : a.token < b.token
  }
}
