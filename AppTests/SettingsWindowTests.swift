import AppKit
import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

/// QA-2.0: the production Settings window shows every pane tab in its toolbar, none in the overflow.
@MainActor
@Suite struct SettingsWindowTests {
  private func controller(defaults: UserDefaults) -> SettingsWindowController {
    let preferences = PreferencesController(defaults: defaults)
    let documents = DocumentStore(fs: FakeFileSystem(), directory: URL(fileURLWithPath: "/zones-t47"), clock: FakeClock())
    let flow = LayoutsFlow(
      documents: documents, layouts: ZonesDocument(layouts: []), assignments: [:], defaults: Insets(margin: 8, gap: 8))
    let layouts = ImportExportController(flow: flow, fs: FakeFileSystem(), panels: .none)
    let environment = SettingsEnvironment(
      preferences: preferences, layouts: layouts,
      shortcuts: ShortcutsModel(preferences: preferences, registrar: nil, granted: true),
      exclusions: ExclusionsModel(preferences: preferences), topology: { nil })
    return SettingsWindowController(
      topology: { nil }, cursor: { .zero }, permission: { .notGranted }, tap: { .dead }, environment: environment,
      onRerunOnboarding: {}, loginItems: FakeLoginItemService(clock: FakeClock()))
  }

  private func spin(_ seconds: TimeInterval = 0.8) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

  /// The toolbar's tab bar is visible when it is among `visibleItems` with a real frame.
  private func tabBarIsVisible(_ window: NSWindow) -> (visible: Bool, detail: String) {
    guard let toolbar = window.toolbar else { return (false, "no toolbar") }
    let visible = toolbar.visibleItems ?? []
    let tabBar = toolbar.items.first { $0.itemIdentifier.rawValue.contains("Tab") || ($0.view?.frame.width ?? 0) > 100 }
    let frame = tabBar?.view?.frame ?? .zero
    let ok = tabBar.map { item in visible.contains { $0 === item } } == true && frame.width > 0
    return (ok, "items=\(toolbar.items.map(\.itemIdentifier.rawValue)) visible=\(visible.map(\.itemIdentifier.rawValue)) frame=\(frame)")
  }

  @Test func allTabsVisibleAtDefaultAndMinimumWidth() {
    let isolated = IsolatedDefaults()
    defer { isolated.tearDown() }
    let window = controller(defaults: isolated.defaults).makeWindow()
    defer { window.close() }
    window.setFrameOrigin(NSPoint(x: 100, y: 100))
    window.orderFrontRegardless()
    spin()
    let atDefault = tabBarIsVisible(window)
    #expect(atDefault.visible, "default \(window.contentLayoutRect.width): \(atDefault.detail)")

    window.setContentSize(window.contentMinSize)
    spin()
    let atMinimum = tabBarIsVisible(window)
    #expect(atMinimum.visible, "minimum \(window.contentLayoutRect.width): \(atMinimum.detail)")
  }
}
