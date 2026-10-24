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
