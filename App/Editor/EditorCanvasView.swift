import AppKit
import ZonesCore
import ZonesLayout

/// Pure geometry for the editor canvas. The editor never recomputes layout math: every rectangle here is a
/// `ResolvedLayout` frame from `LayoutMath.resolve` (via `EditorState.preview`), only translated into view space.
enum EditorCanvasGeometry {
  struct ZoneRect: Hashable {
    var number: Int
    var path: NodePath
    var rect: CGRect
  }

  /// Each Zone's frame in view coordinates. `contentOrigin` is the screen position (AppKit coordinates, y up) of
  /// the view's bottom-left corner; subtracting it is the only change, so 1 view point is 1 screen point and the
  /// Zones stay on the same screen pixels when the window moves or resizes.
  static func zoneRects(preview: ResolvedLayout, contentOrigin: CGPoint) -> [ZoneRect] {
    preview.zones.map {
      ZoneRect(
        number: $0.number, path: $0.path, rect: $0.frame.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y))
    }
  }

  /// One draggable divider: the split node at `path`.
  struct Divider: Hashable {
    var path: NodePath
    var axis: SplitAxis
    /// The split node's whole region in view space (its unit rectangle inside the Layout rectangle).
    var parent: CGRect
    /// A thin rectangle centred on the divider, `hitThickness` wide, for hit-testing and drawing the handle.
    var line: CGRect
  }

  static let hitThickness: CGFloat = 12

  /// Every split node's divider in view space, outermost first.
  static func dividers(layout: Layout, preview: ResolvedLayout, contentOrigin: CGPoint) -> [Divider] {
    let leaves = LayoutMath.unitRects(layout.root)
    var out: [Divider] = []
    func walk(_ node: SplitNode, steps: [Bool]) {
      guard case .split(let axis, let ratio, let first, let second) = node else { return }
      var unit: UnitRect?
      for leaf in leaves where leaf.path.steps.starts(with: steps) {
        unit = unit.map { union($0, leaf.rect) } ?? leaf.rect
      }
      if let unit {
        // Unit space has y down; AppKit y is up, so flip inside the Layout rectangle.
        let lr = preview.layoutRect
        let parentX = lr.minX + unit.x * lr.width - contentOrigin.x
        let parentY = lr.maxY - (unit.y + unit.height) * lr.height - contentOrigin.y
        let parent = CGRect(x: parentX, y: parentY, width: unit.width * lr.width, height: unit.height * lr.height)
        let line: CGRect
        switch axis {
        case .horizontal:
          line = CGRect(
            x: parent.minX + ratio * parent.width - hitThickness / 2, y: parent.minY, width: hitThickness,
            height: parent.height)
        case .vertical:
          line = CGRect(
            x: parent.minX, y: parent.maxY - ratio * parent.height - hitThickness / 2, width: parent.width,
            height: hitThickness)
        }
        out.append(Divider(path: NodePath(steps: steps), axis: axis, parent: parent, line: line))
      }
      walk(first, steps: steps + [false])
      walk(second, steps: steps + [true])
    }
    walk(layout.root, steps: [])
    return out
  }

  private static func union(_ a: UnitRect, _ b: UnitRect) -> UnitRect {
    let minX = min(a.x, b.x)
    let minY = min(a.y, b.y)
    let maxX = max(a.x + a.width, b.x + b.width)
    let maxY = max(a.y + a.height, b.y + b.height)
    return UnitRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  /// The edit a drag of `divider` to `point` (view space) means: `setRatio` with the pointer's fraction of the
  /// parent's extent. Snapping is on unless Option is held (free drag). Range rules belong to the reducer.
  static func event(forDragOf divider: Divider, to point: CGPoint, optionHeld: Bool) -> EditorEvent {
    let ratio: Double
    switch divider.axis {
    case .horizontal: ratio = Double((point.x - divider.parent.minX) / divider.parent.width)
    case .vertical: ratio = Double((divider.parent.maxY - point.y) / divider.parent.height)  // first = top, y up
    }
    return .command(.setRatio(divider.path, ratio, snap: !optionHeld))
  }
}
