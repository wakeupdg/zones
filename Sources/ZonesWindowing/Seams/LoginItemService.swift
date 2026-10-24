import Foundation
import ZonesCore

public enum LoginItemStatus: Hashable, Sendable { case enabled, requiresApproval, notFound, notRegistered }

/// Production: SMLoginItemService. Fake: FakeLoginItemService.
public protocol LoginItemService: Sendable {
  @MainActor func status() -> LoginItemStatus
  @MainActor func register() throws(LoginItemError)
  @MainActor func unregister() throws(LoginItemError)
  @MainActor func openLoginItemsSettings()
}
