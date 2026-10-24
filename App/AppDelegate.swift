import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// The status menu's item titles, in order. AppTests asserts the last one.
  nonisolated static let menuTitles: [String] = ["Edit Layouts…", "Quit Zones"]

  private var statusItem: NSStatusItem?
  /// The editor's door: the "Edit Layouts…" item below and Control+Option+E (AC-126). T36's composition root
  /// replaces this stopgap menu and owns the launcher.
  private var editor: EditorLauncher?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.image = NSImage(
      systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Zones")
    let menu = NSMenu()
    // The unit-test host launches this delegate too; it must not read the real Application Support or grab a hotkey.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
      let launcher = EditorLauncher.production()
      launcher.start()
      editor = launcher
    }
    menu.addItem(ActionTarget.item(title: Self.menuTitles[0]) { [weak self] in self?.editor?.openEditor() })
    let quit = NSMenuItem(
      title: Self.menuTitles[1], action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    menu.addItem(quit)
    item.menu = menu
    statusItem = item
  }
}
