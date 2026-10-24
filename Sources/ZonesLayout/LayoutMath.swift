import CoreGraphics
import Foundation
import ZonesCore

/// Pure layout geometry (LI-020). Unit space: x grows right, y grows DOWN (y = 0 is the top edge).
public enum LayoutMath {
  /// The leaves of `root` as rectangles that tile the unit square, in depth-first order (first child before second).
  /// A `.horizontal` split puts `first` on the left with width share `ratio`; `.vertical` puts `first` on top.
  public static func unitRects(_ root: SplitNode) -> [(path: NodePath, rect: UnitRect)] {
    var out: [(path: NodePath, rect: UnitRect)] = []
    collect(root, steps: [], rect: UnitRect(x: 0, y: 0, width: 1, height: 1), into: &out)
    return out
  }

  /// The visible frame less the per-side Surround fractions. Top and bottom are fractions of the height, left and
  /// right of the width. AppKit y grows up, so bottom raises `minY` and top lowers `maxY`.
  public static func layoutRect(visibleFrame: CGRect, surround: Surround) -> CGRect {
    let w = visibleFrame.width
    let h = visibleFrame.height
    // Subtracting from the extent (not from maxX) keeps an all-zero Surround bit-identical to the visible frame.
    return CGRect(
      x: visibleFrame.minX + surround.left * w, y: visibleFrame.minY + surround.bottom * h,
      width: w - surround.left * w - surround.right * w, height: h - surround.bottom * h - surround.top * h)
  }

  private static func collect(
    _ node: SplitNode, steps: [Bool], rect: UnitRect, into out: inout [(path: NodePath, rect: UnitRect)]
  ) {
    switch node {
    case .leaf:
      out.append((NodePath(steps: steps), rect))
    case .split(let axis, let ratio, let first, let second):
      let a: UnitRect
      let b: UnitRect
      switch axis {
      case .horizontal:
        let w = rect.width * ratio
        a = UnitRect(x: rect.x, y: rect.y, width: w, height: rect.height)
        b = UnitRect(x: rect.x + w, y: rect.y, width: rect.width - w, height: rect.height)
      case .vertical:
        let h = rect.height * ratio
        a = UnitRect(x: rect.x, y: rect.y, width: rect.width, height: h)
        b = UnitRect(x: rect.x, y: rect.y + h, width: rect.width, height: rect.height - h)
      }
      collect(first, steps: steps + [false], rect: a, into: &out)
      collect(second, steps: steps + [true], rect: b, into: &out)
    }
  }
}
