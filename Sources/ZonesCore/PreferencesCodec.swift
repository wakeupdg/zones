import Foundation

/// UserDefaults key "zones.preferences" holds the JSON blob. Decoding never fails: every field is read on its
/// own, and a field that is present but invalid falls back to its default alone (AC-153).
public enum PreferencesCodec {
  /// Returns the preferences and the names of the fields that were coerced, in schema order.
  /// A blob that is not a JSON object gives `Preferences.defaults` and `["*"]`. A missing field takes its
  /// default silently; a present but invalid one is reported and sets `.preferencesCoerced`.
  public static func decode(_ data: Data) -> (Preferences, coercedFields: [String]) {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return (Preferences.defaults, ["*"])
    }
    var fields: [String] = []
    var result = Preferences.defaults

    if let raw = object["schemaVersion"] {
      if let value = integer(raw), value >= 1 { result.schemaVersion = value } else { fields.append("schemaVersion") }
    }
    if let raw = object["activationModifier"] {
      if let value = (raw as? String).flatMap(Modifier.init(rawValue:)) {
        result.activationModifier = value
      } else {
        fields.append("activationModifier")
      }
    }
    if let raw = object["spanModifier"] {
      if let value = (raw as? String).flatMap(Modifier.init(rawValue:)) {
        result.spanModifier = value
      } else {
        fields.append("spanModifier")
      }
    }
    if let raw = object["shortcuts"] { result.shortcuts = decodeShortcuts(raw, fields: &fields) }
    if let raw = object["appearance"] { result.appearance = decodeAppearance(raw, fields: &fields) }
    if let raw = object["exclusions"] {
      if let list = raw as? [Any] {
        let strings = list.compactMap { $0 as? String }
        if strings.count != list.count { fields.append("exclusions") }
        result.exclusions = Set(strings)
      } else {
        fields.append("exclusions")
      }
    }
    if let raw = object["enhancedUI"] {
      if let value = (raw as? String).flatMap(EnhancedUIPolicy.init(rawValue:)) {
        result.enhancedUI = value
      } else {
        fields.append("enhancedUI")
      }
    }
    if let raw = object["notices"] {
      if let list = raw as? [Any] {
        let flags = list.compactMap { ($0 as? String).flatMap(NoticeFlag.init(rawValue:)) }
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

  // MARK: Fields

  private static func decodeShortcuts(_ raw: Any, fields: inout [String]) -> [Shortcut] {
    guard let list = raw as? [Any] else {
      fields.append("shortcuts")
      return Preferences.defaultShortcuts
    }
    var result: [Shortcut] = []
    var droppedUnreadable = false
    for element in list {
      guard let entry = element as? [String: Any], let rawAction = entry["action"],
        let action = decodeValue(ShortcutAction.self, rawAction)
      else {
        droppedUnreadable = true
        continue
      }
      let fallback = Preferences.defaultShortcuts.first { $0.action == action }?.chord
      let chordValue = entry["chord"]
      if chordValue == nil || chordValue is NSNull {
        result.append(Shortcut(action: action, chord: nil))
      } else if let chord = chordValue.flatMap({ decodeValue(Chord.self, $0) }), chord.hasCommandOrControl {
        result.append(Shortcut(action: action, chord: chord))
      } else {
        fields.append("shortcuts.\(fieldName(action))")
        result.append(Shortcut(action: action, chord: fallback))
      }
    }
    if droppedUnreadable { fields.append("shortcuts") }
    return result
  }

  private static func decodeAppearance(_ raw: Any, fields: inout [String]) -> Appearance {
    var result = Preferences.defaults.appearance
    guard let object = raw as? [String: Any] else {
      fields.append("appearance")
      return result
    }
    if let value = object["fill"] {
      if let fill = decodeValue(RGBA.self, value),
        [fill.r, fill.g, fill.b, fill.a].allSatisfy({ $0.isFinite && (0...1).contains($0) })
      {
        result.fill = fill
      } else {
        fields.append("appearance.fill")
      }
    }
    if let value = object["opacity"] {
      if let opacity = number(value), opacity.isFinite, (0...1).contains(opacity) {
        result.opacity = opacity
      } else {
        fields.append("appearance.opacity")
      }
    }
    if let value = object["defaultInsets"] {
      if let insets = decodeValue(Insets.self, value), insets.margin.isFinite, insets.gap.isFinite,
        insets.margin >= 0, insets.gap >= 0
      {
        result.defaultInsets = insets
      } else {
        fields.append("appearance.defaultInsets")
      }
    }
    return result
  }

  // MARK: Helpers

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

  private static func decodeValue<T: Decodable>(_ type: T.Type, _ value: Any) -> T? {
    guard JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value)
    else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func number(_ value: Any) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
  }

  private static func integer(_ value: Any) -> Int? {
    guard let d = number(value), d == d.rounded(), abs(d) < 1_000_000 else { return nil }
    return Int(d)
  }
}
