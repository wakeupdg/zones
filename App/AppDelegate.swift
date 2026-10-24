import AppKit
import ZonesWindowing

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// The status menu's item titles, in order. AppTests asserts the last one.
  nonisolated static let menuTitles: [String] = ["Edit Layouts…", "Quit Zones"]

  private var statusItem: StatusItemController?
  private var onboarding: OnboardingWindowController?
  private var root: CompositionRoot?
  /// The editor's window and its dependencies (T35). The root owns the Control+Option+E chord through
  /// `ShortcutDriver`, so the launcher's own `start()` is never called.
  private var editor: EditorLauncher?
  private var settings: SettingsWindowController?
  private var wakeObserver: (any NSObjectProtocol)?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // The unit-test host launches this delegate too; it must not wire the real tap, hotkeys or Application Support.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
    let probe = AXPermissionProbe()
    // ADR-0021: one onboarding window (T33) for showOnboarding / dismissOnboarding / offerRelaunch.
    let onboarding = OnboardingWindowController(probe: probe, preferences: { [weak self] in self?.root?.state.preferences ?? .defaults })
    let status = StatusItemController(
      onGrant: { [weak onboarding] in onboarding?.grantAccessibility() },
      onEditLayouts: { [weak self] in self?.editor?.openEditor() })
    let surfaces = AppSurfaces(onboarding: onboarding)
    let ui = UIActions(
      openSettings: { [weak self] in self?.settings?.show(source: .menu) },
      openAbout: { [weak self] in self?.settings?.show(tab: .about, source: .menu) },
      openEditor: { [weak self] in self?.editor?.openEditor() },
      requestQuit: { NSApp.terminate(nil) },
      grantAccessibility: { [weak onboarding] in onboarding?.grantAccessibility() })
    let root = CompositionRoot(
      adapters: CompositionRoot.productionAdapters(
        probe: probe, surfaces: surfaces, diagnostics: AlertDiagnosticsPresenter(), ui: ui))
    self.root = root
    // Built from the root's own store, Displays and registrar: a second Carbon registrar would install a handler
    // that swallows every 'ZONE' hotkey event before the root's sees it.
    editor = EditorLauncher(
      documents: root.documents, provider: root.adapters.displays, registrar: root.adapters.hotkeys,
      preferences: root.state.preferences)
    statusItem = status
    self.onboarding = onboarding
    status.attach(root.menu.menu)
    surfaces.permission = { [weak root] in root?.permission.state ?? .notGranted }
    surfaces.refresh = { [weak root] in
      guard let root else { return }
      status.apply(StatusItemModel.derive(root.permission.state, tap: root.permission.tap))
    }
    surfaces.refresh()
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
