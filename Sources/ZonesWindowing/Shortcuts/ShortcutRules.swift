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

  public static let defaults: [Shortcut] = Preferences.defaultShortcuts
}
