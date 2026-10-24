public enum Modifier: String, Codable, CaseIterable, Sendable { case shift, control, option, command }

/// Masked to the four modifiers (AC-051). `init(_:)` and `masked(_:)` are added by the input ticket.
public struct ModifierSet: OptionSet, Hashable, Codable, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let shift = ModifierSet(rawValue: 1 << 0)
  public static let control = ModifierSet(rawValue: 1 << 1)
  public static let option = ModifierSet(rawValue: 1 << 2)
  public static let command = ModifierSet(rawValue: 1 << 3)
}

public enum Key: Hashable, Codable, Sendable {
  case digit(Int), letter(String), arrowLeft, arrowRight, arrowUp, arrowDown, comma
}

/// LI-018: a chord must carry Command or Control to be bindable. The flag is derived, never stored.
public struct Chord: Hashable, Codable, Sendable {
  public var key: Key
  public var modifiers: ModifierSet
  public init(key: Key, modifiers: ModifierSet) {
    self.key = key
    self.modifiers = modifiers
  }

  public var hasCommandOrControl: Bool {
    modifiers.contains(.command) || modifiers.contains(.control)
  }

  private enum CodingKeys: String, CodingKey { case key, modifiers }
}

public enum ShortcutAction: Hashable, Codable, Sendable, CaseIterable {
  case sendToZone(Int), cycleRight, cycleLeft, restore, openEditor, openSettings

  public static let allCases: [ShortcutAction] =
    (1...9).map { .sendToZone($0) } + [.cycleRight, .cycleLeft, .restore, .openEditor, .openSettings]

  /// True for sendToZone, cycleRight, cycleLeft, restore (registered only while granted, AC-105).
  public var isWindowAction: Bool {
    switch self {
    case .sendToZone, .cycleRight, .cycleLeft, .restore: true
    case .openEditor, .openSettings: false
    }
  }
}

public struct Shortcut: Hashable, Codable, Sendable {
  public var action: ShortcutAction
  /// nil = cleared.
  public var chord: Chord?
  public init(action: ShortcutAction, chord: Chord?) {
    self.action = action
    self.chord = chord
  }
}
