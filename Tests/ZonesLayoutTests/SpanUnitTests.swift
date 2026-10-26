import CoreGraphics
import Testing
import ZonesCore

@testable import ZonesLayout

struct SpanTests {
  private let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)

  private func grid2x2(margin: Double, gap: Double) -> ResolvedLayout {
    let root = SplitNode.split(
      axis: .vertical, ratio: 0.5,
      first: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf),
      second: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf))
    return LayoutMath.resolve(
      makeLayout(root: root, insets: Insets(margin: margin, gap: gap)), key: .uuid("D1"), visibleFrame: visible,
      scale: 1)
  }

  @Test func unionIncludesGaps() {
    let flush = grid2x2(margin: 0, gap: 10)
    #expect(Span.rect([1, 4], in: flush) == flush.layoutRect)
    let r = grid2x2(margin: 20, gap: 10)
    let frame = { (n: Int) in r.zones[n - 1].frame }
    // {1,4} spans the Layout rectangle minus margin on every side.
    #expect(Span.rect([1, 4], in: r) == visible.insetBy(dx: 20, dy: 20))
    // {1,2} includes the Gap between them.
    let top = Span.rect([1, 2], in: r)
    #expect(top == CGRect(x: 20, y: 405, width: 1160, height: 375))
    #expect(top == frame(1).union(frame(2)))
    #expect(top.width > frame(1).width + frame(2).width)
    // Singleton equals its Zone frame.
    for n in 1...4 { #expect(Span.rect([n], in: r) == frame(n)) }
    // Unknown numbers are ignored; empty gives .zero.
    #expect(Span.rect([1, 99], in: r) == frame(1))
    #expect(Span.rect([0, -3, 99], in: r) == .zero)
    #expect(Span.rect([], in: r) == .zero)
    // Order independent: a Set has no order, so compare every ordering of the same members.
    #expect(Span.rect([4, 1], in: r) == Span.rect([1, 4], in: r))
    #expect(Span.rect([3, 2, 1], in: r) == Span.rect([1, 2, 3], in: r))
  }
}
