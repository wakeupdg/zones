import Foundation
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
  /// Clock seconds the window has been open in a waiting state (T56); the controller sets it on each trust poll.
  var waited: TimeInterval = 0
  var preferences: Preferences
  var page: Page = .accessibility
  /// The running macOS major version: it picks the Privacy & Security pane name (T66).
  let macOSMajor: Int

  let openSettings: @MainActor () -> Void
  let quitAndReopen: @MainActor () -> Void

  init(
    preferences: Preferences, openSettings: @escaping @MainActor () -> Void,
    quitAndReopen: @escaping @MainActor () -> Void,
    macOSMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
  ) {
    self.preferences = preferences
    self.macOSMajor = macOSMajor
    self.openSettings = openSettings
    self.quitAndReopen = quitAndReopen
  }

  /// Back applies only past page 1; Next only before the last page. The view disables, never dims.
  var canGoBack: Bool { page != .accessibility }
  var canGoNext: Bool { page != .cheatSheet }

  /// macOS 27 renamed the Accessibility pane: its `ACCESSIBILITY` string reads "Device Control and Data Access",
  /// with the Zones toggle in that pane (no Accessibility row below it). macOS 14-26 keep "Accessibility" (T66).
  static func accessibilityPath(macOSMajor: Int) -> String {
    "Privacy & Security > " + (macOSMajor >= 27 ? "Device Control and Data Access" : "Accessibility")
  }

  var accessibilityPath: String { Self.accessibilityPath(macOSMajor: macOSMajor) }

  var viewState: OnboardingViewState {
    OnboardingViewState.derive(permission, relaunchOffered: relaunchOffered, waited: waited)
  }
}
