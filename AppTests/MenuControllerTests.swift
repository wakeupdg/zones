import AppKit
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing
import os

@testable import Zones

@MainActor
@Suite struct MenuControllerTests {
  private func controller(
    _ h: Harness, root: CompositionRoot, builds: OSAllocatedUnfairLock<Int>, cursor: CGPoint
  ) -> MenuController {
    MenuController(
      appState: root.state, topology: root.topology, permission: root.permission, ui: h.adapters.ui,
      frontmost: { h.frontmost.withLock { $0 } }, cursor: { cursor },
      builder: { display, assignment, store, front, exclusions, permission in
        builds.withLock { $0 += 1 }
        return MenuModel.build(
          cursorDisplay: display, assignment: assignment, store: store, frontmost: front, exclusions: exclusions,
          permission: permission)
      })
  }

  @Test func rebuiltOnEveryOpen() {
    let h = Harness()
    let root = h.makeRoot()
    h.displays.enqueue(.snapshot(Fixtures.threeDisplays))
    root.topology.forceSnapshot()
    let builds = OSAllocatedUnfairLock(initialState: 0)
    let menu = controller(h, root: root, builds: builds, cursor: CGPoint(x: 500, y: 500))

    h.frontmost.withLock { $0 = (name: "Editor", bundleID: "com.example.editor") }
    menu.menuNeedsUpdate(menu.menu)
    #expect(builds.withLock { $0 } == 1)
    let firstTitles = menu.menu.items.map(\.title)
    #expect(firstTitles.contains("Never Snap Editor"))
    #expect(menu.menu.items.last?.title == "Quit Zones")
    let exclude = menu.menu.items.first { $0.title == "Never Snap Editor" }
    #expect(exclude?.state == .off)

    // State changes between opens: the second open reflects it, with a second build.
    root.state.toggleExclusion("com.example.editor")
    h.frontmost.withLock { $0 = (name: "Browser", bundleID: "com.example.browser") }
    menu.menuNeedsUpdate(menu.menu)
    #expect(builds.withLock { $0 } == 2)
    #expect(menu.menu.items.map(\.title).contains("Never Snap Browser"))
    #expect(!menu.menu.items.map(\.title).contains("Never Snap Editor"))

    // Zero actor calls: the window system was never touched (AC-017).
    #expect(h.windows.calls.isEmpty)
    #expect(h.enumerator.calls.isEmpty)
  }

  @Test func assignedLayoutIsCheckedAndPickAssigns() {
    let h = Harness()
    let root = h.makeRoot()
    h.displays.enqueue(.snapshot(Fixtures.threeDisplays))
    root.topology.forceSnapshot()
    let builds = OSAllocatedUnfairLock(initialState: 0)
    // The cursor is on the 2x Display.
    let menu = controller(h, root: root, builds: builds, cursor: CGPoint(x: -700, y: 400))
    menu.menuNeedsUpdate(menu.menu)
    let checked = menu.menu.items.filter { $0.state == .on && $0.representedObject is String }
    #expect(checked.count == 1)
    #expect(checked.first?.representedObject as? String == Templates.builtInID(.priorityGrid, count: 3).rawValue)

    let target = Templates.builtInID(.columns, count: 3)
    let item = menu.menu.items.first { ($0.representedObject as? String) == target.rawValue }
    #expect(item != nil)
    if let item { menu.pickLayout(item) }
    let key = Fixtures.threeDisplays.displays[1].key
    #expect(root.state.assignedLayoutID(for: key, session: [:]) == target)
  }

  @Test func grantItemFollowsPermission() {
    let h = Harness()
    let root = h.makeRoot()
    let builds = OSAllocatedUnfairLock(initialState: 0)
    let menu = controller(h, root: root, builds: builds, cursor: .zero)
    menu.menuNeedsUpdate(menu.menu)
    #expect(menu.menu.items.map(\.title).contains("Grant Accessibility…"))  // notGranted at start
    root.permission.receive(.probe(true))
    menu.menuNeedsUpdate(menu.menu)
    #expect(!menu.menu.items.map(\.title).contains("Grant Accessibility…"))
  }

  @Test func grantItemRoutesToTheOnboardingAction() {
    let h = Harness()
    let root = h.makeRoot()
    let builds = OSAllocatedUnfairLock(initialState: 0)
    let menu = controller(h, root: root, builds: builds, cursor: .zero)
    menu.grantAccessibility()
    #expect(h.uiLog.withLock { $0 }.contains("grant"))
    #expect(h.probe.calls.isEmpty)
  }
}
