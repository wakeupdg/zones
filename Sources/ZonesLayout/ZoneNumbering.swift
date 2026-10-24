import ZonesCore

public enum ZoneNumbering {
  /// Row-major Zone Numbers 1...N (ADR-0004, AC-099), derived from unit rectangles and never stored.
  ///
  /// Rows are clustered first: walking the rectangles by ascending top edge, a rectangle joins the current row when
  /// its `y` is within `Constants.numberingEpsilon` of the row's FIRST `y` (comparing to the first, not the
  /// previous, keeps the grouping transitive). Inside a row the order is left edge, then the path steps
  /// (false before true) so the result is deterministic. Unit input means numbers cannot depend on Display size,
  /// scale, Margin or Gap.
  public static func numbers(_ rects: [(path: NodePath, rect: UnitRect)]) -> [NodePath: Int] {
    let byTop = rects.sorted { $0.rect.y < $1.rect.y }
    var rows: [[(path: NodePath, rect: UnitRect)]] = []
    var rowStart = 0.0
    for item in byTop {
      if !rows.isEmpty, item.rect.y - rowStart <= Constants.numberingEpsilon {
        rows[rows.count - 1].append(item)
      } else {
        rows.append([item])
        rowStart = item.rect.y
      }
    }
    var result: [NodePath: Int] = [:]
    var next = 1
    for row in rows {
      for item in row.sorted(by: { precedes($0, $1) }) {
        result[item.path] = next
        next += 1
      }
    }
    return result
  }

  private static func precedes(
    _ a: (path: NodePath, rect: UnitRect), _ b: (path: NodePath, rect: UnitRect)
  ) -> Bool {
    if a.rect.x != b.rect.x { return a.rect.x < b.rect.x }
    for (p, q) in zip(a.path.steps, b.path.steps) where p != q { return !p && q }
    return a.path.steps.count < b.path.steps.count
  }
}
