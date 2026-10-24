import AppKit
import ZonesWindowing

/// What the permission machine shows (ADR-0021): the one onboarding window (T33's `OnboardingWindowController`) and
/// the status item. Every effect is one call on the controller; the Quit and Reopen offer is the onboarding
/// window's button (`offerRelaunch` feeds its model), never an alert of the root's own.
@MainActor
final class AppSurfaces: PermissionSurfaces {
  /// Re-renders the status item from the live state. Set once the root exists.
  var refresh: @MainActor () -> Void = {}
  /// The live `PermissionState` (the driver sets it before it interprets effects). Set once the root exists.
  var permission: @MainActor () -> PermissionState = { .notGranted }

  private let onboarding: OnboardingWindowController
  private var relaunchOffered = false

  init(onboarding: OnboardingWindowController) { self.onboarding = onboarding }

  func setBadge(_ on: Bool) {
    sync()
    refresh()
  }

  func setGrantMenuItem(_ on: Bool) {
    sync()
    refresh()
  }

  func showOnboarding() {
    sync()
    onboarding.show()
  }

  func dismissOnboarding() { onboarding.dismiss() }

  /// Accessibility was granted but the tap still cannot start: macOS wants a relaunch (ADR-0021). The window
  /// shows Quit and Reopen while the offer stands.
  func offerRelaunch(_ on: Bool) {
    relaunchOffered = on
    sync()
    refresh()
    if on { onboarding.show() }
  }

  private func sync() { onboarding.update(permission: permission(), relaunchOffered: relaunchOffered) }
}
