import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout
import ZonesWindowing
import os

/// Runs `DragSessionReducer`: input events in, effects out. Everything goes through one inbox and one loop, so the
/// reducer sees events strictly in order and an `await` on the `WindowActor` never lets another event overtake it.
/// The 60 Hz frame sample timer exists only while the state is `pressed` (AC-156).
@MainActor
final class DragDriver {
  enum Inbound: Sendable {
    case input(InputEvent), tick, topology(TopologySnapshot), space, wake
  }

  private(set) var state: DragState = .idle
  var isIdle: Bool { state == .idle }
  var onIdleChange: @MainActor (Bool) -> Void = { _ in }

  private let clock: any Clock
  private let enumerator: any WindowEnumerator
  private let overlay: any OverlayPresenter
  private let worker: WindowWorker
  private let appState: AppState
  private let topology: TopologyDriver
  private let options: @MainActor () -> AccessibilityOptions
  private let ownPid: pid_t

  private let inbox: AsyncStream<Inbound>
  private let post: AsyncStream<Inbound>.Continuation
  private let tickPending = OSAllocatedUnfairLock(initialState: false)
  private var sampleTimer: TimerHandle?
  private var sampleRefs: [WindowRef] = []
  private var candidates: [WindowRef] = []
  private var lastPoint: CGPoint = .zero
  private var lastFlags: ModifierSet = []
  private var tasks: [Task<Void, Never>] = []

  init(
    clock: any Clock, enumerator: any WindowEnumerator, overlay: any OverlayPresenter, worker: WindowWorker,
    appState: AppState, topology: TopologyDriver, options: @escaping @MainActor () -> AccessibilityOptions,
    ownPid: pid_t
  ) {
    self.clock = clock
    self.enumerator = enumerator
    self.overlay = overlay
    self.worker = worker
    self.appState = appState
    self.topology = topology
    self.options = options
    self.ownPid = ownPid
    (inbox, post) = AsyncStream<Inbound>.makeStream()
  }

  // MARK: Loop

  func start(events: AsyncStream<InputEvent>) {
    stop()
    let post = post
    tasks.append(
      Task {
        for await event in events { post.yield(.input(event)) }
      })
    let inbox = inbox
    tasks.append(
      Task { @MainActor [weak self] in
        for await item in inbox {
          guard let self else { return }
          await self.handle(item)
        }
      })
  }

  func stop() {
    for task in tasks { task.cancel() }
    tasks = []
    stopTimer()
  }

  func topologyChanged(_ snapshot: TopologySnapshot) { post.yield(.topology(snapshot)) }
  func spaceChanged() { post.yield(.space) }
  func wake() { post.yield(.wake) }

  // MARK: One inbound item

  func handle(_ item: Inbound) async {
    switch item {
    case .input(let event): await handle(event)
    case .tick:
      tickPending.withLock { $0 = false }
      await sample()
    case .topology(let snapshot): await rearm(snapshot)
    case .space: await process(.spaceChanged)
    case .wake: await process(.wake)
    }
  }

  private func handle(_ event: InputEvent) async {
    switch event.kind {
    case .leftDown: await mouseDown(event)
    case .leftDragged:
      lastPoint = event.point
      lastFlags = event.flags
      await process(.dragged(point: event.point, flags: event.flags))
    case .leftUp:
      lastPoint = event.point
      lastFlags = event.flags
      await process(.mouseUp(point: event.point, flags: event.flags))
    case .flagsChanged:
      lastFlags = event.flags
      await process(.flagsChanged(event.flags))
    }
  }

  private func mouseDown(_ event: InputEvent) async {
    let found = enumerator.candidates(under: event.point, hint: event.windowUnderPointer)
    let health = await worker.healthSnapshot()
    let prefs = appState.preferences
    // Phase one reads CoreGraphics facts only: no Accessibility call happens before this verdict (ADR-0018).
    let verdict: Verdict =
      found.first.map {
        ExclusionPolicy.phaseOne(
          $0, ownPid: ownPid, exclusions: prefs.exclusions, health: health, now: clock.now)
      } ?? .allow(.full)
    candidates = found
    lastPoint = event.point
    lastFlags = event.flags
    // The modifier configuration is read here, at mouse-down, and nowhere else (AC-111).
    let config = ModifierConfig(activation: prefs.activationModifier, span: prefs.spanModifier)
    await process(
      .mouseDown(point: event.point, flags: event.flags, candidates: found, phaseOne: verdict, config: config))
  }

