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
}
