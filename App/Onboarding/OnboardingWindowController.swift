import AppKit
import SwiftUI
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
  private let activate: @MainActor () -> Void
  private let makeWindow: @MainActor () -> NSWindow

  init(
    probe: any PermissionProbe, preferences: @escaping () -> Preferences,
    relaunch: @escaping @MainActor () -> Void = OnboardingWindowController.relaunchApp,
    activate: @escaping @MainActor () -> Void = { NSApp.activate() },
    makeWindow: @escaping @MainActor () -> NSWindow = OnboardingWindowController.defaultWindow
  ) {
    self.probe = probe
    self.preferences = preferences
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
  /// "Grant Accessibility" menu item stand in. Fronts the existing window when there is one.
  func show() {
    guard !probe.launchedAtLogin else { return }
    let window = window ?? makeAndStoreWindow()
    activate()
    window.makeKeyAndOrderFront(nil)
  }

  /// `PermissionEffect.dismissOnboarding`: closes whichever page is showing.
  func dismiss() {
    window?.close()
  }

  /// Follows the reducer state and the `offerRelaunch` effect.
  func update(permission: PermissionState, relaunchOffered: Bool) {
    model.permission = permission
    model.relaunchOffered = relaunchOffered
  }

  func refreshPreferences() {
    let current = preferences()
    if model.preferences != current { model.preferences = current }
  }

  /// The button action: only the probe, never `AXIsProcessTrusted` (AC-004).
  func openSettings() { model.openSettings() }

  func windowWillClose(_ notification: Notification) {
    window = nil
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

  /// Opens a fresh instance of this bundle, then quits this one.
  static func relaunchApp() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }
}
