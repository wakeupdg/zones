import AppKit
import SwiftUI
import ZonesCore
import ZonesWindowing

/// Adopted by a first responder that wants every key, Command chords included, before the window's own
/// key equivalents (Cmd+W closes Settings otherwise).
@MainActor
protocol KeyCapturing: AnyObject {}

/// The recorder: click it (or focus it and press Space or Return), press a chord, and `onChord` receives it.
/// Tab and Shift-Tab always move focus on; Escape or clicking away stops recording.
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

  /// Focus arrival does not arm the recorder (that traps keyboard users); Space or Return, a click, or the
  /// accessibility press does.
  override func resignFirstResponder() -> Bool {
    recording = false
    return true
  }

  override func accessibilityPerformPress() -> Bool {
    window?.makeFirstResponder(self)
    recording = true
    return true
  }

  override func keyDown(with event: NSEvent) {
    if !handle(event) { super.keyDown(with: event) }
  }

  /// Command chords arrive here first; take them while recording so the window does not act on them.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard recording, window?.firstResponder === self else { return false }
    return handle(event)
  }

  /// Returns false when the key should go up the responder chain.
  private func handle(_ event: NSEvent) -> Bool {
    let flags = UInt64(event.modifierFlags.rawValue)
    switch RecorderKeyMap.disposition(keyCode: event.keyCode, rawFlags: flags, recording: recording) {
    case .startRecording:
      recording = true
    case .stopRecording:
      recording = false
    case .moveFocus(let forward):
      recording = false
      if forward { window?.selectNextKeyView(self) } else { window?.selectPreviousKeyView(self) }
    case .capture(let chord):
      recording = false
      onChord?(chord)
    case .reject:
      NSSound.beep()
    case .passThrough:
      return false
    }
    return true
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
