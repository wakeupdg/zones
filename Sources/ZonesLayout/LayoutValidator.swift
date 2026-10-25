import ZonesCore

public enum LayoutValidator {
  /// The first fault of `l`, or nil. Precedence: `emptyName` (empty after trimming whitespace),
  /// `surroundOutOfRange` (any side outside 0...0.45 or NaN), `overlap` (two leaves share positive area),
  /// `ratioOutOfRange(path)` (first split in depth-first order with a ratio <= 0, >= 1 or NaN), `leafTooSmall(path)`
  /// (first leaf, depth-first, whose unit width or height is under `Constants.minFraction`). A tree whose ratios
  /// are all inside (0,1) tiles its rectangle and never overlaps; a ratio below 0 or above 1 (only a decoded file
  /// can carry one) pushes the first child past its parent and onto its sibling. A ratio of exactly 0 or 1 gives
  /// a zero-area leaf, which is `ratioOutOfRange`, not `overlap`.
  public static func validate(_ l: Layout) -> LayoutFault? {
    if l.name.allSatisfy(\.isWhitespace) { return .emptyName }
    let s = l.surround
    if [s.top, s.left, s.bottom, s.right].contains(where: { !($0 >= 0 && $0 <= Constants.surroundMax) }) {
      return .surroundOutOfRange
    }
    if overlaps(LayoutMath.unitRects(l.root).map(\.rect)) { return .overlap }
    if let path = firstBadRatio(l.root, steps: []) { return .ratioOutOfRange(path) }
    let tooSmall = LayoutMath.unitRects(l.root).first {
      $0.rect.width < Constants.minFraction - 1e-9 || $0.rect.height < Constants.minFraction - 1e-9
    }
    return tooSmall.map { .leafTooSmall($0.path) }
  }

  /// Tolerance for the shared area of two leaves: neighbours touch along an edge, and float noise is far smaller.
  private static let overlapTolerance = 1e-9

  /// True when any two leaf rectangles share positive area. Out-of-range ratios give negative extents, so each
  /// rectangle is normalised first; NaN extents never compare as overlapping.
  private static func overlaps(_ rects: [UnitRect]) -> Bool {
    let spans = rects.map { r in
      (x0: min(r.x, r.x + r.width), x1: max(r.x, r.x + r.width), y0: min(r.y, r.y + r.height),
        y1: max(r.y, r.y + r.height))
    }
    for i in spans.indices {
      for j in spans.indices where j > i {
        let w = min(spans[i].x1, spans[j].x1) - max(spans[i].x0, spans[j].x0)
        let h = min(spans[i].y1, spans[j].y1) - max(spans[i].y0, spans[j].y0)
        if w > overlapTolerance && h > overlapTolerance { return true }
      }
    }
    return false
  }

  private static func firstBadRatio(_ node: SplitNode, steps: [Bool]) -> NodePath? {
    guard case .split(_, let ratio, let first, let second) = node else { return nil }
    if !(ratio > 0 && ratio < 1) { return NodePath(steps: steps) }
    return firstBadRatio(first, steps: steps + [false]) ?? firstBadRatio(second, steps: steps + [true])
  }
}
