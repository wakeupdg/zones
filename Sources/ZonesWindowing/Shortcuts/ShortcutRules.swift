import Foundation
import ZonesCore

public enum ChordWarning: String, Sendable { case commandOnly, commandShiftOnly, controlOnlyWithArrowOrDigit }

public enum RecorderState: Hashable, Sendable {
  case accepted, warning(ChordWarning), conflict(duplicate: ShortcutAction), rejected
}

public enum ShortcutRules {
  /// AC-097 / ADR-0010. Letters are stored uppercase.
  public static let defaults: [Shortcut] = Preferences.defaultShortcuts
}
