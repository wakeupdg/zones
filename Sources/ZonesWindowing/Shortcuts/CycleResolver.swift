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

  /// The last-Snap record, when it still describes the window: same Display, every Zone present in `layout`, and the
  /// read-back `frame` within `Constants.cycleTolerance` (inclusive) of the record's frame on all four of
  /// `minX`, `minY`, `width` and `height`. The record frame is the Snap read-back, so a clamped window still matches.
  public static func matchedRecord(_ last: LastSnapRecord?, frame: CGRect, layout: ResolvedLayout) -> LastSnapRecord? {
    guard let last, last.display == layout.display, !last.zones.isEmpty else { return nil }
    guard last.zones.allSatisfy({ (1...layout.zones.count).contains($0) }) else { return nil }
    let t = Constants.cycleTolerance
    guard abs(last.frame.minX - frame.minX) <= t, abs(last.frame.minY - frame.minY) <= t,
      abs(last.frame.width - frame.width) <= t, abs(last.frame.height - frame.height) <= t
    else { return nil }
    return last
  }

  /// A matched record gives its lowest Zone (a Span only needs to be a member, `next` picks the end from `span`).
  public static func base(_ last: LastSnapRecord?, frame: CGRect, layout: ResolvedLayout) -> Int? {
    if let matched = matchedRecord(last, frame: frame, layout: layout) { return matched.zones.min() }
    return nil
  }
}
