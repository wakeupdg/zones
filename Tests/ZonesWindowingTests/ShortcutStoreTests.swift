import Foundation
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesWindowing

@Suite struct ShortcutStoreTests {
  static let ctrlOpt: ModifierSet = [.control, .option]

  @Test func defaultsMatchADR() {
    let d = ShortcutRules.defaults
    let expected: [Shortcut] =
      [
        Shortcut(action: .sendToZone(1), chord: Chord(key: .digit(1), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(2), chord: Chord(key: .digit(2), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(3), chord: Chord(key: .digit(3), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(4), chord: Chord(key: .digit(4), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(5), chord: Chord(key: .digit(5), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(6), chord: Chord(key: .digit(6), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(7), chord: Chord(key: .digit(7), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(8), chord: Chord(key: .digit(8), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(9), chord: Chord(key: .digit(9), modifiers: [.control, .option])),
        Shortcut(action: .cycleRight, chord: Chord(key: .arrowRight, modifiers: [.control, .option])),
        Shortcut(action: .cycleLeft, chord: Chord(key: .arrowLeft, modifiers: [.control, .option])),
        Shortcut(action: .restore, chord: Chord(key: .letter("R"), modifiers: [.control, .option])),
        Shortcut(action: .openEditor, chord: Chord(key: .letter("E"), modifiers: [.control, .option])),
        Shortcut(action: .openSettings, chord: Chord(key: .comma, modifiers: [.control, .option])),
      ]
    #expect(d.count == 14)
    #expect(d == expected)
    #expect(d.map { $0.action } == ShortcutAction.allCases)
    #expect(d.allSatisfy { $0.chord != nil })
  }

  @Test func requiresCommandOrControl() {
    #expect(!ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.option])))
    #expect(!ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.shift, .option])))
    #expect(!ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.shift])))
    #expect(!ShortcutRules.validate(Chord(key: .digit(1), modifiers: [])))
    #expect(ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.control, .option])))
    #expect(ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.command])))
    #expect(ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.control])))
    #expect(ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.command, .option])))
  }

  @Test func recorderStateTable() {
    let bound = ShortcutRules.defaults
    func chord(_ key: Key, _ m: ModifierSet) -> Chord { Chord(key: key, modifiers: m) }
    let table: [(Chord, ShortcutAction, RecorderState)] = [
      // Duplicate of another action's chord.
      (chord(.digit(2), Self.ctrlOpt), .sendToZone(1), .conflict(duplicate: .sendToZone(2))),
      (chord(.letter("E"), Self.ctrlOpt), .restore, .conflict(duplicate: .openEditor)),
      // Own chord is never a conflict.
      (chord(.digit(1), Self.ctrlOpt), .sendToZone(1), .accepted),
      // Rejected beats conflict.
      (chord(.digit(1), [.option]), .restore, .rejected),
      (chord(.digit(1), [.shift, .option]), .restore, .rejected),
      (chord(.letter("K"), []), .restore, .rejected),
      // Warnings.
      (chord(.letter("K"), [.command]), .restore, .warning(.commandOnly)),
      (chord(.letter("K"), [.command, .shift]), .restore, .warning(.commandShiftOnly)),
      (chord(.arrowRight, [.control]), .restore, .warning(.controlOnlyWithArrowOrDigit)),
      (chord(.arrowUp, [.control]), .restore, .warning(.controlOnlyWithArrowOrDigit)),
      (chord(.digit(3), [.control]), .restore, .warning(.controlOnlyWithArrowOrDigit)),
      // Accepted.
      (chord(.letter("K"), [.control]), .restore, .accepted),
      (chord(.comma, [.control]), .restore, .accepted),
      (chord(.digit(5), Self.ctrlOpt), .restore, .conflict(duplicate: .sendToZone(5))),
    ]
    for (c, action, expected) in table {
      #expect(ShortcutRules.recorderState(c, for: action, bound: bound) == expected)
    }
    // Control+Option+5 with nothing bound elsewhere is accepted (no warning).
    #expect(ShortcutRules.recorderState(chord(.digit(5), Self.ctrlOpt), for: .sendToZone(5), bound: bound) == .accepted)
    #expect(ShortcutRules.recorderState(chord(.digit(5), Self.ctrlOpt), for: .restore, bound: []) == .accepted)
    // First conflict in array order.
    let dup = [
      Shortcut(action: .cycleLeft, chord: chord(.letter("K"), [.control])),
      Shortcut(action: .cycleRight, chord: chord(.letter("K"), [.control])),
    ]
    #expect(
      ShortcutRules.recorderState(chord(.letter("K"), [.control]), for: .restore, bound: dup)
        == .conflict(duplicate: .cycleLeft))
  }
}
