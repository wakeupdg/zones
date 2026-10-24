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

  @Test func grantedAndSuspectHaveNoWindow() {
    for p in [PermissionState.granted, .suspect(since: 1)] {
      #expect(!OnboardingViewState.derive(p, relaunchOffered: false).windowVisible, "\(p)")
    }
  }
}
