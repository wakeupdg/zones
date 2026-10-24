import Foundation
import Observation
import ZonesCore

/// The one owner of `Preferences`. Every change is coerced by the AC-087 rule (`Preferences.coerced()`),
/// encoded with `PreferencesCodec` and written to UserDefaults `zones.preferences` at once, so the next Drag
/// Session reads it with no relaunch (AC-141). The drag and overlay pipeline reads `preferences`.
@MainActor @Observable
final class PreferencesController {
  nonisolated static let defaultsKey = "zones.preferences"

  private(set) var preferences: Preferences
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.defaultsKey) {
      preferences = PreferencesCodec.decode(data).0
    } else {
      preferences = Preferences.defaults
    }
  }

  /// Applies `change`, coerces the Modifier pair, and persists when anything changed.
  func update(_ change: (inout Preferences) -> Void) {
    var next = preferences
    change(&next)
    next = next.coerced()
    guard next != preferences else { return }
    preferences = next
    defaults.set(PreferencesCodec.encode(next), forKey: Self.defaultsKey)
  }

  /// A write-through replacement for a whole value, used by panes that report a full `Preferences`.
  func replace(with value: Preferences) { update { $0 = value } }
}
