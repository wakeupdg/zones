import CoreGraphics
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesLayout

struct HitTestTests {
  private let display = CGRect(x: 0, y: 0, width: 1200, height: 800)

  /// 2x2 Grid, margin 20, gap 10 on a 1200x800 frame. AppKit y grows up, so Zone 1 is top-left:
  /// 1 = (20,405,575,375), 2 = (605,405,575,375), 3 = (20,20,575,375), 4 = (605,20,575,375).
  private func grid2x2(visible: CGRect? = nil) -> ResolvedLayout {
    let root = SplitNode.split(
      axis: .vertical, ratio: 0.5,
      first: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf),
      second: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf))
    let layout = makeLayout(root: root, insets: Insets(margin: 20, gap: 10))
    return LayoutMath.resolve(layout, key: .uuid("D1"), visibleFrame: visible ?? display, scale: 1)
  }

  @Test func gapAndMarginAreNearest() {
    let r = grid2x2()
    #expect(r.zones.map(\.frame) == [
      CGRect(x: 20, y: 405, width: 575, height: 375), CGRect(x: 605, y: 405, width: 575, height: 375),
      CGRect(x: 20, y: 20, width: 575, height: 375), CGRect(x: 605, y: 20, width: 575, height: 375),
    ])
    // Inside each Zone.
    #expect(HitTest.hit(CGPoint(x: 300, y: 600), in: r) == .zone(1))
    #expect(HitTest.hit(CGPoint(x: 900, y: 600), in: r) == .zone(2))
    #expect(HitTest.hit(CGPoint(x: 300, y: 200), in: r) == .zone(3))
    #expect(HitTest.hit(CGPoint(x: 900, y: 200), in: r) == .zone(4))
    // Vertical gap, nearer one side.
    #expect(HitTest.hit(CGPoint(x: 596, y: 600), in: r) == .nearest(1))
    #expect(HitTest.hit(CGPoint(x: 604, y: 600), in: r) == .nearest(2))
    // Horizontal gap.
    #expect(HitTest.hit(CGPoint(x: 300, y: 398), in: r) == .nearest(3))
    #expect(HitTest.hit(CGPoint(x: 300, y: 402), in: r) == .nearest(1))
    // Exactly equidistant: lower Zone Number.
    #expect(HitTest.hit(CGPoint(x: 600, y: 600), in: r) == .nearest(1))
    #expect(HitTest.hit(CGPoint(x: 300, y: 400), in: r) == .nearest(1))
    #expect(HitTest.hit(CGPoint(x: 600, y: 400), in: r) == .nearest(1))
    // Zone frames are half-open: the max edge is out.
    #expect(HitTest.hit(CGPoint(x: 595, y: 600), in: r) == .nearest(1))
    #expect(HitTest.hit(CGPoint(x: 20, y: 600), in: r) == .zone(1))
    // Margin and the visible-frame edge (closed).
    #expect(HitTest.hit(CGPoint(x: 5, y: 600), in: r) == .nearest(1))
    #expect(HitTest.hit(CGPoint(x: 1195, y: 100), in: r) == .nearest(4))
    #expect(HitTest.hit(CGPoint(x: 0, y: 800), in: r) == .nearest(1))
    #expect(HitTest.hit(CGPoint(x: 1200, y: 0), in: r) == .nearest(4))
    #expect(HitTest.hit(CGPoint(x: 0, y: 0), in: r) == .nearest(3))
    // Outside the visible frame, e.g. the menu bar strip.
    let withBar = grid2x2(visible: CGRect(x: 0, y: 0, width: 1200, height: 775))
    #expect(HitTest.hit(CGPoint(x: 600, y: 790), in: withBar) == .none)
    #expect(HitTest.hit(CGPoint(x: -1, y: 400), in: r) == .none)
    #expect(HitTest.hit(CGPoint(x: 1201, y: 400), in: r) == .none)
  }

  @Test func displayAtPoint() {
    let topology = Fixtures.threeDisplays
    let primary = topology.displays[0].key
    let retina = topology.displays[1].key
    let portrait = topology.displays[2].key
    #expect(HitTest.display(at: CGPoint(x: 100, y: 100), in: topology) == primary)
    // Menu bar strip is outside visibleFrame but inside frame.
    #expect(HitTest.display(at: CGPoint(x: 100, y: 1070), in: topology) == primary)
    // Negative-origin Display.
    #expect(HitTest.display(at: CGPoint(x: -700, y: 400), in: topology) == retina)
    #expect(HitTest.display(at: CGPoint(x: -500, y: 2000), in: topology) == portrait)
    // Shared boundaries are half-open.
    #expect(HitTest.display(at: CGPoint(x: 0, y: 100), in: topology) == primary)
    #expect(HitTest.display(at: CGPoint(x: -0.5, y: 100), in: topology) == retina)
    #expect(HitTest.display(at: CGPoint(x: 100, y: 1080), in: topology) == portrait)
    // Outside every Display.
    #expect(HitTest.display(at: CGPoint(x: 5000, y: 5000), in: topology) == nil)
    #expect(HitTest.display(at: CGPoint(x: -1000, y: 1500), in: topology) == nil)
    // Mirrored Display is skipped even when it comes first.
    var mirrored = topology
    var copy = topology.displays[0]
    copy.key = .uuid("44444444-4444-4444-8444-444444444444")
    copy.mirrorOf = primary
    mirrored.displays.insert(copy, at: 0)
    #expect(HitTest.display(at: CGPoint(x: 100, y: 100), in: mirrored) == primary)
  }

  @Test func zoneCentersAreZones() {
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    for seed in 0..<200 as Range<UInt64> {
      var gen = Generator(seed: seed)
      let layout = gen.layout(maxDepth: 4)
      let r = LayoutMath.resolve(layout, key: .uuid("D1"), visibleFrame: bounds, scale: 1)
      for zone in r.zones {
        let center = CGPoint(x: zone.frame.midX, y: zone.frame.midY)
        let got = HitTest.hit(center, in: r)
        #expect(
          got == .zone(zone.number),
          Comment(rawValue: Generator.failureMessage(seed: seed, layout: layout, note: "center of zone \(zone.number) gave \(got)")))
      }
      for _ in 0..<20 {
        let p = CGPoint(x: gen.double(bounds.minX...bounds.maxX), y: gen.double(bounds.minY...bounds.maxY))
        let got = HitTest.hit(p, in: r)
        #expect(
          got != .none,
          Comment(rawValue: Generator.failureMessage(seed: seed, layout: layout, note: "point \(p) gave none")))
      }
    }
  }
}

