import CoreGraphics
import Foundation
import ZonesCore

/// Pure point lookups (ADR-0009 amendment C2). `Hit` is declared in ZonesLayout.swift.
public enum HitTest {
  /// Inside a Zone frame (half-open: min edge in, max edge out; the lower number wins a shared boundary) gives
  /// `.zone`. Else inside the visible frame (closed on all four edges) gives `.nearest` with the minimum edge
  /// distance, distances within `Constants.numberingEpsilon` counting as equal so the lower number wins.
  /// Else `.none`.
  public static func hit(_ point: CGPoint, in layout: ResolvedLayout) -> Hit {
    for zone in layout.zones where halfOpenContains(zone.frame, point) { return .zone(zone.number) }
    let v = layout.visibleFrame
    guard point.x >= v.minX, point.x <= v.maxX, point.y >= v.minY, point.y <= v.maxY else { return .none }
    var best: (number: Int, distance: Double)?
    for zone in layout.zones.sorted(by: { $0.number < $1.number }) {
      let d = edgeDistance(point, zone.frame)
      if let b = best, d >= b.distance - Constants.numberingEpsilon { continue }
      best = (zone.number, d)
    }
    return best.map { .nearest($0.number) } ?? .none
  }

  /// The first non-mirrored Display, in snapshot order, whose `frame` (not `visibleFrame`, so the menu bar strip
  /// still belongs to its Display) contains the point, half-open.
  public static func display(at point: CGPoint, in snapshot: TopologySnapshot) -> DisplayKey? {
    snapshot.displays.first { $0.mirrorOf == nil && halfOpenContains($0.frame, point) }?.key
  }

  private static func halfOpenContains(_ r: CGRect, _ p: CGPoint) -> Bool {
    p.x >= r.minX && p.x < r.maxX && p.y >= r.minY && p.y < r.maxY
  }

  private static func edgeDistance(_ p: CGPoint, _ r: CGRect) -> Double {
    hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
  }
}
