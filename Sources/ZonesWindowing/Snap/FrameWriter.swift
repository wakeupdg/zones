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

  /// What `prepareEnhancedUI` hands back; `run` undoes the toggle. T19 fills it.
  struct EnhancedUIRestore {
    let run: @WindowActor () -> Void
    static let none = EnhancedUIRestore(run: {})
  }

  /// Hook: turn AXEnhancedUserInterface off before the writes. Skips when the policy is `.leave`,
  /// the attribute is absent or it is already off. No AX calls until T19 fills this in.
  @WindowActor func prepareEnhancedUI(pid: pid_t, policy: EnhancedUIPolicy) -> EnhancedUIRestore {
    .none
  }

  @WindowActor public func write(
    _ target: CGRect, mode: SnapMode, to h: WindowHandle, policy: EnhancedUIPolicy,
    health: inout AppHealth, now: TimeInterval
  ) -> FrameWriteResult {
    let restore = prepareEnhancedUI(pid: h.pid, policy: policy)
    defer { restore.run() }

    var steps: [@WindowActor () -> AXStatus] = []
    if mode == .full { steps.append { system.setSize(target.size, h) } }
    steps.append { system.setPosition(target.origin, h) }
    if mode == .full { steps.append { system.setSize(target.size, h) } }

    for step in steps {
      if let failure = Self.failure(of: step()) { return failure }
    }
    switch system.frame(h) {
    case .value(let readBack):
      return Self.matches(readBack, target, mode: mode) ? .applied(readBack) : .clamped(readBack)
    case .timedOut: return .timedOut
    case .elementGone: return .elementGone
    case .apiDisabled: return .refused(Self.apiDisabledCode)
    case .refused(let code): return .refused(code)
    }
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
