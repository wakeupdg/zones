import AppKit
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

/// Slices 5-7: one onboarding window, none at login, and the button reaches the probe.
@MainActor
@Suite struct OnboardingControllerTests {
  private func make(
    launchedAtLogin: Bool = false
  ) -> (OnboardingWindowController, FakePermissionProbe, () -> Int) {
    let probe = FakePermissionProbe(clock: FakeClock())
    probe.launchedAtLogin = launchedAtLogin
    var windows = 0
    let controller = OnboardingWindowController(
      probe: probe, preferences: { Preferences.defaults }, relaunch: {},
      activate: {}, makeWindow: {
        windows += 1
        return OnboardingWindowController.defaultWindow()
      })
    return (controller, probe, { windows })
  }

  @Test func showTwiceKeepsOneWindow() {
    let (controller, _, created) = make()
    controller.show()
    let first = controller.window
    controller.show()
    #expect(created() == 1)
    #expect(controller.window != nil)
    #expect(controller.window === first)
    controller.dismiss()
    #expect(controller.window == nil)
    #expect(NSApp.windows.filter { $0.title == "Welcome to Zones" && $0.isVisible }.isEmpty)
  }

  @Test func noWindowWhenLaunchedAtLogin() {
    let (controller, _, created) = make(launchedAtLogin: true)
    controller.show()
    #expect(created() == 0)
    #expect(controller.window == nil)
  }

  @Test func openSettingsButtonCallsProbe() {
    let (controller, probe, _) = make()
    controller.openSettings()
    #expect(probe.calls == [.openAccessibilitySettings])
  }
}
