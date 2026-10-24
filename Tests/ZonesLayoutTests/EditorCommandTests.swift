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
}

extension EditorDraft {
  fileprivate func withSelection(_ p: NodePath?) -> EditorDraft {
    var d = self
    d.selection = p
    return d
  }
}
