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

  @Test func topologyPersistKeepsEditorAssignment() throws {
    let h = Harness()
    let root = h.makeRoot()
    h.displays.enqueue(.snapshot(EditorWindowTests.topology()))
    root.topology.forceSnapshot()
    let rig = EditorRig(root: root)
    rig.saveTwoColumnsAndAssign()
    let custom = rig.model.draft.layout.id

    // A status-menu pick for Display B persists through the topology driver.
    let columns = Templates.builtInID(.columns, count: 3)
    root.topology.pick(columns, for: .uuid(Self.uuidB))

    let onDisk = try JSONDecoder().decode(
      ZonesDocument.self, from: h.files.read(URL(filePath: "/zones-support/assignments.json")))
    #expect(onDisk.assignments[Self.uuidA]?.layout == custom)
    #expect(onDisk.assignments[Self.uuidB]?.layout == columns)
    #expect(root.state.assignments.mapValues(\.layout) == onDisk.assignments.mapValues(\.layout))
  }

  // MARK: Settings > Layouts

  private static let importURL = URL(filePath: "/import/layouts.json")

  /// A Settings controller built as production builds it (its own flow over the root's documents), bound to the
  /// root's state; its panel "chooses" a file already placed in the fake file system.
  private func settingsController(_ h: Harness, root: CompositionRoot, importing document: ZonesDocument?)
    throws -> ImportExportController
  {
    if let document { try h.files.writeAtomic(document.encoded(for: nil), to: Self.importURL) }
    let flow = LayoutsFlow(
      documents: root.documents, layouts: root.state.document, assignments: root.state.assignments,
      defaults: root.state.preferences.appearance.defaultInsets)
    let controller = ImportExportController(
      flow: flow, fs: h.files,
      panels: FilePanels(chooseImport: { Self.importURL }, chooseExport: { _ in nil }),
      now: { 1_000 })
    controller.bind(to: root.state)
    return controller
  }

  private static func imported(_ id: String, name: String) -> Layout {
    var layout = EditorWindowTests.blankLayout()
    layout.id = LayoutID(rawValue: id)
    layout.name = name
    return layout
  }

  private func menuLayoutIDs(_ root: CompositionRoot) -> [LayoutID] {
    root.menu.rebuild().compactMap { if case .layout(let id, _, _) = $0 { id } else { nil } }
  }

  @Test func settingsImportReachesMenu() throws {
    let h = Harness()
    let root = h.makeRoot()
    h.displays.enqueue(.snapshot(EditorWindowTests.topology()))
    root.topology.forceSnapshot()
    let importedID = LayoutID(rawValue: "22222222-2222-4222-8222-222222222222")
    #expect(!menuLayoutIDs(root).contains(importedID))

    let file = ZonesDocument(
      version: Constants.documentVersion, layouts: [Self.imported(importedID.rawValue, name: "Imported")],
      assignments: [:])
    let controller = try settingsController(h, root: root, importing: file)
    controller.startImport()
    controller.applyImport(.replace)

    #expect(controller.flow.importError == nil)
    #expect(root.state.layouts.layout(importedID)?.name == "Imported")
    #expect(menuLayoutIDs(root).contains(importedID))
  }

  @Test func settingsMergeKeepsAnEditorSavedLayout() throws {
    let h = Harness()
    let root = h.makeRoot()
    // Settings builds its flow first; the editor then saves and assigns a Layout it has never seen.
    let importedID = LayoutID(rawValue: "22222222-2222-4222-8222-222222222222")
    let file = ZonesDocument(
      version: Constants.documentVersion, layouts: [Self.imported(importedID.rawValue, name: "Imported")],
      assignments: [:])
    let controller = try settingsController(h, root: root, importing: file)
    let rig = EditorRig(root: root)
    rig.saveTwoColumnsAndAssign()
    let editorID = rig.model.draft.layout.id

    controller.startImport()
    controller.applyImport(.merge)

    #expect(root.state.layouts.layout(editorID) != nil)
    #expect(root.state.layouts.layout(importedID) != nil)
    #expect(root.state.assignments[Self.uuidA]?.layout == editorID)
    let onDisk = try JSONDecoder().decode(
      ZonesDocument.self, from: h.files.read(URL(filePath: "/zones-support/layouts.json")))
    #expect(Set(onDisk.layouts.map(\.id)) == [editorID, importedID])
    let assignments = try JSONDecoder().decode(
      ZonesDocument.self, from: h.files.read(URL(filePath: "/zones-support/assignments.json")))
    #expect(assignments.assignments[Self.uuidA]?.layout == editorID)
  }
}
