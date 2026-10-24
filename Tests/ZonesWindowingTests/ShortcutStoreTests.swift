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
}
