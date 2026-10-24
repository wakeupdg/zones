import AppKit
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct EditorWindowTests {
  static func display(
    key: String = "D1", frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
    visible: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 875)
  ) -> DisplaySnapshot {
    DisplaySnapshot(
      key: .uuid(key), frame: frame, visibleFrame: visible, scale: 2, isMain: true, mirrorOf: nil,
      name: "Built-in", resolution: CGSize(width: 2880, height: 1800))
  }

  @Test func defaultFrameEqualsVisibleFrame() {
    let snapshot = Self.display()  // visibleFrame is inset by a 25 pt menu bar
    let window = EditorWindowController.makeWindow(display: snapshot)
    #expect(window.frame == WindowPlacement.editorFrame(cursor: snapshot))
    #expect(window.frame == snapshot.visibleFrame)
    #expect(window.styleMask.contains(.resizable))
    #expect(!window.isOpaque)
  }

  // MARK: key map

  private static let cmd: NSEvent.ModifierFlags = .command
  private static let cmdShift: NSEvent.ModifierFlags = [.command, .shift]

  @Test func keyEquivalentsMapToEvents() {
    let table: [(String, NSEvent.ModifierFlags, EditorEvent?)] = [
      ("h", [], .command(.split(.horizontal))),
      ("v", [], .command(.split(.vertical))),
      ("m", [], .command(.merge)),
      ("z", Self.cmd, .undo),
      ("z", Self.cmdShift, .redo),
      ("s", Self.cmd, .save),
      ("w", Self.cmd, .cancel),
      ("a", Self.cmdShift, .assign),
      // Command combos must not fire the bare-letter commands.
      ("h", Self.cmd, nil), ("v", Self.cmd, nil), ("m", Self.cmd, nil),
      ("h", .control, nil), ("h", .option, nil), ("h", .shift, nil),
      // Unmapped.
      ("q", [], nil), ("a", Self.cmd, nil), ("a", [], nil), ("s", [], nil), ("z", [], nil),
      ("w", [], nil), ("w", Self.cmdShift, nil), ("s", Self.cmdShift, nil),
    ]
    for (chars, flags, expected) in table {
      let got = EditorKeyMap.event(characters: chars, keyCode: 0, modifiers: flags, selection: nil)
      #expect(got == expected, "\(chars) \(flags) -> \(String(describing: got))")
    }
    // Caps lock and the device-dependent bits AppKit adds must not break a mapping.
    #expect(
      EditorKeyMap.event(characters: "h", keyCode: 4, modifiers: .capsLock, selection: nil)
        == .command(.split(.horizontal)))
    let commandCaps: NSEvent.ModifierFlags = [.command, .capsLock]
    let saved = EditorKeyMap.event(characters: "S", keyCode: 1, modifiers: commandCaps, selection: nil)
    #expect(saved == .save)
  }
}
