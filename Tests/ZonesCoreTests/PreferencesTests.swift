import Foundation
import Testing
import ZonesCore

@Test func preferencesDefaultsMatchContract() {
  let p = Preferences.defaults
  #expect(p.schemaVersion == Constants.preferencesSchema)
  #expect(p.schemaVersion == 1)
  #expect(p.activationModifier == .shift)
  #expect(p.spanModifier == .control)
  #expect(p.enhancedUI == .toggle)
  #expect(p.exclusions.isEmpty)
  #expect(p.notices.isEmpty)
  #expect(p.shortcuts.isEmpty)  // shortcut ticket sets ShortcutRules.defaults
  #expect(p.appearance.fill == RGBA(r: 0.0, g: 0.478, b: 1.0, a: 1.0))
  #expect(p.appearance.opacity == 0.35)
  #expect(p.appearance.defaultInsets == Insets(margin: 8, gap: 8))
}

@Test func preferencesJSONRoundTrip() throws {
  var p = Preferences.defaults
  p.activationModifier = .option
  p.exclusions = ["com.apple.finder", "com.example.app"]
  p.notices = [.modifiersCoerced]
  p.enhancedUI = .leave
  p.shortcuts = [
    Shortcut(
      action: .sendToZone(3), chord: Chord(key: .digit(3), modifiers: [.control, .option])),
    Shortcut(action: .openSettings, chord: nil),
  ]
  let data = try JSONEncoder().encode(p)
  let back = try JSONDecoder().decode(Preferences.self, from: data)
  #expect(back == p)
}

@Test func shortcutActionAllCasesIsFourteenInOrder() {
  let expected: [ShortcutAction] =
    (1...9).map { .sendToZone($0) } + [.cycleRight, .cycleLeft, .restore, .openEditor, .openSettings]
  #expect(ShortcutAction.allCases.count == 14)
  #expect(ShortcutAction.allCases == expected)
}

@Test func isWindowActionTrueForFirstFour() {
  let flags = ShortcutAction.allCases.map(\.isWindowAction)
  #expect(flags.prefix(9).allSatisfy { $0 })  // sendToZone(1...9)
  #expect(ShortcutAction.cycleRight.isWindowAction)
  #expect(ShortcutAction.cycleLeft.isWindowAction)
  #expect(ShortcutAction.restore.isWindowAction)
  #expect(!ShortcutAction.openEditor.isWindowAction)
  #expect(!ShortcutAction.openSettings.isWindowAction)
  #expect(ShortcutAction.allCases.filter(\.isWindowAction).count == 12)
}

@Test func chordCommandOrControlIsComputed() throws {
  #expect(Chord(key: .comma, modifiers: [.command]).hasCommandOrControl)
  #expect(Chord(key: .comma, modifiers: [.control, .shift]).hasCommandOrControl)
  #expect(!Chord(key: .comma, modifiers: [.shift, .option]).hasCommandOrControl)

  let chord = Chord(key: .arrowLeft, modifiers: [.command])
  let object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(chord)) as? [String: Any])
  #expect(object["hasCommandOrControl"] == nil)
  #expect(Set(object.keys) == ["key", "modifiers"])
  #expect(try JSONDecoder().decode(Chord.self, from: JSONEncoder().encode(chord)) == chord)
}
