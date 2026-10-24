import CoreGraphics
import Foundation
import ZonesCore

/// One tick of the batched frame read, classified against the mouse-down frames (ADR-0006, LOCKED-SPEC section 8).
/// Pure: the reducer decides what the classification means for the press.
struct CandidateTick: Equatable {
  /// A candidate whose origin left its mouse-down frame by more than `Constants.frameTolerance`.
  struct Mover: Equatable {
    var ref: WindowRef
    var downFrame: CGRect
    var facts: WindowFacts?
  }

  /// A candidate changed size: the gesture is a resize and ends the press (AC-048).
  var resized = false
  /// Movers in z-order.
  var movers: [Mover] = []
  /// Candidates whose read timed out this tick, in z-order.
  var timedOut: [WindowRef] = []
  /// Candidates not reported `.gone`, in z-order.
  var survivors: [WindowRef] = []

  static func classify(
    candidates: [WindowRef], downFrames: [WindowID: CGRect], results: [WindowID: SampleResult]
  ) -> CandidateTick {
    var tick = CandidateTick()
    for ref in candidates {
      switch results[ref.id] {
      case .gone?:
        continue
      case .timedOut?:
        tick.timedOut.append(ref)
      case .frame(let frame, let facts)?:
        if let was = downFrames[ref.id] {
          if abs(frame.width - was.width) > Constants.frameTolerance
            || abs(frame.height - was.height) > Constants.frameTolerance
          {
            tick.resized = true
          } else if abs(frame.origin.x - was.origin.x) > Constants.frameTolerance
            || abs(frame.origin.y - was.origin.y) > Constants.frameTolerance
          {
            tick.movers.append(Mover(ref: ref, downFrame: was, facts: facts))
          }
        }
      case nil:
        break
      }
      tick.survivors.append(ref)
    }
    return tick
  }
}
