import CoreGraphics
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesLayout

struct LayoutTilingTests {
  private let tolerance = 1e-9

  @Test func randomTreesTile() {
    var biggest = 0
    for i in 0..<300 {
      var g = Generator(seed: UInt64(i))
      let root = g.tree(maxDepth: g.int(1...8))
      let layout = makeLayout(root: root)
      func fail(_ note: String) -> Comment {
        Comment(rawValue: Generator.failureMessage(seed: UInt64(i), layout: layout, note: note))
      }
      let rects = LayoutMath.unitRects(root)
      biggest = max(biggest, rects.count)
      #expect(rects.count == leafCount(root), fail("leaf count"))
      let area = rects.reduce(0) { $0 + $1.rect.width * $1.rect.height }
      #expect(abs(area - 1) < tolerance, fail("area \(area)"))
      #expect(Set(rects.map(\.path)).count == rects.count, fail("paths not unique"))
      for item in rects {
        let r = item.rect
        #expect(r.x >= -tolerance && r.y >= -tolerance, fail("origin outside unit square"))
        #expect(r.x + r.width <= 1 + tolerance && r.y + r.height <= 1 + tolerance, fail("outside unit square"))
        #expect(r.width >= Constants.minFraction - tolerance, fail("narrow leaf \(r.width)"))
        #expect(r.height >= Constants.minFraction - tolerance, fail("short leaf \(r.height)"))
      }
      for a in 0..<rects.count {
        for b in (a + 1)..<max(a + 1, rects.count) {
          let p = rects[a].rect
          let q = rects[b].rect
          let overlapW = min(p.x + p.width, q.x + q.width) - max(p.x, q.x)
          let overlapH = min(p.y + p.height, q.y + q.height) - max(p.y, q.y)
          #expect(!(overlapW > tolerance && overlapH > tolerance), fail("overlap \(a) \(b)"))
        }
      }
      for ratio in ratios(root) {
        #expect(ratio > 0 && ratio < 1, fail("ratio \(ratio)"))
      }
    }
    #expect(biggest >= 8, "generator never produced a sizeable tree")
    for i in 0..<300 { marginAndGapSeparate(seed: UInt64(i)) }
  }

  /// Part B: layoutRect matches a hand computation; with Margin and Gap the unrounded output separates every
  /// unit-adjacent pair by exactly Gap and sits exactly Margin inside the layout rectangle on the outer edges.
  private func marginAndGapSeparate(seed: UInt64) {
    var g = Generator(seed: seed &+ 1_000_000)
    let root = g.tree(maxDepth: g.int(1...8))
    let visible = CGRect(
      x: g.double(-2000...2000), y: g.double(-2000...2000), width: g.double(800...3000), height: g.double(600...2000))
    let surround = Surround(
      top: g.double(0...0.3), left: g.double(0...0.3), bottom: g.double(0...0.3), right: g.double(0...0.3))
    let insets = Insets(margin: g.double(0...20), gap: g.double(0...10))
    let layout = makeLayout(root: root, surround: surround, insets: insets)
    func fail(_ note: String) -> Comment {
      Comment(rawValue: Generator.failureMessage(seed: seed, layout: layout, note: note))
    }

    let rect = LayoutMath.layoutRect(visibleFrame: visible, surround: surround)
    let expected = CGRect(
      x: visible.minX + surround.left * visible.width, y: visible.minY + surround.bottom * visible.height,
      width: visible.width * (1 - surround.left - surround.right),
      height: visible.height * (1 - surround.top - surround.bottom))
    #expect(abs(rect.minX - expected.minX) < tolerance, fail("layoutRect minX"))
    #expect(abs(rect.minY - expected.minY) < tolerance, fail("layoutRect minY"))
    #expect(abs(rect.width - expected.width) < tolerance, fail("layoutRect width"))
    #expect(abs(rect.height - expected.height) < tolerance, fail("layoutRect height"))
    let zero = Surround(top: 0, left: 0, bottom: 0, right: 0)
    #expect(LayoutMath.layoutRect(visibleFrame: visible, surround: zero) == visible, fail("zero surround"))

    let units = LayoutMath.unitRects(root)
    let frames = Grid.unrounded(units, layoutRect: rect, insets: insets)
    #expect(frames.count == units.count, fail("frame count"))
    let near = { (a: Double, b: Double) in abs(a - b) < 1e-9 }
    for (item, placed) in zip(units, frames) {
      #expect(item.path == placed.path, fail("path order"))
      let u = item.rect
      let f = placed.frame
      if near(u.x, 0) { #expect(near(f.minX, rect.minX + insets.margin), fail("left margin")) }
      if near(u.x + u.width, 1) { #expect(near(f.maxX, rect.maxX - insets.margin), fail("right margin")) }
      if near(u.y, 0) { #expect(near(f.maxY, rect.maxY - insets.margin), fail("top margin")) }
      if near(u.y + u.height, 1) { #expect(near(f.minY, rect.minY + insets.margin), fail("bottom margin")) }
    }
    for (a, fa) in zip(units, frames) {
      for (b, fb) in zip(units, frames) where a.path != b.path {
        let overlapX = min(a.rect.x + a.rect.width, b.rect.x + b.rect.width) - max(a.rect.x, b.rect.x) > tolerance
        let overlapY = min(a.rect.y + a.rect.height, b.rect.y + b.rect.height) - max(a.rect.y, b.rect.y) > tolerance
        if near(a.rect.x + a.rect.width, b.rect.x) && overlapY {
          #expect(near(fb.frame.minX - fa.frame.maxX, insets.gap), fail("horizontal gap"))
        }
        if near(a.rect.y + a.rect.height, b.rect.y) && overlapX {  // a above b; AppKit y is up
          #expect(near(fa.frame.minY - fb.frame.maxY, insets.gap), fail("vertical gap"))
        }
      }
    }
  }
}
