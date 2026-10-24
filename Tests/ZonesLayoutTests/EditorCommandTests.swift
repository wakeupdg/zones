import CoreGraphics
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesLayout

private let geometry = (visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 2.0)
private let zeroInsets = Insets(margin: 0, gap: 0)
private let zeroSurround = Surround(top: 0, left: 0, bottom: 0, right: 0)

private func draft(_ root: SplitNode = .leaf, selection: NodePath? = NodePath(steps: []), name: String = "My Layout")
  -> EditorDraft
{
  EditorDraft(
    layout: Layout(
      id: LayoutID(rawValue: "L1"), name: name, root: root, surround: zeroSurround, insets: zeroInsets),
    selection: selection, dirty: false)
}

private func run(_ c: EditorCommand, _ d: EditorDraft) -> Result<EditorDraft, EditorError> {
  EditorEngine.apply(c, to: d, geometry: geometry)
}

struct EditorCommandTests {
  @Test func splitKeys() throws {
    let start = draft()
    let h = try run(.split(.horizontal), start).get()
    #expect(h.layout.root == .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf))
    #expect(leafCount(h.layout.root) == 2)
    #expect(h.selection == NodePath(steps: [false]))
    #expect(h.dirty)
    let v = try run(.split(.vertical), h).get()
    #expect(leafCount(v.layout.root) == 3)
    #expect(
      v.layout.root
        == .split(
          axis: .horizontal, ratio: 0.5,
          first: .split(axis: .vertical, ratio: 0.5, first: .leaf, second: .leaf), second: .leaf))
    let none = draft(selection: nil)
    #expect(run(.split(.horizontal), none) == .failure(.nothingSelected))
    // a selected divider (split node) is not a Zone
    #expect(run(.split(.vertical), h.withSelection(NodePath(steps: []))) == .failure(.nothingSelected))
  }

  @Test func mergeSiblingsOnly() throws {
    let hint = "split the parent the other way first"
    // two leaf siblings collapse the parent
    let pair = draft(.split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf))
    let selB = try run(.select(NodePath(steps: [true])), pair).get()
    #expect(selB.selection == NodePath(steps: [true]))
    #expect(!selB.dirty)
    let merged = try run(.merge, selB).get()
    #expect(merged.layout.root == .leaf)
    #expect(merged.selection == NodePath(steps: []))
    #expect(merged.dirty)
    // A | (B / C): merging A is refused and nothing changes
    let tree = SplitNode.split(
      axis: .horizontal, ratio: 0.5, first: .leaf,
      second: .split(axis: .vertical, ratio: 0.5, first: .leaf, second: .leaf))
    let a = try run(.select(NodePath(steps: [false])), draft(tree)).get()
    #expect(run(.merge, a) == .failure(.notSiblings(hint: hint)))
    // merging B (sibling C is a leaf) works inside the nested split
    let b = try run(.select(NodePath(steps: [true, false])), draft(tree)).get()
    let mergedBC = try run(.merge, b).get()
    #expect(
      mergedBC.layout.root == .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf))
    #expect(mergedBC.selection == NodePath(steps: [true]))
    // a selected divider is not a Zone; a missing path is nothingSelected
    #expect(run(.merge, selB.withSelection(NodePath(steps: []))) == .failure(.nothingSelected))
    #expect(run(.select(NodePath(steps: [true, true])), pair) == .failure(.nothingSelected))
    #expect(run(.merge, draft(selection: nil)) == .failure(.nothingSelected))
    let cleared = try run(.select(nil), selB).get()
    #expect(cleared.selection == nil)
  }

  @Test func noChordBadgeAndRootMerge() throws {
    var d = draft()
    while LayoutMath.unitRects(d.layout.root).count < 10 {
      // split the largest Zone along its longer side so every split stays valid
      let biggest = LayoutMath.unitRects(d.layout.root).max { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }!
      d.selection = biggest.path
      d = try run(.split(biggest.rect.width >= biggest.rect.height ? .horizontal : .vertical), d).get()
    }
    let resolved = LayoutMath.resolve(
      d.layout, key: .uuid("D1"), visibleFrame: geometry.visibleFrame, scale: geometry.scale)
    #expect(resolved.zones.count == 10)
    let labels = LabelModel.labels(resolved, appearance: Preferences.defaults.appearance)
    #expect(labels.count == 10)
    for label in labels { #expect(label.noChord == (label.number == 10), "zone \(label.number)") }
    // the tenth split was accepted, not refused
    #expect(d.dirty)
    // merging the root leaf is refused and leaves the draft alone
    let single = draft()
    #expect(run(.merge, single) == .failure(.rootMerge))
  }

  @Test func minimumFractionAndWarning() throws {
    let two = draft(.split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf))
    let root = NodePath(steps: [])
    #expect(run(.setRatio(root, 0.05, snap: false), two) == .failure(.tooSmall))
    #expect(run(.setRatio(root, 0.95, snap: false), two) == .failure(.tooSmall))
    let edge = try run(.setRatio(root, 1.0 / 12, snap: false), two).get()
    #expect(edge.dirty)
    #expect(edge.layout.root == .split(axis: .horizontal, ratio: 1.0 / 12, first: .leaf, second: .leaf))
    // out of range or not a divider
    #expect(run(.setRatio(root, 0, snap: false), two) == .failure(.invalidRatio))
    #expect(run(.setRatio(root, 1.5, snap: false), two) == .failure(.invalidRatio))
    #expect(run(.setRatio(root, .nan, snap: false), two) == .failure(.invalidRatio))
    #expect(run(.setRatio(NodePath(steps: [true]), 0.5, snap: false), two) == .failure(.invalidRatio))
    // a nested ratio is judged against the leaf's share of the whole unit square
    let nested = draft(
      .split(
        axis: .horizontal, ratio: 0.5, first: .leaf,
        second: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf)))
    #expect(run(.setRatio(NodePath(steps: [true]), 0.1, snap: false), nested) == .failure(.tooSmall))
    #expect(throws: Never.self) { try run(.setRatio(NodePath(steps: [true]), 0.2, snap: false), nested).get() }

    func resolved(_ t: Template, _ count: Int, _ frame: CGRect) -> ResolvedLayout {
      let layout = Templates.generate(t, count: count, insets: zeroInsets)
      return LayoutMath.resolve(layout, key: .uuid("D1"), visibleFrame: frame, scale: 1)
    }
    #expect(
      EditorEngine.warnings(resolved(.grid, 9, CGRect(x: 0, y: 0, width: 300, height: 200)))
        == Set(1...9))
    #expect(EditorEngine.warnings(resolved(.grid, 4, CGRect(x: 0, y: 0, width: 1920, height: 1080))).isEmpty)
    #expect(EditorEngine.warnings(resolved(.columns, 2, CGRect(x: 0, y: 0, width: 240, height: 80))).isEmpty)
    #expect(EditorEngine.warnings(resolved(.columns, 2, CGRect(x: 0, y: 0, width: 238, height: 80))) == Set(1...2))
    #expect(EditorEngine.warnings(resolved(.rows, 2, CGRect(x: 0, y: 0, width: 120, height: 158))) == Set(1...2))
  }

  @Test func dividerSnapAndNudge() throws {
    let geo = (visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), scale: 2.0)
    func ratio(_ r: Result<EditorDraft, EditorError>, at steps: [Bool] = []) throws -> Double {
      guard case .split(_, let value, _, _)? = EditorEngine.node(at: steps[...], in: try r.get().layout.root) else {
        Issue.record("no split at \(steps)")
        return .nan
      }
      return value
    }
    func apply(_ c: EditorCommand, _ d: EditorDraft) -> Result<EditorDraft, EditorError> {
      EditorEngine.apply(c, to: d, geometry: geo)
    }
    let root = NodePath(steps: [])
    let h = draft(.split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf))
    let v = draft(.split(axis: .vertical, ratio: 0.5, first: .leaf, second: .leaf))
    // pure function
    #expect(EditorEngine.snappedRatio(0.504, candidates: [0.5], parentExtentPoints: 1000) == 0.5)
    #expect(EditorEngine.snappedRatio(0.505, candidates: [0.5], parentExtentPoints: 1000) == 0.5)  // 5 pt
    #expect(EditorEngine.snappedRatio(0.507, candidates: [0.5], parentExtentPoints: 1000) == 0.507)  // 7 pt
    #expect(EditorEngine.snappedRatio(0.3, candidates: [], parentExtentPoints: 1000) == 0.3)
    #expect(EditorEngine.snappedRatio(0.526, candidates: [0.5, 0.53], parentExtentPoints: 1000) == 0.53)
    // 1/2, 1/3 (and 1/4) with snap on; untouched with snap off
    #expect(try ratio(apply(.setRatio(root, 0.504, snap: true), h)) == 0.5)
    #expect(try ratio(apply(.setRatio(root, 0.336, snap: true), h)) == 1.0 / 3)
    #expect(try ratio(apply(.setRatio(root, 0.252, snap: true), h)) == 0.25)
    #expect(try ratio(apply(.setRatio(root, 0.504, snap: false), h)) == 0.504)
    #expect(try ratio(apply(.setRatio(root, 0.336, snap: false), h)) == 0.336)
    // 0.58 is 80 pt from 0.5 on a 1000 pt axis: no snap
    #expect(try ratio(apply(.setRatio(root, 0.58, snap: true), h)) == 0.58)
    // a vertical divider measures against the 800 pt height: 0.34 is 5.3 pt from 1/3
    #expect(try ratio(apply(.setRatio(root, 0.34, snap: true), v)) == 1.0 / 3)
    // the horizontal axis is 1000 pt: the same 0.34 is 6.7 pt away and stays
    #expect(try ratio(apply(.setRatio(root, 0.34, snap: true), h)) == 0.34)
    // a collinear same-axis divider in another branch attracts (0.6 is not a fixed candidate)
    let grid = draft(
      .split(
        axis: .vertical, ratio: 0.5,
        first: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf),
        second: .split(axis: .horizontal, ratio: 0.6, first: .leaf, second: .leaf)))
    let top = NodePath(steps: [false])
    #expect(try ratio(apply(.setRatio(top, 0.603, snap: true), grid), at: [false]) == 0.6)
    #expect(try ratio(apply(.setRatio(top, 0.603, snap: false), grid), at: [false]) == 0.603)
    #expect(try ratio(apply(.setRatio(top, 0.62, snap: true), grid), at: [false]) == 0.62)
    // nudge: points / parent extent, no snapping
    let up = apply(.nudge(root, points: 10), h)
    #expect(abs(try ratio(up) - 0.51) < 1e-12)
    #expect(try up.get().dirty)
    #expect(abs(try ratio(apply(.nudge(root, points: 1), h)) - 0.501) < 1e-12)
    #expect(abs(try ratio(apply(.nudge(root, points: -10), try up.get())) - 0.5) < 1e-12)
    // nested divider: its parent extent is the node's share of the Layout rectangle
    let nested = draft(
      .split(
        axis: .horizontal, ratio: 0.5, first: .leaf,
        second: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf)))
    #expect(abs(try ratio(apply(.nudge(NodePath(steps: [true]), points: 10), nested), at: [true]) - 0.52) < 1e-12)
    // surround shrinks the Layout rectangle
    var inset = h
    inset.layout.surround = Surround(top: 0, left: 0.2, bottom: 0, right: 0.2)  // 600 pt wide
    #expect(abs(try ratio(apply(.nudge(root, points: 6), inset)) - 0.51) < 1e-12)
    // a leaf or a missing node cannot be nudged
    #expect(apply(.nudge(NodePath(steps: [true]), points: 1), h) == .failure(.invalidRatio))
    #expect(apply(.nudge(root, points: 450), h) == .failure(.tooSmall))
    #expect(apply(.nudge(root, points: 500), h) == .failure(.invalidRatio))
    #expect(apply(.nudge(root, points: .nan), h) == .failure(.invalidRatio))
  }
}

extension EditorDraft {
  fileprivate func withSelection(_ p: NodePath?) -> EditorDraft {
    var d = self
    d.selection = p
    return d
  }
}
