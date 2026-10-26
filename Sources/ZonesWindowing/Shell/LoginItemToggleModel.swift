import Observation
import ZonesCore

/// The Launch at Login toggle's look (AC-027). Status alone decides `isOn`; an error beats status for the caption.
public struct LoginItemToggleModel: Hashable, Sendable {
  public var isOn: Bool
  public var caption: String?
  public var showLoginItemsButton: Bool
  /// Never true: the toggle stays usable on `notFound` (research/login-items.md).
  public var disabled: Bool

  public static let approvalCaption = "Zones is turned off in Login Items"
  public static let signatureCaption =
    "This build isn't properly signed; launch-at-login works in the signed release from /Applications"

  public init(isOn: Bool, caption: String?, showLoginItemsButton: Bool, disabled: Bool = false) {
    self.isOn = isOn
    self.caption = caption
    self.showLoginItemsButton = showLoginItemsButton
    self.disabled = disabled
  }

  public static func derive(_ s: LoginItemStatus, error: LoginItemError?) -> LoginItemToggleModel {
    let isOn = s == .enabled
    let caption: String?
    let button: Bool
    switch error {
    case .launchDeniedByUser:
      (caption, button) = (approvalCaption, true)
    case .invalidSignature:
      (caption, button) = (signatureCaption, false)
    case .other(let message):
      (caption, button) = (message, false)
    case nil:
      switch s {
      case .requiresApproval, .notFound: (caption, button) = (approvalCaption, true)
      case .enabled, .notRegistered: (caption, button) = (nil, false)
      }
    }
    return LoginItemToggleModel(isOn: isOn, caption: caption, showLoginItemsButton: button)
  }
}

/// Owns the last registration error and talks to the service. Registers only from `setOn` (a user action):
/// init and `refresh()` only read status (research/login-items.md gotcha 9).
@MainActor @Observable
public final class LoginItemToggleCoordinator {
  public private(set) var model: LoginItemToggleModel
  @ObservationIgnored private let service: any LoginItemService
  @ObservationIgnored private var status: LoginItemStatus = .notRegistered
  @ObservationIgnored private var lastError: LoginItemError?

  public init(service: any LoginItemService) {
    self.service = service
    model = LoginItemToggleModel.derive(.notRegistered, error: nil)
  }

  /// Re-reads status and clears the stored error.
  public func refresh() {
    lastError = nil
    reread()
  }

  public func setOn(_ on: Bool) {
    lastError = nil
    do {
      if on { try service.register() } else { try service.unregister() }
    } catch {
      lastError = error
    }
    reread()
  }

  public func openLoginItemsSettings() { service.openLoginItemsSettings() }

  private func reread() {
    status = service.status()
    model = LoginItemToggleModel.derive(status, error: lastError)
  }
}
