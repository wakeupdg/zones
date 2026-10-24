import Observation
import ZonesCore
import ZonesWindowing

/// The onboarding window's observable state. The controller feeds it from reducer effects and the preference
/// store; the views only read it and call the actions.
@MainActor
@Observable
final class OnboardingModel {
  enum Page: Int { case accessibility, cheatSheet }

  var permission: PermissionState = .notGranted
  var relaunchOffered = false
  var preferences: Preferences
  var page: Page = .accessibility

  let openSettings: @MainActor () -> Void
  let quitAndReopen: @MainActor () -> Void

  init(preferences: Preferences, openSettings: @escaping @MainActor () -> Void, quitAndReopen: @escaping @MainActor () -> Void) {
    self.preferences = preferences
    self.openSettings = openSettings
    self.quitAndReopen = quitAndReopen
  }

  var viewState: OnboardingViewState {
    OnboardingViewState.derive(permission, relaunchOffered: relaunchOffered)
  }
}
