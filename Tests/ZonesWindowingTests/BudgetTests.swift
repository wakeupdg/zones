import CoreGraphics
import Darwin
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

/// AC-039: hot paths hold no memory after warm-up, and the reducer is fast enough for a drag.
@Suite struct BudgetTests {
  typealias F = DragFixtures

  /// Order-of-magnitude bound (64 KiB) so CI never flakes; a per-call leak of even 64 bytes over 1,000 calls exceeds it.
  static let allowedGrowth = 65_536
  static let warmUp = 1_000
  static let measured = 1_000

  static func inUse() -> Int {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    return Int(stats.size_in_use)
  }

  /// Bytes in use after `measured` more calls minus before, after `warmUp` calls. The checksum each call returns
  /// is folded into `sink` so the optimizer keeps the work. The process-wide heap is shared with other running
  /// tests, so the smallest of three rounds is taken: a leak grows in every round, noise does not.
  @discardableResult
  static func growth(of body: () -> Int) -> Int {
    var sink = 0
    for _ in 0..<warmUp { sink &+= body() }
    var smallest = Int.max
    for _ in 0..<3 {
      let before = inUse()
      for _ in 0..<measured { sink &+= body() }
      smallest = min(smallest, inUse() - before)
    }
    withExtendedLifetime(sink) {}
    return smallest
  }

  // Slice 10 (AC-039)
  @Test func hotPathsHoldNoMemory() {
    let topology = Fixtures.threeDisplays
    let layouts = Fixtures.layouts(topology, Fixtures.nineZone)
    let display = topology.displays[0]
    let layout = layouts[display.key]!
    let units = LayoutMath.unitRects(Fixtures.nineZone.root)
    var points: [CGPoint] = []
    for k in 0..<64 { points.append(CGPoint(x: Double((k * 31) % 1920), y: Double((k * 17) % 1080))) }
    let scene = OverlayScene(
      layouts: topology.displays.compactMap { layouts[$0.key] }, appearance: Preferences.defaults.appearance,
      options: AccessibilityOptions(reduceTransparency: false, reduceMotion: false))
    var i = 0

    let hit = Self.growth {
      i &+= 1
      switch HitTest.hit(points[i % points.count], in: layout) {
      case .zone(let n): return n
      case .nearest(let n): return n + 100
      case .none: return -1
      }
    }
    #expect(hit <= Self.allowedGrowth, "HitTest.hit grew the heap by \(hit) bytes")

    let span = Self.growth { Int(Span.rect([1, 2, 5], in: layout).width) }
    #expect(span <= Self.allowedGrowth, "Span.rect grew the heap by \(span) bytes")

    let resolve = Self.growth { LayoutMath.resolve(Fixtures.nineZone, display: display).zones.count }
    #expect(resolve <= Self.allowedGrowth, "LayoutMath.resolve grew the heap by \(resolve) bytes")

    let grid = Self.growth {
      Grid.round(
        units, layoutRect: layout.layoutRect, insets: Fixtures.nineZone.insets, scale: layout.scale
      ).count
    }
    #expect(grid <= Self.allowedGrowth, "Grid.round grew the heap by \(grid) bytes")

    let panels = Self.growth { OverlayModel.panels(scene).count }
    #expect(panels <= Self.allowedGrowth, "OverlayModel.panels grew the heap by \(panels) bytes")
  }

  // Slice 11 (AC-039)
  @Test func tenThousandDraggedEventsUnderTwoSeconds() {
    var state = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift)).0
    for event in [F.dragged(), F.moved(), .armContext(F.context)] {
      state = DragSessionReducer.reduce(state, event).0
    }
    #expect(F.isArmed(state))
    var points: [CGPoint] = []
    for k in 0..<10_000 {
      points.append(CGPoint(x: Double((k * 37) % 1900) + 10, y: Double((k * 23) % 1050) + 10))
    }
    var effects = 0
    let elapsed = ContinuousClock().measure {
      for p in points {
        let (next, fx) = DragSessionReducer.reduce(state, .dragged(point: p, flags: .shift))
        state = next
        effects &+= fx.count
      }
    }
    #expect(F.isArmed(state))
    #expect(effects > 1_000, "the reduction did real work: \(effects) effects")
    #expect(elapsed < .seconds(2), "10,000 dragged events took \(elapsed)")
  }
}
