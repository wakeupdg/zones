import AppKit
import Testing
import ZonesWindowing

@testable import Zones

/// AC-023: an accessory app has no main menu, so Settings must close itself on Cmd+W and Escape.
@MainActor
@Suite struct SettingsWindowKeyboardTests {
  private func makeWindow() -> (SettingsWindow, () -> Int) {
    let window = SettingsWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
      styleMask: NSWindow.StyleMask(rawValue: WindowPlacement.settingsStyleMaskRaw),
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    var closes = 0
    let token = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: nil
    ) { _ in MainActor.assumeIsolated { closes += 1 } }
    _ = token
    return (window, { closes })
  }

  private func keyDown(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags, in window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
  }

  @Test func commandWClosesWindow() {
    let (window, closes) = makeWindow()
    let handled = window.performKeyEquivalent(with: keyDown("w", code: 13, flags: .command, in: window))
    #expect(handled)
    #expect(closes() == 1)
  }

  @Test func otherCommandKeysAreNotSwallowed() {
    let (window, closes) = makeWindow()
    #expect(!window.performKeyEquivalent(with: keyDown("w", code: 13, flags: [.command, .shift], in: window)))
    #expect(!window.performKeyEquivalent(with: keyDown("w", code: 13, flags: [], in: window)))
    #expect(!window.performKeyEquivalent(with: keyDown("q", code: 12, flags: .command, in: window)))
    #expect(closes() == 0)
  }

  @Test func escapeClosesWindow() {
    let (window, closes) = makeWindow()
    window.cancelOperation(nil)
    #expect(closes() == 1)
  }
}
