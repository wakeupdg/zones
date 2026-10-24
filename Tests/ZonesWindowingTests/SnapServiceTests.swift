import ApplicationServices
import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

/// Snap service against `FakeWindowSystem` and `FakeClock`. The fake's `frame` answers come from the
/// queue, so each test scripts the current frame first and the read-back frame second.
@Suite struct SnapServiceTests {
  static let target = CGRect(x: 100, y: 50, width: 400, height: 300)
  static let elsewhere = CGRect(x: 0, y: 0, width: 800, height: 600)

  struct Rig {
    let clock = FakeClock()
    let ws: FakeWindowSystem
    let handle: WindowHandle
    let service: SnapService
    var health = AppHealth()

    init(pid: pid_t = getpid()) {
      ws = FakeWindowSystem(clock: clock)
      handle = WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
      let store = DocumentStore(
        fs: FakeFileSystem(), directory: URL(filePath: "/zones-test"), clock: clock)
      service = SnapService(
        writer: FrameWriter(system: ws, recovery: EnhancedUIRecovery(store: store)), system: ws,
        clock: clock)
    }

    func plan(
      target: CGRect = SnapServiceTests.target, mode: SnapMode = .full, pid: pid_t = getpid()
    ) -> SnapPlan {
      SnapPlan(
        window: WindowRef(
          id: WindowID(rawValue: 1), pid: pid, bundleID: "com.example.app", frame: target, layer: 0),
        display: .uuid("11111111-1111-4111-8111-111111111111"), zones: [1], target: target,
        mode: mode, via: .keyboard, originalFrame: nil)
    }

    /// Script the pre-write frame, then whatever the app reports after the writes.
    func script(current: CGRect, readBack: CGRect? = nil) {
      ws.enqueue(.frame(.value(current)))
      if let readBack { ws.enqueue(.frame(.value(readBack))) }
    }

    @WindowActor mutating func run(_ plan: SnapPlan) -> SnapOutcome {
      service.execute(plan, handle: handle, health: &health)
    }
  }

  /// AC-073: setSize, setPosition, setSize, then the read-back.
  @Test @WindowActor func writeOrderSizePositionSize() {
    var rig = Rig()
    rig.script(current: Self.elsewhere, readBack: Self.target)
    let outcome = rig.run(rig.plan())
    let h = rig.handle
    #expect(outcome.result == .applied(Self.target))
    #expect(
      rig.ws.calls == [
        .frame(h),
        .setSize(Self.target.size, h), .setPosition(Self.target.origin, h),
        .setSize(Self.target.size, h), .frame(h),
      ])
  }

  /// AC-072: the outcome carries what the app accepted, not what was asked for.
  @Test @WindowActor func resultCarriesReadBackFrame() {
    var rig = Rig()
    let accepted = CGRect(x: 100, y: 50, width: 650, height: 500)
    rig.script(current: Self.elsewhere, readBack: accepted)
    rig.ws.enqueue(.frame(.value(accepted)))  // the clamp follow-up reads the same frame again
    let outcome = rig.run(rig.plan())
    #expect(outcome.result == .clamped(accepted))
    #expect(outcome.readBack == accepted)
    #expect(outcome.readBack != Self.target)
  }

  /// AC-079: the window is already in the Zone, so nothing is written.
  @Test @WindowActor func sameZoneIsNoOp() {
    var rig = Rig()
    let nearly = Self.target.offsetBy(dx: 0.9, dy: -1.0)
    rig.script(current: nearly)
    let outcome = rig.run(rig.plan())
    #expect(outcome == SnapOutcome(result: .noOp(.sameFrame), readBack: nearly))
    #expect(rig.ws.calls == [.frame(rig.handle)])

    // Position-only compares the origin and ignores the size.
    rig.ws.reset()
    let sameOrigin = CGRect(origin: Self.target.origin, size: CGSize(width: 900, height: 700))
    rig.script(current: sameOrigin)
    let positionOnly = rig.run(rig.plan(mode: .positionOnly))
    #expect(positionOnly.result == .noOp(.sameFrame))
    #expect(rig.ws.calls == [.frame(rig.handle)])

    // Just past the tolerance is a real move.
    rig.ws.reset()
    rig.script(current: Self.target.offsetBy(dx: 1.5, dy: 0), readBack: Self.target)
    let moved = rig.run(rig.plan())
    #expect(moved.result == .applied(Self.target))
  }

  /// AC-071: the app kept a larger size, so one position write puts the top-left in the Zone. No more.
  @Test @WindowActor func clampedGetsOneRepositionOnly() {
    var rig = Rig()
    let accepted = CGRect(x: 60, y: 20, width: 650, height: 500)  // bigger than the Zone, drifted
    let aligned = CGRect(origin: Self.target.origin, size: accepted.size)
    rig.script(current: Self.elsewhere, readBack: accepted)
    rig.ws.enqueue(.frame(.value(aligned)))
    let outcome = rig.run(rig.plan())
    let h = rig.handle
    #expect(
      rig.ws.calls == [
        .frame(h),
        .setSize(Self.target.size, h), .setPosition(Self.target.origin, h),
        .setSize(Self.target.size, h), .frame(h),
        .setPosition(Self.target.origin, h), .frame(h),
      ])
    #expect(outcome.result == .clamped(aligned))
    #expect(outcome.readBack == aligned)
  }

  /// AC-041: every call in the log names the plan's handle; the second window is never touched.
  @Test @WindowActor func writesOnlyTargetHandle() {
    var rig = Rig()
    let other = WindowHandle(element: AXUIElementCreateApplication(1), pid: 1)
    #expect(other != rig.handle)
    rig.ws.enqueue(.windows([rig.handle, other]))
    #expect(rig.ws.windows(of: getpid()) == [rig.handle, other])
    rig.ws.reset()

    // A clamped Snap, so the follow-up write is covered too.
    let accepted = CGRect(x: 60, y: 20, width: 650, height: 500)
    rig.script(current: Self.elsewhere, readBack: accepted)
    rig.ws.enqueue(.frame(.value(accepted)))
    _ = rig.run(rig.plan())

    var handles: [WindowHandle] = []
    for call in rig.ws.calls {
      switch call {
      case .frame(let h), .setPosition(_, let h), .setSize(_, let h): handles.append(h)
      default: Issue.record("unexpected call \(call)")
      }
    }
    #expect(handles.count == rig.ws.calls.count)
    #expect(handles.allSatisfy { $0 == rig.handle })
    #expect(!handles.contains(other))
  }
}
