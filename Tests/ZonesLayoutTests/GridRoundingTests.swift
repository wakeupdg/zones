import CoreGraphics
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesLayout

struct GridRoundingTests {
  private let tolerance = 1e-9

  /// True when `value` lies on a multiple of `1 / scale`.
  private func onPixelGrid(_ value: Double, _ scale: Double) -> Bool {
    let scaled = value * scale
    return abs(scaled - scaled.rounded()) < tolerance
  }

  @Test func uniformPixelGapsAndSharedDividers() {
    for scale in [1.0, 2.0, 3.0] {
      for i in 0..<200 {
        check(seed: UInt64(i), scale: scale)
      }
      // Exact half-pixel ties off the centre line: 0.25 of 602 is 150.5, 0.75 of 602 is 451.5.
      let tie = SplitNode.split(axis: .horizontal, ratio: 0.25, first: .leaf, second: .leaf)
      verify(
        root: tie, layoutRect: CGRect(x: 10, y: 20, width: 602, height: 400), insets: Insets(margin: 0, gap: 0),
        scale: scale, seed: 0)
    }
  }

  private func check(seed: UInt64, scale: Double) {
    var g = Generator(seed: seed &+ 7_000_000)
    let root = g.tree(maxDepth: g.int(1...8))
    // Integer origin and size keep the layout rectangle's centre line on the half-pixel lattice, which is what makes
    // an exact reflection possible at every scale.
    let layoutRect = CGRect(
      x: Double(g.int(-500...500)), y: Double(g.int(-500...500)), width: Double(g.int(600...2400)),
      height: Double(g.int(500...1600)))
    let insets = Insets(margin: g.double(0...16), gap: g.double(0...10))
    verify(root: root, layoutRect: layoutRect, insets: insets, scale: scale, seed: seed)
  }

  private func verify(root: SplitNode, layoutRect: CGRect, insets: Insets, scale: Double, seed: UInt64) {
    let layout = makeLayout(root: root, insets: insets)
    func fail(_ note: String) -> Comment {
      Comment(rawValue: Generator.failureMessage(seed: seed, layout: layout, note: "scale \(scale): \(note)"))
    }

    let units = LayoutMath.unitRects(root)
    let frames = Grid.round(units, layoutRect: layoutRect, insets: insets, scale: scale)
    #expect(frames.count == units.count, fail("frame count"))
    let gapPixels = (insets.gap * scale).rounded(.toNearestOrAwayFromZero)
    let gap = gapPixels / scale
    var dividerMidpoints: [String: Set<Int>] = [:]
    let near = { (a: Double, b: Double) in abs(a - b) < 1e-9 }

    for (item, placed) in zip(units, frames) {
      #expect(item.path == placed.path, fail("path order"))
      let u = item.rect
      let f = placed.frame
      if near(u.x, 0) { #expect(onPixelGrid(f.minX, scale), fail("left outer edge off grid")) }
      if near(u.x + u.width, 1) { #expect(onPixelGrid(f.maxX, scale), fail("right outer edge off grid")) }
      if near(u.y, 0) { #expect(onPixelGrid(f.maxY, scale), fail("top outer edge off grid")) }
      if near(u.y + u.height, 1) { #expect(onPixelGrid(f.minY, scale), fail("bottom outer edge off grid")) }
    }
    for (a, fa) in zip(units, frames) {
      for (b, fb) in zip(units, frames) where a.path != b.path {
        let overlapX = min(a.rect.x + a.rect.width, b.rect.x + b.rect.width) - max(a.rect.x, b.rect.x) > tolerance
        let overlapY = min(a.rect.y + a.rect.height, b.rect.y + b.rect.height) - max(a.rect.y, b.rect.y) > tolerance
        if near(a.rect.x + a.rect.width, b.rect.x) && overlapY {
          let separation = fb.frame.minX - fa.frame.maxX
          #expect(near(separation, gap), fail("horizontal gap \(separation) != \(gap)"))
          #expect(near(separation * scale, gapPixels), fail("gap is not whole pixels"))
          let midpoint = (fb.frame.minX + fa.frame.maxX) / 2
          #expect(onPixelGrid(midpoint, scale), fail("horizontal divider off grid"))
          let key = "x\(Int((b.rect.x * 1e6).rounded()))"
          dividerMidpoints[key, default: []].insert(Int((midpoint * scale).rounded()))
        }
        if near(a.rect.y + a.rect.height, b.rect.y) && overlapX {  // a above b; AppKit y is up
          let separation = fa.frame.minY - fb.frame.maxY
          #expect(near(separation, gap), fail("vertical gap \(separation) != \(gap)"))
          let midpoint = (fa.frame.minY + fb.frame.maxY) / 2
          #expect(onPixelGrid(midpoint, scale), fail("vertical divider off grid"))
          let key = "y\(Int((b.rect.y * 1e6).rounded()))"
          dividerMidpoints[key, default: []].insert(Int((midpoint * scale).rounded()))
        }
      }
    }
    for (key, midpoints) in dividerMidpoints {
      #expect(midpoints.count == 1, fail("divider \(key) is not shared: \(midpoints)"))
    }

    // Mirror image: swap children of every horizontal split and flip its ratio.
    let mirrored = mirror(root)
    let mirroredUnits = LayoutMath.unitRects(mirrored.root)
    let mirroredFrames = Grid.round(mirroredUnits, layoutRect: layoutRect, insets: insets, scale: scale)
    let byPath = Dictionary(uniqueKeysWithValues: mirroredFrames.map { ($0.path, $0.frame) })
    for placed in frames {
      guard let twin = byPath[mirrored.mapPath(placed.path)] else {
        Issue.record(fail("mirrored path missing"))
        continue
      }
      #expect(near(twin.minX, 2 * layoutRect.midX - placed.frame.maxX), fail("mirror minX"))
      #expect(near(twin.maxX, 2 * layoutRect.midX - placed.frame.minX), fail("mirror maxX"))
      #expect(near(twin.minY, placed.frame.minY) && near(twin.maxY, placed.frame.maxY), fail("mirror y"))
    }
  }

  /// The tree reflected about the vertical centre line, and how a leaf path maps into it.
  private func mirror(_ root: SplitNode) -> (root: SplitNode, mapPath: (NodePath) -> NodePath) {
    func flip(_ node: SplitNode) -> SplitNode {
      guard case .split(let axis, let ratio, let first, let second) = node else { return node }
      if axis == .horizontal {
        return .split(axis: axis, ratio: 1 - ratio, first: flip(second), second: flip(first))
      }
      return .split(axis: axis, ratio: ratio, first: flip(first), second: flip(second))
    }
    func map(_ steps: ArraySlice<Bool>, in node: SplitNode) -> [Bool] {
      guard let step = steps.first, case .split(let axis, _, let first, let second) = node else { return [] }
      let child = step ? second : first
      return [axis == .horizontal ? !step : step] + map(steps.dropFirst(), in: child)
    }
    return (flip(root), { NodePath(steps: map($0.steps[...], in: root)) })
  }
}
