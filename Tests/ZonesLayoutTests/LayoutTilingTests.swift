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
  }
}
