import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@Suite struct DragSessionReducerTests {
  typealias F = DragFixtures

  @Test func clickRequestsNoSample() {
    let down = DragSessionReducer.reduce(.idle, F.mouseDown())
    #expect(F.isPressed(down.0))
    #expect(down.1.isEmpty)

    let up = DragSessionReducer.reduce(down.0, .mouseUp(point: F.downPoint, flags: []))
    #expect(up.0 == .idle)
    #expect(up.1.isEmpty)

    let whole = F.run([F.mouseDown(), .mouseUp(point: F.downPoint, flags: [])])
    #expect(whole.state == .idle)
    #expect(whole.effects.isEmpty)
  }

  @Test func phaseOneSkipEmitsSkipAndStaysIdle() {
    let (s, fx) = DragSessionReducer.reduce(.idle, F.mouseDown(phaseOne: .skip(.ownProcess)))
    #expect(s == .idle)
    #expect(fx == [.skip(.ownProcess, F.window)])
  }

  @Test func emptyCandidatesStayIdle() {
    let (s, fx) = DragSessionReducer.reduce(.idle, F.mouseDown(candidates: []))
    #expect(s == .idle)
    #expect(fx.isEmpty)
  }

  @Test func ignoresSecondMouseDownCore() {
    let (pressed, _) = DragSessionReducer.reduce(.idle, F.mouseDown())
    let (s, fx) = DragSessionReducer.reduce(
      pressed, F.mouseDown(candidates: [F.ref(2, pid: 200)], point: CGPoint(x: 5, y: 5)))
    #expect(s == pressed)
    #expect(fx.isEmpty)
  }

  @Test func overlayOnlyAfterMovedSample() {
    let id = F.window.id
    var (state, fx) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift))
    #expect(fx.isEmpty)

    (state, fx) = DragSessionReducer.reduce(state, F.dragged())
    #expect(fx == [.requestSample([id])])

    (state, fx) = DragSessionReducer.reduce(state, F.unmoved())
    #expect(F.isPressed(state))
    #expect(!fx.contains(where: F.isShowOverlay))

    (state, fx) = DragSessionReducer.reduce(state, F.moved())
    #expect(F.isMoving(state))
    #expect(fx == [.stopSampling, .requestArmContext(window: F.window, point: F.downPoint)])
    #expect(!fx.contains(where: F.isShowOverlay))

    (state, fx) = DragSessionReducer.reduce(state, .armContext(F.context))
    #expect(F.isArmed(state))
    #expect(fx.filter(F.isShowOverlay).count == 1)
  }

  @Test func modifierFirstArmsAfterMove() throws {
    let r = F.run([.flagsChanged(.shift), F.mouseDown(flags: .shift), F.dragged(), F.moved()])
    #expect(F.isArmed(r.state))
    let overlays = r.effects.compactMap { fx -> OverlayScene? in
      if case .showOverlay(let scene) = fx { scene } else { nil }
    }
    #expect(overlays.count == 1)
    let scene = try #require(overlays.first)
    #expect(scene.layouts.count == Fixtures.threeDisplays.displays.count)
    #expect(Set(scene.layouts.map(\.display)) == Set(Fixtures.threeDisplays.displays.map(\.key)))
  }

  @Test func pauseThenMoveStillArms() {
    var (state, _) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift))
    (state, _) = DragSessionReducer.reduce(state, F.dragged())
    for _ in 0..<3 {
      let (next, fx) = DragSessionReducer.reduce(state, F.unmoved())
      #expect(F.isPressed(next))
      #expect(fx == [.requestSample([F.window.id])])
      state = next
    }
    // A timed-out or gone read counts as unmoved too.
    let (afterTimeout, fx) = DragSessionReducer.reduce(state, .frameSample([F.window.id: .timedOut]))
    #expect(F.isPressed(afterTimeout))
    #expect(fx == [.requestSample([F.window.id])])

    let (moving, _) = DragSessionReducer.reduce(afterTimeout, F.moved())
    #expect(F.isMoving(moving))

    let whole = F.run([
      F.mouseDown(flags: .shift), F.dragged(), F.unmoved(), F.unmoved(), F.unmoved(), F.moved(),
    ])
    #expect(F.isArmed(whole.state))
  }

  @Test func resizeFromEveryEdgeEndsSession() {
    let f = F.downFrame
    let d = 40.0
    let frames: [(String, CGRect)] = [
      ("left", CGRect(x: f.minX - d, y: f.minY, width: f.width + d, height: f.height)),
      ("right", CGRect(x: f.minX, y: f.minY, width: f.width + d, height: f.height)),
      ("top", CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height + d)),
      ("bottom", CGRect(x: f.minX, y: f.minY - d, width: f.width, height: f.height + d)),
      ("top-left", CGRect(x: f.minX - d, y: f.minY, width: f.width + d, height: f.height + d)),
      ("top-right", CGRect(x: f.minX, y: f.minY, width: f.width + d, height: f.height + d)),
      ("bottom-left", CGRect(x: f.minX - d, y: f.minY - d, width: f.width + d, height: f.height + d)),
      ("bottom-right", CGRect(x: f.minX, y: f.minY - d, width: f.width + d, height: f.height + d)),
    ]
    for (name, frame) in frames {
      var (state, _) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift))
      (state, _) = DragSessionReducer.reduce(state, F.dragged())
      let (next, fx) = DragSessionReducer.reduce(state, F.sample(frame))
      #expect(next == .idle, "\(name)")
      #expect(!fx.contains(where: F.isShowOverlay), "\(name)")
      #expect(!fx.contains(where: F.isRequestArmContext), "\(name)")
      #expect(fx == [.stopSampling], "\(name)")
    }
  }

  @Test func resizeToleranceIsOnePoint() {
    func outcome(_ dw: Double) -> DragState {
      var (state, _) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift))
      (state, _) = DragSessionReducer.reduce(state, F.dragged())
      let f = F.downFrame
      return DragSessionReducer.reduce(
        state, F.sample(CGRect(x: f.minX, y: f.minY, width: f.width + dw, height: f.height))
      ).0
    }
    #expect(F.isPressed(outcome(1.0)))
    #expect(outcome(1.01) == .idle)
  }

  @Test func modifierLateArms() {
    var (state, fx) = DragSessionReducer.reduce(.idle, F.mouseDown())
    (state, fx) = DragSessionReducer.reduce(state, F.dragged())
    (state, fx) = DragSessionReducer.reduce(state, F.moved())
    #expect(F.isMoving(state))
    #expect(fx == [.stopSampling])
    #expect(!fx.contains(where: F.isShowOverlay))

    (state, fx) = DragSessionReducer.reduce(state, .flagsChanged(.shift))
    #expect(F.isMoving(state))
    #expect(fx == [.requestArmContext(window: F.window, point: F.downFrame.origin)])

    // Shift already present: a repeated flagsChanged does not ask again.
    let (again, againFx) = DragSessionReducer.reduce(state, .flagsChanged([.shift, .option]))
    #expect(again != .idle)
    #expect(againFx.isEmpty)

    (state, fx) = DragSessionReducer.reduce(state, .armContext(F.context))
    #expect(F.isArmed(state))
    #expect(fx.filter(F.isShowOverlay).count == 1)

    let whole = F.run([F.mouseDown(), F.dragged(), F.moved(), .flagsChanged(.shift)])
    #expect(F.isArmed(whole.state))
    #expect(whole.effects.filter(F.isShowOverlay).count == 1)
  }

  @Test func plainDragIsInert() {
    let r = F.run([F.mouseDown(), F.dragged(), F.moved(), F.dragged(CGPoint(x: 400, y: 300))])
    #expect(F.isMoving(r.state))
    let (state, fx) = DragSessionReducer.reduce(r.state, .mouseUp(point: CGPoint(x: 400, y: 300), flags: []))
    #expect(state == .idle)
    #expect(fx.isEmpty)
    #expect(!r.effects.contains(where: F.isShowOverlay))
    #expect(!r.effects.contains(where: F.isSnap))
    #expect(!r.effects.contains(where: F.isRestore))
  }
}
