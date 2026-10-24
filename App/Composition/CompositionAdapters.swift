import Foundation
import ZonesCore
import ZonesWindowing

/// What the permission machine shows (ADR-0021). Production: the status item and the onboarding window.
@MainActor
protocol PermissionSurfaces: AnyObject {
  func setBadge(_ on: Bool)
  func setGrantMenuItem(_ on: Bool)
  func showOnboarding()
  func dismissOnboarding()
  func offerRelaunch(_ on: Bool)
}

/// Copy Diagnostics is preview first (AC-154): `showPreview` returns true when the user confirmed the copy.
@MainActor
protocol DiagnosticsPresenter: AnyObject {
  func showPreview(_ text: String) -> Bool
  func copy(_ text: String)
}

/// Windows the root opens on request. The editor is a later ticket; until then `openEditor` only logs.
struct UIActions {
  var openSettings: @MainActor () -> Void
  var openAbout: @MainActor () -> Void
  var openEditor: @MainActor () -> Void
  var requestQuit: @MainActor () -> Void
  /// The status menu's Grant Accessibility item: the onboarding window (System Settings at login).
  var grantAccessibility: @MainActor () -> Void
}

/// Every adapter the composition root needs, as an injected protocol: tests pass fakes, production passes the
/// real thing (`CompositionRoot.production`).
struct CompositionAdapters {
  var clock: any Clock
  var input: any InputSource
  var windows: any WindowSystem
  var enumerator: any WindowEnumerator
  var displays: any DisplayProvider
  var overlay: any OverlayPresenter
  var hotkeys: any HotkeyRegistrar
  var probe: any PermissionProbe
  var files: any FileSystem
  var supportDirectory: URL
  var preferences: any PreferenceStorage
  var surfaces: any PermissionSurfaces
  var diagnostics: any DiagnosticsPresenter
  var ui: UIActions
  var ownPid: pid_t
  /// The running apps as recovery-record candidates (Enhanced UI recovery at launch).
  var runningApps: @Sendable () -> [RecoveryRecord]
  var bundleID: @Sendable (pid_t) -> String?
  /// Who owns a pid, for the Enhanced UI recovery record.
  var identify: @Sendable (pid_t) -> (bundleID: String, launchDate: Date)?
  var accessibilityOptions: @MainActor () -> AccessibilityOptions
  var bundleInfo: @Sendable () -> BundleInfo
  /// The frontmost app and the cursor, for the menu (read on the main actor, never through Accessibility).
  var frontmost: @MainActor () -> (name: String, bundleID: String)?
  var cursor: @MainActor () -> CGPoint
}
