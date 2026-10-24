import CoreGraphics
import Foundation
import ZonesCore

/// Size, position, size; read back; Enhanced UI off/on with `defer`; retry once then abort
/// (ADR-0022, ADR-0015 amended).
public protocol FrameWriting: Sendable {
  @WindowActor func write(
    _ target: CGRect, mode: SnapMode, to h: WindowHandle, policy: EnhancedUIPolicy,
    health: inout AppHealth, now: TimeInterval
  ) -> FrameWriteResult
}

public struct FrameWriter: FrameWriting {
  let system: any WindowSystem
  let recovery: EnhancedUIRecovery

  public init(system: any WindowSystem, recovery: EnhancedUIRecovery) {
    self.system = system
    self.recovery = recovery
  }

  /// What `prepareEnhancedUI` hands back: the value it read (`nil` when absent, unreadable or the
  /// policy is `.leave`) and the undo for the toggle.
  struct EnhancedUIRestore {
    let prior: Bool?
    let run: @WindowActor () -> Void
    static let none = EnhancedUIRestore(prior: nil, run: {})
  }

  /// Reads AXEnhancedUserInterface and, when it is on, turns it off before the writes (ADR-0022).
  /// Skips every call under `.leave`; skips the set when the attribute is absent, off or unreadable.
  /// The restore always writes `true` and is never retried.
  @WindowActor func prepareEnhancedUI(pid: pid_t, policy: EnhancedUIPolicy) -> EnhancedUIRestore {
    guard policy == .toggle else { return .none }
    guard case .value(let attribute) = system.enhancedUI(pid: pid) else { return .none }
    guard attribute == true else { return EnhancedUIRestore(prior: attribute, run: {}) }
    _ = system.setEnhancedUI(false, pid: pid)
    return EnhancedUIRestore(prior: true, run: { _ = system.setEnhancedUI(true, pid: pid) })
  }

  @WindowActor public func write(
    _ target: CGRect, mode: SnapMode, to h: WindowHandle, policy: EnhancedUIPolicy,
    health: inout AppHealth, now: TimeInterval
  ) -> FrameWriteResult {
    // Cooldown gate: no AX call at all while the app is unresponsive. The first call after the
    // cooldown consumes the one allowed attempt.
    if health.isUnresponsive(h.pid, now: now) { return .timedOut }
    _ = health.consumeRetry(h.pid, now: now)

    let restore = prepareEnhancedUI(pid: h.pid, policy: policy)
    defer { restore.run() }

    var steps: [@WindowActor () -> AXStatus] = []
    if mode == .full { steps.append { system.setSize(target.size, h) } }
    steps.append { system.setPosition(target.origin, h) }
    if mode == .full { steps.append { system.setSize(target.size, h) } }

    for step in steps {
      let status = Self.retryingOnce(step) { $0 == .timedOut }
      if status == .timedOut {
        health.markUnresponsive(h.pid, now: now)
        return .timedOut
      }
      if let failure = Self.failure(of: status) { return failure }
    }
    let read = Self.retryingOnce({ system.frame(h) }) { $0 == .timedOut }
    switch read {
    case .value(let readBack):
      return Self.matches(readBack, target, mode: mode) ? .applied(readBack) : .clamped(readBack)
    case .timedOut:
      health.markUnresponsive(h.pid, now: now)
      return .timedOut
    case .elementGone: return .elementGone
    case .apiDisabled: return .refused(Self.apiDisabledCode)
    case .refused(let code): return .refused(code)
    }
  }

  /// Runs `call`; a timeout repeats that same call once at once. A second timeout is returned as is,
  /// and the caller aborts (ADR-0015 amendment C7: worst case 0.5 s).
  @WindowActor static func retryingOnce<R>(
    _ call: @WindowActor () -> R, timedOut: (R) -> Bool
  ) -> R {
    let first = call()
    return timedOut(first) ? call() : first
  }

  /// kAXErrorAPIDisabled; `FrameWriteResult` has no case of its own for it.
  static let apiDisabledCode: Int32 = -25211

  static func failure(of status: AXStatus) -> FrameWriteResult? {
    switch status {
    case .ok: nil
    case .timedOut: .timedOut
    case .elementGone: .elementGone
    case .apiDisabled: .refused(apiDisabledCode)
    case .refused(let code): .refused(code)
    }
  }

  /// Within `Constants.frameTolerance` per component; position-only compares the origin only.
  static func matches(_ a: CGRect, _ b: CGRect, mode: SnapMode) -> Bool {
    let t = Constants.frameTolerance
    let origin = abs(a.origin.x - b.origin.x) <= t && abs(a.origin.y - b.origin.y) <= t
    guard mode == .full else { return origin }
    return origin && abs(a.width - b.width) <= t && abs(a.height - b.height) <= t
  }
}
