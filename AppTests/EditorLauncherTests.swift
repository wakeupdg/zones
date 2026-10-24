import AppKit
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

/// The editor's door (AC-126): the menu item and the layout the editor opens on. The hotkey and window glue are
/// manual (AC-126, AC-139).
@MainActor
@Suite struct EditorLauncherTests {
  @Test func editLayoutsMenuItemOpensEditor() throws {
    var opened = 0
    let menu = StatusItemController.makeMenu(
      from: [.header("Display"), .separator, .editLayouts, .settings, .separator, .quit], onGrant: {},
      onEditLayouts: { opened += 1 })
    let item = try #require(menu.items.first { $0.title == "Edit Layouts…" })
    _ = item.target?.perform(item.action, with: item)
    #expect(opened == 1)
  }

  private static func store() -> LayoutStore {
    LayoutStore(document: ZonesDocument(version: Constants.documentVersion), defaults: Insets(margin: 8, gap: 8))
  }

  private static func assignment(_ id: LayoutID) -> Assignment {
    Assignment(
      layout: id, displayName: "Built-in", lastVisibleFrame: .zero, lastScale: 2, lastSeen: nil)
  }

  @Test func opensTheLayoutAssignedToTheCursorDisplay() {
    let store = Self.store()
    let columns = Templates.builtInID(.columns, count: 3)
    let layout = EditorLauncher.layoutToEdit(
      display: EditorWindowTests.display(key: "D1"), store: store, assignments: ["D1": Self.assignment(columns)])
    #expect(layout.id == columns)
  }

  @Test func fallsBackToPriorityGridWhenUnassignedOrDangling() {
    let store = Self.store()
    let grid = Templates.builtInID(.priorityGrid, count: 3)
    #expect(EditorLauncher.layoutToEdit(display: EditorWindowTests.display(key: "D1"), store: store, assignments: [:]).id == grid)
    let dangling = ["D1": Self.assignment(LayoutID(rawValue: "gone"))]
    #expect(
      EditorLauncher.layoutToEdit(display: EditorWindowTests.display(key: "D1"), store: store, assignments: dangling).id
        == grid)
    #expect(EditorLauncher.layoutToEdit(display: nil, store: store, assignments: [:]).id == grid)
  }
}