struct LabelModelTests {
  private let appearance = Appearance(
    fill: RGBA(r: 0.2, g: 0.4, b: 0.8, a: 1), opacity: 0.5, defaultInsets: Insets(margin: 0, gap: 0))

  @Test func textScaleAndNoChord() {
    // 12 columns need ratios 1/12 each: right-nested splits of 1/(n-k).
    func strip(_ n: Int) -> SplitNode {
      n == 1 ? .leaf : .split(axis: .horizontal, ratio: 1.0 / Double(n), first: .leaf, second: strip(n - 1))
    }
    let r = LayoutMath.resolve(
      makeLayout(root: strip(12)), key: .uuid("D1"), visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
      scale: 2)
    let labels = LabelModel.labels(r, appearance: appearance)
    #expect(labels.count == 12)
    #expect(labels.map(\.number) == Array(1...12))
    for (label, zone) in zip(labels, r.zones) {
      #expect(label.text == String(label.number))
      #expect(label.contentsScale == 2)
      #expect(label.noChord == (label.number > 9))
      #expect(label.frame == zone.frame)
    }
    #expect(labels.filter(\.noChord).map(\.number) == [10, 11, 12])
  }

  /// Independent WCAG ratio (same formula, written out here so the test does not call LabelModel internals).
  private func luminance(_ c: RGBA) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }

  private func ratio(_ a: RGBA, _ b: RGBA) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
  }

  @Test func outlineContrast() {
    var fills: [RGBA] = []
    for r in [0.0, 1] { for g in [0.0, 1] { for b in [0.0, 1] { fills.append(RGBA(r: r, g: g, b: b, a: 1)) } } }
    for i in 0...100 { fills.append(RGBA(r: Double(i) / 100, g: Double(i) / 100, b: Double(i) / 100, a: 1)) }
    fills.append(RGBA(r: 0.46, g: 0.46, b: 0.46, a: 1))
    var gen = Generator(seed: 7)
    while fills.count < 500 {
      fills.append(RGBA(r: gen.double(0...1), g: gen.double(0...1), b: gen.double(0...1), a: gen.double(0...1)))
    }
    let r = LayoutMath.resolve(
      makeLayout(root: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf)), key: .uuid("D1"),
      visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 1)
    var worst = Double.infinity
    for fill in fills {
      for opacity in [0.1, 0.5, 1] {
        let appearance = Appearance(fill: fill, opacity: opacity, defaultInsets: Insets(margin: 0, gap: 0))
        for label in LabelModel.labels(r, appearance: appearance) {
          let opaque = RGBA(r: fill.r, g: fill.g, b: fill.b, a: 1)
          let value = ratio(label.outline, opaque)
          worst = min(worst, value)
          #expect(value >= 4.5, "fill=\(fill) opacity=\(opacity) ratio=\(value)")
          #expect(label.outline.a == 1)
        }
      }
    }
    #expect(worst >= 4.5)
  }
}
