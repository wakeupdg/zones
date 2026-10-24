import CoreGraphics
import Foundation
import ZonesCore

public enum CycleDirection: Sendable { case left, right }

/// Pure: where a cycle press goes next (ADR-0010, AC-100).
public enum CycleResolver {
  /// Right continues after the highest member of a Span (else after `base`), Left before the lowest; both wrap
  /// into `1...count`. No base: Right starts at 1, Left at the last Zone. `count >= 1`.
  public static func next(from base: Int?, direction: CycleDirection, count: Int, span: Set<Int>?) -> Int {
    let count = max(count, 1)
    let anchor: Int?
    if let span, span.count >= 2 {
      anchor = direction == .right ? span.max() : span.min()
    } else {
      anchor = base
    }
    guard let anchor else { return direction == .right ? 1 : count }
    switch direction {
    case .right: return (anchor % count + count) % count + 1
    case .left: return ((anchor - 2) % count + count) % count + 1
    }
  }
}
