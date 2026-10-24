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
}
