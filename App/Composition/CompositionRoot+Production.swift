import AppKit
import CoreGraphics
import Foundation
import ZonesCore
import ZonesWindowing

extension CompositionRoot {
  /// The production adapters. Construct inside `applicationDidFinishLaunching` (the probe reads the launch event).
  static func productionAdapters(
    probe: any PermissionProbe, surfaces: any PermissionSurfaces, diagnostics: any DiagnosticsPresenter,
    ui: UIActions
  ) -> CompositionAdapters {
    let primary: @Sendable () -> CGRect = { CGDisplayBounds(CGMainDisplayID()) }
    let displays = ScreenDisplayProvider()
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "Zones")
    return CompositionAdapters(
      clock: ProductionClock(), input: EventTapInputSource(primaryFrame: primary),
      windows: AXWindowSystem(primaryFrame: primary), enumerator: CGWindowEnumerator(primaryFrame: primary),
      displays: displays, overlay: PanelOverlayPresenter(displays: displays), hotkeys: CarbonHotkeyRegistrar(),
      probe: probe, files: FoundationFileSystem(), supportDirectory: support,
      preferences: UserDefaultsPreferenceStorage(), surfaces: surfaces, diagnostics: diagnostics, ui: ui,
      ownPid: ProcessInfo.processInfo.processIdentifier,
      runningApps: {
        NSWorkspace.shared.runningApplications.compactMap { app in
          guard let bundleID = app.bundleIdentifier, let launch = app.launchDate else { return nil }
          return RecoveryRecord(
            bundleID: bundleID, pid: app.processIdentifier, launchDate: launch, priorEnhancedUI: false)
        }
      },
      bundleID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
      identify: FrameWriter.runningAppIdentity,
      accessibilityOptions: {
        AccessibilityOptions(
          reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
          reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
      },
      bundleInfo: { BundleInfo.current() },
      frontmost: {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return nil }
        return (name: app.localizedName ?? id, bundleID: id)
      },
      cursor: { NSEvent.mouseLocation }, logSink: UnifiedLogSink())
  }
}
