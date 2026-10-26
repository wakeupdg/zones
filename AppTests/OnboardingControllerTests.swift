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
    launchedAtLogin: Bool = false, clock: FakeClock = FakeClock()
  ) -> (OnboardingWindowController, FakePermissionProbe, () -> Int) {
    let probe = FakePermissionProbe(clock: clock)
    probe.launchedAtLogin = launchedAtLogin
    var windows = 0
    let controller = OnboardingWindowController(
      probe: probe, preferences: { Preferences.defaults }, clock: clock, relaunch: {},
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

  /// T66 (T33 known issue): a show the user did not ask for fronts the window without activating Zones, so the
  /// user's app keeps focus; the default show (first run, the menu item) still activates.
  @Test func backgroundShowNeverActivates() {
    var activations = 0
    let controller = OnboardingWindowController(
      probe: FakePermissionProbe(clock: FakeClock()), preferences: { Preferences.defaults }, relaunch: {},
      activate: { activations += 1 }, makeWindow: OnboardingWindowController.defaultWindow)
    defer { controller.dismiss() }
    controller.show(activating: false)
    #expect(activations == 0)
    #expect(controller.window?.isVisible == true)
    controller.show()
    #expect(activations == 1)
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

  /// The "Grant Accessibility" menu item is an explicit user click: at login (no window by ADR-0021) it must
  /// still open System Settings, or the stand-in is inert.
  @Test func grantMenuItemOpensSettingsWhenLaunchedAtLogin() {
    let (controller, probe, created) = make(launchedAtLogin: true)
    controller.grantAccessibility()
    #expect(created() == 0)
    #expect(controller.window == nil)
    #expect(probe.calls == [.openAccessibilitySettings])
  }

  @Test func grantMenuItemShowsWindowOtherwise() {
    let (controller, probe, created) = make()
    controller.grantAccessibility()
    #expect(created() == 1)
    #expect(probe.calls.isEmpty)
    controller.dismiss()
  }

  /// T56: the stale-entry help line follows the Clock time the window has been open in notGranted, refreshed by
  /// the trust poll; a grant at 12 s still dismisses the window (AC-005 path) and clears the line.
  @Test func staleEntryHelpThenGrantAtTwelveSeconds() {
    let clock = FakeClock()
    let (controller, _, _) = make(clock: clock)
    controller.update(permission: .notGranted, relaunchOffered: false)
    controller.show()
    defer { controller.dismiss() }
    clock.advance(by: 9.9)
    controller.trustPolled()
    #expect(controller.model.viewState.staleEntryHelp == nil)
    clock.advance(by: 0.1)
    controller.trustPolled()
    #expect(controller.model.viewState.staleEntryHelp == OnboardingViewState.staleEntrySentence)
    clock.advance(by: 2)
    controller.update(permission: .granted, relaunchOffered: false)
    controller.dismiss()
    #expect(controller.window == nil)
    #expect(controller.model.viewState.staleEntryHelp == nil)
    // A fresh show starts the wait again from zero.
    controller.update(permission: .notGranted, relaunchOffered: false)
    controller.show()
    controller.trustPolled()
    #expect(controller.model.viewState.staleEntryHelp == nil)
  }

  /// The wait only counts while the window is open: a poll with no window never shows the line.
  @Test func noHelpWithoutWindow() {
    let clock = FakeClock()
    let (controller, _, _) = make(clock: clock)
    controller.update(permission: .notGranted, relaunchOffered: false)
    clock.advance(by: 30)
    controller.trustPolled()
    #expect(controller.model.viewState.staleEntryHelp == nil)
  }

  /// QA-1.8: the app quits only once the replacement instance is running; a failed open keeps Zones alive.
  private func relaunch(openResult: (app: NSRunningApplication?, error: (any Error)?)) async -> Int {
    var terminated = 0
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      OnboardingWindowController.relaunch(
        bundleURL: Bundle.main.bundleURL,
        openApplication: { _, _, completion in completion(openResult.app, openResult.error) },
        terminate: { terminated += 1 },
        didFinish: { done.resume() })
    }
    return terminated
  }

  @Test func relaunchFailureKeepsRunning() async {
    struct Failure: Error {}
    #expect(await relaunch(openResult: (nil, Failure())) == 0)
    #expect(await relaunch(openResult: (NSRunningApplication.current, Failure())) == 0)
    #expect(await relaunch(openResult: (nil, nil)) == 0)
  }

  @Test func relaunchSuccessTerminatesOnce() async {
    #expect(await relaunch(openResult: (NSRunningApplication.current, nil)) == 1)
  }
}
