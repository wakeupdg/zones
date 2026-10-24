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
}
