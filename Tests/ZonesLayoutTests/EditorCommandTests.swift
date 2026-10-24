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
}

extension EditorDraft {
  fileprivate func withSelection(_ p: NodePath?) -> EditorDraft {
    var d = self
    d.selection = p
    return d
  }
}
