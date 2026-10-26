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

    init(pid: pid_t = getpid(), policy: EnhancedUIPolicy = .toggle) {
      ws = FakeWindowSystem(clock: clock)
      handle = WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
      let store = DocumentStore(
        fs: FakeFileSystem(), directory: URL(filePath: "/zones-test"), clock: clock)
      service = SnapService(
        writer: FrameWriter(system: ws, recovery: EnhancedUIRecovery(store: store)), system: ws,
        clock: clock, policy: policy)
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
        .frame(h), .enhancedUI(h.pid),
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
        .frame(h), .enhancedUI(h.pid),
        .setSize(Self.target.size, h), .setPosition(Self.target.origin, h),
        .setSize(Self.target.size, h), .frame(h),
        .enhancedUI(h.pid), .setPosition(Self.target.origin, h), .frame(h),
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
      case .enhancedUI(let pid), .setEnhancedUI(_, let pid): handles.append(pid == rig.handle.pid ? rig.handle : other)
      default: Issue.record("unexpected call \(call)")
      }
    }
    #expect(handles.count == rig.ws.calls.count)
    #expect(handles.allSatisfy { $0 == rig.handle })
    #expect(!handles.contains(other))
  }

  /// AC-077: one immediate retry, then abort, cooldown on the Clock, one attempt afterwards.
  @Test @WindowActor func timeoutRetryOnceThenAbort() {
    var rig = Rig()
    let pid = rig.handle.pid
    let h = rig.handle
    rig.script(current: Self.elsewhere)
    rig.ws.enqueue(.size(.timedOut))
    rig.ws.enqueue(.size(.timedOut))
    let outcome = rig.run(rig.plan())
    #expect(outcome == SnapOutcome(result: .timedOut, readBack: nil))
    // The first call and its one retry; nothing after (the Enhanced UI restore is the only follow-up).
    #expect(
      rig.ws.calls == [
        .frame(h), .enhancedUI(pid), .setSize(Self.target.size, h), .setSize(Self.target.size, h),
      ])
    #expect(rig.health.isUnresponsive(pid, now: rig.clock.now))

    // Cooldown: phase 1 would report skip(unresponsive); the service makes no AX call at all.
    rig.clock.advance(by: 9.9)
    let skipped = rig.run(rig.plan())
    #expect(skipped.result == .timedOut)
    #expect(rig.ws.calls.count == 4)
    #expect(rig.health.isUnresponsive(pid, now: rig.clock.now))

    // After the cooldown exactly one attempt goes through.
    rig.clock.advance(by: 0.1)
    #expect(!rig.health.isUnresponsive(pid, now: rig.clock.now))
    rig.script(current: Self.elsewhere, readBack: Self.target)
    let attempt = rig.run(rig.plan())
    #expect(attempt.result == .applied(Self.target))
    #expect(rig.ws.calls.count == 4 + 6)
    #expect(rig.ws.calls.dropFirst(4).first == .frame(h))
    var spent = rig.health
    let again = spent.consumeRetry(pid, now: rig.clock.now)
    #expect(!again)
  }

  @Test @WindowActor func timeoutRecoversOnRetry() {
    var rig = Rig()
    let h = rig.handle
    rig.script(current: Self.elsewhere, readBack: Self.target)
    rig.ws.enqueue(.position(.timedOut))
    let outcome = rig.run(rig.plan())
    #expect(outcome.result == .applied(Self.target))
    #expect(
      rig.ws.calls == [
        .frame(h), .enhancedUI(h.pid),
        .setSize(Self.target.size, h), .setPosition(Self.target.origin, h),
        .setPosition(Self.target.origin, h),
        .setSize(Self.target.size, h), .frame(h),
      ])
    #expect(!rig.health.isUnresponsive(h.pid, now: rig.clock.now))
  }

  @Test @WindowActor func timeoutOnReadBackAborts() {
    var rig = Rig()
    let h = rig.handle
    rig.script(current: Self.elsewhere)
    rig.ws.enqueue(.frame(.timedOut))
    rig.ws.enqueue(.frame(.timedOut))
    let outcome = rig.run(rig.plan())
    #expect(outcome.result == .timedOut)
    #expect(rig.ws.calls.suffix(2) == [.frame(h), .frame(h)])
    #expect(rig.health.isUnresponsive(h.pid, now: rig.clock.now))
  }

  @Test @WindowActor func timeoutOnFirstReadAborts() {
    var rig = Rig()
    let h = rig.handle
    rig.ws.enqueue(.frame(.timedOut))
    rig.ws.enqueue(.frame(.timedOut))
    let outcome = rig.run(rig.plan())
    #expect(outcome == SnapOutcome(result: .timedOut, readBack: nil))
    #expect(rig.ws.calls == [.frame(h), .frame(h)])
    #expect(rig.health.isUnresponsive(h.pid, now: rig.clock.now))
  }

  /// ADR-0018 amendment C4: a window whose size cannot be set gets setPosition and a read-back only.
  @Test @WindowActor func positionOnlyModeNeverWritesSize() {
    var rig = Rig()
    let h = rig.handle
    let kept = CGRect(origin: Self.target.origin, size: Self.elsewhere.size)
    rig.script(current: Self.elsewhere, readBack: kept)
    let outcome = rig.run(rig.plan(mode: .positionOnly))
    #expect(
      rig.ws.calls == [.frame(h), .enhancedUI(h.pid), .setPosition(Self.target.origin, h), .frame(h)])
    // The size was never asked for, so keeping the old one is not a clamp.
    #expect(outcome == SnapOutcome(result: .applied(kept), readBack: kept))
  }

  /// AC-074: Enhanced UI is read first, set off once before the first size write, and restored last
  /// on every path.
  @Test @WindowActor func enhancedUIRestoredOnEveryPath() {
    let target = Self.target
    func restored(
      _ rig: Rig, sourceLine: Int = #line
    ) {
      #expect(
        rig.ws.calls.last == .setEnhancedUI(true, rig.handle.pid),
        "last call restores Enhanced UI", sourceLocation: SourceLocation(
          fileID: #fileID, filePath: #filePath, line: sourceLine, column: 1))
    }

    // (a) prior on: off before the first size write, back on at the end.
    do {
      var rig = Rig()
      let h = rig.handle
      let pid = h.pid
      rig.script(current: Self.elsewhere, readBack: target)
      rig.ws.enqueue(.enhancedUI(.value(true)))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .applied(target))
      #expect(
        rig.ws.calls == [
          .frame(h), .enhancedUI(pid), .setEnhancedUI(false, pid),
          .setSize(target.size, h), .setPosition(target.origin, h), .setSize(target.size, h),
          .frame(h), .setEnhancedUI(true, pid),
        ])
    }

    // (b) already off, or the attribute is absent: no set at all.
    for prior: Bool? in [false, nil] {
      var rig = Rig()
      let pid = rig.handle.pid
      rig.script(current: Self.elsewhere, readBack: target)
      rig.ws.enqueue(.enhancedUI(.value(prior)))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .applied(target))
      #expect(rig.ws.calls.contains(.enhancedUI(pid)))
      #expect(!rig.ws.calls.contains { if case .setEnhancedUI = $0 { true } else { false } })
    }

    // (c) policy leave: not even a read.
    do {
      var rig = Rig(policy: .leave)
      rig.script(current: Self.elsewhere, readBack: target)
      rig.ws.enqueue(.enhancedUI(.value(true)))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .applied(target))
      #expect(
        !rig.ws.calls.contains {
          switch $0 {
          case .enhancedUI, .setEnhancedUI: true
          default: false
          }
        })
    }

    // (d) refused, elementGone, timedOut abort and clamped: the restore is still the last call.
    do {
      var rig = Rig()
      rig.script(current: Self.elsewhere)
      rig.ws.enqueue(.enhancedUI(.value(true)))
      rig.ws.enqueue(.size(.refused(-25205)))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .refused(-25205))
      restored(rig)
    }
    do {
      var rig = Rig()
      rig.script(current: Self.elsewhere)
      rig.ws.enqueue(.enhancedUI(.value(true)))
      rig.ws.enqueue(.size(.elementGone))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .elementGone)
      restored(rig)
    }
    do {
      var rig = Rig()
      let h = rig.handle
      let pid = h.pid
      rig.script(current: Self.elsewhere)
      rig.ws.enqueue(.enhancedUI(.value(true)))
      rig.ws.enqueue(.size(.timedOut))
      rig.ws.enqueue(.size(.timedOut))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .timedOut)
      #expect(
        rig.ws.calls == [
          .frame(h), .enhancedUI(pid), .setEnhancedUI(false, pid),
          .setSize(target.size, h), .setSize(target.size, h), .setEnhancedUI(true, pid),
        ])
    }
    do {
      var rig = Rig()
      let h = rig.handle
      let pid = h.pid
      let accepted = CGRect(x: 60, y: 20, width: 650, height: 500)
      let aligned = CGRect(origin: target.origin, size: accepted.size)
      rig.script(current: Self.elsewhere, readBack: accepted)
      rig.ws.enqueue(.frame(.value(aligned)))
      rig.ws.enqueue(.enhancedUI(.value(true)))
      rig.ws.enqueue(.enhancedUI(.value(true)))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .clamped(aligned))
      // The first write restores before the follow-up reposition starts its own pair.
      #expect(
        rig.ws.calls == [
          .frame(h), .enhancedUI(pid), .setEnhancedUI(false, pid),
          .setSize(target.size, h), .setPosition(target.origin, h), .setSize(target.size, h),
          .frame(h), .setEnhancedUI(true, pid),
          .enhancedUI(pid), .setEnhancedUI(false, pid),
          .setPosition(target.origin, h), .frame(h), .setEnhancedUI(true, pid),
        ])
    }

    // (e) a failed read skips the toggle and the Snap still writes.
    do {
      var rig = Rig()
      rig.script(current: Self.elsewhere, readBack: target)
      rig.ws.enqueue(.enhancedUI(.timedOut))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .applied(target))
      #expect(!rig.ws.calls.contains { if case .setEnhancedUI = $0 { true } else { false } })
    }

    // (f) a pid in cooldown: zero calls of any kind.
    do {
      var rig = Rig()
      rig.health.markUnresponsive(rig.handle.pid, now: rig.clock.now)
      rig.ws.enqueue(.enhancedUI(.value(true)))
      let outcome = rig.run(rig.plan())
      #expect(outcome.result == .timedOut)
      #expect(rig.ws.calls.isEmpty)
    }
  }
}
