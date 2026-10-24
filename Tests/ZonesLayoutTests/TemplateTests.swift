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

struct LayoutValidatorTests {
  private let zero = Surround(top: 0, left: 0, bottom: 0, right: 0)

  private func layout(
    _ root: SplitNode, name: String = "Custom", surround: Surround? = nil
  ) -> Layout {
    Layout(
      id: LayoutID(rawValue: "x"), name: name, root: root, surround: surround ?? zero,
      insets: Insets(margin: 0, gap: 0))
  }

  private func twoLevel(inner ratio: Double) -> SplitNode {
    .split(
      axis: .horizontal, ratio: 0.5, first: .leaf,
      second: .split(axis: .vertical, ratio: ratio, first: .leaf, second: .leaf))
  }

  @Test func acceptsBuiltInsAndRejectsFaults() {
    for built in Templates.all(insets: zeroInsets) { #expect(LayoutValidator.validate(built) == nil, "\(built.id)") }
    #expect(LayoutValidator.validate(layout(.leaf)) == nil)

    // Ratio outside (0,1), reported at the right path.
    for bad in [0.0, 1.0, -0.2, Double.nan] {
      #expect(
        LayoutValidator.validate(layout(.split(axis: .horizontal, ratio: bad, first: .leaf, second: .leaf)))
          == .ratioOutOfRange(NodePath(steps: [])), "root ratio \(bad)")
      #expect(
        LayoutValidator.validate(layout(twoLevel(inner: bad))) == .ratioOutOfRange(NodePath(steps: [true])),
        "nested ratio \(bad)")
    }
    // First bad ratio in depth-first order wins.
    let twoBad = SplitNode.split(
      axis: .horizontal, ratio: 0.5,
      first: .split(axis: .vertical, ratio: 1.5, first: .leaf, second: .leaf),
      second: .split(axis: .vertical, ratio: 0, first: .leaf, second: .leaf))
    #expect(LayoutValidator.validate(layout(twoBad)) == .ratioOutOfRange(NodePath(steps: [false])))

    // Leaf narrower than 1/12 of the Layout rectangle.
    let tiny = SplitNode.split(axis: .horizontal, ratio: 0.05, first: .leaf, second: .leaf)
    #expect(LayoutValidator.validate(layout(tiny)) == .leafTooSmall(NodePath(steps: [false])))
    let tinyBoth = SplitNode.split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .split(axis: .vertical, ratio: 0.95, first: .leaf, second: .leaf))
    #expect(LayoutValidator.validate(layout(tinyBoth)) == .leafTooSmall(NodePath(steps: [true, true])))
    let edge = SplitNode.split(axis: .horizontal, ratio: 1.0 / 12, first: .leaf, second: .leaf)
    #expect(LayoutValidator.validate(layout(edge)) == nil)

    // Surround.
    func sur(_ v: Double) -> Surround { Surround(top: v, left: 0, bottom: 0, right: 0) }
    #expect(LayoutValidator.validate(layout(.leaf, surround: sur(0.46))) == .surroundOutOfRange)
    #expect(LayoutValidator.validate(layout(.leaf, surround: sur(0.45))) == nil)
    #expect(LayoutValidator.validate(layout(.leaf, surround: sur(-0.01))) == .surroundOutOfRange)
    #expect(LayoutValidator.validate(layout(.leaf, surround: sur(.nan))) == .surroundOutOfRange)
    #expect(
      LayoutValidator.validate(layout(.leaf, surround: Surround(top: 0, left: 0, bottom: 0, right: 0.5)))
        == .surroundOutOfRange)

    // Name.
    #expect(LayoutValidator.validate(layout(.leaf, name: "  ")) == .emptyName)
    #expect(LayoutValidator.validate(layout(.leaf, name: "")) == .emptyName)
    #expect(LayoutValidator.validate(layout(.leaf, name: " a ")) == nil)

    // Precedence: emptyName > surroundOutOfRange > ratioOutOfRange > leafTooSmall.
    let badRatio = SplitNode.split(axis: .horizontal, ratio: 0, first: .leaf, second: .leaf)
    #expect(LayoutValidator.validate(layout(badRatio, name: " ", surround: sur(0.9))) == .emptyName)
    #expect(LayoutValidator.validate(layout(badRatio, surround: sur(0.9))) == .surroundOutOfRange)
    let ratioAndTiny = SplitNode.split(
      axis: .horizontal, ratio: 0.01, first: .leaf,
      second: .split(axis: .vertical, ratio: 1, first: .leaf, second: .leaf))
    #expect(LayoutValidator.validate(layout(ratioAndTiny)) == .ratioOutOfRange(NodePath(steps: [true])))
  }
}
