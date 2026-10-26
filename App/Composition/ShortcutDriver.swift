import Foundation
import ZonesCore
import ZonesWindowing

/// `ShortcutStore` effects to the Carbon registrar and to persistence, and key presses through
/// `ShortcutDispatcher` and `ShortcutResolver` to the `WindowActor` (ADR-0010, ADR-0011).
@MainActor
final class ShortcutDriver {
  private(set) var store: ShortcutStoreState
  private let hotkeys: any HotkeyRegistrar
  private let worker: WindowWorker
  private let appState: AppState
  private let topology: TopologyDriver
  private let ui: UIActions
  private let isIdle: @MainActor () -> Bool
  private var queue: [ShortcutStoreEvent] = []
  private var draining = false
  private var task: Task<Void, Never>?

  init(
    hotkeys: any HotkeyRegistrar, worker: WindowWorker, appState: AppState, topology: TopologyDriver,
    ui: UIActions, isIdle: @escaping @MainActor () -> Bool
  ) {
    self.hotkeys = hotkeys
    self.worker = worker
    self.appState = appState
    self.topology = topology
    self.ui = ui
    self.isIdle = isIdle
    store = ShortcutStoreState(shortcuts: appState.preferences.shortcuts)
  }

  func start() {
    task?.cancel()
    let presses = hotkeys.presses
    task = Task { @MainActor [weak self] in
      for await action in presses {
        guard let self else { return }
        await self.press(action)
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
  }

  // MARK: Store

  func receive(_ event: ShortcutStoreEvent) {
    queue.append(event)
    guard !draining else { return }
    draining = true
    defer { draining = false }
    while !queue.isEmpty {
      let next = queue.removeFirst()
      let (state, effects) = ShortcutStore.reduce(store, next)
      store = state
      for effect in effects { interpret(effect) }
    }
  }

  private func interpret(_ effect: ShortcutStoreEffect) {
    switch effect {
    case .register(let chord, let action): receive(.registration(action, hotkeys.register(chord, for: action)))
    case .unregister(let action): hotkeys.unregister(action)
    case .failed(let action, let why):
      Log.shared.event(
        LogEvent(
          time: ProcessInfo.processInfo.systemUptime, category: .shortcuts, level: .notice,
          message: "shortcut not registered: \(action) \(why)"))
    case .persist(let shortcuts): appState.setShortcuts(shortcuts)
    }
  }

  // MARK: Presses

  /// One key press. Window commands while a Drag Session is live are dropped by the dispatcher with one log line
  /// (AC-110); the Editor and Settings shortcuts always pass.
  func press(_ action: ShortcutAction) async {
    guard case .success(let allowed) = ShortcutDispatcher.dispatch(action, reducerIdle: isIdle()) else { return }
    switch allowed {
    case .openEditor: ui.openEditor()
    case .openSettings: ui.openSettings()
    case .sendToZone, .cycleRight, .cycleLeft, .restore:
      let snapshot = topology.currentSnapshot()
      let layouts = appState.resolvedLayouts(for: snapshot, session: topology.sessionAssignments)
      _ = await worker.shortcut(
        allowed, topology: snapshot, layouts: layouts, exclusions: appState.preferences.exclusions)
    }
  }
}
