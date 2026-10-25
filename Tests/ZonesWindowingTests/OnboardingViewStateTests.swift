import Testing
import ZonesWindowing

@Suite struct OnboardingViewStateTests {
  @Test func notGrantedShowsOpenSettingsOnly() {
    let s = OnboardingViewState.derive(.notGranted, relaunchOffered: false)
    #expect(s.showOpenSettings)
    #expect(!s.showQuitAndReopen)
    #expect(s.relaunchExplanation == nil)
    #expect(s.windowVisible)
    #expect(s.statusLine == "Waiting for Accessibility access")
  }

  @Test func revokedNeverOffersQuitAndReopen() {
    for p in [PermissionState.revoked(failures: 0, firstFailure: nil), .revoked(failures: 3, firstFailure: 0)] {
      let s = OnboardingViewState.derive(p, relaunchOffered: false)
      #expect(!s.showQuitAndReopen, "\(p)")
      #expect(s.showOpenSettings, "\(p)")
      #expect(s.relaunchExplanation == nil, "\(p)")
      #expect(s.windowVisible, "\(p)")
      #expect(s.statusLine == "Accessibility access was turned off", "\(p)")
    }
  }

  @Test func needsRelaunchOffersQuitAndReopenWithSentence() {
    let s = OnboardingViewState.derive(.needsRelaunch, relaunchOffered: true)
    #expect(s.showQuitAndReopen)
    #expect(s.showOpenSettings)
    #expect(s.windowVisible)
    #expect(s.statusLine == "Zones can't recover Accessibility without restarting")
    #expect(!(s.relaunchExplanation ?? "").isEmpty)
    // Quit and Reopen follows offerRelaunch, never the state alone.
    #expect(!OnboardingViewState.derive(.needsRelaunch, relaunchOffered: false).showQuitAndReopen)
  }

  static let help =
    "Is Zones already on in the list? Select Zones, click the minus button (−) to remove it, then click Open System Settings and turn Zones on again."

  /// T56: a stale Accessibility entry (ON in the list, untrusted after a re-signed build) gets a help line once the
  /// window has waited 10 s on the Clock.
  @Test(arguments: [PermissionState.notGranted, .revoked(failures: 0, firstFailure: nil)])
  func staleEntryHelpAppearsAtTenSeconds(_ p: PermissionState) {
    #expect(OnboardingViewState.derive(p, relaunchOffered: false).staleEntryHelp == nil, "\(p)")
    #expect(OnboardingViewState.derive(p, relaunchOffered: false, waited: 9.9).staleEntryHelp == nil, "\(p)")
    #expect(OnboardingViewState.derive(p, relaunchOffered: false, waited: 10).staleEntryHelp == Self.help, "\(p)")
    #expect(OnboardingViewState.derive(p, relaunchOffered: false, waited: 60).staleEntryHelp == Self.help, "\(p)")
  }

  @Test func grantedAndSuspectHaveNoWindow() {
    for p in [PermissionState.granted, .suspect(since: 1)] {
      #expect(!OnboardingViewState.derive(p, relaunchOffered: false).windowVisible, "\(p)")
    }
  }
}
