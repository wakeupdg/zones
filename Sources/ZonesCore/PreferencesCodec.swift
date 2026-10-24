import Foundation

/// UserDefaults key "zones.preferences" holds the JSON blob. Decoding never fails: every field is read on its
/// own, and a field that is present but invalid falls back to its default alone (AC-153).
public enum PreferencesCodec {
  /// Returns the preferences and the names of the fields that were coerced, in schema order.
  /// A blob that is not a JSON object gives `Preferences.defaults` and `["*"]`. A missing field takes its
  /// default silently; a present but invalid one is reported and sets `.preferencesCoerced`.
  /// Decoding goes through `JSONDecoder` (not `JSONSerialization`), which keeps doubles bit-exact.
  public static func decode(_ data: Data) -> (Preferences, coercedFields: [String]) {
    guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
      return (Preferences.defaults, ["*"])
    }
    var fields: [String] = []
    var result = Preferences.defaults

    if let field = raw.schemaVersion {
      if let value = field.value, value >= 1 { result.schemaVersion = value } else { fields.append("schemaVersion") }
    }
    if let field = raw.activationModifier {
      if let value = field.value.flatMap(Modifier.init(rawValue:)) {
        result.activationModifier = value
      } else {
        fields.append("activationModifier")
      }
    }
    if let field = raw.spanModifier {
      if let value = field.value.flatMap(Modifier.init(rawValue:)) {
        result.spanModifier = value
      } else {
        fields.append("spanModifier")
      }
    }
    if let field = raw.shortcuts { result.shortcuts = resolveShortcuts(field.value, fields: &fields) }
    if let field = raw.appearance { result.appearance = resolveAppearance(field.value, fields: &fields) }
    if let field = raw.exclusions {
      if let list = field.value {
        let strings = list.compactMap(\.value)
        if strings.count != list.count { fields.append("exclusions") }
        result.exclusions = Set(strings)
      } else {
        fields.append("exclusions")
      }
    }
    if let field = raw.enhancedUI {
      if let value = field.value.flatMap(EnhancedUIPolicy.init(rawValue:)) {
        result.enhancedUI = value
      } else {
        fields.append("enhancedUI")
      }
    }
    if let field = raw.notices {
      if let list = field.value {
        let flags = list.compactMap { $0.value.flatMap(NoticeFlag.init(rawValue:)) }
        if flags.count != list.count { fields.append("notices") }
        result.notices = Set(flags)
      } else {
        fields.append("notices")
      }
    }