  private func sample() async {
    guard case .pressed = state, !sampleRefs.isEmpty else { return }
    let refs = sampleRefs
    let results = await worker.sample(refs)
    // A session that ended while the read was in flight ignores its answer.
    guard case .pressed = state else { return }
    await process(.frameSample(results))
  }

  private func rearm(_ snapshot: TopologySnapshot) async {
    guard case .armed(_, _, _, _, let old, _, _, _) = state else { return }
    let layouts = appState.resolvedLayouts(for: snapshot, session: topology.sessionAssignments)
    let context = ArmContext(
      topology: snapshot, layouts: layouts, appearance: appState.preferences.appearance, options: options(),
      hasOriginalFrame: old.hasOriginalFrame)
    await process(.topologyChanged(context))
  }

  // MARK: Reducer step

  func process(_ event: DragEvent) async {
    let wasIdle = isIdle
    let (next, effects) = DragSessionReducer.reduce(state, event)
    state = next
    if wasIdle, !isIdle { onIdleChange(false) }
    for effect in effects { await interpret(effect) }
    // The sample timer lives only in `pressed`, whatever path left it.
    if case .pressed = state {} else { stopTimer() }
    if !wasIdle, isIdle { onIdleChange(true) }
  }

  private func interpret(_ effect: DragEffect) async {
    switch effect {
    case .requestSample(let ids):
      sampleRefs = candidates.filter { ids.contains($0.id) }
      startTimer()
    case .stopSampling: stopTimer()
    case .requestArmContext(let window, _):
      let context = await makeContext(for: window)
      await process(.armContext(context))
      // The reducer holds no cursor point outside armed: replay the last one so the first highlight appears.
      if case .armed = state { await process(.dragged(point: lastPoint, flags: lastFlags)) }
    case .showOverlay(let scene): overlay.show(scene)
    case .updateHighlight(let highlight): overlay.highlight(highlight)
    case .hideOverlay: overlay.hide()
    case .reassertPanels: overlay.reassert()
    case .snap(let plan): _ = await worker.snap(plan)
    case .restore(let window, _): _ = await worker.restore(window, topology: topology.currentSnapshot())
    case .skip(let reason, let ref): Log.shared.skip(reason, ref, category: .input)
    case .log(let message):
      Log.shared.event(LogEvent(time: clock.now, category: .input, level: .info, message: message))
    }
  }

  /// Answers `requestArmContext` from the committed topology and the Layout store (no Accessibility call except the
  /// registry lookup on the `WindowActor`).
  private func makeContext(for window: WindowRef) async -> ArmContext {
    let snapshot = topology.currentSnapshot()
    return ArmContext(
      topology: snapshot, layouts: appState.resolvedLayouts(for: snapshot, session: topology.sessionAssignments),
      appearance: appState.preferences.appearance, options: options(),
      hasOriginalFrame: await worker.hasOriginalFrame(window))
  }

  // MARK: Sample timer

  private func startTimer() {
    guard sampleTimer == nil else { return }
    let pending = tickPending
    let post = post
    sampleTimer = clock.schedule(.frameSample, after: Constants.sampleInterval, repeats: true) {
      // Coalesce: at most one tick waits in the inbox, so a slow read never builds a backlog.
      let alreadyQueued = pending.withLock { queued -> Bool in
        defer { queued = true }
        return queued
      }
      if !alreadyQueued { post.yield(.tick) }
    }
  }

  private func stopTimer() {
    if let handle = sampleTimer { clock.cancel(handle) }
    sampleTimer = nil
    sampleRefs = []
    tickPending.withLock { $0 = false }
  }
}
