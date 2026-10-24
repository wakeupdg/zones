import Foundation
import Testing
import ZonesCore
import ZonesTestSupport

@Test func preferencesDefaultsMatchContract() {
  let p = Preferences.defaults
  #expect(p.schemaVersion == Constants.preferencesSchema)
  #expect(p.schemaVersion == 1)
  #expect(p.activationModifier == .shift)
  #expect(p.spanModifier == .control)
  #expect(p.enhancedUI == .toggle)
  #expect(p.exclusions.isEmpty)
  #expect(p.notices.isEmpty)
  #expect(p.shortcuts == Preferences.defaultShortcuts)
  #expect(p.shortcuts.count == 14)
  #expect(p.shortcuts.allSatisfy { $0.chord?.modifiers == [.control, .option] })
  #expect(p.appearance.fill == RGBA(r: 0.2, g: 0.5, b: 1.0, a: 1.0))
  #expect(p.appearance.opacity == 0.3)
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

@Suite struct PreferencesTests {
  static let pairs: [[Modifier]] = Modifier.allCases.flatMap { a in Modifier.allCases.map { [a, $0] } }

  @Test(arguments: pairs)
  func modifiersMustDiffer(pair: [Modifier]) {
    var input = Preferences.defaults
    input.activationModifier = pair[0]
    input.spanModifier = pair[1]
    input.notices = [.separateSpacesOff]
    let output = input.coerced()

    #expect(output.activationModifier == pair[0])
    #expect(output.spanModifier != output.activationModifier)
    if pair[0] != pair[1] {
      #expect(output == input)
      #expect(!output.notices.contains(.modifiersCoerced))
    } else {
      #expect(output.spanModifier == (pair[0] == .control ? .shift : .control))
      #expect(output.notices == [.separateSpacesOff, .modifiersCoerced])
    }
  }

  static func validPreferences() -> Preferences {
    var p = Preferences.defaults
    p.activationModifier = .option
    p.appearance.opacity = 0.5
    p.exclusions = ["com.example.custom"]
    return p
  }

  static func blob(_ p: Preferences, edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    var object = try #require(
      JSONSerialization.jsonObject(with: PreferencesCodec.encode(p)) as? [String: Any])
    edit(&object)
    return try JSONSerialization.data(withJSONObject: object)
  }

  @Test func fieldByFieldCoercion() throws {
    let input = Self.validPreferences()

    // (d) a clean blob changes nothing.
    let clean = PreferencesCodec.decode(try Self.blob(input))
    #expect(clean.0 == input)
    #expect(clean.coercedFields.isEmpty)
    #expect(clean.0.notices == input.notices)

    // (a) one unknown modifier value: only that field falls back.
    let (a, aFields) = PreferencesCodec.decode(try Self.blob(input) { $0["spanModifier"] = "hyper" })
    var expectedA = input
    expectedA.spanModifier = .control
    expectedA.notices.insert(.preferencesCoerced)
    #expect(a == expectedA)
    #expect(aFields == ["spanModifier"])

    // (b) one chord lacking Command and Control: only that action's chord returns to its default.
    var edited = input
    let index = try #require(edited.shortcuts.firstIndex { $0.action == .openSettings })
    edited.shortcuts[index].chord = Chord(key: .comma, modifiers: [.shift, .option])
    let (b, bFields) = PreferencesCodec.decode(try Self.blob(edited))
    var expectedB = input
    expectedB.notices.insert(.preferencesCoerced)
    #expect(b == expectedB)
    #expect(bFields == ["shortcuts.openSettings"])
    #expect(b.shortcuts.filter { $0.action != .openSettings } == input.shortcuts.filter { $0.action != .openSettings })

    // (c) not a JSON object: defaults.
    let (c, cFields) = PreferencesCodec.decode(Data("[1,2,3]".utf8))
    #expect(c == Preferences.defaults)
    #expect(cFields == ["*"])
    let (garbage, garbageFields) = PreferencesCodec.decode(Data([0xFF, 0x00]))
    #expect(garbage == Preferences.defaults && garbageFields == ["*"])
  }

  @Test func appearanceRoundTrip() throws {
    var generator = Generator(seed: 0xA11CE)
    for _ in 0..<200 {
      var p = Preferences.defaults
      p.appearance = Appearance(
        fill: RGBA(
          r: generator.double(0...1), g: generator.double(0...1), b: generator.double(0...1),
          a: generator.double(0...1)),
        opacity: generator.double(0...1),
        defaultInsets: Insets(margin: generator.double(0...64), gap: generator.double(0...64)))
      let (back, fields) = PreferencesCodec.decode(PreferencesCodec.encode(p))
      #expect(back == p)
      #expect(fields.isEmpty)
      #expect(PreferencesCodec.encode(back) == PreferencesCodec.encode(p))
    }

    for bad in [1.5, -0.1, Double.nan, Double.infinity, -Double.infinity] {
      var p = Self.validPreferences()
      p.appearance.opacity = bad
      let (back, fields) = PreferencesCodec.decode(PreferencesCodec.encode(p))
      var expected = p
      expected.appearance.opacity = Preferences.defaults.appearance.opacity
      expected.notices.insert(.preferencesCoerced)
      #expect(back == expected, "opacity \(bad)")
      #expect(fields == ["appearance.opacity"], "opacity \(bad)")
    }
  }
}
