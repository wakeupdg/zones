import Testing
import ZonesCore

@testable import Zones

/// QA-1.0: an inapplicable Back or Next is disabled, not dimmed while still enabled.
@MainActor
@Suite struct OnboardingViewTests {
  private func makeModel() -> OnboardingModel {
    OnboardingModel(preferences: Preferences.defaults, openSettings: {}, quitAndReopen: {})
  }

  @Test func inapplicableNavIsDisabled() {
    let model = makeModel()
    model.page = .accessibility
    #expect(!model.canGoBack)
    #expect(model.canGoNext)
    model.page = .cheatSheet
    #expect(model.canGoBack)
    #expect(!model.canGoNext)
  }
}
