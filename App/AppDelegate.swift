import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// The status menu's item titles, in order. AppTests asserts the last one.
  nonisolated static let menuTitles: [String] = ["Quit Zones"]

  private var statusItem: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.image = NSImage(
      systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Zones")
    let menu = NSMenu()
    let quit = NSMenuItem(
      title: Self.menuTitles[0], action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    menu.addItem(quit)
    item.menu = menu
    statusItem = item
  }
}
