import Foundation
import ZonesCore

/// Logic behind Settings > Shortcuts: what each recorder row shows and which `ShortcutStore` events a recorded
/// chord, Clear, Accept or Reset produce. The decisions come from `ShortcutRules.recorderState` and
/// `ShortcutStore.reduce`; this type only maps them to messages and drives the reducer's effects.
public struct ShortcutsFlow {
  /// What the recorder row shows under a chord it did not store, or could not register.
  public struct Message: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case warning, conflict, rejected, inUse, invalid }
    public var kind: Kind
    public var text: String
    /// A warning chord is held back until the person presses Accept.
    public var needsAccept: Bool
    /// The proposed chord (the one a warning would store on Accept).
    public var chord: Chord
  }

  /// The hotkey registrar as the flow sees it. Wired to `HotkeyRegistrar` by the App.
  public struct Driver {
    public var register: (Chord, ShortcutAction) -> HotkeyRegistration
    public var unregister: (ShortcutAction) -> Void
    public init(
      register: @escaping (Chord, ShortcutAction) -> HotkeyRegistration,
      unregister: @escaping (ShortcutAction) -> Void
    ) {
      self.register = register
      self.unregister = unregister
    }
  }

  public private(set) var state: ShortcutStoreState
  /// At most one message per action; cleared when that action next stores a chord.
  public private(set) var messages: [ShortcutAction: Message] = [:]

  public var shortcuts: [Shortcut] { state.shortcuts }

  /// `granted`: Accessibility permission, which decides whether window actions are registered at all.
  /// Every action that has a chord is taken to be registered already (the launch pass did that).
  public init(shortcuts: [Shortcut], granted: Bool) {
    let registered = Set(shortcuts.filter { $0.chord != nil && (granted || !$0.action.isWindowAction) }.map(\.action))
    state = ShortcutStoreState(shortcuts: shortcuts, registered: registered, granted: granted)
  }

  /// Offers a recorded chord for `action`. Returns the shortcuts to persist when it was stored, else nil and
  /// `messages[action]` says why (conflict, rejected, warning awaiting Accept, in use).
  public mutating func record(_ chord: Chord, for action: ShortcutAction, driver: Driver) -> [Shortcut]? {
    messages[action] = nil
    switch ShortcutRules.recorderState(chord, for: action, bound: state.shortcuts) {
    case .accepted:
      return run(.set(action, chord), driver: driver)
    case .warning(let warning):
      messages[action] = Message(
        kind: .warning, text: Self.text(for: warning), needsAccept: true, chord: chord)
      return nil
    case .conflict(let other):
      messages[action] = Message(
        kind: .conflict, text: "Already used by \(Self.name(of: other)).", needsAccept: false, chord: chord)
      return nil
    case .rejected:
      messages[action] = Message(
        kind: .rejected, text: "A shortcut needs Command or Control.", needsAccept: false, chord: chord)
      return nil
    }
  }

  /// The Accept button on a warning: stores the held chord. nil when nothing is waiting.
  public mutating func accept(_ action: ShortcutAction, driver: Driver) -> [Shortcut]? {
    guard let held = messages[action], held.needsAccept else { return nil }
    messages[action] = nil
    return run(.set(action, held.chord), driver: driver)
  }

  /// Clear: the action is left unbound (no default returns).
  public mutating func clear(_ action: ShortcutAction, driver: Driver) -> [Shortcut]? {
    messages[action] = nil
    return run(.set(action, nil), driver: driver)
  }

  /// Reset to defaults: every action takes its `ShortcutRules.defaults` chord. Messages are dropped first, so
  /// only a chord another app holds right now shows a message afterwards.
  public mutating func resetToDefaults(driver: Driver) -> [Shortcut]? {
    messages = [:]
    var stored = false
    for action in ShortcutAction.allCases {
      let chord = ShortcutRules.defaults.first { $0.action == action }?.chord
      if run(.set(action, chord), driver: driver) != nil { stored = true }
    }
    return stored ? state.shortcuts : nil
  }

  /// Feeds `event` to the reducer and carries out its effects, answering `register` effects with the driver.
  /// Returns the shortcuts of the last `persist` effect.
  private mutating func run(_ event: ShortcutStoreEvent, driver: Driver) -> [Shortcut]? {
    var queue = [event]
    var persisted: [Shortcut]?
    while !queue.isEmpty {
      let (next, effects) = ShortcutStore.reduce(state, queue.removeFirst())
      state = next
      for effect in effects {
        switch effect {
        case .register(let chord, let action):
          queue.append(.registration(action, driver.register(chord, action)))
        case .unregister(let action):
          driver.unregister(action)
        case .failed(let action, let failure):
          messages[action] = Self.failure(failure, chord: state.pending[action] ?? chord(of: action))
        case .persist(let list):
          persisted = list
        }
      }
    }
    return persisted
  }

  private func chord(of action: ShortcutAction) -> Chord {
    state.shortcuts.first { $0.action == action }?.chord ?? Chord(key: .comma, modifiers: [])
  }

  private static func failure(_ failure: HotkeyRegistration, chord: Chord) -> Message {
    switch failure {
    case .inUse:
      Message(
        kind: .inUse, text: "That shortcut is in use by another app. The previous shortcut is kept.",
        needsAccept: false, chord: chord)
    case .invalid, .registered:
      Message(
        kind: .invalid, text: "That key cannot be used as a shortcut. The previous shortcut is kept.",
        needsAccept: false, chord: chord)
    }
  }

  // MARK: Text

  static func text(for warning: ChordWarning) -> String {
    switch warning {
    case .commandOnly: "Command alone is used by many apps. Accept to use it anyway."
    case .commandShiftOnly: "Command+Shift is used by many apps. Accept to use it anyway."
    case .controlOnlyWithArrowOrDigit: "Control with an arrow or digit is used by macOS. Accept to use it anyway."
    }
  }

  public static func name(of action: ShortcutAction) -> String {
    switch action {
    case .sendToZone(let n): "Send to Zone \(n)"
    case .cycleRight: "Cycle right"
    case .cycleLeft: "Cycle left"
    case .restore: "Restore original size"
    case .openEditor: "Open Editor"
    case .openSettings: "Open Settings"
    }
  }

  /// A chord as key caps, modifiers in the macOS order: Control, Option, Shift, Command.
  public static func text(for chord: Chord) -> String {
    var out = ""
    if chord.modifiers.contains(.control) { out += "\u{2303}" }
    if chord.modifiers.contains(.option) { out += "\u{2325}" }
    if chord.modifiers.contains(.shift) { out += "\u{21E7}" }
    if chord.modifiers.contains(.command) { out += "\u{2318}" }
    switch chord.key {
    case .digit(let n): out += String(n)
    case .letter(let s): out += s.uppercased()
    case .arrowLeft: out += "\u{2190}"
    case .arrowRight: out += "\u{2192}"
    case .arrowUp: out += "\u{2191}"
    case .arrowDown: out += "\u{2193}"
    case .comma: out += ","
    }
    return out
  }
}
