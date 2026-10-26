import AppKit
import SwiftUI
import os
import ZonesCore
import ZonesWindowing

/// Owns the single onboarding window (ADR-0021). `show()` creates or fronts it, `dismiss()` closes it. It never
/// polls trust: `PermissionMachine` does, and the composition root calls `show`, `dismiss` and `update` for the
/// `showOnboarding`, `dismissOnboarding` and `offerRelaunch` effects.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
  private(set) var window: NSWindow?
  let model: OnboardingModel

  private let probe: any PermissionProbe
  private let preferences: () -> Preferences
  private let clock: any Clock
  private let activate: @MainActor () -> Void
  private let makeWindow: @MainActor () -> NSWindow
  /// Clock time the window opened in a waiting state (`notGranted` or `revoked`); nil otherwise (T56).
  private var waitingSince: TimeInterval?

  init(
    probe: any PermissionProbe, preferences: @escaping () -> Preferences,
    clock: any Clock = ProductionClock(),
    relaunch: @escaping @MainActor () -> Void = OnboardingWindowController.relaunchApp,
    activate: @escaping @MainActor () -> Void = { NSApp.activate() },
    makeWindow: @escaping @MainActor () -> NSWindow = OnboardingWindowController.defaultWindow
  ) {
    self.probe = probe
    self.preferences = preferences
    self.clock = clock
    self.activate = activate
    self.makeWindow = makeWindow
    model = OnboardingModel(
      preferences: preferences(),
      openSettings: { [probe] in probe.openAccessibilitySettings() },
      quitAndReopen: relaunch)
    super.init()
    // Key caps follow the Activation and Span Modifier chosen in General (single source: the preference blob).
    // The controller lives for the app lifetime, so the observer token is never removed.
    _ = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshPreferences() } }
  }

  /// `PermissionEffect.showOnboarding`. A no-op on the launched-at-login path: the badge and the
  /// "Grant Accessibility" menu item stand in. Fronts the existing window when there is one. With `activating`
  /// false (T66) the window comes to the front without activating Zones, so the user's app keeps focus.
  func show(activating: Bool = true) {
    guard !probe.launchedAtLogin else { return }
    let window = window ?? makeAndStoreWindow()
    startWaitIfNeeded()
    if activating {
      activate()
      window.makeKeyAndOrderFront(nil)
    } else {
      window.orderFrontRegardless()
    }
  }

  /// The "Grant Accessibility" menu item: an explicit user click, so it is never inert. Launched at login no
  /// window appears (ADR-0021), so it opens the Accessibility pane directly; otherwise it fronts
  /// the onboarding window.
  func grantAccessibility() {
    if probe.launchedAtLogin {
      probe.openAccessibilitySettings()
    } else {
      show()
    }
  }

  /// `PermissionEffect.dismissOnboarding`: closes whichever page is showing.
  func dismiss() {
    window?.close()
  }

  /// Follows the reducer state and the `offerRelaunch` effect.
  func update(permission: PermissionState, relaunchOffered: Bool) {
    model.permission = permission
    model.relaunchOffered = relaunchOffered
    if OnboardingViewState.waitsForGrant(permission) { startWaitIfNeeded() } else { resetWait() }
  }

  /// After each trust poll (`PermissionDriver.onTrustPoll`, 1 s in the waiting states): refreshes how long the
  /// window has waited, so the stale-entry help line needs no timer of its own (AC-156).
  func trustPolled() {
    guard let waitingSince else { return }
    model.waited = clock.now - waitingSince
  }

  private func startWaitIfNeeded() {
    guard window != nil, waitingSince == nil, OnboardingViewState.waitsForGrant(model.permission) else { return }
    waitingSince = clock.now
    model.waited = 0
  }

  private func resetWait() {
    waitingSince = nil
    model.waited = 0
  }

  func refreshPreferences() {
    let current = preferences()
    if model.preferences != current { model.preferences = current }
  }

  /// The button action: only the probe, never `AXIsProcessTrusted` (AC-004).
  func openSettings() { model.openSettings() }

  func windowWillClose(_ notification: Notification) {
    window = nil
    resetWait()
  }

  private func makeAndStoreWindow() -> NSWindow {
    let window = makeWindow()
    window.delegate = self
    window.contentView = NSHostingView(rootView: OnboardingView(model: model))
    self.window = window
    return window
  }

  static func defaultWindow() -> NSWindow {
    let window = SettingsWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Welcome to Zones"
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.center()
    return window
  }

  /// `NSWorkspace.openApplication(at:configuration:completionHandler:)`, as a seam for tests.
  typealias OpenApplication = (
    _ url: URL, _ configuration: NSWorkspace.OpenConfiguration,
    _ completion: @escaping @Sendable (NSRunningApplication?, (any Error)?) -> Void
  ) -> Void

  /// Opens a fresh instance of this bundle, then quits this one.
  static func relaunchApp() {
    relaunch(
      bundleURL: Bundle.main.bundleURL,
      openApplication: { url, configuration, completion in
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
      },
      terminate: { NSApp.terminate(nil) })
  }

  /// Terminates only once the new instance is running (`app != nil`, no error). On failure Zones keeps running,
  /// logs under category `app`, and the Quit and Reopen offer (model state) stays up. `didFinish` fires after
  /// the decision, on the main actor.
  static func relaunch(
    bundleURL: URL, openApplication: OpenApplication, terminate: @escaping @MainActor () -> Void,
    didFinish: (@MainActor () -> Void)? = nil
  ) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    // The completion arrives on an arbitrary queue; hop to the main actor before deciding.
    openApplication(bundleURL, configuration) { app, error in
      let failure = error.map { String(describing: $0) } ?? (app == nil ? "no application returned" : nil)
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if let failure {
            Logger(subsystem: UnifiedLogSink.subsystem, category: LogCategory.app.rawValue)
              .error("Relaunch failed, staying running: \(failure, privacy: .public)")
          } else {
            terminate()
          }
          didFinish?()
        }
      }
    }
  }
}
