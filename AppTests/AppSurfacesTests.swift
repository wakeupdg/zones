import AppKit
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

/// ADR-0021: the permission effects reach T33's one onboarding window and its Quit and Reopen offer; the root
/// never opens System Settings by itself and never runs its own alert (AC-070 first-run path).
@MainActor
@Suite struct AppSurfacesTests {
  private func make(launchedAtLogin: Bool = false) -> (AppSurfaces, OnboardingWindowController, FakePermissionProbe, () -> Int) {
    let probe = FakePermissionProbe(clock: FakeClock())
    probe.launchedAtLogin = launchedAtLogin
    var windows = 0
    let onboarding = OnboardingWindowController(
      probe: probe, preferences: { Preferences.defaults }, relaunch: {}, activate: {},
      makeWindow: {
        windows += 1
        return OnboardingWindowController.defaultWindow()
      })
    let surfaces = AppSurfaces(onboarding: onboarding)
    return (surfaces, onboarding, probe, { windows })
  }

  @Test func showOnboardingOpensTheOnboardingWindowNotSystemSettings() {
    let (surfaces, onboarding, probe, created) = make()
    surfaces.showOnboarding()
    surfaces.showOnboarding()
    #expect(created() == 1)
    #expect(onboarding.window != nil)
    #expect(probe.calls.isEmpty)
    surfaces.dismissOnboarding()
    #expect(onboarding.window == nil)
  }

  @Test func noWindowWhenLaunchedAtLogin() {
    let (surfaces, onboarding, probe, created) = make(launchedAtLogin: true)
    surfaces.showOnboarding()
    #expect(created() == 0)
    #expect(onboarding.window == nil)
    #expect(probe.calls.isEmpty)
  }

  @Test func offerRelaunchFeedsTheOnboardingModel() {
    let (surfaces, onboarding, _, _) = make()
    var refreshed = 0
    surfaces.refresh = { refreshed += 1 }
    surfaces.permission = { .needsRelaunch }
    surfaces.offerRelaunch(true)
    #expect(onboarding.model.permission == .needsRelaunch)
    #expect(onboarding.model.relaunchOffered)
    #expect(onboarding.model.viewState.showQuitAndReopen)
    surfaces.offerRelaunch(false)
    #expect(!onboarding.model.relaunchOffered)
    #expect(refreshed == 2)
    onboarding.dismiss()
  }

  /// T66 (T33 known issue): Accessibility lost while Zones runs in the background (`revoked`, the relaunch offer)
  /// fronts the window without taking focus; first run and Re-run Onboarding (`notGranted`) and the Grant menu
  /// item are user actions and still activate.
  @Test func lossWhileInBackgroundDoesNotStealFocus() {
    var activations = 0
    let onboarding = OnboardingWindowController(
      probe: FakePermissionProbe(clock: FakeClock()), preferences: { Preferences.defaults }, relaunch: {},
      activate: { activations += 1 }, makeWindow: OnboardingWindowController.defaultWindow)
    let surfaces = AppSurfaces(onboarding: onboarding)
    defer { onboarding.dismiss() }

    surfaces.permission = { .revoked(failures: 0, firstFailure: nil) }
    surfaces.showOnboarding()
    #expect(activations == 0)
    #expect(onboarding.window?.isVisible == true)
    surfaces.permission = { .needsRelaunch }
    surfaces.offerRelaunch(true)
    #expect(activations == 0)

    onboarding.dismiss()
    surfaces.permission = { .notGranted }
    surfaces.showOnboarding()
    #expect(activations == 1)
    onboarding.grantAccessibility()
    #expect(activations == 2)
  }

  @Test func permissionChangesReachTheModel() {
    let (surfaces, onboarding, _, _) = make()
    surfaces.permission = { .revoked(failures: 3, firstFailure: 0) }
    surfaces.setBadge(true)
    #expect(onboarding.model.permission == .revoked(failures: 3, firstFailure: 0))
  }
}
