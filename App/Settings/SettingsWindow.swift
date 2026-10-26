import AppKit

/// The Settings window. The app is an accessory app with no main menu, so nothing supplies a File > Close item:
/// the window handles Cmd+W and Escape itself so a keyboard-only user can dismiss it (AC-023, HIG).
final class SettingsWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    // A shortcut recorder owns every key while it records, Cmd+W included; idle, the window keeps Cmd+W.
    if (firstResponder as? KeyCapturing)?.isRecording == true { return super.performKeyEquivalent(with: event) }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
    if event.type == .keyDown, flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
      performClose(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  /// Escape, when no field or popup in the responder chain consumed it.
  override func cancelOperation(_ sender: Any?) {
    performClose(sender)
  }
}
