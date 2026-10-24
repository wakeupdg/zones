import CoreGraphics
import Foundation
import ZonesCore

/// Turns unit rectangles into AppKit-global frames inside a layout rectangle (LI-020, pure).
///
/// Edge rule (shared by `unrounded` and `round`, so the two cannot disagree on which edge is which):
/// every distinct unit coordinate on an axis is canonicalised once (values within `1e-9` collapse to one), then
/// mapped to a position as a pure function of that coordinate, never of traversal order. Two neighbours that
/// touch the same unit coordinate therefore read the identical divider. Outer edges sit exactly Margin inside the
/// layout rectangle; an interior divider `d` yields zone edges `d - gap/2` and `d + gap/2`.
public enum Grid {
  /// The same frames as `round` without pixel snapping, with the Gap in points as given.
  /// AC-116 measures exact Gap and Margin on this output.
  public static func unrounded(
    _ rects: [(path: NodePath, rect: UnitRect)], layoutRect: CGRect, insets: Insets
  ) -> [(path: NodePath, frame: CGRect)] {
    frames(rects, layoutRect: layoutRect, margin: insets.margin, gap: insets.gap, snap: { value, _ in value })
  }

  /// Pixel-snapped frames for a display of the given `scale` (pixels per point).
  ///
  /// Rounding rule, applied once: every position (outer edges and interior dividers) is snapped to the nearest
  /// `1 / scale`, with exact half-pixel ties broken toward the layout rectangle's centre so that reflecting the tree
  /// reflects the pixels. The Gap is `max(0, round(gap * scale))` whole pixels, rounded once, and an interior divider
  /// `d` yields zone edges `d - g/2` and `d + g/2` pixels: every Gap is the same pixel count and the divider lies on a
  /// pixel boundary. An odd `g` puts the zone edges on half pixels (allowed by AC-069). There is no "remainder to the
  /// last Zone".
  public static func round(
    _ rects: [(path: NodePath, rect: UnitRect)], layoutRect: CGRect, insets: Insets, scale: Double
  ) -> [(path: NodePath, frame: CGRect)] {
    let pixelScale = scale > 0 ? scale : 1
    let gapPixels = max(0, (insets.gap * pixelScale).rounded(.toNearestOrAwayFromZero))
    return frames(
      rects, layoutRect: layoutRect, margin: insets.margin, gap: gapPixels / pixelScale,
      snap: { snapToPixel($0, center: $1, scale: pixelScale) })
  }

  /// Nearest multiple of `1 / scale`; an exact half-pixel tie goes toward `center`.
  private static func snapToPixel(_ value: Double, center: Double, scale: Double) -> Double {
    let scaled = value * scale
    let floor = scaled.rounded(.down)
    let fraction = scaled - floor
    let pixel: Double
    if abs(fraction - 0.5) < tieTolerance {
      pixel = value < center ? floor + 1 : floor
    } else {
      pixel = fraction < 0.5 ? floor : floor + 1
    }
    return pixel / scale
  }

  /// Tolerance, in pixels, for calling a fractional pixel an exact tie (absorbs float noise from a mirrored tree).
  private static let tieTolerance = 1e-9

  /// Tolerance for treating two unit coordinates as the same divider.
  private static let unitTolerance = 1e-9

  private static func frames(
    _ rects: [(path: NodePath, rect: UnitRect)], layoutRect: CGRect, margin: Double, gap: Double,
    snap: (_ value: Double, _ center: Double) -> Double
  ) -> [(path: NodePath, frame: CGRect)] {
    let left = layoutRect.minX + margin
    let right = layoutRect.maxX - margin
    let bottom = layoutRect.minY + margin
    let top = layoutRect.maxY - margin
    let half = gap / 2

    let canonX = canonicalizer(rects.flatMap { [$0.rect.x, $0.rect.x + $0.rect.width] })
    let canonY = canonicalizer(rects.flatMap { [$0.rect.y, $0.rect.y + $0.rect.height] })

    func xPosition(_ u: Double) -> Double {
      if u <= unitTolerance { return snap(left, layoutRect.midX) }
      if u >= 1 - unitTolerance { return snap(right, layoutRect.midX) }
      return snap(left + u * (right - left), layoutRect.midX)
    }
    func yPosition(_ u: Double) -> Double {  // u grows down, AppKit y grows up
      if u <= unitTolerance { return snap(top, layoutRect.midY) }
      if u >= 1 - unitTolerance { return snap(bottom, layoutRect.midY) }
      return snap(top - u * (top - bottom), layoutRect.midY)
    }

    return rects.map { item in
      let x0 = canonX(item.rect.x)
      let x1 = canonX(item.rect.x + item.rect.width)
      let y0 = canonY(item.rect.y)
      let y1 = canonY(item.rect.y + item.rect.height)
      let minX = xPosition(x0) + (x0 <= unitTolerance ? 0 : half)
      let maxX = xPosition(x1) - (x1 >= 1 - unitTolerance ? 0 : half)
      let maxY = yPosition(y0) - (y0 <= unitTolerance ? 0 : half)
      let minY = yPosition(y1) + (y1 >= 1 - unitTolerance ? 0 : half)
      return (item.path, CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY)))
    }
  }

  /// Maps a raw unit coordinate to one representative per cluster of values closer than `unitTolerance`.
  private static func canonicalizer(_ values: [Double]) -> (Double) -> Double {
    var reps: [Double] = []
    for v in values.sorted() where reps.last.map({ v - $0 > unitTolerance }) ?? true { reps.append(v) }
    return { v in
      if abs(v) <= unitTolerance { return 0 }
      if abs(v - 1) <= unitTolerance { return 1 }
      return reps.first { abs(v - $0) <= unitTolerance } ?? v
    }
  }
}
