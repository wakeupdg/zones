import Foundation
import ServiceManagement
import ZonesCore

/// Production `LoginItemService` over `SMAppService.mainApp`. A thin wrapper; no unit test (OS call).
public struct SMLoginItemService: LoginItemService {
  public init() {}

  @MainActor public func status() -> LoginItemStatus {
    switch SMAppService.mainApp.status {
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notFound: .notFound
    case .notRegistered: .notRegistered
    @unknown default: .notFound
    }
  }

  @MainActor public func register() throws(LoginItemError) {
    do { try SMAppService.mainApp.register() } catch { try Self.map(error) }
  }

  @MainActor public func unregister() throws(LoginItemError) {
    do { try SMAppService.mainApp.unregister() } catch { try Self.map(error) }
  }

  @MainActor public func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

  /// NSError code 3 is invalid signature, 11 launch denied by the user, 12 already registered (success).
  private static func map(_ error: any Error) throws(LoginItemError) {
    let ns = error as NSError
    switch ns.code {
    case 3: throw .invalidSignature
    case 11: throw .launchDeniedByUser
    case 12: return
    default: throw .other(ns.localizedDescription)
    }
  }
}