    if !fields.isEmpty { result.notices.insert(.preferencesCoerced) }
    let differing = result.coerced()
    if differing != result {
      if !fields.contains("spanModifier") { fields.append("spanModifier") }
      result = differing
    }
    return (result, fields)
  }

  /// Sorted keys and sorted sets, so equal preferences give equal bytes. Non-finite numbers are written as
  /// strings, which decode back as invalid and are coerced.
  public static func encode(_ p: Preferences) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
      positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
    let wire = Wire(
      schemaVersion: p.schemaVersion, activationModifier: p.activationModifier, spanModifier: p.spanModifier,
      shortcuts: p.shortcuts, appearance: p.appearance, exclusions: p.exclusions.sorted(),
      enhancedUI: p.enhancedUI, notices: p.notices.sorted { $0.rawValue < $1.rawValue })
    return (try? encoder.encode(wire)) ?? Data("{}".utf8)
  }

  private struct Wire: Encodable {
    var schemaVersion: Int
    var activationModifier: Modifier
    var spanModifier: Modifier
    var shortcuts: [Shortcut]
    var appearance: Appearance
    var exclusions: [String]
    var enhancedUI: EnhancedUIPolicy
    var notices: [NoticeFlag]
  }

  // MARK: Lenient wire types

  /// A value that decodes or is marked invalid; it never throws, so one bad field cannot sink the blob.
  private struct Lenient<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
  }

  private struct Raw: Decodable {
    var schemaVersion: Lenient<Int>?
    var activationModifier: Lenient<String>?
    var spanModifier: Lenient<String>?
    var shortcuts: Lenient<[Lenient<RawShortcut>]>?
    var appearance: Lenient<RawAppearance>?
    var exclusions: Lenient<[Lenient<String>]>?
    var enhancedUI: Lenient<String>?
    var notices: Lenient<[Lenient<String>]>?

    private enum CodingKeys: String, CodingKey {
      case schemaVersion, activationModifier, spanModifier, shortcuts, appearance, exclusions, enhancedUI, notices
    }

    init(from decoder: any Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      schemaVersion = try Self.field(c, .schemaVersion)
      activationModifier = try Self.field(c, .activationModifier)
      spanModifier = try Self.field(c, .spanModifier)
      shortcuts = try Self.field(c, .shortcuts)
      appearance = try Self.field(c, .appearance)
      exclusions = try Self.field(c, .exclusions)
      enhancedUI = try Self.field(c, .enhancedUI)
      notices = try Self.field(c, .notices)
    }

    /// nil when the key is absent (take the default silently); `.value == nil` when present but invalid.
    private static func field<T>(
      _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> Lenient<T>? {
      c.contains(key) ? try c.decode(Lenient<T>.self, forKey: key) : nil
    }
  }

  private struct RawShortcut: Decodable {
    var action: ShortcutAction
    var chord: Lenient<Chord>?

    private enum CodingKeys: String, CodingKey { case action, chord }

    init(from decoder: any Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      action = try c.decode(ShortcutAction.self, forKey: .action)
      chord = c.contains(.chord) ? try c.decode(Lenient<Chord>.self, forKey: .chord) : nil
    }
  }

  private struct RawAppearance: Decodable {
    var fill: Lenient<RGBA>?
    var opacity: Lenient<Double>?
    var defaultInsets: Lenient<Insets>?

    private enum CodingKeys: String, CodingKey { case fill, opacity, defaultInsets }

    init(from decoder: any Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      fill = c.contains(.fill) ? try c.decode(Lenient<RGBA>.self, forKey: .fill) : nil
      opacity = c.contains(.opacity) ? try c.decode(Lenient<Double>.self, forKey: .opacity) : nil
      defaultInsets = c.contains(.defaultInsets) ? try c.decode(Lenient<Insets>.self, forKey: .defaultInsets) : nil
    }
  }

  // MARK: Fields

  private static func resolveShortcuts(_ list: [Lenient<RawShortcut>]?, fields: inout [String]) -> [Shortcut] {
    guard let list else {
      fields.append("shortcuts")
      return Preferences.defaultShortcuts
    }
    var result: [Shortcut] = []
    var droppedUnreadable = false
    for element in list {
      guard let entry = element.value else {
        droppedUnreadable = true
        continue
      }
      let action = entry.action
      guard let chordField = entry.chord else {
        result.append(Shortcut(action: action, chord: nil))
        continue
      }
      if let chord = chordField.value, chord.hasCommandOrControl {
        result.append(Shortcut(action: action, chord: chord))
      } else {
        fields.append("shortcuts.\(fieldName(action))")
        result.append(Shortcut(action: action, chord: Preferences.defaultShortcuts.first { $0.action == action }?.chord))
      }
    }
    if droppedUnreadable { fields.append("shortcuts") }
    return result
  }

  private static func resolveAppearance(_ raw: RawAppearance?, fields: inout [String]) -> Appearance {
    var result = Preferences.defaults.appearance
    guard let raw else {
      fields.append("appearance")
      return result
    }
    if let field = raw.fill {
      if let fill = field.value, [fill.r, fill.g, fill.b, fill.a].allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
        result.fill = fill
      } else {
        fields.append("appearance.fill")
      }
    }
    if let field = raw.opacity {
      if let opacity = field.value, opacity.isFinite, (0...1).contains(opacity) {
        result.opacity = opacity
      } else {
        fields.append("appearance.opacity")
      }
    }
    if let field = raw.defaultInsets {
      if let insets = field.value, insets.margin.isFinite, insets.gap.isFinite, insets.margin >= 0, insets.gap >= 0 {
        result.defaultInsets = insets
      } else {
        fields.append("appearance.defaultInsets")
      }
    }
    return result
  }

  private static func fieldName(_ action: ShortcutAction) -> String {
    switch action {
    case .sendToZone(let n): "sendToZone\(n)"
    case .cycleRight: "cycleRight"
    case .cycleLeft: "cycleLeft"
    case .restore: "restore"
    case .openEditor: "openEditor"
    case .openSettings: "openSettings"
    }
  }
}
