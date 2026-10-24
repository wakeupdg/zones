import AppKit
import ZonesCore
import ZonesWindowing

/// The menu bar item (AC-018): a template image, badged while permission is not granted or the tap is not alive.
@MainActor
final class StatusItemController {
  private let item: NSStatusItem

  init() {
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    apply(StatusItemModel(badged: true))
  }

  func attach(_ menu: NSMenu) { item.menu = menu }

  func apply(_ model: StatusItemModel) {
    let name = model.badged ? "rectangle.badge.xmark" : "rectangle.split.3x3"
    let image =
      NSImage(systemSymbolName: name, accessibilityDescription: "Zones")
      ?? NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Zones")
    image?.isTemplate = model.isTemplate
    item.button?.image = image
  }
}

/// What the permission machine shows. Every effect refreshes the status item from the live state; the grant
/// menu item is rebuilt on every menu open, so `setGrantMenuItem` has nothing to cache.
@MainActor
final class AppSurfaces: PermissionSurfaces {
  /// Set once the root exists.
  var refresh: @MainActor () -> Void = {}
  private let probe: any PermissionProbe
  private var offeredRelaunch = false

  init(probe: any PermissionProbe) { self.probe = probe }

  func setBadge(_ on: Bool) { refresh() }
  func setGrantMenuItem(_ on: Bool) { refresh() }

  /// EXTENSION(T33): the onboarding window replaces this. Until then System Settings opens at the Accessibility pane.
  func showOnboarding() { probe.openAccessibilitySettings() }
  func dismissOnboarding() {}

  /// Accessibility was granted but the tap still cannot start: macOS wants a relaunch (ADR-0021).
  func offerRelaunch(_ on: Bool) {
    refresh()
    guard on, !offeredRelaunch else { return }
    offeredRelaunch = true
    let alert = NSAlert()
    alert.messageText = "Zones needs to relaunch"
    alert.informativeText = "Accessibility is on, but macOS only lets Zones use it after a relaunch."
    alert.addButton(withTitle: "Relaunch")
    alert.addButton(withTitle: "Later")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
      Task { @MainActor in NSApp.terminate(nil) }
    }
  }
}
