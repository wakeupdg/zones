/// What the onboarding window shows for a `PermissionState` (ADR-0021). Pure: the window follows the
/// reducer's effects (`showOnboarding`, `dismissOnboarding`, `offerRelaunch`) and never polls trust itself.
public struct OnboardingViewState: Hashable, Sendable {
  public var statusLine: String
  public var showOpenSettings: Bool
  public var showQuitAndReopen: Bool
  public var relaunchExplanation: String?
  public var windowVisible: Bool

  public init(
    statusLine: String, showOpenSettings: Bool, showQuitAndReopen: Bool, relaunchExplanation: String?,
    windowVisible: Bool
  ) {
    self.statusLine = statusLine
    self.showOpenSettings = showOpenSettings
    self.showQuitAndReopen = showQuitAndReopen
    self.relaunchExplanation = relaunchExplanation
    self.windowVisible = windowVisible
  }

  public static func derive(_ p: PermissionState, relaunchOffered: Bool) -> OnboardingViewState {
    OnboardingViewState(
      statusLine: "Waiting for Accessibility access", showOpenSettings: true, showQuitAndReopen: false,
      relaunchExplanation: nil, windowVisible: true)
  }
}
