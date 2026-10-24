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

  init(adapters: CompositionAdapters) {
    self.adapters = adapters
    documents = DocumentStore(fs: adapters.files, directory: adapters.supportDirectory, clock: adapters.clock)
    state = AppState(documents: documents, storage: adapters.preferences)
    recovery = EnhancedUIRecovery(store: documents)
    let writer = FrameWriter(system: adapters.windows, recovery: recovery, identify: adapters.identify)
    worker = WindowWorker(
      system: adapters.windows, enumerator: adapters.enumerator, writer: writer, clock: adapters.clock,
      ownPid: adapters.ownPid, bundleID: adapters.bundleID)
  }
}
