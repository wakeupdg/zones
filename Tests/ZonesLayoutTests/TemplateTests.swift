import CoreGraphics
import Testing
import ZonesCore

@testable import ZonesLayout

private let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
private let zeroInsets = Insets(margin: 0, gap: 0)
private let eps = 1e-6
/// Grid.round snaps edges to whole device pixels (scale 1), so an equal share that is not a whole number of points
/// (800 / 3) lands within one pixel of the ideal value.
private let pixel = 1.0

private func resolve(_ layout: Layout) -> ResolvedLayout {
  LayoutMath.resolve(layout, key: .uuid("D1"), visibleFrame: visible, scale: 1)
}

struct TemplateTests {
  @Test func countsShapesAndNames() {
    #expect(Template.allCases.map(\.rawValue) == ["Columns", "Rows", "Grid", "Priority Grid", "Focus"])
    for template in Template.allCases {
      for count in template.counts {
        let layout = Templates.generate(template, count: count, insets: zeroInsets)
        #expect(layout.name == template.rawValue, "\(template) \(count)")
        let zones = resolve(layout).zones
        #expect(zones.count == count, "\(template) \(count)")
        switch template {
        case .columns:
          for (i, z) in zones.enumerated() {
            #expect(abs(z.frame.width - 1200 / Double(count)) < eps)
            #expect(abs(z.frame.minX - 1200 / Double(count) * Double(i)) < eps)
            #expect(abs(z.frame.height - 800) < eps)
          }
        case .rows:
          // AppKit y grows up: Zone 1 is the top row, so its minY is the highest.
          for (i, z) in zones.enumerated() {
            #expect(abs(z.frame.height - 800 / Double(count)) <= pixel)
            #expect(abs(z.frame.maxY - (800 - 800 / Double(count) * Double(i))) <= pixel)
            #expect(abs(z.frame.width - 1200) < eps)
          }
        case .grid:
          let side = count == 4 ? 2 : 3
          for (i, z) in zones.enumerated() {
            #expect(abs(z.frame.width - 1200 / Double(side)) < eps)
            #expect(abs(z.frame.height - 800 / Double(side)) <= pixel)
            #expect(abs(z.frame.minX - 1200 / Double(side) * Double(i % side)) < eps)
            #expect(abs(z.frame.maxY - (800 - 800 / Double(side) * Double(i / side))) <= pixel)
          }
        case .priorityGrid:
          let widths = zones.map(\.frame.width)
          #expect(abs(widths[0] - 300) < eps && abs(widths[1] - 600) < eps && abs(widths[2] - 300) < eps)
          #expect(zones.allSatisfy { $0.frame.minY == zones[0].frame.minY && abs($0.frame.height - 800) < eps })
          #expect(abs(zones[1].frame.minX - 300) < eps && abs(zones[2].frame.minX - 900) < eps)
        case .focus:
          #expect(zones.count == 1)
        }
      }
    }
  }

  @Test func focusIsOneCenteredZone() {
    let layout = Templates.generate(.focus, count: 1, insets: zeroInsets)
    #expect(layout.root == .leaf)
    #expect(layout.surround == Surround(top: 0.2, left: 0.2, bottom: 0.2, right: 0.2))
    let r = resolve(layout)
    #expect(r.zones.count == 1)
    let zone = r.zones[0]
    #expect(zone.number == 1)
    let want = CGRect(x: 240, y: 160, width: 720, height: 480)
    #expect(abs(zone.frame.minX - want.minX) < eps && abs(zone.frame.minY - want.minY) < eps)
    #expect(abs(zone.frame.width - want.width) < eps && abs(zone.frame.height - want.height) < eps)
    for ix in 0...4 {
      for iy in 0...4 {
        let p = CGPoint(x: visible.minX + visible.width * Double(ix) / 4, y: visible.minY + visible.height * Double(iy) / 4)
        let got = HitTest.hit(p, in: r)
        #expect(got == .zone(1) || got == .nearest(1), "\(p) gave \(got)")
      }
    }
    #expect(HitTest.hit(CGPoint(x: -1, y: 400), in: r) == .none)
    #expect(HitTest.hit(CGPoint(x: 600, y: 801), in: r) == .none)
  }
}
