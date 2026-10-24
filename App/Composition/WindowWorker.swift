import CoreGraphics
import Foundation
import ZonesCore
import ZonesWindowing

enum ShortcutRun: Hashable, Sendable {
  case snap(SnapOutcome), restore(RestoreResult), noOp(NoOpReason)
}

/// Everything that touches Accessibility, in one `WindowActor` object (ADR-0015): the Original Frame registry, the
/// unresponsive-app health table and the window handles matched to Drag Session candidates. Its methods are the
/// effect interpreters of the drag and shortcut drivers; they hold no policy of their own.
@WindowActor
final class WindowWorker {
  private let system: any WindowSystem
  private let enumerator: any WindowEnumerator
  private let snapService: SnapService
  private let restoreService: RestoreService
  private let clock: any Clock
  private let ownPid: pid_t
  private let bundleID: @Sendable (pid_t) -> String?
  private(set) var registry = OriginalFrameRegistry()
  private(set) var health = AppHealth()
  private var handles: [WindowID: WindowHandle] = [:]

  nonisolated init(
    system: any WindowSystem, enumerator: any WindowEnumerator, writer: any FrameWriting, clock: any Clock,
    ownPid: pid_t, bundleID: @escaping @Sendable (pid_t) -> String?
  ) {
    self.system = system
    self.enumerator = enumerator
    self.clock = clock
    self.ownPid = ownPid
    self.bundleID = bundleID
    snapService = SnapService(writer: writer, system: system, clock: clock)
    restoreService = RestoreService(writer: writer, clock: clock)
  }

  // MARK: Launch

  func applyLaunchTimeouts() { WindowActor.applyLaunchTimeouts(to: system) }

  /// Sets Enhanced UI back on for each app a previous run left with it off (AC-076).
  func restoreEnhancedUI(pids: [pid_t]) {
    for pid in pids { _ = system.setEnhancedUI(true, pid: pid) }
  }

  func trivialRead() -> AXStatus { system.trivialRead() }

  func notices() -> AsyncStream<AXNotice> { system.notices() }

  func apply(_ notice: AXNotice) {
    registry.apply(notice)
    switch notice {
    case .destroyed(let key): handles = handles.filter { $0.value.key != key }
    case .appTerminated(let pid): handles = handles.filter { $0.value.pid != pid }
    case .moved, .apiDisabled: break
    }
  }

  // MARK: Reads for the Drag Session

  func healthSnapshot() -> AppHealth { health }

  func hasOriginalFrame(_ ref: WindowRef) -> Bool {
    guard let handle = handles[ref.id] else { return false }
    return registry.entry(handle.key) != nil
  }

  /// Test seam and keyboard path: store an Original Frame the way a first Snap would.
  @discardableResult func capture(_ entry: OriginalFrameEntry) -> Bool { registry.capture(entry) }

  /// One batched frame read for the candidates. Facts ride with a moved sample (ADR-0006).
  func sample(_ refs: [WindowRef]) -> [WindowID: SampleResult] {
    var results: [WindowID: SampleResult] = [:]
    var live: [(ref: WindowRef, handle: WindowHandle)] = []
    for ref in refs {
      if let handle = handles[ref.id] ?? resolve(ref) {
        handles[ref.id] = handle
        live.append((ref, handle))
      } else {
        results[ref.id] = .gone
      }
    }
    guard !live.isEmpty else { return results }
    let frames = system.frames(live.map(\.handle))
    for (ref, handle) in live {
      switch frames[handle.key] {
      case .value(let frame)?:
        var facts: WindowFacts?
        if Self.moved(frame, from: ref.frame), case .value(let read) = system.facts(handle) { facts = read }
        results[ref.id] = .frame(frame, facts)
      case .timedOut?:
        results[ref.id] = .timedOut
      default:
        handles[ref.id] = nil
        results[ref.id] = .gone
      }
    }
    return results
  }

  /// The handle whose frame equals the candidate's CoreGraphics frame (both in AppKit global space).
  private func resolve(_ ref: WindowRef) -> WindowHandle? {
    let candidates = system.windows(of: ref.pid)
    guard !candidates.isEmpty else { return nil }
    let frames = system.frames(candidates)
    var best: (handle: WindowHandle, distance: Double)?
    for handle in candidates {
      guard case .value(let frame)? = frames[handle.key] else { continue }
      let distance = Self.distance(frame, ref.frame)
      if distance <= Constants.cycleTolerance, distance < (best?.distance ?? .infinity) { best = (handle, distance) }
    }
    return best?.handle
  }

  // MARK: Writes

  func snap(_ plan: SnapPlan) -> SnapOutcome? {
    guard let handle = handles[plan.window.id] ?? resolve(plan.window) else {
      log("snap: no Accessibility window for the dragged window", plan.window)
      return nil
    }
    handles[plan.window.id] = handle
    return execute(plan, handle: handle)
  }

