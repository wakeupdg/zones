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
}
