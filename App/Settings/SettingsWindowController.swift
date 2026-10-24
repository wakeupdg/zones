import AppKit
import SwiftUI
import ZonesCore
import ZonesWindowing

/// Where a Settings open request came from (AC-023).
enum SettingsOpenSource { case menu, hotkey }

/// One reusable Settings window. Placement and key status follow AC-022 and AC-023.
@MainActor
final class SettingsWindowController {
  /// SPK-014: macOS majors where a Carbon hotkey handler that called `NSApp.activate()` was observed to make
  /// the window key. Only 27 is recorded; 14 and 15 are untested, so there the hotkey orders front only.
  nonisolated static let hotkeyKeyOSMajors: Set<Int> = [27]

  private let topology: () -> TopologySnapshot?
  private let cursor: () -> CGPoint
  private let selection = SettingsSelection()
  private let coordinator: LoginItemToggleCoordinator
  private let osMajor: Int
  private var window: NSWindow?
  private let makeContent: (SettingsSelection, LoginItemToggleCoordinator) -> NSView

  init(
    topology: @escaping () -> TopologySnapshot?, cursor: @escaping () -> CGPoint,
    permission: @escaping () -> PermissionState, tap: @escaping () -> TapState,
    environment: SettingsEnvironment? = nil, registrar: (any HotkeyRegistrar)? = nil,
    onRerunOnboarding: @escaping () -> Void, loginItems: any LoginItemService = SMLoginItemService(),
    bundle: @escaping () -> BundleInfo = { BundleInfo.current() },
    osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
  ) {
    self.topology = topology
    self.cursor = cursor
    self.osMajor = osMajor
    coordinator = LoginItemToggleCoordinator(service: loginItems)
    let environment =
      environment ?? SettingsEnvironment.live(topology: topology, permission: permission, registrar: registrar)
    makeContent = { selection, coordinator in
      NSHostingView(
        rootView: SettingsView(
          selection: selection, environment: environment, about: AboutModel(bundle: bundle()),
          permission: permission, tap: tap, onRerunOnboarding: onRerunOnboarding, coordinator: coordinator))
    }
  }

  func show(tab: SettingsTab = .general, source: SettingsOpenSource) {
    let window = window ?? makeWindow()
    self.window = window
    selection.tab = tab
    place(window)
    NSApp.activate()
    switch source {
    case .menu:
      window.makeKeyAndOrderFront(nil)
    case .hotkey:
      window.orderFrontRegardless()
      if Self.hotkeyKeyOSMajors.contains(osMajor) { window.makeKey() }
    }
  }

  private func makeWindow() -> NSWindow {
    let window = SettingsWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
      styleMask: NSWindow.StyleMask(rawValue: WindowPlacement.settingsStyleMaskRaw),
      backing: .buffered, defer: false)
    window.title = "Zones Settings"
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.contentView = makeContent(selection, coordinator)
    return window
  }

  /// Recomputed on every open: centered in the visible frame of the Display under the cursor.
  private func place(_ window: NSWindow) {
    guard let topology = topology(),
      let display = WindowPlacement.cursorDisplay(cursor: cursor(), in: topology)
    else {
      window.center()
      return
    }
    window.setFrame(WindowPlacement.settingsFrame(cursor: display, size: window.frame.size), display: true)
  }
}
