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
    launchTrace.append("permissionProbe")
    let trusted = adapters.probe.isTrusted()
    if !trusted, !adapters.probe.launchedAtLogin {
      adapters.surfaces.showOnboarding()
    }
    permission.receive(.probe(trusted))
  }
}
