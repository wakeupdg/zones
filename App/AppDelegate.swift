import AppKit
import ZonesWindowing

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// The status menu's item titles, in order. AppTests asserts the last one.
  nonisolated static let menuTitles: [String] = ["Edit Layouts…", "Quit Zones"]

  private var statusItem: StatusItemController?
  private var root: CompositionRoot?
  /// The editor's window and its dependencies (T35). The root owns the Control+Option+E chord through
  /// `ShortcutDriver`, so the launcher's own `start()` is never called.
  private var editor: EditorLauncher?
  private var settings: SettingsWindowController?
  private var wakeObserver: (any NSObjectProtocol)?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // The unit-test host launches this delegate too; it must not wire the real tap, hotkeys or Application Support.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
    let editor = EditorLauncher.production()
    self.editor = editor
    let status = StatusItemController()
    let probe = AXPermissionProbe()
    let surfaces = AppSurfaces(probe: probe)
    let ui = UIActions(
      openSettings: { [weak self] in self?.settings?.show(source: .menu) },
      openAbout: { [weak self] in self?.settings?.show(tab: .about, source: .menu) },
      openEditor: { editor.openEditor() },
      requestQuit: { NSApp.terminate(nil) })
    let root = CompositionRoot(
      adapters: CompositionRoot.productionAdapters(
        probe: probe, surfaces: surfaces, diagnostics: AlertDiagnosticsPresenter(), ui: ui))
    self.root = root
    statusItem = status
    status.attach(root.menu.menu)
    surfaces.refresh = { [weak root] in
      guard let root else { return }
      status.apply(StatusItemModel.derive(root.permission.state, tap: root.permission.tap))
    }
    settings = SettingsWindowController(
      topology: { [weak root] in root?.topology.snapshot }, cursor: { NSEvent.mouseLocation },
      permission: { [weak root] in root?.permission.state ?? .notGranted },
      tap: { [weak root] in root?.permission.tap ?? .alive },
      preferences: { [weak root] in root?.state.preferences ?? .defaults },
      onChange: { [weak root] in root?.state.setPreferences($0) },
      onRerunOnboarding: { [weak root] in root?.permission.receive(.reonboard) })
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak root] _ in
      MainActor.assumeIsolated { root?.wake() }
    }
    Task { @MainActor in
      await root.start()
      surfaces.refresh()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    root?.quit()
  }
}
