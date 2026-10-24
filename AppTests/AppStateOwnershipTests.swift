import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

/// T48: AppState is the one in-memory owner of Layouts and Assignments, so a write by the editor, Settings or the
/// topology driver is visible to the next drag arm, shortcut and menu without a relaunch.
@MainActor
@Suite struct AppStateOwnershipTests {
  static let uuidA = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
  static let uuidB = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"

  /// The editor as the window controller drives it: reducer, router, then `documentChanged` when the document moved.
  @MainActor
  final class EditorRig {
    let root: CompositionRoot
    let sink = EditorWindowTests.RecordingSink()
    let topology = EditorWindowTests.topology()
    private let hooks: EditorStateHooks
    private let router: EditorEffectRouter
    private(set) var model: EditorState
    private(set) var document: ZonesDocument

    init(root: CompositionRoot, layout: Layout = EditorWindowTests.blankLayout(), display: String = AppStateOwnershipTests.uuidA) {
      self.root = root
      hooks = EditorLauncher.hooks(for: root.state)
      let topology = self.topology
      router = EditorEffectRouter(
        store: root.documents, sink: sink, topology: { topology }, upsertLive: hooks.upsertLive)
      document = hooks.loadDocument()
      model = EditorModel.open(layout, display: .uuid(display), topology: topology, assignments: document.assignments)
    }

    func send(_ event: EditorEvent) {
      let (next, effects) = EditorModel.reduce(model, event, context: (topology, document))
      model = next
      let written = router.route(effects, document: document)
      if written != document {
        document = written
        hooks.documentChanged(written)
      }
    }

    /// Select the single Zone, split it once, Save and Assign: the AC-139 loop minus the second split.
    func saveTwoColumnsAndAssign() {
      send(.command(.select(NodePath(steps: []))))
      send(.command(.split(.horizontal)))
      send(.save)
      send(.assign)
    }
  }

  @Test func editorSaveReachesDragContext() {
    let h = Harness()
    let root = h.makeRoot()
    let rig = EditorRig(root: root)
    let before = root.state.resolvedLayouts(for: rig.topology, session: [:])
    #expect(before[.uuid(Self.uuidA)]?.layoutID == Templates.builtInID(.priorityGrid, count: 3))

    rig.saveTwoColumnsAndAssign()

    let id = rig.model.draft.layout.id
    let after = root.state.resolvedLayouts(for: rig.topology, session: [:])
    #expect(root.state.layouts.layout(id) == rig.model.draft.layout)
    #expect(after[.uuid(Self.uuidA)]?.layoutID == id)
    #expect(after[.uuid(Self.uuidA)]?.zones.count == 2)
    #expect(root.state.assignedLayoutID(for: .uuid(Self.uuidA), session: [:]) == id)
  }
}
