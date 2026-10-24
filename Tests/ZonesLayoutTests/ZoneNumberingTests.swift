import CoreGraphics
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesLayout

struct ZoneNumberingTests {
  private let epsilon = Constants.numberingEpsilon

  @Test func rowMajorBijection() {
    fixedCase()
    for i in 0..<250 {
      var g = Generator(seed: UInt64(i))
      var root = g.tree(maxDepth: g.int(1...8))
      checkNumbers(root, seed: UInt64(i), note: "initial")
      checkInvariance(root, seed: UInt64(i), generator: &g)
      for edit in 0..<6 {  // numbers are recomputed after every editor-style command
        root = randomEdit(root, generator: &g)
        checkNumbers(root, seed: UInt64(i), note: "after edit \(edit)")
      }
    }
  }

  /// Left tall Zone, right column split top and bottom: 1 left, 2 right-top, 3 right-bottom.
  private func fixedCase() {
    let root = SplitNode.split(
      axis: .horizontal, ratio: 0.5, first: .leaf,
      second: .split(axis: .vertical, ratio: 0.5, first: .leaf, second: .leaf))
    let numbers = ZoneNumbering.numbers(LayoutMath.unitRects(root))
    #expect(numbers[NodePath(steps: [false])] == 1)
    #expect(numbers[NodePath(steps: [true, false])] == 2)
    #expect(numbers[NodePath(steps: [true, true])] == 3)
    // A single leaf is Zone 1 at the root path.
    #expect(ZoneNumbering.numbers(LayoutMath.unitRects(.leaf)) == [NodePath(steps: []): 1])
  }

  private func checkNumbers(_ root: SplitNode, seed: UInt64, note: String) {
    let layout = makeLayout(root: root)
    func fail(_ text: String) -> Comment {
      Comment(rawValue: Generator.failureMessage(seed: seed, layout: layout, note: "\(note): \(text)"))
    }
    let rects = LayoutMath.unitRects(root)
    let numbers = ZoneNumbering.numbers(rects)
    #expect(Set(numbers.keys) == Set(rects.map(\.path)), fail("keys are the leaf paths"))
    #expect(Set(numbers.values) == Set(1...rects.count), fail("values are 1...N"))
    let ordered = rects.sorted { numbers[$0.path, default: 0] < numbers[$1.path, default: 0] }
    for a in 0..<ordered.count {
      for b in (a + 1)..<max(a + 1, ordered.count) {
        let p = ordered[a].rect
        let q = ordered[b].rect
        let above = p.y < q.y - epsilon
        let sameRowLeftFirst = abs(p.y - q.y) <= epsilon && p.x <= q.x
        #expect(above || sameRowLeftFirst, fail("zone \(a + 1) must precede zone \(b + 1)"))
      }
    }
  }

  /// The numbering is derived from unit rectangles, so frame scale, Margin and Gap cannot change it: the order of the
  /// rendered frames (top edge, then left edge) at several frames and Insets gives the same numbers.
  private func checkInvariance(_ root: SplitNode, seed: UInt64, generator g: inout Generator) {
    let layout = makeLayout(root: root)
    let units = LayoutMath.unitRects(root)
    let numbers = ZoneNumbering.numbers(units)
    for _ in 0..<4 {
      let frame = CGRect(
        x: g.double(-1000...1000), y: g.double(-1000...1000), width: g.double(900...3000),
        height: g.double(700...2000))
      let insets = Insets(margin: g.double(0...12), gap: g.double(0...6))
      let placed = Grid.unrounded(units, layoutRect: frame, insets: insets)
      let byFrame = placed.sorted { a, b in
        abs(a.frame.maxY - b.frame.maxY) > 1e-6 ? a.frame.maxY > b.frame.maxY : a.frame.minX < b.frame.minX
      }
      for (index, item) in byFrame.enumerated() {
        #expect(
          numbers[item.path] == index + 1,
          Comment(
            rawValue: Generator.failureMessage(
              seed: seed, layout: layout, note: "numbers changed with frame \(frame) insets \(insets)")))
      }
    }
  }

  /// Splits a random leaf, or collapses a random sibling pair of leaves back to a leaf.
  private func randomEdit(_ root: SplitNode, generator g: inout Generator) -> SplitNode {
    let paths = LayoutMath.unitRects(root).map(\.path)
    let leaf = g.pick(paths)
    let collapsible = paths.filter { $0.steps.last == false }.map { Array($0.steps.dropLast()) }.filter {
      guard case .split(_, _, .leaf, .leaf)? = node(at: $0[...], in: root) else { return false }
      return true
    }
    if !collapsible.isEmpty && g.bool() {
      return replacing(g.pick(collapsible)[...], in: root, with: .leaf)
    }
    let split = SplitNode.split(axis: g.bool() ? .horizontal : .vertical, ratio: g.double(0.3...0.7), first: .leaf, second: .leaf)
    return replacing(leaf.steps[...], in: root, with: split)
  }
}
