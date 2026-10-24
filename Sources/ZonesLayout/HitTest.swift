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
  /// still belongs to its Display) contains the point, half-open. A point no frame contains (the cursor pinned on
  /// the top or right edge of the outermost Display, where the flip lands it on `maxY`/`maxX`) falls back to the
  /// nearest non-mirrored Display by edge distance, the first in snapshot order on a tie, provided it lies within
  /// `edgeSlack`. Further out the cursor is on a Display the snapshot does not know, and the answer stays `nil`
  /// so a drop there never lands on a neighbour.
  public static func display(at point: CGPoint, in snapshot: TopologySnapshot) -> DisplayKey? {
    let candidates = snapshot.displays.filter { $0.mirrorOf == nil }
    if let hit = candidates.first(where: { halfOpenContains($0.frame, point) }) { return hit.key }
    var best: (key: DisplayKey, distance: Double)?
    for d in candidates {
      let distance = edgeDistance(point, d.frame)
      if let b = best, distance >= b.distance { continue }
      best = (d.key, distance)
    }
    guard let best, best.distance <= edgeSlack else { return nil }
    return best.key
  }

  /// How far outside every frame (points) a point may fall and still resolve to the nearest Display.
  static let edgeSlack = 8.0

  private static func halfOpenContains(_ r: CGRect, _ p: CGPoint) -> Bool {
    p.x >= r.minX && p.x < r.maxX && p.y >= r.minY && p.y < r.maxY
  }

  private static func edgeDistance(_ p: CGPoint, _ r: CGRect) -> Double {
    hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
  }
}
