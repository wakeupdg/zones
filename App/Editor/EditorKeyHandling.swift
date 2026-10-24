import AppKit
import ZonesCore
import ZonesLayout

/// Pure key + modifiers to `EditorEvent?` map (AC-139). The window glue calls it from `performKeyEquivalent` and
/// `keyDown`; no state lives here.
enum EditorKeyMap {
  static func event(
    characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, selection: NodePath?
  ) -> EditorEvent? {
    let flags = modifiers.intersection([.command, .shift, .option, .control])
    if let direction = ArrowKey(keyCode: keyCode) {
      // Nudge sign convention: `EditorEngine.nudge` adds `points / extent` to the first child's ratio, so a positive
      // value moves the divider right (side by side) or down (stacked, first = top). Right/Down are therefore +,
      // Left/Up are -. Shift = 10 points, bare = 1 point; any other modifier is not a nudge.
      guard let selection, flags.subtracting(.shift).isEmpty else { return nil }
      let step = flags.contains(.shift) ? 10.0 : 1.0
      return .command(.nudge(selection, points: direction.sign * step))
    }
    let key = characters.lowercased()
    switch (key, flags) {
    case ("h", []): return .command(.split(.horizontal))
    case ("v", []): return .command(.split(.vertical))
    case ("m", []): return .command(.merge)
    case ("z", .command): return .undo
    case ("z", [.command, .shift]): return .redo
    case ("s", .command): return .save
    case ("w", .command): return .cancel
    case ("a", [.command, .shift]): return .assign
    default: return nil
    }
  }
}

/// The four arrow keys by hardware key code (layout independent).
private enum ArrowKey {
  case left, right, down, up

  init?(keyCode: UInt16) {
    switch keyCode {
    case 123: self = .left
    case 124: self = .right
    case 125: self = .down
    case 126: self = .up
    default: return nil
    }
  }

  var sign: Double {
    switch self {
    case .left, .up: -1
    case .right, .down: 1
    }
  }
}
