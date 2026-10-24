import AppKit
import SwiftUI
import ZonesCore
import ZonesWindowing

/// Adopted by a first responder that wants every key, Command chords included, before the window's own
/// key equivalents (Cmd+W closes Settings otherwise).
@MainActor
protocol KeyCapturing: AnyObject {}

/// The recorder: click it, press a chord, and `onChord` receives it. Escape or clicking away stops recording.
/// Building a `Chord` needs a mapped key; keys Zones cannot bind are ignored. Validation (Command or Control,
/// conflicts, warnings) is `ShortcutRules.recorderState`, applied by the model, not here.
struct ChordRecorderView: NSViewRepresentable {
  let chord: Chord?
  let accessibilityName: String
  let onChord: (Chord) -> Void

  func makeNSView(context: Context) -> RecorderField {
    let field = RecorderField()
    field.onChord = onChord
    return field
  }

  func updateNSView(_ field: RecorderField, context: Context) {
    field.onChord = onChord
    field.chord = chord
    field.setAccessibilityLabel("Shortcut for \(accessibilityName)")
  }
}

final class RecorderField: NSView, KeyCapturing {
  var onChord: ((Chord) -> Void)?
  var chord: Chord? {
    didSet { if chord != oldValue { needsDisplay = true } }
  }
  private var recording = false {
    didSet { needsDisplay = true }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    setAccessibilityRole(.button)
    focusRingType = .default
  }

  override var acceptsFirstResponder: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
  override var needsPanelToBecomeKey: Bool { true }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    recording = true
  }

  override func becomeFirstResponder() -> Bool {
    recording = true
    return true
  }

  override func resignFirstResponder() -> Bool {
    recording = false
    return true
  }

  override func keyDown(with event: NSEvent) { capture(event) }

  /// Command chords arrive here first; take them while recording so the window does not act on them.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard recording, window?.firstResponder === self else { return false }
    capture(event)
    return true
  }

  private func capture(_ event: NSEvent) {
    if event.keyCode == 53 {  // Escape stops recording
      recording = false
      window?.makeFirstResponder(nil)
      return
    }
    guard let key = RecorderKeyMap.key(forKeyCode: event.keyCode) else {
      NSSound.beep()
      return
    }
    let modifiers = RecorderKeyMap.modifiers(rawFlags: UInt64(event.modifierFlags.rawValue))
    recording = false
    window?.makeFirstResponder(nil)
    onChord?(Chord(key: key, modifiers: modifiers))
  }

  override func draw(_ dirtyRect: NSRect) {
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
    NSColor.controlBackgroundColor.setFill()
    path.fill()
    (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
    path.lineWidth = recording ? 2 : 1
    path.stroke()
    let text: String
    let color: NSColor
    if recording {
      text = "Type shortcut"
      color = .secondaryLabelColor
    } else if let chord {
      text = ShortcutsFlow.text(for: chord)
      color = .labelColor
    } else {
      text = "Not set"
      color = .tertiaryLabelColor
    }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: color,
    ]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(
      at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    setAccessibilityValue(text)
  }
}
