import Foundation

/// Production: AXPermissionProbe. Fake: FakePermissionProbe.
public protocol PermissionProbe: Sendable {
  func isTrusted() -> Bool
  @MainActor func openAccessibilitySettings()
  var launchedAtLogin: Bool { get }
}
