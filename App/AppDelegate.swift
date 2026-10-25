import AppKit
import ZonesCore
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
      documents: root.documents, state: root.state, provider: root.adapters.displays,
      registrar: root.adapters.hotkeys)
    statusItem = status
    self.onboarding = onboarding
    status.attach(root.menu.menu)
    surfaces.permission = { [weak root] in root?.permission.state ?? .notGranted }
    root.permission.onTrustPoll = { [weak onboarding] in onboarding?.trustPolled() }
    surfaces.refresh = { [weak root] in
      guard let root else { return }
      status.apply(StatusItemModel.derive(root.permission.state, tap: root.permission.tap))
    }
    surfaces.refresh()
    // T34's Settings own one PreferencesController on the same "zones.preferences" blob; every change it persists
    // is forwarded to the root's AppState so the drag pipeline sees it without a relaunch (AC-141).
    let topology: () -> TopologySnapshot? = { [weak root] in root?.topology.snapshot }
    let permission: () -> PermissionState = { [weak root] in root?.permission.state ?? .notGranted }
    let settingsEnvironment = SettingsEnvironment.live(
      topology: topology, permission: permission, registrar: root.adapters.hotkeys)
    settingsEnvironment.preferences.onChange = { [weak root] in root?.state.setPreferences($0) }
    // Settings > Layouts reads and writes through the root's AppState, the one owner of Layouts and Assignments.
    settingsEnvironment.layouts.bind(to: root.state)
    settings = SettingsWindowController(
      topology: topology, cursor: { NSEvent.mouseLocation }, permission: permission,
      tap: { [weak root] in root?.permission.tap ?? .alive }, environment: settingsEnvironment,
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
