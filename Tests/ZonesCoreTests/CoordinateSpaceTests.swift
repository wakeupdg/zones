import CoreGraphics
import Testing
import ZonesTestSupport

@testable import ZonesCore

struct CoordinateSpaceTests {
  private let topology = Fixtures.threeDisplays

  /// The intersection area, 0 for rectangles that only touch.
  private func area(_ a: CGRect, _ b: CGRect) -> Double {
    let i = a.intersection(b)
    return i.isNull ? 0 : i.width * i.height
  }

  /// Brute-force oracle: largest intersection area, ties to the earlier Display, nil when nothing overlaps.
  private func oracle(_ rect: CGRect) -> DisplayKey? {
    var best: (key: DisplayKey, area: Double)?
    for d in topology.displays {
      let a = area(rect, d.frame)
      if a > 0, a > (best?.area ?? 0) { best = (d.key, a) }
    }
    return best?.key
  }

  @Test func roundTripAndDisplayFor() {
    let primary = topology.primaryFrame
    let union = topology.displays.dropFirst().reduce(topology.displays[0].frame) { $0.union($1.frame) }
    for i in 0..<500 {
      var g = Generator(seed: UInt64(i))
      let r = g.rect(in: union)
      let back = CoordinateSpace.appKitRect(CoordinateSpace.axRect(r, primaryFrame: primary), primaryFrame: primary)
      #expect(abs(back.minX - r.minX) < 1e-9 && abs(back.minY - r.minY) < 1e-9, "seed=\(i) origin \(back) vs \(r)")
      #expect(abs(back.width - r.width) < 1e-9 && abs(back.height - r.height) < 1e-9, "seed=\(i) size")
      let ax = CoordinateSpace.axRect(r, primaryFrame: primary)
      #expect(ax.width == r.width && ax.height == r.height && ax.minX == r.minX, "seed=\(i) only y flips")
      let found = CoordinateSpace.display(for: r, in: topology)?.key
      #expect(found == oracle(r), "seed=\(i) display(for: \(r)) = \(String(describing: found))")
    }

    // The portrait Display above the primary has negative AX y.
    let portrait = topology.displays[2]
    var g = Generator(seed: 99)
    for _ in 0..<50 {
      let r = g.rect(in: portrait.frame)
      #expect(CoordinateSpace.axRect(r, primaryFrame: primary).minY < 0, "portrait rect \(r) must have negative AX y")
      #expect(CoordinateSpace.display(for: r, in: topology)?.key == portrait.key)
    }
    // A fixed value: the portrait's bottom edge (AppKit y 1080) is the primary's top edge (AX y 0).
    #expect(CoordinateSpace.axRect(CGRect(x: 0, y: 1080, width: 10, height: 100), primaryFrame: primary).minY == -100)

    // Seam between the 2x Display (x < 0) and the primary (x >= 0): the larger overlap wins.
    let left = topology.displays[1]
    let main = topology.displays[0]
    #expect(CoordinateSpace.display(for: CGRect(x: -100, y: 100, width: 300, height: 200), in: topology)?.key == main.key)
    #expect(CoordinateSpace.display(for: CGRect(x: -250, y: 100, width: 300, height: 200), in: topology)?.key == left.key)
    // An exact tie goes to the earlier Display in the snapshot (primary is listed first).
    #expect(CoordinateSpace.display(for: CGRect(x: -100, y: 100, width: 200, height: 200), in: topology)?.key == main.key)
    // Off every Display.
    #expect(CoordinateSpace.display(for: CGRect(x: 5000, y: 5000, width: 10, height: 10), in: topology) == nil)
    // Touching an edge only is not an overlap.
    #expect(CoordinateSpace.display(for: CGRect(x: 1920, y: 0, width: 50, height: 50), in: topology) == nil)
  }

  @Test func panelLocalSubtractsThePanelOrigin() {
    let local = CoordinateSpace.panelLocal(
      CGRect(x: 110, y: 220, width: 50, height: 60), panelFrame: CGRect(x: 100, y: 200, width: 400, height: 300))
    #expect(local == CGRect(x: 10, y: 20, width: 50, height: 60))
    let negative = CoordinateSpace.panelLocal(
      CGRect(x: -500, y: 1200, width: 20, height: 20), panelFrame: CGRect(x: -600, y: 1080, width: 1080, height: 1920))
    #expect(negative == CGRect(x: 100, y: 120, width: 20, height: 20))
  }
}
