import Foundation

/// What the onboarding window shows for a `PermissionState` (ADR-0021). Pure: the window follows the
/// reducer's effects (`showOnboarding`, `dismissOnboarding`, `offerRelaunch`) and never polls trust itself.
public struct OnboardingViewState: Hashable, Sendable {
  public var statusLine: String
  public var showOpenSettings: Bool
  public var showQuitAndReopen: Bool
  public var relaunchExplanation: String?
  public var windowVisible: Bool
  /// T56: the second help line for a stale Accessibility entry (ON in the list but keyed to an older signature).
  public var staleEntryHelp: String?

  public init(
    statusLine: String, showOpenSettings: Bool, showQuitAndReopen: Bool, relaunchExplanation: String?,
    windowVisible: Bool, staleEntryHelp: String? = nil
  ) {
    self.statusLine = statusLine
    self.showOpenSettings = showOpenSettings
    self.showQuitAndReopen = showQuitAndReopen
    self.relaunchExplanation = relaunchExplanation
    self.windowVisible = windowVisible
    self.staleEntryHelp = staleEntryHelp
  }

  static let relaunchSentence = "Zones must quit and reopen to pick up the restored Accessibility permission."
  public static let staleEntrySentence =
    "Is Zones already on in the list? Select Zones, click the minus button (−) to remove it, then click Open System Settings and turn Zones on again."
  /// Seconds on the Clock the window waits in `notGranted` or `revoked` before the stale-entry help line shows.
  public static let staleEntryDelay: TimeInterval = 10

  /// The states in which the window waits for the user to grant Accessibility (the help line's clock runs).
  public static func waitsForGrant(_ p: PermissionState) -> Bool {
    switch p {
    case .notGranted, .revoked: true
    case .granted, .suspect, .needsRelaunch: false
    }
  }

  /// `waited` is how long the window has been open in a waiting state, in Clock seconds.
  public static func derive(_ p: PermissionState, relaunchOffered: Bool, waited: TimeInterval = 0)
    -> OnboardingViewState
  {
    let help = waitsForGrant(p) && waited >= staleEntryDelay ? staleEntrySentence : nil
    return switch p {
    case .needsRelaunch:
      OnboardingViewState(
        statusLine: "Zones can't recover Accessibility without restarting", showOpenSettings: true,
        showQuitAndReopen: relaunchOffered,
        relaunchExplanation: relaunchOffered ? Self.relaunchSentence : nil, windowVisible: true)
    case .revoked:
      OnboardingViewState(
        statusLine: "Accessibility access was turned off", showOpenSettings: true, showQuitAndReopen: false,
        relaunchExplanation: nil, windowVisible: true, staleEntryHelp: help)
    case .notGranted:
      OnboardingViewState(
        statusLine: "Waiting for Accessibility access", showOpenSettings: true, showQuitAndReopen: false,
        relaunchExplanation: nil, windowVisible: true, staleEntryHelp: help)
    case .granted, .suspect:
      // The window is closed by the `dismissOnboarding` effect, not by the view.
      OnboardingViewState(
        statusLine: "Accessibility access granted", showOpenSettings: false, showQuitAndReopen: false,
        relaunchExplanation: nil, windowVisible: false)
    }
  }
}
