import Foundation
import ZonesCore

public enum HotkeyRegistration: Hashable, Sendable { case registered, inUse, invalid }

/// Production: CarbonHotkeyRegistrar. Fake: FakeHotkeyRegistrar.
public protocol HotkeyRegistrar: Sendable {
  @MainActor func register(_ chord: Chord, for action: ShortcutAction) -> HotkeyRegistration
  @MainActor func unregister(_ action: ShortcutAction)
  @MainActor func bound(_ action: ShortcutAction) -> Chord?
  var presses: AsyncStream<ShortcutAction> { get }
}
