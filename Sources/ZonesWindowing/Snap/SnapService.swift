import CoreGraphics
import Foundation
import ZonesCore

public struct SnapOutcome: Hashable, Sendable {
  public var result: FrameWriteResult
  /// The frame the app reports after the writes; this is the recorded truth.
  public var readBack: CGRect?
  public init(result: FrameWriteResult, readBack: CGRect?) {
    self.result = result
    self.readBack = readBack
  }
}

/// noOp when the target is within `frameTolerance` of the current frame (AC-079); clamped gets one
/// position follow-up (AC-071). Touches only the handle it is given (AC-041).
public struct SnapService: Sendable {
  let writer: any FrameWriting
  let system: any WindowSystem
  let clock: any Clock
  let policy: EnhancedUIPolicy

  public init(
    writer: any FrameWriting, system: any WindowSystem, clock: any Clock,
    policy: EnhancedUIPolicy = .toggle
  ) {
    self.writer = writer
    self.system = system
    self.clock = clock
    self.policy = policy
  }

  @WindowActor public func execute(
    _ plan: SnapPlan, handle: WindowHandle, health: inout AppHealth
  ) -> SnapOutcome {
    let now = clock.now
    if health.isUnresponsive(handle.pid, now: now) {
      return SnapOutcome(result: .timedOut, readBack: nil)
    }
    _ = health.consumeRetry(handle.pid, now: now)
    switch FrameWriter.retryingOnce({ system.frame(handle) }, timedOut: { $0 == .timedOut }) {
    case .value(let current):
      if FrameWriter.matches(current, plan.target, mode: plan.mode) {
        return SnapOutcome(result: .noOp(.sameFrame), readBack: current)
      }
    case .timedOut:
      health.markUnresponsive(handle.pid, now: now)
      return SnapOutcome(result: .timedOut, readBack: nil)
    case .elementGone: return SnapOutcome(result: .elementGone, readBack: nil)
    case .apiDisabled: return SnapOutcome(result: .refused(FrameWriter.apiDisabledCode), readBack: nil)
    case .refused(let code): return SnapOutcome(result: .refused(code), readBack: nil)
    }
    let result = writer.write(
      plan.target, mode: plan.mode, to: handle, policy: policy, health: &health, now: now)
    guard case .clamped(let accepted) = result else {
      return SnapOutcome(result: result, readBack: Self.frame(of: result))
    }
    return realign(accepted, to: plan.target, handle: handle, health: &health)
  }

  /// The app kept a different size. One position write puts the top-left on the Zone's origin, then
  /// the read-back is the truth. The result stays `.clamped` so the caller can log it. A follow-up
  /// that fails keeps the first read-back; a timeout still aborts, as everywhere.
  @WindowActor private func realign(
    _ accepted: CGRect, to target: CGRect, handle: WindowHandle, health: inout AppHealth
  ) -> SnapOutcome {
    let follow = writer.write(
      CGRect(origin: target.origin, size: accepted.size), mode: .positionOnly, to: handle,
      policy: policy, health: &health, now: clock.now)
    switch follow {
    case .applied(let r), .clamped(let r): return SnapOutcome(result: .clamped(r), readBack: r)
    case .timedOut: return SnapOutcome(result: .timedOut, readBack: accepted)
    default: return SnapOutcome(result: .clamped(accepted), readBack: accepted)
    }
  }

  static func frame(of result: FrameWriteResult) -> CGRect? {
    switch result {
    case .applied(let r), .clamped(let r): r
    default: nil
    }
  }
}