  private func execute(_ plan: SnapPlan, handle: WindowHandle) -> SnapOutcome {
    let outcome = snapService.execute(plan, handle: handle, health: &health)
    switch outcome.result {
    case .applied(let frame), .clamped(let frame):
      if let original = plan.originalFrame {
        _ = registry.capture(OriginalFrameEntry(key: handle.key, frame: original, via: plan.via))
      }
      registry.recordSnap(
        LastSnapRecord(key: handle.key, display: plan.display, zones: plan.zones, frame: outcome.readBack ?? frame))
    case .noOp(.sameFrame):
      registry.recordSnap(
        LastSnapRecord(key: handle.key, display: plan.display, zones: plan.zones, frame: outcome.readBack ?? plan.target))
    default:
      log("snap not applied: \(outcome.result)", plan.window)
    }
    return outcome
  }

  /// Mouse-up over no Zone: put the window back at its Original Frame.
  func restore(_ ref: WindowRef, topology: TopologySnapshot) -> RestoreResult? {
    guard let handle = handles[ref.id] else {
      log("restore: no Accessibility window for the dragged window", ref)
      return nil
    }
    var window = ref
    if case .value(let frame) = system.frame(handle) { window.frame = frame }
    var facts: WindowFacts?
    if case .value(let read) = system.facts(handle) { facts = read }
    return restoreService.restoreFocused(
      registry: &registry, key: handle.key, window: window, facts: facts, handle: handle, topology: topology,
      mode: .full, health: &health)
  }

  // MARK: Keyboard path

  /// One window-action press on the focused window: read, plan, write. The plan is pure; this only reads and writes.
  func shortcut(
    _ action: ShortcutAction, topology: TopologySnapshot, layouts: [DisplayKey: ResolvedLayout],
    exclusions: Set<String>
  ) -> ShortcutRun {
    var focused: FocusedWindow?
    var handle: WindowHandle?
    var verdict = Verdict.allow(.full)
    if let h = system.focusedWindow(), case .value(let frame) = system.frame(h),
      case .value(let facts) = system.facts(h)
    {
      let ref = reference(for: h, frame: frame)
      handle = h
      verdict = ExclusionPolicy.phaseOne(
        ref, ownPid: ownPid, exclusions: exclusions, health: health, now: clock.now)
      focused = FocusedWindow(record: WindowRecord(ref: ref, handle: h, facts: facts), facts: facts, frame: frame)
    }
    let plan = ShortcutResolver.plan(
      action, focused: focused, verdict: verdict, topology: topology, layouts: layouts, registry: registry)
    switch plan {
    case .noOp(let reason): return .noOp(reason)
    case .snap(let snapPlan):
      guard let handle else { return .noOp(.windowAbsent) }
      return .snap(execute(snapPlan, handle: handle))
    case .restore(let entry, let target):
      guard let handle, let focused else { return .noOp(.windowAbsent) }
      var mode = SnapMode.full
      if case .allow(let allowed) = verdict { mode = allowed }
      let result = restoreService.restore(entry, handle: handle, target: target, mode: mode, health: &health)
      switch result {
      case .applied, .clamped, .failed(.elementGone): registry.forget(focused.record.handle.key)
      case .noOp, .failed: break
      }
      return .restore(result)
    }
  }

  /// The CoreGraphics description of an Accessibility window: the on-screen window of that pid with the same frame,
  /// else a stand-in carrying only the facts we have.
  private func reference(for handle: WindowHandle, frame: CGRect) -> WindowRef {
    let match = enumerator.onScreenWindows()
      .filter { $0.pid == handle.pid && Self.distance($0.frame, frame) <= Constants.cycleTolerance }
      .min { Self.distance($0.frame, frame) < Self.distance($1.frame, frame) }
    if let match {
      handles[match.id] = handle
      return match
    }
    return WindowRef(
      id: WindowID(rawValue: 0), pid: handle.pid, bundleID: bundleID(handle.pid), frame: frame, layer: 0)
  }

  // MARK: Helpers

  private func log(_ message: String, _ ref: WindowRef) {
    Log.shared.event(
      LogEvent(
        time: clock.now, category: .windowing, level: .info, message: message, bundleID: ref.bundleID, pid: ref.pid))
  }

  private static func distance(_ a: CGRect, _ b: CGRect) -> Double {
    max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height))
  }

  private static func moved(_ frame: CGRect, from down: CGRect) -> Bool {
    abs(frame.origin.x - down.origin.x) > Constants.frameTolerance
      || abs(frame.origin.y - down.origin.y) > Constants.frameTolerance
  }
}
