public enum Modifier: String, Codable, CaseIterable, Sendable { case shift, control, option, command }

/// Masked to the four modifiers (AC-051).
public struct ModifierSet: OptionSet, Hashable, Codable, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let shift = ModifierSet(rawValue: 1 << 0)
  public static let control = ModifierSet(rawValue: 1 << 1)
  public static let option = ModifierSet(rawValue: 1 << 2)
  public static let command = ModifierSet(rawValue: 1 << 3)

  public init(_ m: Modifier) {
    switch m {
    case .shift: self = .shift
    case .control: self = .control
    case .option: self = .option
    case .command: self = .command
    }
  }

  // Raw CGEventFlags bits. Caps Lock (1 << 16), keypad (1 << 21), Fn (1 << 23) and the rest are ignored.
  private static let cgShift: UInt64 = 1 << 17
  private static let cgControl: UInt64 = 1 << 18
  private static let cgOption: UInt64 = 1 << 19
  private static let cgCommand: UInt64 = 1 << 20

  /// The four modifiers present in raw `CGEventFlags` bits; every other bit is ignored (AC-051).
  public static func masked(_ cgFlags: UInt64) -> ModifierSet {
    var set = ModifierSet()
    if cgFlags & cgShift != 0 { set.insert(.shift) }
    if cgFlags & cgControl != 0 { set.insert(.control) }
    if cgFlags & cgOption != 0 { set.insert(.option) }
    if cgFlags & cgCommand != 0 { set.insert(.command) }
    return set
  }
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
