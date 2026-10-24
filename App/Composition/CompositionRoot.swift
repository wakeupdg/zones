import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// The one place the running app's object graph is built (called from `applicationDidFinishLaunching`).
/// Construction touches no adapter and starts no timer; `start()` does the launch sequence.
@MainActor
final class CompositionRoot {
  let adapters: CompositionAdapters
  let documents: DocumentStore
  let state: AppState
  let recovery: EnhancedUIRecovery
  let worker: WindowWorker
  let permission: PermissionDriver
  let topology: TopologyDriver
  let drag: DragDriver
  let shortcuts: ShortcutDriver
  let lifecycle: LifecycleDriver
  let diagnostics: DiagnosticsController
  let menu: MenuController
  private var loops: [Task<Void, Never>] = []
  /// The launch steps the root performed, in order (AC-159, AC-076, ADR-0021).
  private(set) var launchTrace: [String] = []

  init(adapters: CompositionAdapters) {
    self.adapters = adapters
    documents = DocumentStore(fs: adapters.files, directory: adapters.supportDirectory, clock: adapters.clock)
    state = AppState(documents: documents, storage: adapters.preferences)
    recovery = EnhancedUIRecovery(store: documents)
    let writer = FrameWriter(system: adapters.windows, recovery: recovery, identify: adapters.identify)
    worker = WindowWorker(
      system: adapters.windows, enumerator: adapters.enumerator, writer: writer, clock: adapters.clock,
      ownPid: adapters.ownPid, bundleID: adapters.bundleID)
    permission = PermissionDriver(
      clock: adapters.clock, input: adapters.input, probe: adapters.probe, worker: worker,
      surfaces: adapters.surfaces, overlay: adapters.overlay, recovery: recovery)
    topology = TopologyDriver(
      clock: adapters.clock, displays: adapters.displays, overlay: adapters.overlay, appState: state)
    drag = DragDriver(
      clock: adapters.clock, enumerator: adapters.enumerator, overlay: adapters.overlay, worker: worker,
      appState: state, topology: topology, options: adapters.accessibilityOptions, ownPid: adapters.ownPid)
    shortcuts = ShortcutDriver(
      hotkeys: adapters.hotkeys, worker: worker, appState: state, topology: topology, ui: adapters.ui,
      isIdle: { [drag] in drag.isIdle })
    lifecycle = LifecycleDriver(
      input: adapters.input, probe: adapters.probe, overlay: adapters.overlay, recovery: recovery,
      permission: permission, topology: topology)
    diagnostics = DiagnosticsController(
      appState: state, topology: topology, permission: permission, presenter: adapters.diagnostics,
      bundle: adapters.bundleInfo)
    menu = MenuController(
      appState: state, topology: topology, permission: permission, probe: adapters.probe, ui: adapters.ui,
      frontmost: adapters.frontmost, cursor: adapters.cursor)
    drag.onIdleChange = { [shortcuts] idle in shortcuts.receive(.reducerIdle(idle)) }
    permission.onWindowHotkeys = { [shortcuts] granted in shortcuts.receive(.permission(granted: granted)) }
    topology.onChange = { [drag] snapshot in drag.topologyChanged(snapshot) }
    topology.onSpaceChanged = { [drag] in drag.spaceChanged() }
    permission.dragIdle = { [drag] in drag.isIdle }
    permission.onForceTopologySnapshot = { [topology] in topology.forceSnapshot() }
  }

  /// The launch sequence: Accessibility timeouts, Enhanced UI recovery, then the permission probe. The tap starts
  /// only when the probe says granted (the permission machine's `startTap`).
  func start() async {
    launchTrace.append("timeouts")
    await worker.applyLaunchTimeouts()
    launchTrace.append("enhancedUIRecovery")
    let restored = recovery.restoreAtLaunch(running: adapters.runningApps())
    await worker.restoreEnhancedUI(pids: restored.map { pid_t($0.pid) })
    startLoops()
    launchTrace.append("permissionProbe")
    let trusted = adapters.probe.isTrusted()
    if !trusted, !adapters.probe.launchedAtLogin {
      adapters.surfaces.showOnboarding()
    }
    permission.receive(.probe(trusted))
    shortcuts.receive(.launch)
  }

  /// The long-lived consumers: Displays, input events, hotkeys, tap signals and Accessibility notices. The Display
  /// snapshot is read first so the first Drag Session already has a topology.
  private func startLoops() {
    topology.forceSnapshot()
    topology.start()
    drag.start(events: adapters.input.events)
    shortcuts.start()
    let signals = adapters.input.signals
    loops.append(
      Task { @MainActor [permission] in
        for await signal in signals { permission.signal(signal) }
      })
    loops.append(
      Task { @MainActor [worker, permission] in
        let notices = await worker.notices()
        for await notice in notices {
          await worker.apply(notice)
          if notice == .apiDisabled { permission.receive(.apiDisabled) }
        }
      })
  }

  /// Wake from sleep (AC-026): the Drag Session ends, then the lifecycle effects run in order.
  func wake() {
    drag.wake()
    lifecycle.wake()
  }

  /// Quit (AC-026): loops stop, then the lifecycle effects run in order.
  func quit() {
    for task in loops { task.cancel() }
    loops = []
    drag.stop()
    topology.stop()
    shortcuts.stop()
    lifecycle.quit()
  }
}
