import ZonesCore

public enum LayoutValidator {
  /// The first fault of `l`, or nil. Precedence: `emptyName` (empty after trimming whitespace),
  /// `surroundOutOfRange` (any side outside 0...0.45 or NaN), `ratioOutOfRange(path)` (first split in depth-first
  /// order with a ratio <= 0, >= 1 or NaN), `leafTooSmall(path)` (first leaf, depth-first, whose unit width or
  /// height is under `Constants.minFraction`). `overlap` is never produced: a split tree tiles its rectangle, so
  /// Zones cannot overlap.
  public static func validate(_ l: Layout) -> LayoutFault? {
    if l.name.allSatisfy(\.isWhitespace) { return .emptyName }
    let s = l.surround
    if [s.top, s.left, s.bottom, s.right].contains(where: { !($0 >= 0 && $0 <= Constants.surroundMax) }) {
      return .surroundOutOfRange
    }
    if let path = firstBadRatio(l.root, steps: []) { return .ratioOutOfRange(path) }
    let tooSmall = LayoutMath.unitRects(l.root).first {
      $0.rect.width < Constants.minFraction - 1e-9 || $0.rect.height < Constants.minFraction - 1e-9
    }
    return tooSmall.map { .leafTooSmall($0.path) }
  }

  private static func firstBadRatio(_ node: SplitNode, steps: [Bool]) -> NodePath? {
    guard case .split(_, let ratio, let first, let second) = node else { return nil }
    if !(ratio > 0 && ratio < 1) { return NodePath(steps: steps) }
    return firstBadRatio(first, steps: steps + [false]) ?? firstBadRatio(second, steps: steps + [true])
  }
}
