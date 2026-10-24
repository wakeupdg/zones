import Foundation
import ZonesCore
import ZonesWindowing

/// Feeds `DisplayProvider` changes to `TopologyMonitor` and interprets its effects (ADR-0014). No window is ever
/// moved here: a topology change resizes the panels and tells the Drag Session, nothing else.
@MainActor
final class TopologyDriver {
  private(set) var state = TopologyState()
  /// Called after a new snapshot is committed (`topologyChanged`).
  var onChange: @MainActor (TopologySnapshot) -> Void = { _ in }
  var onSpaceChanged: @MainActor () -> Void = {}

  private let clock: any Clock
  private let displays: any DisplayProvider
  private let overlay: any OverlayPresenter
  private let appState: AppState
  private var timers: [TimerID: TimerHandle] = [:]
  private var task: Task<Void, Never>?

  init(clock: any Clock, displays: any DisplayProvider, overlay: any OverlayPresenter, appState: AppState) {
    self.clock = clock
    self.displays = displays
    self.overlay = overlay
    self.appState = appState
  }

  var snapshot: TopologySnapshot? { state.current }

  /// Session-only picks for Displays with an unstable key.
  var sessionAssignments: [DisplayKey: LayoutID] { state.session }

  /// The committed snapshot; the provider is read once when none has been committed yet.
  func currentSnapshot() -> TopologySnapshot {
    if let current = state.current { return current }
    forceSnapshot()
    return state.current ?? displays.snapshot()
  }

  func start() {
    task?.cancel()
    let changes = displays.changes
    task = Task { @MainActor [weak self] in
      for await change in changes {
        guard let self else { return }
        self.receive(change)
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
  }

  func receive(_ change: RawDisplayChange) {
    switch change {
    case .activeSpace: onSpaceChanged()
    case .reconfiguration, .screenParameters, .wake: run(.raw(change))
    }
  }

  /// Wake and launch: read the Displays now, without waiting for the debounce.
  func forceSnapshot() { interpret(.readSnapshot) }

  func pick(_ layout: LayoutID, for key: DisplayKey) { run(.assignmentPicked(key, layout)) }

  func timerFired(_ id: TimerID) {
    timers[id] = nil
    run(.timer(id))
  }

  private func run(_ event: TopologyEvent) {
    let (next, effects) = TopologyMonitor.reduce(
      state, event, assignments: appState.assignments, now: clock.now)
    state = next
    for effect in effects { interpret(effect) }
  }

  private func interpret(_ effect: TopologyEffect) {
    switch effect {
    case .schedule(let id, let seconds):
      if let old = timers.removeValue(forKey: id) { clock.cancel(old) }
      timers[id] = clock.schedule(id, after: seconds, repeats: false) { [weak self] in
        Task { @MainActor in self?.timerFired(id) }
      }
    case .cancel(let id):
      if let old = timers.removeValue(forKey: id) { clock.cancel(old) }
    case .readSnapshot:
      let read = displays.snapshot()
      run(.snapshot(read, nilUUIDs: TopologyMonitor.nilUUIDCount(in: read)))
    case .topologyChanged(let snapshot): onChange(snapshot)
    case .resizePanels(let snapshot): overlay.resize(to: snapshot)
    case .persistAssignment(let key, let assignment): appState.setAssignment(key, assignment)
    case .sessionAssignment(let key, let layout):
      Log.shared.event(
        LogEvent(
          time: clock.now, category: .topology, level: .info,
          message: "session assignment for \(key) -> \(layout.rawValue)"))
    case .notice(let flag): appState.insertNotice(flag)
    }
  }
}
