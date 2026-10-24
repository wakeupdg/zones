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

  // MARK: Cmd-W with a recorder focused (QA-2.2)

  private func windowWithRecorder() -> (SettingsWindow, RecorderField, () -> Int, () -> [Chord]) {
    let window = SettingsWindow(
      contentRect: NSRect(x: -4000, y: -4000, width: 320, height: 200),
      styleMask: NSWindow.StyleMask(rawValue: WindowPlacement.settingsStyleMaskRaw), backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
    let field = RecorderField(frame: NSRect(x: 10, y: 10, width: 150, height: 24))
    content.addSubview(field)
    window.contentView = content
    var closes = 0
    var chords: [Chord] = []
    field.onChord = { chords.append($0) }
    let token = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: nil
    ) { _ in MainActor.assumeIsolated { closes += 1 } }
    _ = token
    window.makeFirstResponder(field)
    return (window, field, { closes }, { chords })
  }

  private func commandW(in window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
  }

  @Test func cmdWClosesWithIdleRecorderFocused() {
    let (window, field, closes, chords) = windowWithRecorder()
    #expect(window.firstResponder === field)
    #expect(!field.isRecording)
    #expect(window.performKeyEquivalent(with: commandW(in: window)))
    #expect(closes() == 1)
    #expect(chords().isEmpty)
  }

  @Test func cmdWStaysCapturedWhileRecording() {
    let (window, field, closes, chords) = windowWithRecorder()
    #expect(field.accessibilityPerformPress())
    #expect(field.isRecording)
    #expect(window.performKeyEquivalent(with: commandW(in: window)))
    #expect(closes() == 0)
    #expect(chords() == [Chord(key: .letter("W"), modifiers: [.command])])
  }
}
