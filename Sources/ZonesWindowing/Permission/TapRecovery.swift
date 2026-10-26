import Foundation
import ZonesCore

public enum TapRecoveryEffect: Hashable, Sendable {
  case reenable, recreate, tapLost, tapUnavailable
  case schedule(TimerID, TimeInterval), cancel(TimerID)
}

/// Pure tap-health state machine. A disabled tap is re-enabled at most `Constants.reenableLimit` times per
/// `Constants.reenableWindow` seconds (AC-011); the next disable declares the tap lost and schedules a recreate
/// retry. The driver feeds it `TapSignal`s and the `deadTapRetry` timer and carries out the effects.
public struct TapRecovery: Hashable, Sendable {
  public var state: TapState
  /// Times of the re-enables still inside the window.
  public var reenables: [TimeInterval]

  public init(state: TapState = .alive, reenables: [TimeInterval] = []) {
    self.state = state
    self.reenables = reenables
  }

  public mutating func reduce(_ signal: TapSignal?, timer: TimerID?, now: TimeInterval)
    -> [TapRecoveryEffect]
  {
    if let signal { return reduce(signal, now: now) }
    if timer == .deadTapRetry, state == .dead { return [.recreate] }
    return []
  }

  private mutating func reduce(_ signal: TapSignal, now: TimeInterval) -> [TapRecoveryEffect] {
    switch signal {
    case .disabledByTimeout, .disabledByUserInput:
      // Only a live tap can be disabled; a dead or unavailable one has nothing to re-enable.
      guard state == .alive else { return [] }
      reenables.removeAll { now - $0 >= Constants.reenableWindow }
      if reenables.count < Constants.reenableLimit {
        reenables.append(now)
        return [.reenable]
      }
      state = .dead
      return [.tapLost, .schedule(.deadTapRetry, Constants.deadTapRetry)]
    case .recreated(true):
      let wasDead = state == .dead
      state = .alive
      reenables = []
      return wasDead ? [.cancel(.deadTapRetry)] : []
    case .recreated(false):
      switch state {
      case .alive:
        state = .unavailable
        return [.tapUnavailable]
      case .dead:
        return [.schedule(.deadTapRetry, Constants.deadTapRetry)]
      case .unavailable:
        return []
      }
    }
  }
}
