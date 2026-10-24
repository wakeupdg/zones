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
    switch system.frame(handle) {
    case .value: break
    case .timedOut: return SnapOutcome(result: .timedOut, readBack: nil)
    case .elementGone: return SnapOutcome(result: .elementGone, readBack: nil)
    case .apiDisabled: return SnapOutcome(result: .refused(FrameWriter.apiDisabledCode), readBack: nil)
    case .refused(let code): return SnapOutcome(result: .refused(code), readBack: nil)
    }
    let result = writer.write(
      plan.target, mode: plan.mode, to: handle, policy: policy, health: &health, now: clock.now)
    return SnapOutcome(result: result, readBack: Self.frame(of: result))
  }

  static func frame(of result: FrameWriteResult) -> CGRect? {
    switch result {
    case .applied(let r), .clamped(let r): r
    default: nil
    }
  }
}
