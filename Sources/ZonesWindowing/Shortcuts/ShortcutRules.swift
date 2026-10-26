import Foundation
import ZonesCore

public enum ChordWarning: String, Sendable { case commandOnly, commandShiftOnly, controlOnlyWithArrowOrDigit }

public enum RecorderState: Hashable, Sendable {
  case accepted, warning(ChordWarning), conflict(duplicate: ShortcutAction), rejected
}

public enum ShortcutRules {
  /// AC-097 / ADR-0010. Letters are stored uppercase.
  /// LI-018: a chord is bindable only with Command or Control.
  public static func validate(_ c: Chord) -> Bool { c.hasCommandOrControl }

  /// Precedence: rejected, conflict, warning, accepted.
  public static func recorderState(_ c: Chord, for a: ShortcutAction, bound: [Shortcut]) -> RecorderState {
    guard validate(c) else { return .rejected }
    if let other = bound.first(where: { $0.action != a && $0.chord == c }) {
      return .conflict(duplicate: other.action)
    }
    if c.modifiers == [.command] { return .warning(.commandOnly) }
    if c.modifiers == [.command, .shift] { return .warning(.commandShiftOnly) }
    if c.modifiers == [.control] {
      switch c.key {
      case .digit, .arrowLeft, .arrowRight, .arrowUp, .arrowDown: return .warning(.controlOnlyWithArrowOrDigit)
      case .letter, .comma: break
      }
    }
    return .accepted
  }

  public static let defaults: [Shortcut] = Preferences.defaultShortcuts
}
