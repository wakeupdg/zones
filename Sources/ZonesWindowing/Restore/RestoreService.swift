import CoreGraphics
import Foundation
import ZonesCore

public enum RestoreResult: Hashable, Sendable {
  case applied(CGRect), clamped(CGRect), noOp(NoOpReason), failed(FrameWriteResult)
}

/// Restore writes through `FrameWriting` (size, position, size, read back); it never reimplements the
/// write protocol (ADR-0022). The registry is a plain value, so the service holds no registry and no timer.
public struct RestoreService: Sendable {
  let writer: any FrameWriting
  let clock: any Clock
  let policy: EnhancedUIPolicy
  let log: Log

  public init(writer: any FrameWriting, clock: any Clock, policy: EnhancedUIPolicy = .toggle) {
    self.init(writer: writer, clock: clock, policy: policy, log: .shared)
  }

  init(writer: any FrameWriting, clock: any Clock, policy: EnhancedUIPolicy, log: Log) {
    self.writer = writer
    self.clock = clock
    self.policy = policy
    self.log = log
  }

  /// Writes `target` (the planner's frame) and maps the write result. The caller owns the registry
  /// and forgets the entry on `applied` or `clamped`.
  @WindowActor public func restore(
    _ e: OriginalFrameEntry, handle: WindowHandle, target: CGRect, mode: SnapMode,
    health: inout AppHealth
  ) -> RestoreResult {
    let result = writer.write(
      target, mode: mode, to: handle, policy: policy, health: &health, now: clock.now)
    switch result {
    case .applied(let frame):
      // The planner moved an off-Display frame onto a Display: the Original Frame was not reproduced.
      return FrameWriter.matches(target, e.frame, mode: .full) ? .applied(frame) : .clamped(frame)
    case .clamped(let frame): return .clamped(frame)
    case .noOp(let reason): return .noOp(reason)
    case .refused, .timedOut, .elementGone: return .failed(result)
    }
  }

  /// Additive helper (T24): the lookup, the plan, the write and the forget in one call, so the
  /// keyboard shortcut and the drag reducer share one path. No entry gives `noOp(.noEntry)`; a
  /// full-screen window gives `noOp(.fullScreen)`. Applied and clamped forget the key; `elementGone`
  /// forgets it too (eviction at next touch); other failures keep the entry.
  @WindowActor public func restoreFocused(
    registry: inout OriginalFrameRegistry, key: WindowKey, window: WindowRef, facts: WindowFacts?,
    handle: WindowHandle, topology: TopologySnapshot, mode: SnapMode, health: inout AppHealth
  ) -> RestoreResult {
    guard let entry = registry.entry(key) else { return noOp(.noEntry, window) }
    let target: CGRect
    switch RestorePlanner.plan(entry, window: window, facts: facts, topology: topology) {
    case .success(let frame): target = frame
    case .failure(let reason): return noOp(reason, window)
    }
    let result = restore(entry, handle: handle, target: target, mode: mode, health: &health)
    switch result {
    case .applied, .clamped, .failed(.elementGone): registry.forget(key)
    case .noOp, .failed: break
    }
    return result
  }

  /// One log line per no-op: the reason, pid and bundleID, never a title (LI-003).
  private func noOp(_ reason: NoOpReason, _ window: WindowRef) -> RestoreResult {
    log.event(
      LogEvent(
        time: clock.now, category: .restore, level: .info, message: "restore noOp " + reason.rawValue,
        bundleID: window.bundleID, pid: window.pid))
    return .noOp(reason)
  }
}
