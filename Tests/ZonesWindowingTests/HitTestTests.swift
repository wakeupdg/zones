import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport

/// The reducer's view of `HitTest.hit` (AC-080): everything inside the visible frame resolves to a Zone,
/// only points outside it resolve to `.none`.
@Suite struct HitTestTests {
  typealias F = DragFixtures

  @Test func gapAndMarginAreNearest() {
    let layout = F.layout()
    let z1 = F.zoneFrame(1)
    let z2 = F.zoneFrame(2)
    let z5 = F.zoneFrame(5)
    let visible = layout.visibleFrame

    // Inside a Zone.
    #expect(HitTest.hit(F.center(5), in: layout) == .zone(5))

    // Gap between 1 and 2: nearer one side, then the other; the exact middle ties to the lower number.
    let gapY = z1.midY
    #expect(HitTest.hit(CGPoint(x: z1.maxX + 1, y: gapY), in: layout) == .nearest(1))
    #expect(HitTest.hit(CGPoint(x: z2.minX - 1, y: gapY), in: layout) == .nearest(2))
    #expect(HitTest.hit(CGPoint(x: (z1.maxX + z2.minX) / 2, y: gapY), in: layout) == .nearest(1))

    // Margin and the surround, inside the visible frame.
    #expect(HitTest.hit(CGPoint(x: visible.minX + 1, y: z1.midY), in: layout) == .nearest(1))
    #expect(HitTest.hit(CGPoint(x: visible.maxX - 1, y: z5.midY), in: layout) == .nearest(6))
    #expect(HitTest.hit(CGPoint(x: z5.midX, y: visible.minY + 1), in: layout) == .nearest(8))
    #expect(HitTest.hit(CGPoint(x: z5.midX, y: visible.maxY - 1), in: layout) == .nearest(2))

    // Outside the visible frame, such as the menu bar strip: no Zone.
    let strip = F.topology.displays[0]
    #expect(strip.frame.maxY > strip.visibleFrame.maxY)
    #expect(HitTest.hit(CGPoint(x: z5.midX, y: visible.maxY + 5), in: layout) == .none)
    #expect(HitTest.hit(CGPoint(x: visible.minX - 1, y: z5.midY), in: layout) == .none)
    #expect(HitTest.hit(CGPoint(x: visible.maxX + 1, y: z5.midY), in: layout) == .none)
  }
}
