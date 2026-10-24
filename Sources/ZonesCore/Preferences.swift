import Foundation

public enum EnhancedUIPolicy: String, Codable, Sendable { case toggle, leave }

public struct Appearance: Hashable, Codable, Sendable {
  public var fill: RGBA
  public var opacity: Double
  public var defaultInsets: Insets
  public init(fill: RGBA, opacity: Double, defaultInsets: Insets) {
    self.fill = fill
    self.opacity = opacity
    self.defaultInsets = defaultInsets
  }
}

public enum NoticeFlag: String, Codable, Sendable { case modifiersCoerced, preferencesCoerced, separateSpacesOff }

/// One bundle identifier.
public typealias ExclusionRule = String

public struct Preferences: Hashable, Codable, Sendable {
  public var schemaVersion: Int
  /// Coerced to differ from `spanModifier` (AC-087).
  public var activationModifier: Modifier
  public var spanModifier: Modifier
  public var shortcuts: [Shortcut]
  public var appearance: Appearance
  public var exclusions: Set<ExclusionRule>
  public var enhancedUI: EnhancedUIPolicy
  public var notices: Set<NoticeFlag>

  public init(
    schemaVersion: Int, activationModifier: Modifier, spanModifier: Modifier, shortcuts: [Shortcut],
    appearance: Appearance, exclusions: Set<ExclusionRule>, enhancedUI: EnhancedUIPolicy,
    notices: Set<NoticeFlag>
  ) {
    self.schemaVersion = schemaVersion
    self.activationModifier = activationModifier
    self.spanModifier = spanModifier
    self.shortcuts = shortcuts
    self.appearance = appearance
    self.exclusions = exclusions
    self.enhancedUI = enhancedUI
    self.notices = notices
  }

  /// Keeps the Activation modifier and makes the Span modifier differ from it (AC-087): Span becomes Control,
  /// or Shift when Activation is Control. Sets `.modifiersCoerced` only when it changed something.
  public func coerced() -> Preferences {
    guard spanModifier == activationModifier else { return self }
    var copy = self
    copy.spanModifier = activationModifier == .control ? .shift : .control
    copy.notices.insert(.modifiersCoerced)
    return copy
  }

  /// AC-097 / ADR-0010: Control+Option+1..9 sendToZone, Right/Left cycle, R restore, E openEditor, Comma
  /// openSettings. Core cannot import ZonesWindowing, so the shortcut ticket's `ShortcutRules.defaults` returns this.
  public static let defaultShortcuts: [Shortcut] = {
    let modifiers: ModifierSet = [.control, .option]
    let digits = (1...9).map { Shortcut(action: .sendToZone($0), chord: Chord(key: .digit($0), modifiers: modifiers)) }
    return digits + [
      Shortcut(action: .cycleRight, chord: Chord(key: .arrowRight, modifiers: modifiers)),
      Shortcut(action: .cycleLeft, chord: Chord(key: .arrowLeft, modifiers: modifiers)),
      Shortcut(action: .restore, chord: Chord(key: .letter("r"), modifiers: modifiers)),
      Shortcut(action: .openEditor, chord: Chord(key: .letter("e"), modifiers: modifiers)),
      Shortcut(action: .openSettings, chord: Chord(key: .comma, modifiers: modifiers)),
    ]
  }()

  public static let defaults = Preferences(
    schemaVersion: Constants.preferencesSchema,
    activationModifier: .shift,
    spanModifier: .control,
    shortcuts: defaultShortcuts,
    appearance: Appearance(
      fill: RGBA(r: 0.2, g: 0.5, b: 1.0, a: 1.0), opacity: 0.3,
      defaultInsets: Insets(margin: 8, gap: 8)),
    exclusions: [],
    enhancedUI: .toggle,
    notices: [])
}
